// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
/**
 * @abstract Defines the PDSAdminController protocol contract.
 */
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Middleware Protocol

/**
 * @abstract Handles one step in an XRPC request middleware chain.
 * @discussion Middleware may validate, reject, enrich, or record request state before
 * the endpoint handler runs. Returning NO stops chain execution.
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

/** Human-readable name for diagnostics and debugging. */
@property (nonatomic, copy, readonly) NSString *middlewareName;

@end

#pragma mark - Middleware Chain

/**
 * @abstract Executes a sequence of middleware in insertion order.
 */
@interface XrpcMiddlewareChain : NSObject <XrpcMiddleware>

/** Adds middleware to the end of the chain. */
- (void)addMiddleware:(id<XrpcMiddleware>)middleware;

/** Adds multiple middleware objects in array order. */
- (void)addMiddlewares:(NSArray<id<XrpcMiddleware>> *)middlewares;

/** Number of middleware objects in the chain. */
@property (nonatomic, readonly) NSUInteger count;

@end

#pragma mark - Auth Middleware

/**
 * @abstract Authenticates user and admin requests before endpoint dispatch.
 */
@interface AuthMiddleware : NSObject <XrpcMiddleware>

/** Human-readable middleware name. */
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
 * @abstract Applies request rate limits per authenticated user or source IP.
 */
@interface RateLimitMiddleware : NSObject <XrpcMiddleware>

/** Human-readable middleware name. */
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
 * @abstract Validates that the authenticated actor owns a requested repository or record.
 */
@interface ResourceOwnershipMiddleware : NSObject <XrpcMiddleware>

/** Human-readable middleware name. */
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

/** Error domain for middleware errors. */
extern NSString * const XrpcMiddlewareErrorDomain;

/**
 * @abstract Error codes returned by XRPC middleware failures.
 */
typedef NS_ENUM(NSInteger, XrpcMiddlewareError) {
    /** The endpoint requires authentication. */
    XrpcMiddlewareErrorAuthRequired = 1000,
    /** The supplied authentication token or proof is invalid. */
    XrpcMiddlewareErrorAuthInvalid = 1001,
    /** The endpoint requires administrative privileges. */
    XrpcMiddlewareErrorAdminRequired = 1002,
    /** The request exceeded its configured rate limit. */
    XrpcMiddlewareErrorRateLimited = 1003,
    /** The authenticated actor does not own the target resource. */
    XrpcMiddlewareErrorNotOwner = 1004,
    /** Middleware failed because of an internal error. */
    XrpcMiddlewareErrorInternal = 1005,
};

#pragma mark - Middleware Presets

/**
 * @abstract Builds common XRPC middleware chains for endpoint registration.
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
