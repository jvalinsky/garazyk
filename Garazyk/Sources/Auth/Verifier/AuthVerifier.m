// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AuthVerifier.m

 @abstract AuthVerifier implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Auth/Verifier/AuthVerifier.h"
#import "Auth/JWT.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/PDSKeyProtocol.h"
#import "Auth/PDSReplayCache.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"
#import "Metrics/PDSMetrics.h"
#import "Security/PDSSecurityCompare.h"
#import "Auth/OAuthProvider/OAuthProviderProtocols.h"
#import <Security/Security.h>

NSString * const AuthVerifierErrorDomain = @"com.atproto.authverifier";

#pragma mark - AuthVerifierPrincipal

@interface AuthVerifierPrincipal ()
@property (nonatomic, copy, readwrite) NSString *did;
@property (nonatomic, copy, readwrite, nullable) NSString *accessTokenJWT;
@property (nonatomic, copy, readwrite, nullable) NSDictionary *tokenClaims;
@property (nonatomic, copy, readwrite, nullable) NSString *dpopThumbprint;
@property (nonatomic, assign, readwrite) BOOL usedDPoP;
@property (nonatomic, assign, readwrite) BOOL isAdmin;
@end

@implementation AuthVerifierPrincipal

- (instancetype)initWithDID:(NSString *)did
              accessTokenJWT:(nullable NSString *)accessTokenJWT
               tokenClaims:(nullable NSDictionary *)tokenClaims
            dpopThumbprint:(nullable NSString *)dpopThumbprint
                   usedDPoP:(BOOL)usedDPoP
                    isAdmin:(BOOL)isAdmin {
    self = [super init];
    if (self) {
        _did = [did copy];
        _accessTokenJWT = [accessTokenJWT copy];
        _tokenClaims = [tokenClaims copy];
        _dpopThumbprint = [dpopThumbprint copy];
        _usedDPoP = usedDPoP;
        _isAdmin = isAdmin;
    }
    return self;
}

@end

#pragma mark - AuthVerifier

@interface AuthVerifier ()
@property (nonatomic, strong, nullable) id<TokenKeyResolver> keyResolver;
@property (nonatomic, strong) id<AccountPolicy> accountPolicy;
@property (nonatomic, strong, nullable) id<DPoPNonceStore> nonceStore;
@property (nonatomic, strong) id localPublicKey;
@property (nonatomic, copy) NSString *localIssuer;
@end

@implementation AuthVerifier

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithKeyResolver:(nullable id<TokenKeyResolver>)keyResolver
                      accountPolicy:(id<AccountPolicy>)accountPolicy
                         nonceStore:(nullable id<DPoPNonceStore>)nonceStore {
    self = [super init];
    if (self) {
        _keyResolver = keyResolver;
        _accountPolicy = accountPolicy;
        _nonceStore = nonceStore;
        _requireDPoP = NO;
    }
    return self;
}

- (void)setLocalPublicKey:(id)publicKey {
    self.localPublicKey = publicKey;
}

- (void)setLocalIssuer:(NSString *)issuer {
    self.localIssuer = issuer;
    if (self.expectedAudience.length == 0) {
        self.expectedAudience = issuer;
    }
}

#pragma mark - Public API

- (nullable AuthVerifierPrincipal *)verifyRequest:(HttpRequest *)request
                                        response:(nullable HttpResponse *)response
                                           error:(NSError **)error {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *dpopHeader = [request headerForKey:@"DPoP"];

    return [self verifyAuthHeader:authHeader
                       dpopHeader:dpopHeader
                         request:request
                        response:response
                           error:error];
}

- (nullable AuthVerifierPrincipal *)verifyAccessToken:(nullable NSString *)token
                                               error:(NSError **)error {
    if (!token) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing token"}];
        }
        [[PDSMetrics sharedMetrics] incrementAuthFailure:@"missing_token"];
        return nil;
    }
    return [self verifyAuthHeader:[NSString stringWithFormat:@"Bearer %@", token]
                       dpopHeader:nil
                         request:nil
                        response:nil
                           error:error];
}

- (nullable AuthVerifierPrincipal *)verifyAuthHeader:(nullable NSString *)authHeader
                                            dpopHeader:(nullable NSString *)dpopHeader
                                              request:(nullable HttpRequest *)request
                                             response:(nullable HttpResponse *)response
                                                error:(NSError **)error {
    if (!authHeader) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing Authorization header"}];
        }
        return nil;
    }

    NSString *token = nil;
    BOOL isDPoP = NO;

    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
        isDPoP = YES;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid Authorization scheme"}];
        }
        return nil;
    }

    if (isDPoP && dpopHeader.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorDPoPMissing
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing DPoP header"}];
        }
        [[PDSMetrics sharedMetrics] incrementAuthFailure:@"dpop_missing"];
        return nil;
    }

    if (self.requireDPoP && !isDPoP) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorDPoPRequired
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP is required"}];
        }
        return nil;
    }

    NSString *dpopThumbprint = nil;
    NSURL *dpopURL = nil;

    if (isDPoP && request) {
        dpopURL = [self expectedDPoPURLForRequest:request];
        if (!dpopURL) {
            GZ_LOG_AUTH_WARN(@"Unable to construct DPoP URL for request");
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unable to construct DPoP URL"}];
            }
            return nil;
        }

        NSError *dpopError = nil;
        BOOL validProof = [AuthCryptoDPoP verifyProof:dpopHeader
                                             method:request.methodString ?: @"GET"
                                                url:dpopURL
                                              nonce:nil
                                       requireNonce:self.nonceStore != nil
                                     nonceValidator:(id<AuthCryptoDPoPNonceValidator>)self.nonceStore
                                      replayChecker:[PDSReplayCache sharedCache]
                                      outThumbprint:&dpopThumbprint
                                              error:&dpopError];

        if (!validProof) {
            BOOL needsNonce = [dpopError.userInfo[@"use_dpop_nonce"] boolValue];
            if (needsNonce && response) {
                response.statusCode = 401;
                NSString *nonce = nil;
                if ([self.nonceStore respondsToSelector:@selector(issueNonceForJWKThumbprint:error:)]) {
                    NSError *nonceError = nil;
                    nonce = [self.nonceStore issueNonceForJWKThumbprint:dpopThumbprint ?: @"" error:&nonceError];
                }
                if (!nonce) {
                    nonce = [[NSUUID UUID] UUIDString];
                }
                [response setHeader:nonce forKey:@"DPoP-Nonce"];
                [response setHeader:@"DPoP error=\"use_dpop_nonce\"" forKey:@"WWW-Authenticate"];
                [response setHeader:@"no-store" forKey:@"Cache-Control"];
                [response setHeader:@"no-cache" forKey:@"Pragma"];
            }
            if (error) {
                *error = dpopError;
            }
            [[PDSMetrics sharedMetrics] incrementAuthFailure:@"dpop_invalid"];
            return nil;
        }
    }

    JWT *jwt = [JWT jwtWithToken:token error:nil];
    if (!jwt) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT format"}];
        }
        [[PDSMetrics sharedMetrics] incrementAuthFailure:@"invalid_token"];
        return nil;
    }

    JWTPayload *payload = jwt.payload;
    NSString *issuer = payload.iss;
    NSString *subject = payload.sub;
    NSString *audience = payload.aud;
    NSString *tokenJkt = payload.cnf[@"jkt"];
    NSDictionary *claims = [payload toDictionary];

    if (!issuer) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing issuer claim"}];
        }
        [[PDSMetrics sharedMetrics] incrementAuthFailure:@"missing_issuer"];
        return nil;
    }

    if (!subject || ![subject hasPrefix:@"did:"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid subject claim"}];
        }
        [[PDSMetrics sharedMetrics] incrementAuthFailure:@"invalid_subject"];
        return nil;
    }

    BOOL isLocalIssuer = [PDSSecurityCompare constantTimeEqualString:issuer string:self.localIssuer] ||
                         [PDSSecurityCompare constantTimeEqualString:issuer string:self.expectedAudience];

    if (isLocalIssuer) {
        JWTVerifier *verifier = [[JWTVerifier alloc] init];
        verifier.publicKey = self.localPublicKey;
        verifier.expectedIssuer = self.localIssuer;
        verifier.expectedAudience = self.expectedAudience;
        verifier.allowedAlgorithms = @[@"ES256K", @"ES256"];

        NSError *verifyError = nil;
        if (![verifier verifyJWT:jwt error:&verifyError]) {
            if (error) {
                *error = verifyError ?: [NSError errorWithDomain:AuthVerifierErrorDomain
                                                            code:AuthVerifierErrorInvalidSignature
                                                        userInfo:@{NSLocalizedDescriptionKey: @"JWT verification failed"}];
            }
            [[PDSMetrics sharedMetrics] incrementAuthFailure:@"invalid_signature"];
            return nil;
        }
    } else if (self.keyResolver && [self.keyResolver isIssuerAllowed:issuer]) {
        NSError *jwksError = nil;
        NSDictionary *jwks = [self.keyResolver jwksForIssuer:issuer error:&jwksError];
        if (!jwks) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidIssuer
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fetch JWKS: %@", jwksError.localizedDescription]}];
            }
            [[PDSMetrics sharedMetrics] incrementAuthFailure:@"invalid_issuer"];
            return nil;
        }

        // Verify signature using the fetched JWKS
        NSString *kid = jwt.header.kid;
        NSDictionary *targetKey = nil;
        NSArray *keys = jwks[@"keys"];
        if ([keys isKindOfClass:[NSArray class]]) {
            for (NSDictionary *key in keys) {
                if (!kid || [key[@"kid"] isEqualToString:kid]) {
                    targetKey = key;
                    break;
                }
            }
        }

        if (!targetKey) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidSignature
                                         userInfo:@{NSLocalizedDescriptionKey: @"No matching key found in JWKS"}];
            }
            [[PDSMetrics sharedMetrics] incrementAuthFailure:@"invalid_signature"];
            return nil;
        }

        NSError *verifyError = nil;
        id<PDSPublicKeyProtocol> pubKey = [AuthCryptoJWK publicKeyFromJWK:targetKey error:&verifyError];
        if (!pubKey) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidSignature
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid key in JWKS: %@", verifyError.localizedDescription]}];
            }
            [[PDSMetrics sharedMetrics] incrementAuthFailure:@"invalid_signature"];
            return nil;
        }

        NSData *signingInput = [jwt.signingInput dataUsingEncoding:NSUTF8StringEncoding];
        NSData *signature = [JWT base64URLDecode:jwt.encodedSignature error:nil];
        if (![pubKey verifySignature:signature forData:signingInput error:&verifyError]) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidSignature
                                         userInfo:@{NSLocalizedDescriptionKey: @"JWT signature verification failed for remote issuer"}];
            }
            [[PDSMetrics sharedMetrics] incrementAuthFailure:@"invalid_signature"];
            return nil;
        }

        // After successful signature check, we still need to validate standard claims
        JWTVerifier *claimsVerifier = [[JWTVerifier alloc] init];
        claimsVerifier.expectedIssuer = issuer;
        claimsVerifier.expectedAudience = self.expectedAudience;
        claimsVerifier.allowedAlgorithms = @[@"ES256", @"RS256"];
        if (![claimsVerifier validateClaims:jwt.payload ofJWT:jwt error:&verifyError]) {
            if (error) *error = verifyError;
            return nil;
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidIssuer
                                     userInfo:@{NSLocalizedDescriptionKey: @"Issuer not allowed"}];
        }
        [[PDSMetrics sharedMetrics] incrementAuthFailure:@"invalid_issuer"];
        return nil;
    }

    if (audience && self.expectedAudience.length > 0 && ![PDSSecurityCompare constantTimeEqualString:audience string:self.expectedAudience]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidAudience
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid audience"}];
        }
        return nil;
    }

    if (isDPoP) {
        if (!tokenJkt) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorDPoPRequired
                                         userInfo:@{NSLocalizedDescriptionKey: @"Token not bound to DPoP key"}];
            }
            return nil;
        }
        if (dpopThumbprint && ![PDSSecurityCompare constantTimeEqualString:tokenJkt string:dpopThumbprint]) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorDPoPThumbprintMismatch
                                         userInfo:@{NSLocalizedDescriptionKey: @"DPoP thumbprint mismatch"}];
            }
            return nil;
        }
    } else if (tokenJkt) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorDPoPRequired
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP-bound token used without DPoP"}];
        }
        return nil;
    }

    NSError *accountError = nil;
    BOOL accountAllowed = [self.accountPolicy isAccountAllowed:subject error:&accountError];
    if (!accountAllowed) {
        if (error) {
            *error = accountError ?: [NSError errorWithDomain:AuthVerifierErrorDomain
                                                         code:AuthVerifierErrorAccountTakedown
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Account is suspended"}];
        }
        [[PDSMetrics sharedMetrics] incrementAuthFailure:@"account_suspended"];
        return nil;
    }

    BOOL isAdmin = NO;
    if ([self.accountPolicy respondsToSelector:@selector(isAdmin:error:)]) {
        NSError *adminError = nil;
        isAdmin = [self.accountPolicy isAdmin:subject error:&adminError];
    }

    return [[AuthVerifierPrincipal alloc] initWithDID:subject
                                          accessTokenJWT:token
                                           tokenClaims:claims
                                        dpopThumbprint:dpopThumbprint
                                               usedDPoP:isDPoP
                                                isAdmin:isAdmin];
}

- (nullable NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request {
    NSString *method = request.methodString ?: @"GET";
    NSString *path = request.path ?: @"/";

    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }

    NSString *hostHeader = [request headerForKey:@"Host"];
    NSString *scheme = @"https";

    NSString *forwardedProto = [request headerForKey:@"X-Forwarded-Proto"];
    if (forwardedProto.length > 0) {
        NSString *firstProto = [[forwardedProto componentsSeparatedByString:@","] firstObject];
        firstProto = [firstProto stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([firstProto isEqualToString:@"http"] || [firstProto isEqualToString:@"https"]) {
            scheme = firstProto;
        }
    } else if ([hostHeader containsString:@"localhost"] || [hostHeader hasPrefix:@"127.0.0.1"]) {
        scheme = @"http";
    }

    NSString *urlString = [NSString stringWithFormat:@"%@://%@%@", scheme, hostHeader, path];
    if (request.queryString.length > 0) {
        urlString = [urlString stringByAppendingFormat:@"?%@", request.queryString];
    }

    return [NSURL URLWithString:urlString];
}

@end
