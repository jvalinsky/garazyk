/*!
 @file RelayAPIHandler.h

 @abstract HTTP handler for Relay API endpoints.

 @discussion Provides JSON API endpoints for the relay web UI:
 - GET /api/relay/metrics - Current relay metrics
 - GET /api/relay/upstreams - List upstream connections
 - GET /api/relay/health - Health check

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;
@class RelayUpstreamManager;
@class RelayMetrics;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class RelayAPIHandler

 @abstract HTTP handler for relay API endpoints.

 @discussion Serves JSON data for the relay dashboard UI.
 */
@interface RelayAPIHandler : NSObject

/*!
 @method sharedHandler

 @abstract Get singleton handler instance.

 @return Shared RelayAPIHandler instance.
 */
+ (instancetype)sharedHandler;

/*!
 @method canHandleRequest:

 @abstract Check if handler can process request.

 @param request HTTP request to check.

 @return YES if path starts with "/api/relay", NO otherwise.
 */
- (BOOL)canHandleRequest:(HttpRequest *)request;

/*!
 @method handleRequest:response:

 @abstract Handle Relay API request.

 @param request HTTP request.
 @param response HTTP response to populate.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method setMetrics:

 @abstract Set the relay metrics instance.

 @param metrics The RelayMetrics instance.
 */
- (void)setMetrics:(RelayMetrics *)metrics;

/*!
 @method setUpstreamManager:

 @abstract Set the upstream manager for connection status queries.

 @param manager The RelayUpstreamManager instance (may be nil if relay not configured).
 */
- (void)setUpstreamManager:(RelayUpstreamManager *)manager;

@end

NS_ASSUME_NONNULL_END
