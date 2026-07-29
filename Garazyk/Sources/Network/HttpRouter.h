// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "HttpRoute.h"

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class WebSocketUpgradeHandler;

/*!
 @header HttpRouter.h

 @abstract Secure, thread-safe HTTP router for the PDS.

 @discussion HttpRouter provides a modern routing implementation that addresses
 the security and performance issues in the original HttpServer routing system.
 It uses a trie-based routing table with secure path matching and thread-safe
 operations.

 Key improvements:
 - Prevents path traversal attacks
 - Thread-safe route registration and lookup
 - Trie-based routing for O(k) lookup performance
 - Parameter extraction and validation
 - Clean API design

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!
 @class HttpRouter

 @abstract Thread-safe HTTP router with secure path matching.

 @discussion HttpRouter manages a collection of routes and provides secure,
 high-performance route resolution. It prevents path traversal attacks and
 supports parameter extraction from URLs.

 Thread Safety: All methods are thread-safe and can be called concurrently.
 */
@interface HttpRouter : NSObject

/**
 * @abstract Exposes the base url value.
 */
@property (nonatomic, copy) NSString *baseURL;

/*!
 @method initWithBaseURL:

 @abstract Initialize router with a base URL.

 @param baseURL The base URL for the router.

 @return An initialized HttpRouter instance.
 */
- (instancetype)initWithBaseURL:(NSString *)baseURL;

/*!
 @method handleRequest:response:

 @abstract Handle an HTTP request and generate a response.

 @param request The HTTP request to handle.
 @param response The HTTP response to populate.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method addRoute:pattern:handler:

 @abstract Add a route with default priority.

 @param method The HTTP method or "*" for all methods.
 @param pattern The URL pattern.
 @param handler The handler block.
 */
- (void)addRoute:(NSString *)method
         pattern:(NSString *)pattern
         handler:(HttpRouteHandler)handler;

/*!
 @method addRoute:pattern:handler:priority:

 @abstract Add a route with specified priority.

 @param method The HTTP method or "*" for all methods.
 @param pattern The URL pattern.
 @param handler The handler block.
 @param priority Route priority (higher values = higher priority).
 */
- (void)addRoute:(NSString *)method
         pattern:(NSString *)pattern
         handler:(HttpRouteHandler)handler
        priority:(NSUInteger)priority;

/*!
 @method handlerForRequest:

 @abstract Find the appropriate handler for a request.

 @param request The HTTP request to match.

 @return The matching handler, or nil if no route matches.
 */
- (nullable HttpRouteHandler)handlerForRequest:(HttpRequest *)request;

/*!
 @method normalizePath:

 @abstract Securely normalizes a URL path by resolving `..` and `.` segments.

 @discussion Strips leading slashes, collapses double slashes, resolves `..`
 parent-directory segments (dropping traversals above root), and removes `.`
 current-directory segments. Prevents path traversal attacks from bypassing
 route matching.

 @param path The raw URL path to normalize.
 @return The normalized path without `..` or `.` segments.
 */
- (NSString *)normalizePath:(NSString *)path;

/*!
 @method extractParametersFromPath:pattern:

 @abstract Extract parameters from a URL path using a pattern.

 @param path The actual request path.
 @param pattern The route pattern with parameters.

 @return Dictionary of extracted parameters, or nil if pattern doesn't match.
 */
- (nullable NSDictionary<NSString *, NSString *> *)extractParametersFromPath:(NSString *)path
                                                                     pattern:(NSString *)pattern;

/*!
 @method setupRoutes

 @abstract Set up the default routes for the server.
 */
- (void)setupRoutes;

@end

NS_ASSUME_NONNULL_END