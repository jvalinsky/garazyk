// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoAuthVerifier.m

 @abstract ATProtoAuthVerifier implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Auth/Verifier/AuthVerifier.h"
#import "Auth/Crypto/JWT.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/PDSKeyProtocol.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"
#import "Metrics/GZMetrics.h"
#import "Security/PDSSecurityCompare.h"
#import "Auth/Verifier/AuthVerifierProtocols.h"
#import <Security/Security.h>

NSString * const AuthVerifierErrorDomain = @"com.atproto.authverifier";

static BOOL AuthVerifierEnvBool(NSString *value) {
    if (value.length == 0) {
        return NO;
    }
    NSString *normalized = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [normalized isEqualToString:@"1"] ||
           [normalized isEqualToString:@"true"] ||
           [normalized isEqualToString:@"yes"] ||
           [normalized isEqualToString:@"on"];
}

static BOOL AuthVerifierIsTrustedProxyRemoteAddress(NSString *remoteAddress) {
    NSString *candidate = [[remoteAddress ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (candidate.length == 0) {
        return NO;
    }
    if ([candidate hasPrefix:@"127."] || [candidate isEqualToString:@"::1"] || [candidate isEqualToString:@"localhost"]) {
        return YES;
    }
    if ([candidate hasPrefix:@"10."] || [candidate hasPrefix:@"192.168."]) {
        return YES;
    }
    if ([candidate hasPrefix:@"172."]) {
        NSArray<NSString *> *parts = [candidate componentsSeparatedByString:@"."];
        if (parts.count >= 2) {
            NSInteger secondOctet = [parts[1] integerValue];
            if (secondOctet >= 16 && secondOctet <= 31) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL AuthVerifierShouldTrustForwardedHeaders(HttpRequest *request) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if (!AuthVerifierEnvBool(env[@"PDS_TRUST_PROXY_HEADERS"])) {
        return NO;
    }
    return AuthVerifierIsTrustedProxyRemoteAddress(request.remoteAddress);
}

#pragma mark - ATProtoAuthVerifierPrincipal

@interface ATProtoAuthVerifierPrincipal ()
@property (nonatomic, copy, readwrite) NSString *did;
@property (nonatomic, copy, readwrite, nullable) NSString *accessTokenJWT;
@property (nonatomic, copy, readwrite, nullable) NSDictionary *tokenClaims;
@property (nonatomic, copy, readwrite, nullable) NSString *dpopThumbprint;
@property (nonatomic, assign, readwrite) BOOL usedDPoP;
@property (nonatomic, assign, readwrite) BOOL isAdmin;
@end

@implementation ATProtoAuthVerifierPrincipal

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

#pragma mark - ATProtoAuthVerifier

@interface ATProtoAuthVerifier ()
@property (nonatomic, strong, nullable) id<TokenKeyResolver> keyResolver;
@property (nonatomic, strong) id<AccountPolicy> accountPolicy;
@property (nonatomic, strong, nullable) id<DPoPNonceStore> nonceStore;
@property (nonatomic, strong) id localPublicKey;
@property (nonatomic, copy) NSString *localIssuer;
@end

@implementation ATProtoAuthVerifier

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
    _localPublicKey = publicKey;
}

- (void)setLocalIssuer:(NSString *)issuer {
    _localIssuer = [issuer copy];
    if (self.expectedAudience.length == 0) {
        self.expectedAudience = issuer;
    }
}

#pragma mark - Public API

- (nullable ATProtoAuthVerifierPrincipal *)verifyRequest:(HttpRequest *)request
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

- (nullable ATProtoAuthVerifierPrincipal *)verifyAccessToken:(nullable NSString *)token
                                               error:(NSError **)error {
    if (!token) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing token"}];
        }
        [[GZMetrics sharedMetrics] incrementAuthFailure:@"missing_token"];
        return nil;
    }
    return [self verifyAuthHeader:[NSString stringWithFormat:@"Bearer %@", token]
                       dpopHeader:nil
                         request:nil
                        response:nil
                           error:error];
}

- (nullable ATProtoAuthVerifierPrincipal *)verifyAuthHeader:(nullable NSString *)authHeader
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
        [[GZMetrics sharedMetrics] incrementAuthFailure:@"dpop_missing"];
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

    if (isDPoP) {
        // A nil request means DPoP proof verification is impossible (no URL to
        // bind to). Reject immediately rather than silently skipping the check
        // while leaving isDPoP=true — the caller would then receive a principal
        // that reports DPoP was used when no proof was actually verified.
        if (!request) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"DPoP verification requires a request object"}];
            }
            return nil;
        }

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
        BOOL validProof = [ATProtoAuthCryptoDPoP verifyProof:dpopHeader
                                             method:request.methodString ?: @"GET"
                                                url:dpopURL
                                              nonce:nil
                                       requireNonce:self.nonceStore != nil
                                     nonceValidator:(id<AuthCryptoDPoPNonceValidator>)self.nonceStore
                                      replayChecker:self.replayChecker
                                      outThumbprint:&dpopThumbprint
                                 expectedAccessToken:token
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
            [[GZMetrics sharedMetrics] incrementAuthFailure:@"dpop_invalid"];
            return nil;
        }
    }

    ATProtoJWT *jwt = [ATProtoJWT jwtWithToken:token error:nil];
    if (!jwt) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT format"}];
        }
        [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_token"];
        return nil;
    }

    ATProtoJWTPayload *payload = jwt.payload;
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
        [[GZMetrics sharedMetrics] incrementAuthFailure:@"missing_issuer"];
        return nil;
    }

    if (!subject || ![subject hasPrefix:@"did:"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid subject claim"}];
        }
        [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_subject"];
        return nil;
    }

    BOOL isLocalIssuer = [PDSSecurityCompare constantTimeEqualString:issuer string:self.localIssuer] ||
                         [PDSSecurityCompare constantTimeEqualString:issuer string:self.expectedAudience];

    if (isLocalIssuer) {
        ATProtoJWTVerifier *verifier = [[ATProtoJWTVerifier alloc] init];
        verifier.publicKey = self.localPublicKey;
        verifier.keyManager = self.localKeyManager;
        verifier.expectedIssuer = self.localIssuer;
        verifier.expectedAudience = self.expectedAudience;
        verifier.allowedAlgorithms = @[@"ES256K", @"ES256"];
        verifier.expectedTokenUse = @"access";
        verifier.expectedTyp = @"at+jwt";

        NSError *verifyError = nil;
        if (![verifier verifyJWT:jwt error:&verifyError]) {
            if (error) {
                *error = verifyError ?: [NSError errorWithDomain:AuthVerifierErrorDomain
                                                            code:AuthVerifierErrorInvalidSignature
                                                        userInfo:@{NSLocalizedDescriptionKey: @"JWT verification failed"}];
            }
            [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_signature"];
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
            [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_issuer"];
            return nil;
        }

        // Verify signature using the fetched JWKS
        NSString *kid = jwt.header.kid;
        NSDictionary *targetKey = nil;
        NSArray *keys = jwks[@"keys"];
        if ([keys isKindOfClass:[NSArray class]]) {
            // §4.4: Require kid when JWKS has multiple keys to prevent key confusion.
            // When only one key exists, the first-key fallback is unambiguous.
            if (kid.length == 0 && keys.count > 1) {
                if (error) {
                    *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                                 code:AuthVerifierErrorInvalidSignature
                                             userInfo:@{NSLocalizedDescriptionKey: @"Multiple JWKS keys require a 'kid' claim in the token"}];
                }
                [[GZMetrics sharedMetrics] incrementAuthFailure:@"missing_kid"];
                return nil;
            }
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
            [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_signature"];
            return nil;
        }

        NSError *verifyError = nil;
        id<PDSPublicKeyProtocol> pubKey = [ATProtoAuthCryptoJWK publicKeyFromJWK:targetKey error:&verifyError];
        if (!pubKey) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidSignature
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid key in JWKS: %@", verifyError.localizedDescription]}];
            }
            [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_signature"];
            return nil;
        }

        NSData *signingInput = [jwt.signingInput dataUsingEncoding:NSUTF8StringEncoding];
        NSData *signature = [ATProtoJWT base64URLDecode:jwt.encodedSignature error:nil];
        if (![pubKey verifySignature:signature forData:signingInput error:&verifyError]) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidSignature
                                         userInfo:@{NSLocalizedDescriptionKey: @"JWT signature verification failed for remote issuer"}];
            }
            [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_signature"];
            return nil;
        }

        // After successful signature check, we still need to validate standard claims
        ATProtoJWTVerifier *claimsVerifier = [[ATProtoJWTVerifier alloc] init];
        claimsVerifier.expectedIssuer = issuer;
        claimsVerifier.expectedAudience = self.expectedAudience;
        claimsVerifier.allowedAlgorithms = @[@"ES256", @"RS256"];
        claimsVerifier.expectedTokenUse = @"access";
        claimsVerifier.expectedTyp = @"at+jwt";
        if (![claimsVerifier validateClaims:jwt.payload ofJWT:jwt error:&verifyError]) {
            if (error) *error = verifyError;
            return nil;
        }

        // §4.4: Enforce allowedAlgorithms against the ATProtoJWT's alg claim on the
        // remote-issuer path. validateClaims: does not check alg — it only
        // validates exp, nbf, iss, aud, token_use, and typ. The local-issuer
        // path enforces alg in ATProtoJWTVerifier.verifyJWT: via its own method, but
        // the remote path verifies the signature manually and needs an
        // explicit alg check here to prevent cross-algorithm confusion.
        NSString *remoteAlg = jwt.header.alg ?: @"";
        if (![claimsVerifier.allowedAlgorithms containsObject:remoteAlg]) {
            if (error) {
                *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                             code:AuthVerifierErrorInvalidSignature
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported algorithm '%@' for remote issuer", remoteAlg]}];
            }
            [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_algorithm"];
            return nil;
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AuthVerifierErrorDomain
                                         code:AuthVerifierErrorInvalidIssuer
                                     userInfo:@{NSLocalizedDescriptionKey: @"Issuer not allowed"}];
        }
        [[GZMetrics sharedMetrics] incrementAuthFailure:@"invalid_issuer"];
        return nil;
    }

    if (self.expectedAudience.length > 0 && ![PDSSecurityCompare constantTimeEqualString:audience ?: @"" string:self.expectedAudience]) {
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
        [[GZMetrics sharedMetrics] incrementAuthFailure:@"account_suspended"];
        return nil;
    }

    BOOL isAdmin = NO;
    if ([self.accountPolicy respondsToSelector:@selector(isAdmin:error:)]) {
        NSError *adminError = nil;
        isAdmin = [self.accountPolicy isAdmin:subject error:&adminError];
    }

    return [[ATProtoAuthVerifierPrincipal alloc] initWithDID:subject
                                          accessTokenJWT:token
                                           tokenClaims:claims
                                        dpopThumbprint:dpopThumbprint
                                               usedDPoP:isDPoP
                                                isAdmin:isAdmin];
}

- (nullable NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request {
    NSString *path = request.path ?: @"/";
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }

    NSString *hostHeader = [[request headerForKey:@"Host"]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *hostLower = [hostHeader lowercaseString];
    BOOL localHost = [hostLower containsString:@"localhost"] ||
                     [hostLower hasPrefix:@"127.0.0.1"] ||
                     [hostLower hasPrefix:@"[::1]"] ||
                     [hostLower isEqualToString:@"::1"];

    // §4.6: only honor X-Forwarded-Proto when the operator opted in AND the
    // immediate peer is a trusted proxy address. Otherwise the client picks
    // the scheme their DPoP proof is compared against.
    BOOL trustForwarded = AuthVerifierShouldTrustForwardedHeaders(request);

    NSString *scheme = nil;
    if (trustForwarded) {
        NSString *forwardedProto = [[request headerForKey:@"X-Forwarded-Proto"] lowercaseString];
        if (forwardedProto.length > 0) {
            NSString *firstProto = [[forwardedProto componentsSeparatedByString:@","] firstObject];
            firstProto = [firstProto stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([firstProto isEqualToString:@"http"] || [firstProto isEqualToString:@"https"]) {
                scheme = firstProto;
            }
        }
    }

    NSURL *issuerURL = [NSURL URLWithString:self.localIssuer ?: @""];
    if (scheme.length == 0) {
        if (localHost) {
            scheme = @"http";
        } else if (issuerURL.scheme.length > 0) {
            scheme = issuerURL.scheme;
        } else {
            scheme = @"https";
        }
    }

    // §4.6: production htu authority comes from the configured issuer, not the
    // client-supplied Host header. Host is accepted only for local/dev or when
    // forwarded headers are trusted from a proxy peer.
    NSString *authority = nil;
    if (issuerURL.host.length > 0 && !localHost) {
        authority = issuerURL.host;
        if (issuerURL.port != nil) {
            BOOL isDefaultPort =
                ([issuerURL.scheme.lowercaseString isEqualToString:@"https"] &&
                 issuerURL.port.integerValue == 443) ||
                ([issuerURL.scheme.lowercaseString isEqualToString:@"http"] &&
                 issuerURL.port.integerValue == 80);
            if (!isDefaultPort) {
                authority = [NSString stringWithFormat:@"%@:%@",
                             issuerURL.host, issuerURL.port];
            }
        }
    } else if (hostHeader.length > 0 && (trustForwarded || localHost)) {
        authority = hostHeader;
    } else if (hostHeader.length > 0 && issuerURL.host.length == 0) {
        // No issuer configured (misconfig / early boot): refuse rather than
        // binding htu to an unvalidated Host (literal https://(null)/… was the
        // prior failure mode when Host was also missing).
        authority = nil;
    }

    if (authority.length == 0) {
        return nil;
    }

    NSString *urlString = [NSString stringWithFormat:@"%@://%@%@", scheme, authority, path];
    if (request.queryString.length > 0) {
        urlString = [urlString stringByAppendingFormat:@"?%@", request.queryString];
    }

    return [NSURL URLWithString:urlString];
}

@end
