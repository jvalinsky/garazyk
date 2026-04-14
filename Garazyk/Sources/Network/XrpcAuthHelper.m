//
//  XrpcAuthHelper.m
//  ATProtoPDS
//
//  Authentication helper implementation for XRPC endpoints.
//

#import "Network/XrpcAuthHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/CryptoUtils.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Admin/PDSAdminController.h"
#import "Admin/PDSAdminAuth.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"

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

static BOOL XrpcAuthShouldTrustForwardedHeaders(HttpRequest *request) {
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

static void XrpcAuthAttachDPoPNonceToResponseIfMissing(HttpResponse *response) {
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

static NSURL *XrpcAuthExpectedDPoPURL(HttpRequest *request, JWTMinter *jwtMinter) {
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

    PDSConfiguration *configuration = [PDSConfiguration sharedConfiguration];
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
    if (hostHeader.length > 0 && (trustForwarded || localHostHeader)) {
        authority = hostHeader;
    } else if (issuerURL.host.length > 0) {
        authority = issuerURL.host;
        if (issuerURL.port != nil) {
            BOOL isDefaultPort = ([issuerURL.scheme.lowercaseString isEqualToString:@"https"] && issuerURL.port.integerValue == 443) ||
                                 ([issuerURL.scheme.lowercaseString isEqualToString:@"http"] && issuerURL.port.integerValue == 80);
            if (!isDefaultPort) {
                authority = [NSString stringWithFormat:@"%@:%@", issuerURL.host, issuerURL.port];
            }
        }
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

#pragma mark - Public Methods

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request {
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:jwtMinter
                         adminController:adminController
                                 request:request
                                response:nil];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response {
    if (!authHeader) return nil;
    
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
        return nil;
    }

    // DPoP verification
    NSString *dpopThumbprint = nil;
    if (isDPoP) {
        NSString *dpopProof = [request headerForKey:@"DPoP"];
        if (dpopProof.length == 0) {
            PDS_LOG_AUTH_WARN(@"Missing DPoP header for DPoP authorization");
            return nil;
        }

        NSURL *dpopURL = XrpcAuthExpectedDPoPURL(request, jwtMinter);
        if (!dpopURL) {
            PDS_LOG_AUTH_WARN(@"Unable to construct DPoP URL for request");
            return nil;
        }

        // Verify DPoP proof
        NSError *dpopError = nil;
        if (![OAuth2DPoPProof verifyProof:dpopProof
                                   method:request.methodString
                                      url:dpopURL
                                    nonce:nil
                             requireNonce:[PDSConfiguration sharedConfiguration].requireDPoPNonce
                            outThumbprint:&dpopThumbprint
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
            PDS_LOG_AUTH_WARN(@"Invalid DPoP proof (%@)", XrpcAuthSanitizedErrorSummary(dpopError));
            return nil;
        }

        XrpcAuthAttachDPoPNonceToResponseIfMissing(response);
    }

    // Parse the JWT token
    NSError *parseError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&parseError];
    if (!jwt || parseError) {
        PDS_LOG_HTTP_WARN(@"Failed to parse JWT token from authorization header");
        return nil;
    }

    // Create verifier and set expected issuer
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    if (jwtMinter) {
        verifier.keyManager = jwtMinter.keyManager;
        verifier.publicKey = jwtMinter.publicKey;
    }

    // Use configurable issuer from PDSConfiguration, default to localhost
    PDSConfiguration *configuration = [PDSConfiguration sharedConfiguration];
    NSString *expectedIssuer = jwtMinter.issuer ?: [configuration canonicalIssuerWithPortHint:0];
    verifier.expectedIssuer = expectedIssuer;
    // Do not set expectedAudience here; we do custom validation to support did:web variants
    verifier.allowedAlgorithms = [self allowedAlgorithmsForMinter:jwtMinter];

    // Verify the JWT
    NSError *verifyError = nil;
    BOOL isValid = [verifier verifyJWT:jwt error:&verifyError];
    if (!isValid || verifyError) {
        PDS_LOG_AUTH_WARN(@"JWT verification failed for request from IP: %@", request.remoteAddress ?: @"unknown");
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
            PDS_LOG_AUTH_WARN(@"JWT verification failed due to invalid audience: %@", tokenAud);
            return nil;
        }
    }

    // Enforce DPoP binding
    NSString *tokenJkt = jwt.payload.cnf[@"jkt"];
    if (isDPoP) {
        if (!tokenJkt) {
            PDS_LOG_AUTH_WARN(@"DPoP authorization used with non-DPoP-bound token");
            return nil;
        }
        if (![CryptoUtils constantTimeCompare:tokenJkt to:dpopThumbprint]) {
            PDS_LOG_AUTH_WARN(@"DPoP thumbprint mismatch");
            return nil;
        }
    } else if (tokenJkt) {
        PDS_LOG_AUTH_WARN(@"DPoP-bound token sent as Bearer token");
        return nil;
    }

    // Extract DID from subject claim
    NSString *did = jwt.payload.sub;
    if (!did || ![did hasPrefix:@"did:"]) {
        PDS_LOG_AUTH_WARN(@"Invalid DID in JWT subject claim");
        return nil;
    }

    // Check takedown status
    NSError *takedownError = nil;
    BOOL isTakedown = [adminController isAccountTakedownActive:did error:&takedownError];
    if (takedownError) {
        PDS_LOG_AUTH_WARN(@"Failed to check takedown status (%@)", XrpcAuthSanitizedErrorSummary(takedownError));
        return nil;
    }
    if (isTakedown) {
        PDS_LOG_AUTH_WARN(@"Rejected request for suspended account %@", did);
        return nil;
    }

    return did;
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                            controller:(PDSController *)controller
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response {
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:controller.jwtMinter
                         adminController:controller.adminController
                                 request:request
                                response:response];
}

+ (BOOL)authorizeAdminRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
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

+ (NSArray<NSString *> *)allowedAlgorithmsForMinter:(JWTMinter *)minter {
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
