// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcMiddleware.m
//  ATProtoPDS
//
//  Declarative middleware system implementation.
//

#import "Network/XrpcMiddleware.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/RateLimiter.h"
#import "App/PDSController.h"
#import "Admin/PDSAdminController.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"

NSString * const XrpcMiddlewareErrorDomain = @"com.atproto.pds.middleware";

#pragma mark - XrpcMiddlewareChain

@interface XrpcMiddlewareChain ()
@property (nonatomic, strong) NSMutableArray<id<XrpcMiddleware>> *middlewares;
@end

@implementation XrpcMiddlewareChain

- (instancetype)init {
    if ((self = [super init])) {
        _middlewares = [NSMutableArray array];
    }
    return self;
}

- (NSString *)middlewareName {
    return @"Chain";
}

- (NSUInteger)count {
    return self.middlewares.count;
}

- (void)addMiddleware:(id<XrpcMiddleware>)middleware {
    [self.middlewares addObject:middleware];
}

- (void)addMiddlewares:(NSArray<id<XrpcMiddleware>> *)middlewares {
    [self.middlewares addObjectsFromArray:middlewares];
}

- (BOOL)handleRequest:(HttpRequest *)request
             response:(HttpResponse *)response
                error:(NSError **)error {
    for (id<XrpcMiddleware> middleware in self.middlewares) {
        NSError *middlewareError = nil;
        BOOL shouldContinue = [middleware handleRequest:request
                                               response:response
                                                  error:&middlewareError];
        if (!shouldContinue) {
            if (error) {
                *error = middlewareError ?: [NSError errorWithDomain:XrpcMiddlewareErrorDomain
                                                                code:XrpcMiddlewareErrorInternal
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Middleware rejected request"}];
            }
            return NO;
        }
    }
    return YES;
}

@end

#pragma mark - AuthMiddleware

@interface AuthMiddleware ()
@property (nonatomic, strong, nullable) PDSController *controller;
@property (nonatomic, strong, nullable) JWTMinter *jwtMinter;
@property (nonatomic, strong, nullable) id<PDSAdminController> adminController;
@property (nonatomic, strong, nullable) id serviceDatabases;
@property (nonatomic, assign) BOOL requireAdmin;
@end

@implementation AuthMiddleware

- (NSString *)middlewareName {
    return self.requireAdmin ? @"AdminAuth" : @"UserAuth";
}

+ (instancetype)userAuthWithController:(PDSController *)controller {
    AuthMiddleware *middleware = [[AuthMiddleware alloc] init];
    middleware.controller = controller;
    middleware.requireAdmin = NO;
    return middleware;
}

+ (instancetype)adminAuthWithController:(PDSController *)controller
                        serviceDatabases:(id)serviceDatabases {
    AuthMiddleware *middleware = [[AuthMiddleware alloc] init];
    middleware.controller = controller;
    middleware.serviceDatabases = serviceDatabases;
    middleware.requireAdmin = YES;
    return middleware;
}

+ (instancetype)userAuthWithJwtMinter:(JWTMinter *)jwtMinter
                     adminController:(id<PDSAdminController>)adminController {
    AuthMiddleware *middleware = [[AuthMiddleware alloc] init];
    middleware.jwtMinter = jwtMinter;
    middleware.adminController = adminController;
    middleware.requireAdmin = NO;
    return middleware;
}

- (BOOL)handleRequest:(HttpRequest *)request
             response:(HttpResponse *)response
                error:(NSError **)error {
    // Get auth components
    JWTMinter *jwtMinter = self.jwtMinter ?: self.controller.jwtMinter;
    id<PDSAdminController> adminController = self.adminController ?: self.controller.adminController;

    if (!jwtMinter || !adminController) {
        if (error) {
            *error = [NSError errorWithDomain:XrpcMiddlewareErrorDomain
                                         code:XrpcMiddlewareErrorInternal
                                     userInfo:@{NSLocalizedDescriptionKey: @"Server not configured for authentication"}];
        }
        PDS_LOG_AUTH_WARN(@"AuthMiddleware: Server not configured for authentication");
        return NO;
    }

    NSString *authHeader = [request headerForKey:@"Authorization"];

    if (self.requireAdmin) {
        // Admin auth: validate JWT + check admin privileges
        BOOL authorized = [XrpcAuthHelper authorizeAdminRequest:request
                                                       response:response
                                               serviceDatabases:self.serviceDatabases
                                                      jwtMinter:jwtMinter
                                                adminController:adminController];
        if (!authorized) {
            if (error) {
                *error = [NSError errorWithDomain:XrpcMiddlewareErrorDomain
                                             code:XrpcMiddlewareErrorAdminRequired
                                         userInfo:@{NSLocalizedDescriptionKey: @"Admin privileges required"}];
            }
            return NO;
        }

        // Extract DID for downstream use
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:nil];
        if (did) {
            // Inject authenticated DID into request for downstream handlers
            request.authenticatedDid = did;
        }

        return YES;
    } else {
        // User auth: validate JWT, extract DID
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            if (error) {
                *error = [NSError errorWithDomain:XrpcMiddlewareErrorDomain
                                             code:XrpcMiddlewareErrorAuthRequired
                                         userInfo:@{NSLocalizedDescriptionKey: @"Authentication required"}];
            }
            return NO;
        }

        // Inject authenticated DID into request for downstream handlers
        request.authenticatedDid = did;
        return YES;
    }
}

@end

#pragma mark - RateLimitMiddleware

@interface RateLimitMiddleware ()
@property (nonatomic, assign) NSInteger limit;
@property (nonatomic, assign) NSTimeInterval windowSeconds;
@property (nonatomic, assign) BOOL perUser; // NO = per IP
@property (nonatomic, strong) RateLimiter *limiter;
@end

@implementation RateLimitMiddleware

- (NSString *)middlewareName {
    return self.perUser ? @"RateLimitPerUser" : @"RateLimitPerIP";
}

+ (instancetype)perUser:(NSInteger)limit perWindow:(NSTimeInterval)windowSeconds {
    RateLimitMiddleware *middleware = [[RateLimitMiddleware alloc] init];
    middleware.limit = limit;
    middleware.windowSeconds = windowSeconds;
    middleware.perUser = YES;
    middleware.limiter = [RateLimiter sharedLimiter];
    return middleware;
}

+ (instancetype)perIP:(NSInteger)limit perWindow:(NSTimeInterval)windowSeconds {
    RateLimitMiddleware *middleware = [[RateLimitMiddleware alloc] init];
    middleware.limit = limit;
    middleware.windowSeconds = windowSeconds;
    middleware.perUser = NO;
    middleware.limiter = [RateLimiter sharedLimiter];
    return middleware;
}

- (BOOL)handleRequest:(HttpRequest *)request
             response:(HttpResponse *)response
                error:(NSError **)error {
    NSString *key = nil;
    NSString *identifier = nil;

    if (self.perUser) {
        // Get authenticated DID from middleware context (injected by AuthMiddleware)
        identifier = request.authenticatedDid;
        if (!identifier) {
            // No authenticated user - can't rate limit per user
            // Fall back to IP-based limiting
            identifier = request.remoteAddress ?: @"unknown";
        }
        key = [NSString stringWithFormat:@"ratelimit:user:%@:%.0f", identifier, self.windowSeconds];
    } else {
        identifier = request.remoteAddress ?: @"unknown";
        key = [NSString stringWithFormat:@"ratelimit:ip:%@:%.0f", identifier, self.windowSeconds];
    }

    RateLimitResult *result = [self.limiter checkRateLimitForKey:key
                                                           limit:self.limit
                                                    windowSeconds:self.windowSeconds];

    if (!result.allowed) {
        response.statusCode = HttpStatusTooManyRequests;
        [response setJsonBody:@{
            @"error": @"RateLimitExceeded",
            @"message": [NSString stringWithFormat:@"Rate limit exceeded (%ld per %.0f seconds)",
                                                      (long)self.limit, self.windowSeconds]
        }];
        [response setHeader:[NSString stringWithFormat:@"%.0f", result.retryAfter]
                     forKey:@"Retry-After"];

        if (error) {
            *error = [NSError errorWithDomain:XrpcMiddlewareErrorDomain
                                         code:XrpcMiddlewareErrorRateLimited
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Rate limit exceeded",
                                         @"retryAfter": @(result.retryAfter)
                                     }];
        }
        return NO;
    }

    return YES;
}

@end

#pragma mark - ResourceOwnershipMiddleware

@interface ResourceOwnershipMiddleware ()
@property (nonatomic, copy) NSString *paramName;
@property (nonatomic, assign) BOOL fromBody;
@property (nonatomic, assign) BOOL isRecord; // NO = repo, YES = record
@end

@implementation ResourceOwnershipMiddleware

- (NSString *)middlewareName {
    return self.isRecord ? @"ResourceOwnership(Record)" : @"ResourceOwnership(Repo)";
}

+ (instancetype)ownsRepoFromParam:(NSString *)paramName fromBody:(BOOL)fromBody {
    ResourceOwnershipMiddleware *middleware = [[ResourceOwnershipMiddleware alloc] init];
    middleware.paramName = paramName;
    middleware.fromBody = fromBody;
    middleware.isRecord = NO;
    return middleware;
}

+ (instancetype)ownsRecordFromParam:(NSString *)paramName {
    ResourceOwnershipMiddleware *middleware = [[ResourceOwnershipMiddleware alloc] init];
    middleware.paramName = paramName;
    middleware.fromBody = YES;
    middleware.isRecord = YES;
    return middleware;
}

- (BOOL)handleRequest:(HttpRequest *)request
             response:(HttpResponse *)response
                error:(NSError **)error {
    // Get authenticated DID from middleware context
    NSString *authDID = request.authenticatedDid;
    if (!authDID) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Authentication required"}];
        if (error) {
            *error = [NSError errorWithDomain:XrpcMiddlewareErrorDomain
                                         code:XrpcMiddlewareErrorAuthRequired
                                     userInfo:@{NSLocalizedDescriptionKey: @"Authentication required"}];
        }
        return NO;
    }

    // Extract resource identifier
    NSString *resourceID = nil;
    if (self.fromBody) {
        NSDictionary *body = request.jsonBody ?: @{};
        resourceID = body[self.paramName];
    } else {
        // Extract from query string
        resourceID = [request queryParamForKey:self.paramName];
    }

    if (!resourceID || ![resourceID isKindOfClass:[NSString class]]) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"InvalidRequest", @"message": [NSString stringWithFormat:@"Missing or invalid %@", self.paramName]}];
        if (error) {
            *error = [NSError errorWithDomain:XrpcMiddlewareErrorDomain
                                         code:XrpcMiddlewareErrorInternal
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing resource identifier"}];
        }
        return NO;
    }

    NSString *resourceDID = nil;

    if (self.isRecord) {
        // Parse AT-URI: at://<did>/<collection>/<rkey>
        if ([resourceID hasPrefix:@"at://"]) {
            NSString *withoutScheme = [resourceID substringFromIndex:5];
            NSArray *parts = [withoutScheme componentsSeparatedByString:@"/"];
            if (parts.count >= 1) {
                resourceDID = parts[0];
            }
        } else {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Invalid AT-URI format"}];
            return NO;
        }
    } else {
        // Resource ID is the repo DID directly
        resourceDID = resourceID;
    }

    // Validate ownership
    if (![authDID isEqualToString:resourceDID]) {
        PDS_LOG_AUTH_WARN(@"ResourceOwnership: User %@ attempted to access resource owned by %@", authDID, resourceDID);
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot access resource owned by another user"}];
        if (error) {
            *error = [NSError errorWithDomain:XrpcMiddlewareErrorDomain
                                         code:XrpcMiddlewareErrorNotOwner
                                     userInfo:@{NSLocalizedDescriptionKey: @"Not resource owner"}];
        }
        return NO;
    }

    return YES;
}

@end

#pragma mark - XrpcMiddlewarePresets

@implementation XrpcMiddlewarePresets

+ (NSArray<id<XrpcMiddleware>> *)protectedEndpointWithController:(PDSController *)controller
                                                       rateLimit:(NSInteger)rateLimit {
    NSMutableArray<id<XrpcMiddleware>> *middlewares = [NSMutableArray array];
    
    // Auth required
    [middlewares addObject:[AuthMiddleware userAuthWithController:controller]];
    
    // Optional rate limit
    if (rateLimit > 0) {
        NSTimeInterval window = 60.0; // 1 minute window
        [middlewares addObject:[RateLimitMiddleware perUser:rateLimit perWindow:window]];
    }
    
    return [middlewares copy];
}

+ (NSArray<id<XrpcMiddleware>> *)adminEndpointWithController:(PDSController *)controller
                                             serviceDatabases:(id)serviceDatabases {
    return @[[AuthMiddleware adminAuthWithController:controller
                                     serviceDatabases:serviceDatabases]];
}

+ (NSArray<id<XrpcMiddleware>> *)publicEndpointWithRateLimit:(NSInteger)limit {
    if (limit <= 0) {
        return @[];
    }
    NSTimeInterval window = 60.0; // 1 minute window
    return @[[RateLimitMiddleware perIP:limit perWindow:window]];
}

@end
