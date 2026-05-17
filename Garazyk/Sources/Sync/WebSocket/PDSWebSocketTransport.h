// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSWebSocketTransport.h

 @abstract Platform-agnostic WebSocket frame-level transport protocol.

 @discussion Defines a unified abstraction for WebSocket frame transmission
 and reception, independent of whether the underlying connection uses the
 HTTP upgrade path (ATProtoNetworkConnection) or raw BSD sockets.

 Both message-oriented (for application frames) and frame-oriented (for
 heartbeat/control frames) operations are supported.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!

 @abstract Callback when a complete message is received.

 @param data The decoded message payload (text or binary, excluding frame headers).
 */
typedef void (^PDSWebSocketTransportMessageHandler)(NSData *data);

/*!

 @abstract Callback when the connection closes.

 @param code WebSocket close code (1000 = normal closure, 1006 = abnormal, etc.).
 @param reason Textual close reason (may be empty).
 */
typedef void (^PDSWebSocketTransportCloseHandler)(NSInteger code, NSString *reason);

/*!

 @abstract Callback when an error occurs.

 @param error The underlying error.
 */
typedef void (^PDSWebSocketTransportErrorHandler)(NSError *error);

/*!
 @protocol PDSWebSocketTransport

 @abstract Platform-agnostic WebSocket frame transport.

 @discussion Provides frame-level send/receive operations for WebSocket
 messages and control frames. Implementations wrap either HTTP upgrade
 connections (ATProtoNetworkConnection) or raw socket file descriptors.
 */
@protocol PDSWebSocketTransport <NSObject>

/*!
 @abstract Callback invoked when a complete WebSocket message is received.

 Invoked on the transport's event queue (typically a background queue).
 Multiple messages may be received concurrently.
 */
@property (nonatomic, copy, nullable) PDSWebSocketTransportMessageHandler messageHandler;

/*!
 @abstract Callback invoked when the connection closes.

 Invoked once per connection, after all pending operations complete.
 */
@property (nonatomic, copy, nullable) PDSWebSocketTransportCloseHandler closeHandler;

/*!
 @abstract Callback invoked when a protocol or I/O error occurs.

 The connection may remain open after an error; the errorHandler does not
 automatically close the transport.
 */
@property (nonatomic, copy, nullable) PDSWebSocketTransportErrorHandler errorHandler;

/*!
 @abstract Sends a WebSocket message (application data).

 @param data The application payload (text or binary, unframed).

 @param completion Callback when the frame is sent or an error occurs.

 @discussion Encodes the payload into a WebSocket frame and sends it.
 The completion handler is called after the frame is transmitted to the
 network, not when received by the peer.
 */
/**
 * @abstract Performs the sendMessage operation.
 */
- (void)sendMessage:(NSData *)data
         completion:(void (^)(NSError * _Nullable error))completion;

/*!
 @abstract Closes the connection gracefully.

 @param code WebSocket close code (1000, 1001, 1006, etc.).
 @param reason Textual close reason (may be empty or nil).
 @param completion Callback when the close frame is sent.

 @discussion Sends a WebSocket close frame and waits for the peer's close response.
 After this method returns, new messages cannot be sent.
 */
- (void)closeWithCode:(NSInteger)code
               reason:(nullable NSString *)reason
           completion:(void (^)(NSError * _Nullable error))completion;

/*!
 @abstract Begins listening for incoming frames and errors.

 @discussion After calling start, the transport will invoke messageHandler,
 closeHandler, and errorHandler callbacks as events arrive. This method
 must be called before any messages are expected.
 */
- (void)start;

@end

NS_ASSUME_NONNULL_END
