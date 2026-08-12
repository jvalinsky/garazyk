// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoWebSocketServer.h

 @abstract WebSocket server for real-time communication.

 @discussion Implements WebSocket protocol (RFC 6455) for bidirectional
 communication. Used by the ATProtoFirehose and other streaming endpoints.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class ATProtoWebSocketConnection;
@class ATProtoWebSocketServer;

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
- (void)webSocketServer:(ATProtoWebSocketServer *)server didAcceptConnection:(ATProtoWebSocketConnection *)connection;
- (void)webSocketServer:(ATProtoWebSocketServer *)server didCloseConnection:(ATProtoWebSocketConnection *)connection;
- (void)webSocketServer:(ATProtoWebSocketServer *)server didFailWithError:(NSError *)error;
- (void)webSocketServer:(ATProtoWebSocketServer *)server stateDidChange:(WebSocketServerState)state;
@end

/*!
 @class ATProtoWebSocketServer

 @abstract WebSocket server for streaming connections.

 @discussion Manages WebSocket connections and broadcasts messages to clients.
 */
@interface ATProtoWebSocketServer : NSObject

/*! The host address to listen on. */
@property (nonatomic, readonly) NSString *host;

/*! The port to listen on. */
@property (nonatomic, readonly) uint16_t port;

/*! Current server state. */
@property (nonatomic, readonly) WebSocketServerState state;

/*! Delegate for server events. */
@property (nonatomic, weak, nullable) id<WebSocketServerDelegate> delegate;

/*! Currently active connections. */
@property (nonatomic, readonly) NSSet<ATProtoWebSocketConnection *> *connections;

/*! WebSocket subprotocol to use. */
@property (nonatomic, copy, nullable) NSString *subprotocol;

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port;

/*! Starts the server. */
- (BOOL)start:(NSError **)error;

/*! Stops the server. */
- (void)stop;

/*! Broadcasts a message to connections matching a predicate. */
- (void)broadcastMessage:(NSData *)message toConnectionsMatching:(NSPredicate * _Nullable)predicate;

@end

NS_ASSUME_NONNULL_END
