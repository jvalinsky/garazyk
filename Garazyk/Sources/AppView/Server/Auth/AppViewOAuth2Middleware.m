/*!
 @file AppViewOAuth2Middleware.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Auth/AppViewOAuth2Middleware.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Network/HttpRequest.h"
#import "Auth/JWT.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/CryptoUtils.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

NSErrorDomain const AppViewOAuth2MiddlewareErrorDomain = @"AppViewOAuth2Middleware";

@interface AppViewOAuth2Middleware ()

@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, copy, nullable) NSString *masterSecret;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *tokenCache;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t cacheQueue;

@end

@implementation AppViewOAuth2Middleware

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                    masterSecret:(nullable NSString *)masterSecret {
    self = [super init];
    if (self) {
        _database = database;
        _masterSecret = [masterSecret copy];
        _tokenCache = [NSMutableDictionary dictionary];
        _cacheQueue = dispatch_queue_create("com.garazyk.appview.oauth2-cache",
                                            DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (BOOL)validateRequest:(HttpRequest *)request
              callerDID:(NSString *_Nullable *_Nullable)callerDID
                   error:(NSError **)error {
    NSString *token = [self extractBearerToken:request];
    if (!token) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorInvalidToken
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Missing or invalid Authorization header"
            }];
        }
        return NO;
    }

    // Check if it's a direct DID (for dev/testing)
    for (NSString *prefix in @[@"did:plc:", @"did:web:"]) {
        if ([token hasPrefix:prefix]) {
            if (callerDID) *callerDID = token;
            return YES;
        }
    }

    // Try to parse as JWT
    NSError *jwtError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&jwtError];
    if (!jwt || !jwt.payload.sub) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorInvalidToken
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Invalid JWT token"
            }];
        }
        return NO;
    }

    // Check token expiration
    if (jwt.payload.exp) {
        if ([[NSDate date] compare:jwt.payload.exp] == NSOrderedDescending) {
            if (error) {
                *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                             code:AppViewOAuth2ErrorExpiredToken
                                         userInfo:@{
                    NSLocalizedDescriptionKey: @"Token has expired"
                }];
            }
            return NO;
        }
    }

    // Validate DPoP proof if present
    NSString *dpopHeader = [request headerForKey:@"DPoP"];
    NSString *tokenJkt = jwt.payload.cnf[@"jkt"];

    if (dpopHeader.length > 0) {
        // DPoP proof present — must verify proof and check cnf.jkt binding
        NSString *dpopThumbprint = nil;
        if (![self validateDPoPProof:request
                              token:token
                          tokenJkt:tokenJkt
                        outThumbprint:&dpopThumbprint
                             error:error]) {
            return NO;
        }
    } else if (tokenJkt.length > 0) {
        // Token is DPoP-bound but no DPoP proof provided
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorDPoPKeyMismatch
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"DPoP-bound token requires DPoP proof"
            }];
        }
        return NO;
    }

    if (callerDID) *callerDID = jwt.payload.sub;

    // Cache the validated token
    [self cacheToken:token withDID:jwt.payload.sub];

    return YES;
}

- (nullable NSString *)extractBearerToken:(HttpRequest *)request {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (![authHeader hasPrefix:@"Bearer "]) return nil;

    NSString *token = [authHeader substringFromIndex:7];
    return token.length > 0 ? token : nil;
}

- (BOOL)validateDPoPProof:(HttpRequest *)request
                    token:(NSString *)token
                tokenJkt:(nullable NSString *)tokenJkt
           outThumbprint:(NSString *_Nullable *_Nullable)outThumbprint
                   error:(NSError **)error {
    NSString *dpopHeader = [request headerForKey:@"DPoP"];
    if (dpopHeader.length == 0) {
        // No DPoP header — only valid if token is not DPoP-bound (checked by caller)
        return YES;
    }

    // Build the expected DPoP URL from the request
    NSString *method = [request methodString] ?: @"GET";
    NSString *scheme = [request headerForKey:@"X-Forwarded-Proto"] ?: @"https";
    NSString *host = [request headerForKey:@"Host"] ?: @"localhost";
    NSString *path = [request path] ?: @"/";
    NSString *urlStr = [NSString stringWithFormat:@"%@://%@%@", scheme, host, path];
    NSURL *dpopURL = [NSURL URLWithString:urlStr];

    // Verify the DPoP proof using the canonical verifier (RFC 9449)
    NSString *dpopThumbprint = nil;
    NSError *dpopError = nil;
    BOOL validProof = [AuthCryptoDPoP verifyProof:dpopHeader
                                           method:method
                                              url:dpopURL
                                            nonce:nil
                                     requireNonce:NO
                                   nonceValidator:nil
                                    replayChecker:nil
                                    outThumbprint:&dpopThumbprint
                                            error:&dpopError];

    if (!validProof) {
        PDS_LOG_AUTH_DEBUG(@"[OAuth2Middleware] DPoP proof verification failed: %@",
                           dpopError.localizedDescription ?: @"unknown");
        if (error) {
            *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                         code:AppViewOAuth2ErrorInvalidDPoPProof
                                     userInfo:@{
                NSLocalizedDescriptionKey: dpopError.localizedDescription ?: @"DPoP proof invalid"
            }];
        }
        return NO;
    }

    if (outThumbprint) *outThumbprint = dpopThumbprint;

    // Enforce DPoP binding: cnf.jkt from access token must match proof thumbprint
    if (tokenJkt.length > 0) {
        if (![CryptoUtils constantTimeCompare:tokenJkt to:dpopThumbprint]) {
            PDS_LOG_AUTH_DEBUG(@"[OAuth2Middleware] DPoP thumbprint mismatch");
            if (error) {
                *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                             code:AppViewOAuth2ErrorDPoPKeyMismatch
                                         userInfo:@{
                    NSLocalizedDescriptionKey: @"DPoP proof key does not match token binding"
                }];
            }
            return NO;
        }
    } else {
        // No cnf.jkt on token but DPoP proof provided — accept
        // (token was not DPoP-bound at issuance, but client sent proof anyway)
        PDS_LOG_AUTH_DEBUG(@"[OAuth2Middleware] DPoP proof accepted for non-DPoP-bound token");
    }

    return YES;
}

#pragma mark - Token Cache

- (void)cacheToken:(NSString *)token withDID:(NSString *)did {
    NSDictionary *entry = @{
        @"did": did,
        @"cached_at": @(floor([[NSDate date] timeIntervalSince1970]))
    };

    dispatch_barrier_async(self.cacheQueue, ^{
        self.tokenCache[token] = entry;
    });
}

- (nullable NSString *)cachedDIDForToken:(NSString *)token {
    __block NSString *did = nil;
    dispatch_sync(self.cacheQueue, ^{
        NSDictionary *entry = self.tokenCache[token];
        if (entry) {
            // Check if cache entry is still valid (5 minute TTL)
            NSTimeInterval cachedAt = [entry[@"cached_at"] doubleValue];
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if (now - cachedAt < 300.0) {
                did = entry[@"did"];
            } else {
                [self.tokenCache removeObjectForKey:token];
            }
        }
    });
    return did;
}

@end
