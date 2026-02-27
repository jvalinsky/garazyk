/*!
 @file AuthCryptoDPoP.m

 @abstract Canonical DPoP proof verification and creation implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AuthCrypto/AuthCryptoDPoP.h"
#import "AuthCrypto/AuthCryptoBase64URL.h"
#import "AuthCrypto/AuthCryptoJWK.h"
#import "AuthCrypto/AuthCryptoECDSA.h"
#import "Debug/PDSLogger.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

NSString * const AuthCryptoDPoPErrorDomain = @"com.atproto.authcrypto.dpop";

@implementation AuthCryptoDPoPResult
@end

@implementation AuthCryptoDPoP

+ (NSString *)canonicalHTUFromURL:(NSURL *)url {
    if (!url) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) return nil;

    NSString *scheme = [components.scheme lowercaseString];
    NSString *host = [components.host lowercaseString];
    if (scheme.length == 0 || host.length == 0) return nil;

    NSString *path = components.percentEncodedPath;
    if (path.length == 0) path = @"/";

    NSNumber *port = components.port;
    BOOL includePort = NO;
    if (port != nil) {
        NSInteger portValue = port.integerValue;
        BOOL defaultHTTPS = [scheme isEqualToString:@"https"] && portValue == 443;
        BOOL defaultHTTP = [scheme isEqualToString:@"http"] && portValue == 80;
        includePort = !(defaultHTTPS || defaultHTTP);
    }

    NSURLComponents *canonical = [[NSURLComponents alloc] init];
    canonical.scheme = scheme;
    canonical.host = host;
    canonical.percentEncodedPath = path;
    canonical.query = nil;
    canonical.fragment = nil;
    if (includePort) canonical.port = port;

    return canonical.string;
}

+ (nullable NSString *)canonicalHTUFromString:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) return nil;
    NSURL *url = [NSURL URLWithString:urlString];
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
    NSArray<NSString *> *parts = [dpopJwt componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP format"}];
        }
        return NO;
    }

    NSData *headerData = [AuthCryptoBase64URL decode:parts[0]];
    NSData *payloadData = [AuthCryptoBase64URL decode:parts[1]];
    NSData *signatureData = [AuthCryptoBase64URL decode:parts[2]];
    if (!headerData || !payloadData || !signatureData) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode DPoP components"}];
        }
        return NO;
    }

    NSError *jsonError = nil;
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:&jsonError];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&jsonError];
    if (!header || !payload) {
        if (error) *error = jsonError;
        return NO;
    }

    NSString *typ = header[@"typ"];
    NSString *alg = header[@"alg"];
    NSDictionary *jwk = header[@"jwk"];
    if (![typ isEqualToString:@"dpop+jwt"] || ![alg isEqualToString:@"ES256"] || ![jwk isKindOfClass:[NSDictionary class]]) {
        PDS_LOG_AUTH_DEBUG(@"DPoP verification failed: Invalid header (typ=%@, alg=%@, has_jwk=%d)", typ, alg, jwk != nil);
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP header"}];
        }
        return NO;
    }

    NSString *htm = payload[@"htm"];
    NSString *htu = payload[@"htu"];
    NSString *jti = payload[@"jti"];
    NSNumber *iat = payload[@"iat"];
    if (!htm || !htu || !jti || !iat) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing DPoP claims"}];
        }
        return NO;
    }

    NSString *expectedHTU = [self canonicalHTUFromURL:url];
    NSString *receivedHTU = [self canonicalHTUFromString:htu];
    if (expectedHTU.length == 0 || receivedHTU.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP htu claim"}];
        }
        return NO;
    }

    NSString *normalizedMethod = [method uppercaseString];
    if (![htm isEqualToString:normalizedMethod]) {
        PDS_LOG_AUTH_DEBUG(@"DPoP verification failed: htm mismatch (expected=%@, got=%@)", normalizedMethod, htm);
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-6
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP htm mismatch"}];
        }
        return NO;
    }

    if (![receivedHTU isEqualToString:expectedHTU]) {
        PDS_LOG_AUTH_DEBUG(@"DPoP verification failed: htu mismatch (expected=%@, got=%@)", expectedHTU, receivedHTU);
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-7
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP htu mismatch"}];
        }
        return NO;
    }

    NSString *proofNonce = payload[@"nonce"];
    BOOL nonceRequired = requireNonce || nonce.length > 0;
    if (nonceRequired && proofNonce.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-8
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof missing required nonce",
                                                @"use_dpop_nonce": @YES}];
        }
        return NO;
    }

    if (proofNonce.length > 0) {
        if (nonce.length > 0 && ![proofNonce isEqualToString:nonce]) {
            if (error) {
                *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                             code:-8
                                         userInfo:@{NSLocalizedDescriptionKey: @"DPoP nonce mismatch",
                                                    @"use_dpop_nonce": @YES}];
            }
            return NO;
        }

        if (nonceValidator && ![nonceValidator validateNonce:proofNonce]) {
            if (error) {
                *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                             code:-8
                                         userInfo:@{NSLocalizedDescriptionKey: @"DPoP nonce expired or invalid",
                                                    @"use_dpop_nonce": @YES}];
            }
            return NO;
        }
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (iat.doubleValue > now + 60) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-9
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP iat in future"}];
        }
        return NO;
    }

    NSNumber *exp = payload[@"exp"];
    if (exp && exp.doubleValue < now) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-10
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof expired"}];
        }
        return NO;
    }

    if (now - iat.doubleValue > 300) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP iat too old"}];
        }
        return NO;
    }

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

    SecKeyRef publicKey = [AuthCryptoJWK createPublicKeyFromJWK:jwk error:error];
    if (!publicKey) return NO;

    NSData *derSignature = [AuthCryptoECDSA derSignatureFromRaw:signatureData error:error];
    if (!derSignature) {
        CFRelease(publicKey);
        return NO;
    }

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    BOOL verified = SecKeyVerifySignature(publicKey,
                                          kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                          (__bridge CFDataRef)signingData,
                                          (__bridge CFDataRef)derSignature,
                                          NULL);
    CFRelease(publicKey);
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
    NSString *kty = jwk[@"kty"];
    NSString *alg = jwk[@"alg"];
    if (!alg && [kty isEqualToString:@"EC"]) alg = @"ES256";
    if (![kty isEqualToString:@"EC"] || ![alg isEqualToString:@"ES256"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-14
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported DPoP key type"}];
        }
        return nil;
    }

    NSDictionary *header = @{
        @"typ": @"dpop+jwt",
        @"alg": alg,
        @"jwk": [AuthCryptoJWK publicJWKFromJWK:jwk]
    };

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;
    NSString *headerEncoded = [AuthCryptoBase64URL encode:headerData];

    NSString *normalizedHTU = [self canonicalHTUFromURL:url];
    if (normalizedHTU.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoDPoPErrorDomain
                                         code:-15
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP URL target"}];
        }
        return nil;
    }

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
    SecKeyRef privateKey = [AuthCryptoJWK createPrivateKeyFromJWK:jwk error:error];
    if (!privateKey) return nil;

    CFErrorRef signError = NULL;
    NSData *signatureData = CFBridgingRelease(SecKeyCreateSignature(privateKey,
                                                                     kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                     (__bridge CFDataRef)[signingInput dataUsingEncoding:NSUTF8StringEncoding],
                                                                     &signError));
    CFRelease(privateKey);

    if (signError || !signatureData) {
        if (error) {
            *error = signError ? CFBridgingRelease(signError)
                : [NSError errorWithDomain:AuthCryptoDPoPErrorDomain code:-16
                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign DPoP proof"}];
        } else if (signError) {
            CFRelease(signError);
        }
        return nil;
    }

    NSData *rawSignature = [AuthCryptoECDSA rawSignatureFromDER:signatureData expectedSize:32 error:error];
    if (!rawSignature) return nil;

    NSString *signatureEncoded = [AuthCryptoBase64URL encode:rawSignature];
    return [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, claimsEncoded, signatureEncoded];
}

@end
