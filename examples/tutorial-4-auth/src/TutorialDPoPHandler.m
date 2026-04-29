/*!
 @file TutorialDPoPHandler.m

 @abstract DPoP proof generation and verification implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "TutorialDPoPHandler.h"
#import "TutorialECDSAUtils.h"
#import "TutorialBase64URL.h"

@implementation TutorialDPoPHandler

+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                      uri:(NSString *)uri
                                    nonce:(nullable NSString *)nonce
                                  keyPair:(TutorialECDSAKeyPair *)keyPair
                                    error:(NSError **)error {
    // Build header with typ: dpop+jwt and JWK
    NSDictionary *header = @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": keyPair.publicJWK
    };

    // Build payload with DPoP claims
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *payload = [@{
        @"jti": [[NSUUID UUID] UUIDString],
        @"htm": method,
        @"htu": uri,
        @"iat": @(now),
        @"exp": @(now + 300)  // 5 minute max lifetime
    } mutableCopy];

    if (nonce) {
        payload[@"nonce"] = nonce;
    }

    // Serialize header and payload
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!headerData || !payloadData) return nil;

    NSString *headerB64 = [TutorialBase64URL encode:headerData];
    NSString *payloadB64 = [TutorialBase64URL encode:payloadData];

    // Sign with ES256
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    NSData *signature = [TutorialECDSAUtils signData:signingData
                                       withPrivateKey:keyPair.privateJWK
                                                error:error];
    if (!signature) return nil;

    NSString *signatureB64 = [TutorialBase64URL encode:signature];
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

+ (BOOL)verifyDPoPProof:(NSString *)proof
                  method:(NSString *)method
                     uri:(NSString *)uri
              publicJWK:(NSDictionary *)publicJWK
                   nonce:(nullable NSString *)nonce
       allowedClockSkew:(NSTimeInterval)allowedClockSkew
                   error:(NSError **)error {
    // 1. Parse JWT
    NSArray *parts = [proof componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP proof format"}];
        }
        return NO;
    }

    // 2. Decode and verify header
    NSData *headerData = [TutorialBase64URL decode:parts[0]];
    if (!headerData) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode DPoP header"}];
        }
        return NO;
    }
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:error];
    if (!header) return NO;

    // Verify typ
    if (![header[@"typ"] isEqualToString:@"dpop+jwt"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid typ: expected dpop+jwt"}];
        }
        return NO;
    }

    // Verify alg
    if (![header[@"alg"] isEqualToString:@"ES256"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid alg: expected ES256"}];
        }
        return NO;
    }

    // 3. Decode and verify payload claims
    NSData *payloadData = [TutorialBase64URL decode:parts[1]];
    if (!payloadData) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode DPoP payload"}];
        }
        return NO;
    }
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (!payload) return NO;

    // Verify HTTP method
    if (![payload[@"htm"] isEqualToString:method]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"HTTP method mismatch"}];
        }
        return NO;
    }

    // Verify HTTP URI (canonical comparison)
    if (![payload[@"htu"] isEqualToString:uri]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"HTTP URI mismatch"}];
        }
        return NO;
    }

    // Verify timestamp (allow clock skew)
    NSTimeInterval iat = [payload[@"iat"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (fabs(now - iat) > 300 + allowedClockSkew) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof too old or from future"}];
        }
        return NO;
    }

    // Verify nonce if provided
    if (nonce && ![payload[@"nonce"] isEqualToString:nonce]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:9
                                     userInfo:@{NSLocalizedDescriptionKey: @"Nonce mismatch"}];
        }
        return NO;
    }

    // 4. Verify ES256 signature
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signatureData = [TutorialBase64URL decode:parts[2]];

    if (!signatureData || signatureData.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature format"}];
        }
        return NO;
    }

    return [TutorialECDSAUtils verifySignature:signatureData
                                      forData:signingData
                                withPublicKey:publicJWK
                                        error:error];
}

@end
