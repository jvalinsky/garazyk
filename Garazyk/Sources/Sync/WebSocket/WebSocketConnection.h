// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoWebSocketConnection.h

 @abstract WebSocket client connection for real-time communication.

 @discussion Implements WebSocket protocol (RFC 6455) client connection
 with support for text/binary messages, ping/pong, and graceful close.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Network/ATProtoNetworkTransport.h"
#import <Foundation/Foundation.h>
#import <stdint.h>

@class ATProtoWebSocketConnection;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for WebSocket connection errors. */
extern NSString *const WebSocketConnectionErrorDomain;

/*! Error code when connection is closed. */
extern NSInteger const WebSocketConnectionErrorCodeConnectionClosed;

/*! Error code for invalid WebSocket frame. */
extern NSInteger const WebSocketConnectionErrorCodeInvalidFrame;

/*! Error code when write fails. */
extern NSInteger const WebSocketConnectionErrorCodeWriteFailed;

/*!

 @abstract Connection lifecycle states.

 @constant WebSocketConnectionStateConnecting Connection is being established.
 @constant WebSocketConnectionStateConnected Connection is active.
 @constant WebSocketConnectionStateClosing Connection is closing.
 @constant WebSocketConnectionStateClosed Connection is closed.
 */
typedef NS_ENUM(NSInteger, WebSocketConnectionState) {
  WebSocketConnectionStateConnecting,
  WebSocketConnectionStateConnected,
  WebSocketConnectionStateClosing,
  WebSocketConnectionStateClosed
};

/*!
 @protocol WebSocketConnectionDelegate

 @abstract Delegate for WebSocket connection events.
 */
@protocol WebSocketConnectionDelegate <NSObject>
@optional
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection
          didReceiveMessage:(NSData *)message;
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection
             didReceiveText:(NSString *)text;
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection
           didCloseWithCode:(NSInteger)code
                     reason:(NSString *)reason;
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection
           didFailWithError:(NSError *)error;
- (void)webSocketConnectionStateDidChange:(ATProtoWebSocketConnection *)connection;

/*! Called when backpressure warning threshold is reached. */
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection
    didReachBackpressureWarning:(double)fillPercentage
                     queueBytes:(NSUInteger)bytes;

/*! Called when backpressure critical threshold is reached. */
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection
    didReachBackpressureCritical:(double)fillPercentage
                      queueBytes:(NSUInteger)bytes;

/*! Called when backpressure is cleared (queue drops below warning threshold). */
- (void)webSocketConnectionDidClearBackpressure:(ATProtoWebSocketConnection *)connection;

/*! Called when connection is about to be closed due to queue overflow. */
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection
    willCloseForQueueOverflow:(NSUInteger)bytes
                        limit:(NSUInteger)limit;
@end

/*!
 @class ATProtoWebSocketConnection

 @abstract WebSocket client connection.

 @discussion Provides WebSocket client functionality with delegate callbacks.
 */
@interface ATProtoWebSocketConnection : NSObject

/*! Remote host address. */
@property(nonatomic, readonly) NSString *host;

/*! Remote IP address of the client. */
@property(nonatomic, copy) NSString *remoteAddress;

/*! Remote port. */
@property(nonatomic, readonly) uint16_t port;

/*! WebSocket path. */
@property(nonatomic, readonly) NSString *path;

/*! Whether the outbound connection uses TLS. */
@property(nonatomic, readonly, getter=isSecureTLS) BOOL secureTLS;

/*! Query string from the URL. */
@property(nonatomic, readonly, copy) NSString *queryString;

/*! Parsed query parameters. Single values are NSString, repeated values are
 * NSArray<NSString *>. */
@property(nonatomic, readonly, copy, nullable)
    NSDictionary<NSString *, id> *queryParams;

/*! Current connection state. */
@property(nonatomic, readonly) WebSocketConnectionState state;

/*! Delegate for connection events. */
@property(nonatomic, weak, nullable) id<WebSocketConnectionDelegate> delegate;

/*! Interval between heartbeat pings. */
@property(nonatomic, assign) NSTimeInterval heartbeatInterval;

/*! Timeout for heartbeat responses. */
@property(nonatomic, assign) NSTimeInterval heartbeatTimeout;

/*! Maximum bytes allowed in outbound queue. Default: 10MB. */
@property(nonatomic, assign) NSUInteger maxOutboundQueueBytes;

/*! Threshold percentage (0.0-1.0) for backpressure warning. Default: 0.7 (70%). */
@property(nonatomic, assign) double backpressureWarningThreshold;

/*! Threshold percentage (0.0-1.0) for backpressure critical. Default: 0.9 (90%). */
@property(nonatomic, assign) double backpressureCriticalThreshold;

/*! Negotiated subprotocol. */
@property(nonatomic, copy, nullable) NSString *subprotocol;

/*! Authorization value sent during the client upgrade handshake. */
@property(nonatomic, copy, nullable) NSString *authorizationHeader;

/*! Unique connection identifier. */
@property(nonatomic, readonly) NSUUID *identifier;

/*! Close code from close frame. */
@property(nonatomic, assign) NSInteger closeCode;

/*! Close reason from close frame. */
@property(nonatomic, copy, nullable) NSString *closeReason;

/*! Number of queued outbound frames waiting to be flushed. */
@property(nonatomic, readonly) NSUInteger pendingSendCount;

/*! Approximate number of bytes queued for sending. */
@property(nonatomic, readonly) NSUInteger pendingSendBytes;

- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                        path:(NSString *)path;
- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                        path:(NSString *)path
                   secureTLS:(BOOL)secureTLS;
- (instancetype)initWithConnection:(id<ATProtoNetworkConnection>)connection;

/*! Establishes the WebSocket connection. */
- (BOOL)connect:(NSError **)error;

/*! Starts internal read loop for an already connected/accepted connection. */
- (void)start;

/*! Starts read loop/heartbeats without re-starting the transport. */
- (void)startOnExistingTransport;

/*! Closes the connection. */
- (void)close;

/*! Closes with a specific code and reason. */
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;

/*! Sends a binary message. */
- (void)sendMessage:(NSData *)data;

/*! Sends a text message. */
- (void)sendText:(NSString *)text;

/*! Sends a ping frame. */
- (void)sendPing:(NSData *_Nullable)payload;

/*! Sends a pong frame. */
- (void)sendPong:(NSData *_Nullable)payload;

/*!
 @method suspendReading

 @abstract Suspends the read loop, causing TCP backpressure to propagate.

 @discussion After calling this, the current in-flight receive operation
 completes normally, but startReading will not be called again. The OS
 socket buffer fills, the TCP window shrinks, and the remote peer
 naturally slows or stops sending.
*/
- (void)suspendReading;

/*!
 @method resumeReading

 @abstract Resumes the read loop after a previous suspendReading call.

 @discussion Restarts the recursive read loop by calling startReading.
 Has no effect if reading is not currently suspended.
*/
- (void)resumeReading;

/*! Whether reading is currently suspended. */
@property (nonatomic, readonly) BOOL isReadingSuspended;

@end

NS_ASSUME_NONNULL_END
