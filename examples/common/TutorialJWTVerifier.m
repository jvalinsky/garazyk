/*!
 @file TutorialJWTVerifier.m

 @abstract ES256 JWT token verification implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "TutorialJWTVerifier.h"
#import "TutorialECDSAUtils.h"
#import "TutorialBase64URL.h"

@implementation TutorialJWTVerifier

- (instancetype)initWithIssuer:(NSString *)issuer
                       keyPair:(TutorialECDSAKeyPair *)keyPair {
    self = [super init];
    if (self) {
        _expectedIssuer = [issuer copy];
        _keyPair = keyPair;
    }
    return self;
}

- (nullable NSDictionary *)verifyToken:(NSString *)token
                                error:(NSError **)error {
    // 1. Parse JWT into parts
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"TutorialJWT"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT format: expected 3 parts"}];
        }
        return nil;
    }

    // 2. Decode header
    NSData *headerData = [TutorialBase64URL decode:parts[0]];
    if (!headerData) {
        if (error) {
            *error = [NSError errorWithDomain:@"TutorialJWT"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode JWT header"}];
        }
        return nil;
    }
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:error];
    if (!header) return nil;

    // 3. Verify algorithm
    if (![header[@"alg"] isEqualToString:@"ES256"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TutorialJWT"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                     @"Unsupported algorithm: expected ES256"}];
        }
        return nil;
    }

    // 4. Decode payload
    NSData *payloadData = [TutorialBase64URL decode:parts[1]];
    if (!payloadData) {
        if (error) {
            *error = [NSError errorWithDomain:@"TutorialJWT"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode JWT payload"}];
        }
        return nil;
    }
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (!payload) return nil;

    // 5. Verify signature
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signatureData = [TutorialBase64URL decode:parts[2]];

    if (!signatureData || signatureData.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:@"TutorialJWT"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature format"}];
        }
        return nil;
    }

    if (!self.keyPair) {
        if (error) {
            *error = [NSError errorWithDomain:@"TutorialJWT"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"No verification key configured"}];
        }
        return nil;
    }

    BOOL signatureValid = [TutorialECDSAUtils verifySignature:signatureData
                                                      forData:signingData
                                                withPublicKey:self.keyPair.publicJWK
                                                        error:error];
    if (!signatureValid) {
        return nil;
    }

    // 6. Verify claims
    if (![payload[@"iss"] isEqualToString:self.expectedIssuer]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TutorialJWT"
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid issuer"}];
        }
        return nil;
    }

    NSTimeInterval exp = [payload[@"exp"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (exp < now) {
        if (error) {
            *error = [NSError errorWithDomain:@"TutorialJWT"
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"Token expired"}];
        }
        return nil;
    }

    return payload;
}

@end
