/*!
 @file AuthCryptoDPoP.m

 @abstract Canonical DPoP proof verification and creation implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AuthCrypto/AuthCryptoDPoP.h"
#import "AuthCrypto/AuthCryptoBase64URL.h"
#import "AuthCrypto/AuthCryptoJWK.h"
#import "Auth/PDSKeyProtocol.h"
#import "Debug/PDSLogger.h"

NSString * const AuthCryptoDPoPErrorDomain = @"com.atproto.authcrypto.dpop";

@implementation AuthCryptoDPoPResult
@end

@implementation AuthCryptoDPoP

+ (NSString *)canonicalHTUFromURL:(NSURL *)url {
    if (!url) return @"";

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) return @"";

    NSString *scheme = [components.scheme lowercaseString];
    NSString *host = [components.host lowercaseString];

    if (!scheme || !host) return @"";

    // Default ports based on scheme
    NSNumber *defaultPort = [scheme isEqualToString:@"https"] ? @443 : @80;
    NSInteger port = components.port ? components.port.integerValue : defaultPort.integerValue;

    // Only include port if non-default
    NSString *portString = @"";
    if (([scheme isEqualToString:@"https"] && port != 443) ||
        ([scheme isEqualToString:@"http"] && port != 80)) {
        portString = [NSString stringWithFormat:@":%ld", (long)port];
    }

    // Canonical form: scheme://host[:port]/path?query (no fragment, trailing slash preserved)
    NSString *path = components.path ?: @"/";
    NSString *query = components.query ? [NSString stringWithFormat:@"?%@", components.query] : @"";

    return [NSString stringWithFormat:@"%@://%@%@%@%@", scheme, host, portString, path, query];
}

+ (nullable NSString *)canonicalHTUFromString:(NSString *)urlString {
    if (!urlString) return nil;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return nil;
    return [self canonicalHTUFromURL:url];
}

+ (BOOL)verifyProof:(NSString *)dpopJwt
              method:(NSString *)method
                 url:(NSURL *)url
               nonce:(nullable NSString *)nonce
        requireNonce:(BOOL)requireNonce
      nonceValidator:(nullable id<AuthCryptoDPoPNonceValidator>)nonceValidator
       replayChecker:(nullable id<AuthCryptoDPoPReplayChecker>)replayChecker
       outThumbprint:(NSString * _Nullable * _Nullable)thumbprint
               error:(NSError **)error {

    if (!dpopJwt) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof is nil"}];
        }
        return NO;
    }

    NSArray *parts = [dpopJwt componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP proof format"}];
        }
        return NO;
    }

    // Decode header
    NSData *headerData = [AuthCryptoBase64URL decode:parts[0]];
    if (!headerData) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP header encoding"}];
        }
        return NO;
    }

    NSError *headerError = nil;
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:&headerError];
    if (!header || headerError) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP header JSON"}];
        }
        return NO;
    }

    // Validate header
    if (![header[@"typ"] isEqualToString:@"dpop+jwt"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP header typ must be 'dpop+jwt'"}];
        }
        return NO;
    }

    if (![header[@"alg"] isEqualToString:@"ES256"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP only supports ES256"}];
        }
        return NO;
    }

    NSDictionary *jwk = header[@"jwk"];
    if (!jwk) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP header missing jwk"}];
        }
        return NO;
    }

    // Validate JWK has no private key material
    if (jwk[@"d"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP JWK must not contain private key material"}];
        }
        return NO;
    }

    // Decode payload
    NSData *payloadData = [AuthCryptoBase64URL decode:parts[1]];
    if (!payloadData) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP payload encoding"}];
        }
        return NO;
    }

    NSError *payloadError = nil;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&payloadError];
    if (!payload || payloadError) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP payload JSON"}];
        }
        return NO;
    }

    // Validate payload claims
    NSString *proofHtm = payload[@"htm"];
    NSString *proofHtu = payload[@"htu"];
    NSNumber *iat = payload[@"iat"];
    NSString *jti = payload[@"jti"];
    NSString *proofNonce = payload[@"nonce"];

    if (![proofHtm isEqualToString:[method uppercaseString]]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-7
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP htm mismatch"}];
        }
        return NO;
    }

    // Canonical HTU check
    NSString *expectedHTU = [self canonicalHTUFromURL:url];
    if (![proofHtu isEqualToString:expectedHTU]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-8
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP htu mismatch"}];
        }
        return NO;
    }

    if (!iat) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-9
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP payload missing iat"}];
        }
        return NO;
    }

    // Check timestamp (5 minute window)
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (fabs(now - iat.doubleValue) > 300) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-10
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof expired"}];
        }
        return NO;
    }

    // Nonce validation
    if (requireNonce && !proofNonce) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof missing required nonce"}];
        }
        return NO;
    }

    if (nonce && ![proofNonce isEqualToString:nonce]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP nonce mismatch"}];
        }
        return NO;
    }

    if (proofNonce && nonceValidator) {
        if (![nonceValidator validateNonce:proofNonce]) {
            if (error) {
                *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                             code:-11
                                         userInfo:@{NSLocalizedDescriptionKey: @"DPoP nonce validation failed"}];
            }
            return NO;
        }
    }

    // Replay check
    if (replayChecker) {
        NSDate *jtiExpiration = [NSDate dateWithTimeIntervalSince1970:iat.doubleValue + 300];
        if (![replayChecker checkAndAddJTI:jti expiration:jtiExpiration]) {
            if (error) {
                *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                             code:-12
                                         userInfo:@{NSLocalizedDescriptionKey: @"DPoP jti reuse detected"}];
            }
            return NO;
        }
    }

    // Create public key from JWK using protocol-based API
    NSError *keyError = nil;
    id<PDSPublicKeyProtocol> publicKey = [AuthCryptoJWK publicKeyFromJWK:jwk error:&keyError];
    if (!publicKey) {
        if (error) {
            *error = keyError ?: [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create public key from JWK"}];
        }
        return NO;
    }

    // Decode signature (raw r||s format, 64 bytes)
    NSData *signatureData = [AuthCryptoBase64URL decode:parts[2]];
    if (!signatureData || signatureData.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP signature"}];
        }
        return NO;
    }

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    // Verify signature using protocol
    NSError *verifyError = nil;
    BOOL verified = [publicKey verifySignature:signatureData forData:signingData error:&verifyError];
    if (!verified) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-13
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP signature verification failed"}];
        }
        return NO;
    }

    if (thumbprint) {
        *thumbprint = [AuthCryptoJWK thumbprint:jwk error:error];
        if (!*thumbprint) return NO;
    }

    return YES;
}

+ (nullable NSString *)createProofForURL:(NSURL *)url
                                  method:(NSString *)method
                                     key:(NSDictionary *)jwk
                                   error:(NSError **)error {

    if (!url || !method || !jwk) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return nil;
    }

    NSString *normalizedHTU = [self canonicalHTUFromURL:url];
    if (!normalizedHTU) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL for DPoP"}];
        }
        return nil;
    }

    // Get public JWK (without private key material) for header
    NSDictionary *publicJWK = [AuthCryptoJWK publicJWKFromJWK:jwk];

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:@{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": publicJWK
    } options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [AuthCryptoBase64URL encode:headerData];
    if (!headerEncoded) return nil;

    NSDictionary *claims = @{
        @"jti": [[NSUUID UUID] UUIDString],
        @"htm": [method uppercaseString],
        @"htu": normalizedHTU,
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };

    NSData *claimsData = [NSJSONSerialization dataWithJSONObject:claims options:0 error:error];
    if (!claimsData) return nil;
    NSString *claimsEncoded = [AuthCryptoBase64URL encode:claimsData];

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerEncoded, claimsEncoded];

    // Create private key using protocol-based API
    NSError *keyError = nil;
    id<PDSPrivateKeyProtocol> privateKey = [AuthCryptoJWK privateKeyFromJWK:jwk error:&keyError];
    if (!privateKey) {
        if (error) {
            *error = keyError ?: [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-15
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create private key from JWK"}];
        }
        return nil;
    }

    // Sign using protocol
    NSData *signatureData = [privateKey signData:[signingInput dataUsingEncoding:NSUTF8StringEncoding] error:&keyError];
    if (!signatureData) {
        if (error) {
            *error = keyError ?: [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-16
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign DPoP proof"}];
        }
        return nil;
    }

    NSString *signatureEncoded = [AuthCryptoBase64URL encode:signatureData];
    return [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, claimsEncoded, signatureEncoded];
}

@end
