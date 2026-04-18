//
//  XrpcMiddleware.h
//  ATProtoPDS
//
//  Declarative middleware system for XRPC endpoints.
//  Provides Express.js-style middleware chains for authentication, rate limiting,
//  and resource ownership validation.
//

#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;
@class PDSController;
@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Middleware Protocol

/**
 * Protocol for XRPC middleware handlers.
 *
 * Middleware can:
 * - Validate and reject requests (return NO, set error on response)
 * - Modify request headers or body
 * - Inject context into the request (e.g., authenticated DID)
 * - Perform side effects (logging, rate limiting)
 *
 * Middleware chains are executed in order. If any middleware returns NO,
 * the chain stops and the response is sent.
 */
@protocol XrpcMiddleware <NSObject>

/**
 * Process the request.
 *
 * @param request HTTP request to process
 * @param response HTTP response for setting errors
 * @param error On return, contains error describing why request was rejected
 * @return YES to continue to next middleware/handler, NO to stop and return response
 */
- (BOOL)handleRequest:(HttpRequest *)request
             response:(HttpResponse *)response
                error:(NSError **)error;

@optional

/// Human-readable name for debugging
@property (nonatomic, copy, readonly) NSString *middlewareName;

@end

#pragma mark - Middleware Chain

/**
 * Executes a sequence of middleware in order.
 *
 * If any middleware returns NO, the chain stops and the response is returned.
 * The chain passes the request through all middleware before reaching the final handler.
 */
@interface XrpcMiddlewareChain : NSObject <XrpcMiddleware>

/// Add middleware to the chain (executed in order added)
- (void)addMiddleware:(id<XrpcMiddleware>)middleware;

/// Add multiple middleware at once
- (void)addMiddlewares:(NSArray<id<XrpcMiddleware>> *)middlewares;

/// Number of middleware in chain
@property (nonatomic, readonly) NSUInteger count;

@end

#pragma mark - Auth Middleware

/**
 * Authentication middleware for XRPC endpoints.
 *
 * Provides both user authentication (JWT/DPoP) and admin authentication.
 */
@interface AuthMiddleware : NSObject <XrpcMiddleware>

/// Middleware name
@property (nonatomic, copy, readonly) NSString *middlewareName;

/**
 * Create middleware that requires valid user authentication.
 *
 * Validates JWT or DPoP token, extracts DID, checks takedown status.
 * Injects "X-Authenticated-DID" header into request for downstream handlers.
 *
 * @param controller PDS controller with jwtMinter and adminController
 * @return Middleware that requires user auth
 */
+ (instancetype)userAuthWithController:(PDSController *)controller;

/**
 * Create middleware that requires admin privileges.
 *
 * Validates authentication AND checks that user has admin privileges
 * via PDSAdminAuth.
 *
 * @param controller PDS controller
 * @param serviceDatabases Service databases for account lookups
 * @return Middleware that requires admin auth
 */
+ (instancetype)adminAuthWithController:(PDSController *)controller
                        serviceDatabases:(id)serviceDatabases;

/**
 * Create middleware that requires valid user authentication.
 *
 * Uses jwtMinter and adminController directly (for use before full controller is available).
 */
+ (instancetype)userAuthWithJwtMinter:(JWTMinter *)jwtMinter
                     adminController:(id<PDSAdminController>)adminController;

@end

#pragma mark - Rate Limit Middleware

/**
 * Rate limiting middleware for XRPC endpoints.
 *
 * Tracks request counts per user (DID) or per IP address.
 */
@interface RateLimitMiddleware : NSObject <XrpcMiddleware>

/// Middleware name
@property (nonatomic, copy, readonly) NSString *middlewareName;

/**
 * Create rate limit middleware per authenticated user (DID).
 *
 * Requires authentication to have already run (injects DID from X-Authenticated-DID header).
 *
 * @param limit Maximum requests allowed per window
 * @param windowSeconds Time window in seconds
 * @return Middleware that limits per-user requests
 */
+ (instancetype)perUser:(NSInteger)limit perWindow:(NSTimeInterval)windowSeconds;

/**
 * Create rate limit middleware per IP address.
 *
 * @param limit Maximum requests allowed per window
 * @param windowSeconds Time window in seconds
 * @return Middleware that limits per-IP requests
 */
+ (instancetype)perIP:(NSInteger)limit perWindow:(NSTimeInterval)windowSeconds;

@end

#pragma mark - Resource Ownership Middleware

/**
 * Resource ownership validation middleware.
 *
 * Validates that the authenticated user owns the resource they're trying to access.
 */
@interface ResourceOwnershipMiddleware : NSObject <XrpcMiddleware>

/// Middleware name
@property (nonatomic, copy, readonly) NSString *middlewareName;

/**
 * Create middleware that validates repo ownership.
 *
 * Extracts repo parameter from request body or query, validates
 * that the authenticated DID matches the repo DID.
 *
 * @param paramName Name of parameter containing repo DID (e.g., "repo", "did")
 * @param fromBody If YES, extract from JSON body; if NO, extract from query string
 * @return Middleware that validates repo ownership
 */
+ (instancetype)ownsRepoFromParam:(NSString *)paramName fromBody:(BOOL)fromBody;

/**
 * Create middleware that validates record ownership.
 *
 * Extracts AT-URI from parameter, validates that repo part matches auth DID.
 *
 * @param paramName Name of parameter containing AT-URI
 * @return Middleware that validates record ownership
 */
+ (instancetype)ownsRecordFromParam:(NSString *)paramName;

@end

#pragma mark - Error Domain

/// Error domain for middleware errors
extern NSString * const XrpcMiddlewareErrorDomain;

/// Error codes for middleware failures
typedef NS_ENUM(NSInteger, XrpcMiddlewareError) {
    XrpcMiddlewareErrorAuthRequired = 1000,      // Authentication required
    XrpcMiddlewareErrorAuthInvalid = 1001,       // Invalid authentication
    XrpcMiddlewareErrorAdminRequired = 1002,     // Admin privileges required
    XrpcMiddlewareErrorRateLimited = 1003,      // Rate limit exceeded
    XrpcMiddlewareErrorNotOwner = 1004,          // User doesn't own resource
    XrpcMiddlewareErrorInternal = 1005,          // Internal error
};

#pragma mark - Middleware Presets

/**
 * Factory for common middleware chain presets.
 *
 * Provides pre-configured middleware chains for typical endpoint patterns.
 */
@interface XrpcMiddlewarePresets : NSObject

/**
 * Protected endpoint: user authentication with optional rate limiting.
 *
 * @param controller PDS controller
 * @param rateLimit Requests per minute per user (0 = no rate limit)
 * @return Array of middleware for protected endpoint
 */
+ (NSArray<id<XrpcMiddleware>> *)protectedEndpointWithController:(PDSController *)controller
                                                       rateLimit:(NSInteger)rateLimit;

/**
 * Admin endpoint: admin authentication required.
 *
 * @param controller PDS controller
 * @param serviceDatabases Service databases for account lookups
 * @return Array of middleware for admin endpoint
 */
+ (NSArray<id<XrpcMiddleware>> *)adminEndpointWithController:(PDSController *)controller
                                             serviceDatabases:(id)serviceDatabases;

/**
 * Public endpoint with rate limiting.
 *
 * @param limit Requests per minute per IP
 * @return Array of middleware for public endpoint with rate limiting
 */
+ (NSArray<id<XrpcMiddleware>> *)publicEndpointWithRateLimit:(NSInteger)limit;

@end

NS_ASSUME_NONNULL_END
