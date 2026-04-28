/*!
 @file PDSWebSocketServer.h

 @abstract Unified WebSocket server with transport abstraction.

 @discussion Consolidates HTTP upgrade path and raw socket path under
 a single server interface using the PDSWebSocketTransport abstraction.
 Eliminates duplicate code and enables platform-agnostic WebSocket support.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSWebSocketTransport.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSWebSocketServer;
@protocol PDSNetworkListener;

/*!
 @typedef PDSWebSocketConnectionHandler

 @abstract Callback when a new WebSocket connection is established.

 @param transport The transport object for the new connection (conforms to PDSWebSocketTransport).
 */
typedef void (^PDSWebSocketConnectionHandler)(id<PDSWebSocketTransport> transport);

/*!
 @typedef PDSWebSocketErrorHandler

 @abstract Callback when the server encounters an error.

 @param error The error that occurred.
 */
typedef void (^PDSWebSocketServerErrorHandler)(NSError *error);
typedef id<PDSNetworkListener> _Nullable (^PDSWebSocketListenerFactory)(NSUInteger port);

/*!
 @class PDSWebSocketServer

 @abstract Unified WebSocket server supporting both HTTP upgrade and raw sockets.

 @discussion Provides a single server implementation that:
 - Accepts HTTP upgrade requests (from HttpServer)
 - Accepts raw WebSocket connections on a dedicated port
 - Uses PDSNetworkTransport for platform abstraction
 - Notifies via callbacks when connections are accepted
 */
@interface PDSWebSocketServer : NSObject

/*!
 @property port

 @abstract The port the server listens on (0 = ephemeral, assigned by OS).

 Valid after calling start:success:.
 */
@property (nonatomic, readonly) NSUInteger port;

/*!
 @property connectionHandler

 @abstract Callback invoked when a new WebSocket connection is accepted.

 Invoked on an internal dispatch queue; the handler should not perform
 long-running operations.
 */
@property (nonatomic, copy, nullable) PDSWebSocketConnectionHandler connectionHandler;

/*!
 @property errorHandler

 @abstract Callback invoked when the server encounters an error.

 Does not automatically close the server; subsequent connections may still succeed.
 */
@property (nonatomic, copy, nullable) PDSWebSocketServerErrorHandler errorHandler;

/*!
 @method initWithPort:

 @abstract Creates a server listening on the specified port.

 @param port The port to listen on (0 for ephemeral port assignment).

 @return An initialized server instance.
 */
- (instancetype)initWithPort:(NSUInteger)port;

- (instancetype)initWithPort:(NSUInteger)port
             listenerFactory:(PDSWebSocketListenerFactory)listenerFactory;

/*!
 @method startWithError:

 @abstract Starts the server and begins accepting connections.

 @param error On failure, contains the error that prevented startup.

 @return YES if the server started successfully, NO otherwise.

 @discussion After calling this method, the server listens on its port and
 invokes connectionHandler for each accepted connection. The port property
 is valid after success.
 */
- (BOOL)startWithError:(NSError **)error;

/*!
 @method stop

 @abstract Stops the server gracefully.

 @discussion Stops accepting new connections and closes the listener.
 Existing connections remain open until they close naturally or are
 closed by the application.
 */
- (void)stop;

/*!
 @method delegateNewTransport:forPath:

 @abstract Delegates a transport from the HTTP upgrade path.

 @param transport The transport wrapping an HTTP-upgraded connection.
 @param path The WebSocket request path (for routing if needed).

 @discussion Called by HttpServer when an HTTP upgrade request is received.
 The transport is wrapped in a PDSWebSocketNetworkAdapter if needed, then
 passed to the connectionHandler.
 */
- (void)delegateNewTransport:(id<PDSWebSocketTransport>)transport forPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
