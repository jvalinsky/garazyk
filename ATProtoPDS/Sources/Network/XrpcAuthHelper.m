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

        // Construct DPoP URL
        NSString *host = [request headerForKey:@"Host"] ?: @"";
        NSString *scheme = nil;
        NSString *forwardedProto = [request headerForKey:@"X-Forwarded-Proto"];
        if (forwardedProto.length > 0) {
            scheme = forwardedProto;
        } else {
            NSString *lowercaseHost = [host lowercaseString];
            if ([lowercaseHost containsString:@"localhost"] || 
                [lowercaseHost hasPrefix:@"127.0.0.1"] || 
                [lowercaseHost hasPrefix:@"::1"]) {
                scheme = @"http";
            } else {
                scheme = @"https";
            }
        }

        NSMutableString *urlString = [NSMutableString string];
        if (host.length > 0) {
            [urlString appendFormat:@"%@://%@%@", scheme, host, request.path ?: @"/"];
            if (request.queryString.length > 0) {
                [urlString appendFormat:@"?%@", request.queryString];
            }
        }

        NSURL *dpopURL = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
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
                             requireNonce:YES
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
                    [response setJsonBody:@{
                        @"error": @"use_dpop_nonce",
                        @"message": dpopError.localizedDescription ?: @"DPoP nonce required"
                    }];
                }
                return nil;
            }
            PDS_LOG_AUTH_WARN(@"Invalid DPoP proof: %@", dpopError.localizedDescription ?: @"unknown error");
            return nil;
        }
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
    verifier.expectedAudience = expectedIssuer; // Ensure tokens are for this PDS instance
    verifier.allowedAlgorithms = [self allowedAlgorithmsForMinter:jwtMinter];

    // Verify the JWT
    NSError *verifyError = nil;
    BOOL isValid = [verifier verifyJWT:jwt error:&verifyError];
    if (!isValid || verifyError) {
        NSLog(@"[AuthRegistry] JWT verification failed: %@. Expected issuer: %@, JWT issuer: %@, subject: %@", 
              verifyError.localizedDescription, expectedIssuer, jwt.payload.iss, jwt.payload.sub);
        PDS_LOG_AUTH_WARN(@"JWT verification failed for request from IP: %@", request.remoteAddress ?: @"unknown");
        return nil;
    }

    // Enforce DPoP binding
    NSString *tokenJkt = jwt.payload.cnf[@"jkt"];
    if (isDPoP) {
        if (!tokenJkt) {
            NSLog(@"[AuthRegistry] DPoP used but token not bound");
            PDS_LOG_AUTH_WARN(@"DPoP authorization used with non-DPoP-bound token");
            return nil;
        }
        if (![CryptoUtils constantTimeCompare:tokenJkt to:dpopThumbprint]) {
            NSLog(@"[AuthRegistry] DPoP thumbprint mismatch");
            PDS_LOG_AUTH_WARN(@"DPoP thumbprint mismatch");
            return nil;
        }
    } else if (tokenJkt) {
        NSLog(@"[AuthRegistry] DPoP-bound token sent as Bearer");
        PDS_LOG_AUTH_WARN(@"DPoP-bound token sent as Bearer token");
        return nil;
    }

    // Extract DID from subject claim
    NSString *did = jwt.payload.sub;
    NSLog(@"[AuthRegistry] Validated JWT for subject: %@", did);
    if (!did || ![did hasPrefix:@"did:"]) {
        NSLog(@"[AuthRegistry] Invalid DID in subject: %@", did);
        PDS_LOG_AUTH_WARN(@"Invalid DID in JWT subject claim: %@", did);
        return nil;
    }

    // Check takedown status
    NSError *takedownError = nil;
    BOOL isTakedown = [adminController isAccountTakedownActive:did error:&takedownError];
    if (takedownError) {
        PDS_LOG_AUTH_WARN(@"Failed to check takedown status for %@: %@", did, takedownError.localizedDescription);
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
