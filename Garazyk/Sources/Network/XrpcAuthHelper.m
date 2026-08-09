// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAuthHelper.m
//  ATProtoPDS
//
//  Authentication helper implementation for XRPC endpoints.
//

#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/Crypto/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/PDSReplayCache.h"
#import "Auth/Crypto/CryptoUtils.h"
#import "Auth/Verifier/AuthVerifier.h"
#import "App/ATProtoServiceConfiguration.h"
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Services/PDS/PDSAccountService.h"
#import "Admin/PDSAdminController.h"
#import "Admin/PDSAdminAuth.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Core/Repositories/PDSSessionRepository.h"
#import "Debug/GZLogger.h"

/*!
 @abstract Whether the new ATProtoAuthVerifier cluster should be used instead of the
    legacy XrpcAuthHelper path. Controlled by the PDS_USE_AUTH_VERIFIER env var.
    When enabled, authentication routes through ATProtoAuthVerifier/PDSAccountPolicy.
    When disabled (default), the legacy XrpcAuthHelper path is used.
    This switch allows safe cutover with zero-rebuild rollback.
 */
static BOOL XrpcAuthUseAuthVerifier(void) {
    static BOOL checked = NO;
    static BOOL useVerifier = NO;
    if (!checked) {
        NSString *value = [[[NSProcessInfo processInfo] environment][@"PDS_USE_AUTH_VERIFIER"] lowercaseString];
        useVerifier = [value isEqualToString:@"1"] || [value isEqualToString:@"true"] || [value isEqualToString:@"yes"];
        if (useVerifier) {
            GZ_LOG_AUTH_INFO(@"ATProtoAuthVerifier cluster enabled via PDS_USE_AUTH_VERIFIER");
        }
        checked = YES;
    }
    return useVerifier;
}

static BOOL XrpcAuthEnvBool(NSString *value) {
    if (value.length == 0) {
        return NO;
    }
    NSString *normalized = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [normalized isEqualToString:@"1"] ||
           [normalized isEqualToString:@"true"] ||
           [normalized isEqualToString:@"yes"] ||
           [normalized isEqualToString:@"on"];
}

static BOOL XrpcAuthIsTrustedProxyRemoteAddress(NSString *remoteAddress) {
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

static BOOL XrpcAuthShouldTrustForwardedHeaders(ATProtoHttpRequest *request) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if (!XrpcAuthEnvBool(env[@"PDS_TRUST_PROXY_HEADERS"])) {
        return NO;
    }
    return XrpcAuthIsTrustedProxyRemoteAddress(request.remoteAddress);
}

static NSString *XrpcAuthSanitizedErrorSummary(NSError *error) {
    if (!error) {
        return @"domain=unknown code=0";
    }
    return [NSString stringWithFormat:@"domain=%@ code=%ld",
                                      error.domain ?: @"unknown",
                                      (long)error.code];
}

static void XrpcAuthAttachDPoPNonceToResponseIfMissing(ATProtoHttpResponse *response) {
    if (!response) {
        return;
    }
    NSString *existingNonce = [response headerForKey:@"DPoP-Nonce"];
    if (existingNonce.length > 0) {
        return;
    }
    NSString *nextNonce = [[PDSNonceManager sharedManager] generateNonce];
    if (nextNonce.length > 0) {
        [response setHeader:nextNonce forKey:@"DPoP-Nonce"];
    }
}

static NSURL *XrpcAuthExpectedDPoPURL(ATProtoHttpRequest *request, ATProtoJWTMinter *jwtMinter) {
    NSString *hostHeader = [[request headerForKey:@"Host"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *hostLower = [hostHeader lowercaseString];
    BOOL localHostHeader = [hostLower containsString:@"localhost"] ||
                           [hostLower hasPrefix:@"127.0.0.1"] ||
                           [hostLower hasPrefix:@"[::1]"] ||
                           [hostLower isEqualToString:@"::1"];
    BOOL trustForwarded = XrpcAuthShouldTrustForwardedHeaders(request);

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

    ATProtoServiceConfiguration *configuration = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *issuer = jwtMinter.issuer ?: [configuration canonicalIssuerWithPortHint:0];
    NSURL *issuerURL = [NSURL URLWithString:issuer ?: @""];
    if (scheme.length == 0) {
        if (localHostHeader) {
            scheme = @"http";
        } else if (issuerURL.scheme.length > 0) {
            scheme = issuerURL.scheme;
        } else {
            scheme = @"https";
        }
    }

    NSString *authority = nil;
    // Authoritative source: use the configured issuer URL when available.
    // The issuer URL is the trusted source of truth for the expected host.
    // Only fall back to the Host header in local development (no issuer configured).
    if (issuerURL.host.length > 0) {
        authority = issuerURL.host;
        if (issuerURL.port != nil) {
            BOOL isDefaultPort = ([issuerURL.scheme.lowercaseString isEqualToString:@"https"] && issuerURL.port.integerValue == 443) ||
                                 ([issuerURL.scheme.lowercaseString isEqualToString:@"http"] && issuerURL.port.integerValue == 80);
            if (!isDefaultPort) {
                authority = [NSString stringWithFormat:@"%@:%@", issuerURL.host, issuerURL.port];
            }
        }
    } else if (hostHeader.length > 0 && (trustForwarded || localHostHeader)) {
        // Without an issuer URL (e.g. local dev), accept the Host header from trusted sources.
        authority = hostHeader;
    }
    if (authority.length == 0) {
        return nil;
    }

    NSMutableString *urlString = [NSMutableString stringWithFormat:@"%@://%@%@", scheme, authority, request.path ?: @"/"];
    if (request.queryString.length > 0) {
        [urlString appendFormat:@"?%@", request.queryString];
    }
    return [NSURL URLWithString:urlString];
}

@implementation XrpcAuthHelper

#pragma mark - Private Helpers

+ (void)setAuthRequiredResponse:(ATProtoHttpResponse *)response {
    if (response && response.statusCode == HttpStatusOK) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"AuthRequired",
            @"message": @"Authentication required"
        }];
    }
}

#pragma mark - Public Methods

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(ATProtoJWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(ATProtoHttpRequest *)request {
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:jwtMinter
                         adminController:adminController
                                 request:request
                                response:nil];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(ATProtoJWTMinter *)jwtMinter
                       adminController:(nullable id<PDSAdminController>)adminController
                               request:(ATProtoHttpRequest *)request
                              response:(nullable ATProtoHttpResponse *)response {
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:jwtMinter
                         adminController:adminController
                       sessionRepository:nil
                                 request:request
                                response:response];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(ATProtoJWTMinter *)jwtMinter
                       adminController:(nullable id<PDSAdminController>)adminController
                     sessionRepository:(nullable id<PDSSessionRepository>)sessionRepository
                               request:(ATProtoHttpRequest *)request
                              response:(nullable ATProtoHttpResponse *)response {

    if (!authHeader) {
        [self setAuthRequiredResponse:response];
        return nil;
    }
    
    // Parse Bearer or DPoP token
    NSString *token = nil;
    BOOL isDPoP = NO;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
        if ([request headerForKey:@"DPoP"].length > 0) {
            isDPoP = YES; // Some clients send Bearer but attach a DPoP header
        }
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
        isDPoP = YES;
    } else {
        [self setAuthRequiredResponse:response];
        return nil;
    }

    // DPoP verification
    NSString *dpopThumbprint = nil;
    if (isDPoP) {
        NSString *dpopProof = [request headerForKey:@"DPoP"];
        if (dpopProof.length == 0) {
            GZ_LOG_AUTH_WARN(@"Missing DPoP header for DPoP authorization");
            [self setAuthRequiredResponse:response];
            return nil;
        }

        NSURL *dpopURL = XrpcAuthExpectedDPoPURL(request, jwtMinter);
        if (!dpopURL) {
            GZ_LOG_AUTH_WARN(@"Unable to construct DPoP URL for request");
            [self setAuthRequiredResponse:response];
            return nil;
        }

        // Verify DPoP proof (bind to access token via ath per RFC 9449 §4.3 / §4.2)
        NSError *dpopError = nil;
        if (![OAuth2DPoPProof verifyProof:dpopProof
                                   method:request.methodString
                                      url:dpopURL
                                    nonce:nil
                             requireNonce:[ATProtoServiceConfiguration sharedConfiguration].requireDPoPNonce
                            outThumbprint:&dpopThumbprint
                      expectedAccessToken:token
                                    error:&dpopError]) {
            if ([dpopError.userInfo[@"use_dpop_nonce"] boolValue]) {
                if (response) {
                    response.statusCode = HttpStatusUnauthorized;
                    NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
                    if (nonce.length > 0) {
                        [response setHeader:nonce forKey:@"DPoP-Nonce"];
                    }
                    [response setHeader:@"DPoP error=\"use_dpop_nonce\"" forKey:@"WWW-Authenticate"];
                    [response setHeader:@"no-store" forKey:@"Cache-Control"];
                    [response setHeader:@"no-cache" forKey:@"Pragma"];
                    [response setJsonBody:@{
                        @"error": @"use_dpop_nonce",
                        @"message": @"DPoP nonce required"
                    }];
                }
                return nil;
            }
            GZ_LOG_AUTH_WARN(@"Invalid DPoP proof (%@)", XrpcAuthSanitizedErrorSummary(dpopError));
            [self setAuthRequiredResponse:response];
            return nil;
        }

        XrpcAuthAttachDPoPNonceToResponseIfMissing(response);
    }

    // Parse the ATProtoJWT token
    NSError *parseError = nil;
    ATProtoJWT *jwt = [ATProtoJWT jwtWithToken:token error:&parseError];
    if (!jwt || parseError) {
        GZ_LOG_HTTP_WARN(@"Failed to parse JWT token from authorization header");
        [self setAuthRequiredResponse:response];
        return nil;
    }

    // Create verifier and set expected issuer
    ATProtoJWTVerifier *verifier = [[ATProtoJWTVerifier alloc] init];
    if (jwtMinter) {
        verifier.keyManager = jwtMinter.keyManager;
        verifier.publicKey = jwtMinter.publicKey;
    }

    // Use configurable issuer from ATProtoServiceConfiguration, default to localhost
    ATProtoServiceConfiguration *configuration = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *expectedIssuer = jwtMinter.issuer ?: [configuration canonicalIssuerWithPortHint:0];
    verifier.expectedIssuer = expectedIssuer;
    // Do not set expectedAudience here; we do custom validation to support did:web variants
    verifier.allowedAlgorithms = [self allowedAlgorithmsForMinter:jwtMinter];

    // Verify the ATProtoJWT
    NSError *verifyError = nil;
    BOOL isValid = [verifier verifyJWT:jwt error:&verifyError];
    if (!isValid || verifyError) {
        GZ_LOG_AUTH_WARN(@"JWT verification failed for request from IP: %@", request.remoteAddress ?: @"unknown");
        [self setAuthRequiredResponse:response];
        return nil;
    }

    // Custom Audience Verification
    NSString *tokenAud = jwt.payload.aud;
    if (tokenAud) {
        BOOL validAud = [tokenAud isEqualToString:expectedIssuer];
        if (!validAud) {
            NSURL *issuerURL = [NSURL URLWithString:expectedIssuer];
            if (issuerURL.host) {
                NSString *didWebHost = [NSString stringWithFormat:@"did:web:%@", issuerURL.host];
                NSString *didWebHostPort = nil;
                if (issuerURL.port) {
                    didWebHostPort = [NSString stringWithFormat:@"did:web:%@%%3A%@", issuerURL.host, issuerURL.port];
                }
                if ([tokenAud isEqualToString:didWebHost] || (didWebHostPort && [tokenAud isEqualToString:didWebHostPort])) {
                    validAud = YES;
                }
            }
        }
        if (!validAud) {
            GZ_LOG_AUTH_WARN(@"JWT verification failed due to invalid audience: %@", tokenAud);
            [self setAuthRequiredResponse:response];
            return nil;
        }
    }

    // Enforce DPoP binding
    NSString *tokenJkt = jwt.payload.cnf[@"jkt"];
    if (isDPoP) {
        if (!tokenJkt) {
            GZ_LOG_AUTH_WARN(@"DPoP authorization used with non-DPoP-bound token");
            [self setAuthRequiredResponse:response];
            return nil;
        }
        if (![ATProtoCryptoUtils constantTimeCompare:tokenJkt to:dpopThumbprint]) {
            GZ_LOG_AUTH_WARN(@"DPoP thumbprint mismatch");
            [self setAuthRequiredResponse:response];
            return nil;
        }
    } else if (tokenJkt) {
        GZ_LOG_AUTH_WARN(@"DPoP-bound token sent as Bearer token");
        [self setAuthRequiredResponse:response];
        return nil;
    }

    // Extract DID from subject claim
    NSString *did = jwt.payload.sub;
    if (!did || ![did hasPrefix:@"did:"]) {
        GZ_LOG_AUTH_WARN(@"Invalid DID in JWT subject claim");
        [self setAuthRequiredResponse:response];
        return nil;
    }

    // Check session revocation
    NSString *sid = jwt.payload.sid;
    if (sid && sessionRepository) {
        NSError *sessionError = nil;
        if (![sessionRepository isSessionActive:sid forAccountDid:did error:&sessionError]) {
            GZ_LOG_HTTP_WARN(@"JWT session revoked: sid=%@, did=%@", sid, did);
            if (response) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"ExpiredToken", @"message": @"Session has been revoked"}];
            }
            return nil;
        }
    }

    // Check takedown status
    NSError *takedownError = nil;
    BOOL isTakedown = [adminController isAccountTakedownActive:did error:&takedownError];
    if (takedownError) {
        GZ_LOG_AUTH_WARN(@"Failed to check takedown status (%@) — allowing request",
                         XrpcAuthSanitizedErrorSummary(takedownError));
        // Database unavailable: allow request through rather than blocking all access.
        // The takedown check is defense-in-depth; if the DB is down, blocking everything
        // would be worse than allowing a potentially-taken-down account through.
    } else if (isTakedown) {
        GZ_LOG_AUTH_WARN(@"Rejected request for suspended account %@", did);
        [self setAuthRequiredResponse:response];
        return nil;
    }

    return did;
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                            controller:(PDSController *)controller
                               request:(ATProtoHttpRequest *)request
                              response:(ATProtoHttpResponse *)response {
    // When the ATProtoAuthVerifier switch is on, delegate to the application-owned verifier.
    if (XrpcAuthUseAuthVerifier()) {
        ATProtoAuthVerifier *verifier = controller.application.authVerifier;
        if (!verifier) {
            GZ_LOG_CORE_ERROR(@"ATProtoAuthVerifier requested but not available — rejecting request");
            [self setAuthRequiredResponse:response];
            return nil;
        } else {
            NSError *verifierError = nil;
            ATProtoAuthVerifierPrincipal *principal = [verifier verifyRequest:request
                                                              response:response
                                                                 error:&verifierError];
            if (principal) {
                GZ_LOG_AUTH_DEBUG(@"ATProtoAuthVerifier: authenticated %@ (admin=%d, dpop=%d)",
                                   principal.did, principal.isAdmin, principal.usedDPoP);
                return principal.did;
            }
            // ATProtoAuthVerifier rejected — fall through to legacy path for parity comparison
            GZ_LOG_AUTH_WARN(@"ATProtoAuthVerifier rejected (%@) — checking legacy path",
                              XrpcAuthSanitizedErrorSummary(verifierError));
        }
    }

    // Legacy path
    id<PDSSessionRepository> sessionRepo = nil;
    if ([controller.accountService respondsToSelector:@selector(sessionRepository)]) {
        sessionRepo = controller.accountService.sessionRepository;
    }
    
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:controller.jwtMinter
                         adminController:controller.adminController
                       sessionRepository:sessionRepo
                                 request:request
                                response:response];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                              services:(id<XrpcRoutePackServices>)services
                               request:(ATProtoHttpRequest *)request
                              response:(nullable ATProtoHttpResponse *)response {
    // When the ATProtoAuthVerifier switch is on, delegate to the registry-injected verifier.
    if (XrpcAuthUseAuthVerifier()) {
        ATProtoAuthVerifier *verifier = services.authVerifier;
        if (!verifier) {
            GZ_LOG_CORE_ERROR(@"ATProtoAuthVerifier requested but route services did not provide one — rejecting request");
            [self setAuthRequiredResponse:response];
            return nil;
        }
        if (verifier) {
            NSError *verifierError = nil;
            ATProtoAuthVerifierPrincipal *principal = [verifier verifyRequest:request
                                                              response:response
                                                                 error:&verifierError];
            if (principal) {
                GZ_LOG_AUTH_DEBUG(@"ATProtoAuthVerifier (services): authenticated %@ (admin=%d, dpop=%d)",
                                   principal.did, principal.isAdmin, principal.usedDPoP);
                return principal.did;
            }
            GZ_LOG_AUTH_WARN(@"ATProtoAuthVerifier (services) rejected (%@) — checking legacy path",
                              XrpcAuthSanitizedErrorSummary(verifierError));
        }
    }

    id<PDSSessionRepository> sessionRepo = nil;
    if ([services.accountService respondsToSelector:@selector(sessionRepository)]) {
        sessionRepo = services.accountService.sessionRepository;
    }

    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:services.jwtMinter
                         adminController:services.adminController
                       sessionRepository:sessionRepo
                                 request:request
                                response:response];
}

+ (BOOL)authorizeAdminRequest:(ATProtoHttpRequest *)request
                      response:(ATProtoHttpResponse *)response
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(ATProtoJWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [self extractDIDFromAuthHeader:authHeader
                                        jwtMinter:jwtMinter
                                  adminController:adminController
                                          request:request];
    if (!did) {
        if (response.statusCode == HttpStatusOK) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", 
                                   @"message": @"Admin authentication required"}];
        }
        return NO;
    }

    NSError *dbError = nil;
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:&dbError];
    if (!db) {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": @"DatabaseUnavailable", 
                               @"message": dbError.localizedDescription ?: @"Failed to open service database"}];
        return NO;
    }

    PDSAdminAuth *adminAuth = [PDSAdminAuth sharedAuth];
    NSError *authError = nil;
    if (![adminAuth isAuthenticatedWithRequest:request.headers]) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{@"error": @"Forbidden", 
                               @"message": @"Admin privileges required (valid admin token)"}];
        return NO;
    }
    
    return YES;
}

#pragma mark - Private Helpers

+ (NSArray<NSString *> *)allowedAlgorithmsForMinter:(ATProtoJWTMinter *)minter {
    if (!minter) {
        return nil;
    }

    NSMutableOrderedSet<NSString *> *algorithms = [NSMutableOrderedSet orderedSet];
    NSString *configuredAlgorithm = [[minter.signingAlgorithm 
                                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] 
                                     uppercaseString];
    if (configuredAlgorithm.length > 0) {
        [algorithms addObject:configuredAlgorithm];
    }

    if (minter.keyManager) {
        [algorithms addObjectsFromArray:@[@"ES256", @"RS256"]];
    }

    if (algorithms.count == 0 && minter.publicKey) {
        [algorithms addObject:@"ES256K"];
    }

    return algorithms.count > 0 ? algorithms.array : nil;
}

@end
