/*!
 @file WebSocketServer.h

 @abstract WebSocket server for real-time communication.

 @discussion Implements WebSocket protocol (RFC 6455) for bidirectional
 communication. Used by the Firehose and other streaming endpoints.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class WebSocketConnection;
@class WebSocketServer;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for WebSocket server operations. */
extern NSString * const WebSocketServerErrorDomain;

/*! Error code when listener fails to start. */
extern NSInteger const WebSocketServerErrorCodeListenerFailed;

/*! Error code for invalid WebSocket handshake. */
extern NSInteger const WebSocketServerErrorCodeInvalidHandshake;

/*! Error code when connection fails. */
extern NSInteger const WebSocketServerErrorCodeConnectionFailed;

/*!
 @enum WebSocketServerState

 @abstract Server lifecycle states.

 @constant WebSocketServerStateIdle Server is not running.
 @constant WebSocketServerStateStarting Server is starting up.
 @constant WebSocketServerStateRunning Server is accepting connections.
 @constant WebSocketServerStateStopping Server is shutting down.
 @constant WebSocketServerStateFailed Server failed to start.
 */
typedef NS_ENUM(NSInteger, WebSocketServerState) {
    WebSocketServerStateIdle,
    WebSocketServerStateStarting,
    WebSocketServerStateRunning,
    WebSocketServerStateStopping,
    WebSocketServerStateFailed
};

/*!
 @protocol WebSocketServerDelegate

 @abstract Delegate for WebSocket server events.
 */
@protocol WebSocketServerDelegate <NSObject>
@optional
- (void)webSocketServer:(WebSocketServer *)server didAcceptConnection:(WebSocketConnection *)connection;
- (void)webSocketServer:(WebSocketServer *)server didCloseConnection:(WebSocketConnection *)connection;
- (void)webSocketServer:(WebSocketServer *)server didFailWithError:(NSError *)error;
- (void)webSocketServer:(WebSocketServer *)server stateDidChange:(WebSocketServerState)state;
@end

/*!
 @class WebSocketServer

 @abstract WebSocket server for streaming connections.

 @discussion Manages WebSocket connections and broadcasts messages to clients.
 */
@interface WebSocketServer : NSObject

/*! The host address to listen on. */
@property (nonatomic, readonly) NSString *host;

/*! The port to listen on. */
@property (nonatomic, readonly) uint16_t port;

/*! Current server state. */
@property (nonatomic, readonly) WebSocketServerState state;

/*! Delegate for server events. */
@property (nonatomic, weak, nullable) id<WebSocketServerDelegate> delegate;

/*! Currently active connections. */
@property (nonatomic, readonly) NSSet<WebSocketConnection *> *connections;

/*! WebSocket subprotocol to use. */
@property (nonatomic, copy, nullable) NSString *subprotocol;

/*! Mutable set of connections (internal use). */
@property (nonatomic, strong, readonly) NSMutableSet<WebSocketConnection *> *mutableConnections;

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port;

/*! Starts the server. */
- (BOOL)start:(NSError **)error;

/*! Stops the server. */
- (void)stop;

/*! Broadcasts a message to connections matching a predicate. */
- (void)broadcastMessage:(NSData *)message toConnectionsMatching:(NSPredicate * _Nullable)predicate;

@end

NS_ASSUME_NONNULL_END
