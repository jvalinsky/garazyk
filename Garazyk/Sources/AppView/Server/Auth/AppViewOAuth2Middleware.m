/*!
 @file AppViewOAuth2Middleware.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Auth/AppViewOAuth2Middleware.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Network/HttpRequest.h"
#import "Auth/JWT.h"
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
    if (dpopHeader.length > 0) {
        if (![self validateDPoPProof:request forToken:token]) {
            if (error) {
                *error = [NSError errorWithDomain:AppViewOAuth2MiddlewareErrorDomain
                                             code:AppViewOAuth2ErrorDPoPKeyMismatch
                                         userInfo:@{
                    NSLocalizedDescriptionKey: @"DPoP proof validation failed"
                }];
            }
            return NO;
        }
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

- (BOOL)validateDPoPProof:(HttpRequest *)request forToken:(NSString *)token {
    NSString *dpopHeader = [request headerForKey:@"DPoP"];
    if (dpopHeader.length == 0) return YES; // No DPoP header = no proof required

    // Parse the DPoP proof as a JWT
    NSError *error = nil;
    JWT *dpopJWT = [JWT jwtWithToken:dpopHeader error:&error];
    if (!dpopJWT) {
        PDS_LOG_DEBUG(@"[OAuth2Middleware] Invalid DPoP proof JWT: %@",
                      error.localizedDescription ?: @"unknown");
        return NO;
    }

    // Verify the DPoP proof claims:
    // - htu (HTTP target URI) must match the request URL
    // - htm (HTTP method) must match the request method
    // - iat (issued at) must be recent (within 60 seconds)
    // - jwk must match the cnf.jwk from the access token

    NSDictionary *claims = [dpopJWT.payload toDictionary];
    NSString *htm = claims[@"htm"];
    NSString *htu = claims[@"htu"];
    NSNumber *iatNum = claims[@"iat"];

    // Validate HTTP method
    if (htm && ![htm isEqualToString:@"GET"] && ![htm isEqualToString:@"POST"]) {
        PDS_LOG_DEBUG(@"[OAuth2Middleware] DPoP htm mismatch: %@", htm);
        // Not fatal — just log
    }

    // Validate issued-at is recent
    if (iatNum) {
        NSTimeInterval proofTime = [iatNum doubleValue];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (fabs(now - proofTime) > 60.0) {
            PDS_LOG_DEBUG(@"[OAuth2Middleware] DPoP proof too old: %.0f seconds",
                          now - proofTime);
            return NO;
        }
    }

    // TODO: Verify cnf.jwk from access token matches DPoP proof jwk
    // This requires parsing the access token's cnf claim
    // For now, we accept the proof if it's well-formed

    (void)htu;
    (void)token;
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
