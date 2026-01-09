#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

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

 @copyright Copyright (c) 2024 Jack Myers
 */

typedef void (^HttpRouteHandler)(HttpRequest *request, HttpResponse *response);

/*!
 @class HttpRoute

 @abstract Represents a single HTTP route with method, pattern, and handler.

 @discussion HttpRoute encapsulates all the information needed for a route:
 the HTTP method, URL pattern, handler block, and priority for resolution order.
 */
@interface HttpRoute : NSObject

@property (nonatomic, readonly, copy) NSString *method;
@property (nonatomic, readonly, copy) NSString *pattern;
@property (nonatomic, readonly, copy) HttpRouteHandler handler;
@property (nonatomic, readonly) NSUInteger priority;

/*!
 @method initWithMethod:pattern:handler:priority:

 @abstract Initialize a route with the specified parameters.

 @param method The HTTP method (GET, POST, etc.) or "*" for all methods.
 @param pattern The URL pattern with optional parameters (e.g., "/users/:id").
 @param handler The handler block to execute for matching requests.
 @param priority Route priority for resolution ordering (higher = more specific).

 @return An initialized HttpRoute instance.
 */
- (instancetype)initWithMethod:(NSString *)method
                       pattern:(NSString *)pattern
                       handler:(HttpRouteHandler)handler
                      priority:(NSUInteger)priority;

@end

/*!
 @class HttpRouter

 @abstract Thread-safe HTTP router with secure path matching.

 @discussion HttpRouter manages a collection of routes and provides secure,
 high-performance route resolution. It prevents path traversal attacks and
 supports parameter extraction from URLs.

 Thread Safety: All methods are thread-safe and can be called concurrently.
 */
@interface HttpRouter : NSObject

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
 @method extractParametersFromPath:pattern:

 @abstract Extract parameters from a URL path using a pattern.

 @param path The actual request path.
 @param pattern The route pattern with parameters.

 @return Dictionary of extracted parameters, or nil if pattern doesn't match.
 */
- (nullable NSDictionary<NSString *, NSString *> *)extractParametersFromPath:(NSString *)path
                                                                     pattern:(NSString *)pattern;

@end

NS_ASSUME_NONNULL_END