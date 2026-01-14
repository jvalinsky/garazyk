#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

/*!
 @class WebSocketUpgradeHandler

 @abstract Handles WebSocket upgrade requests per RFC 6455.

 @discussion Validates WebSocket upgrade headers, computes the accept key,
 and prepares the response for protocol switching. Used by XRPC subscription
 endpoints like com.atproto.sync.subscribeRepos.
 */
@interface WebSocketUpgradeHandler : NSObject

/*!
 @method handleUpgradeRequest:response:

 @abstract Validates and processes a WebSocket upgrade request.

 @param request The HTTP request containing upgrade headers.
 @param response The response to configure (status, headers, body).

 @return YES if the upgrade is valid and should proceed, NO if an error
         response was set on the response object.
 */
- (BOOL)handleUpgradeRequest:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method computeAcceptKey:

 @abstract Computes the Sec-WebSocket-Accept key per RFC 6455.

 @param key The Sec-WebSocket-Key from the client request.

 @return The computed accept key as a base64-encoded string.
 */
- (NSString *)computeAcceptKey:(NSString *)key;

/*!
 @method isWebSocketUpgradeRequest:

 @abstract Checks if the request appears to be a WebSocket upgrade attempt.

 @param request The HTTP request to check.

 @return YES if the request has WebSocket upgrade headers.
 */
- (BOOL)isWebSocketUpgradeRequest:(HttpRequest *)request;

/*!
 @method subscriptionPathPrefix

 @abstract Returns the path prefix for WebSocket subscription endpoints.

 @return The path prefix (e.g., "/xrpc/").
 */
- (NSString *)subscriptionPathPrefix;

/*!
 @method isSubscriptionPath:

 @abstract Checks if the request path is a WebSocket subscription endpoint.

 @param path The request path to check.

 @return YES if the path matches a subscription endpoint pattern.
 */
- (BOOL)isSubscriptionPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
