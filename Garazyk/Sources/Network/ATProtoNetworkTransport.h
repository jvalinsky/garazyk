// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoNetworkTransport.h

 @abstract Platform-abstracted networking interfaces for AT Protocol connections.

 @discussion Defines the transport layer abstractions for network connections,
 allowing platform-specific implementations (macOS via Network framework,
 Linux via BSD sockets) while presenting a unified interface.

 Provides protocols for:
 - Transport: Base cancel/start lifecycle
 - Connection: Bidirectional data transfer (send/receive)
 - Listener: Inbound connection acceptance

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <stdint.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!

 @abstract Connection lifecycle states.

 @constant ATProtoNetworkConnectionStateWaiting Initial state, not yet started.
 @constant ATProtoNetworkConnectionStatePreparing Connection in progress.
 @constant ATProtoNetworkConnectionStateReady Data transfer ready.
 @constant ATProtoNetworkConnectionStateFailed Error occurred.
 @constant ATProtoNetworkConnectionStateCancelled Connection closed.
 */
typedef NS_ENUM(NSInteger, ATProtoNetworkConnectionState) {
    ATProtoNetworkConnectionStateWaiting = 0,
    ATProtoNetworkConnectionStatePreparing,
    ATProtoNetworkConnectionStateReady,
    ATProtoNetworkConnectionStateFailed,
    ATProtoNetworkConnectionStateCancelled
};

/*!

 @abstract Listener lifecycle states.

 @constant ATProtoNetworkListenerStateWaiting Not yet started.
 @constant ATProtoNetworkListenerStateReady Accepting connections.
 @constant ATProtoNetworkListenerStateFailed Error occurred.
 @constant ATProtoNetworkListenerStateCancelled Stopped.
 */
typedef NS_ENUM(NSInteger, ATProtoNetworkListenerState) {
    ATProtoNetworkListenerStateWaiting = 0,
    ATProtoNetworkListenerStateReady,
    ATProtoNetworkListenerStateFailed,
    ATProtoNetworkListenerStateCancelled
};

/*!
 @protocol ATProtoNetworkTransport

 @abstract Base protocol for network transport objects.

 @discussion Defines the common lifecycle methods shared by all transport types.
 */
@protocol ATProtoNetworkTransport <NSObject>

/*! Cancels the transport, releasing all resources. */
- (void)cancel;

/*!
 @method startWithQueue:

 @abstract Starts the transport on the specified dispatch queue.

 @param queue The dispatch queue for callback execution.
 */
- (void)startWithQueue:(dispatch_queue_t)queue;

@end

/*!
 @protocol ATProtoNetworkConnection

 @abstract Bidirectional network connection for data transfer.

 @discussion Represents an established connection capable of sending and
 receiving data. Supports callbacks for state changes and data operations.

 @see ATProtoNetworkListener
 */
@protocol ATProtoNetworkConnection <ATProtoNetworkTransport>

/*! Callback invoked when connection state changes. */
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(ATProtoNetworkConnectionState state, NSError * _Nullable error);

/*! The remote peer's IP address (for logging/rate limiting). */
@property (nonatomic, readonly, nullable) NSString *remoteAddress;

/*!
 @method sendData:completion:

 @abstract Sends data over the connection.

 @param data The bytes to transmit.

 @param completion Callback with error if transmission failed.
 */
- (void)sendData:(NSData *)data completion:(void (^ _Nullable)(NSError * _Nullable error))completion;

/*!
 @method receiveWithMinimumLength:maximumLength:completion:

 @abstract Receives data from the connection.

 @param minLength Minimum bytes to receive before calling completion.

 @param maxLength Maximum bytes to receive in a single callback.

 @param completion Callback with received data, completion flag, and error.

 @discussion The completion handler is called when:
 - isComplete is YES: Connection closed after this data
 - data has minLength bytes: Partial data available
 - error is non-nil: Receive operation failed
 */
- (void)receiveWithMinimumLength:(NSUInteger)minLength
                  maximumLength:(NSUInteger)maxLength
                     completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion;

@end

/*!
 @protocol ATProtoNetworkListener

 @abstract Inbound connection acceptor.

 @discussion Listens on a port and notifies when new connections arrive.
 Each accepted connection is passed to the newConnectionHandler callback.

 @see ATProtoNetworkConnection
 */
@protocol ATProtoNetworkListener <ATProtoNetworkTransport>

/*! Callback invoked when listener state changes. */
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(ATProtoNetworkListenerState state, NSError * _Nullable error);

/*! Callback invoked when a new connection is accepted. */
@property (nonatomic, copy, nullable) void (^newConnectionHandler)(id<ATProtoNetworkConnection> connection);

/*! The port the listener is bound to (valid after reaching Ready state). */
@property (nonatomic, readonly) NSUInteger port;

@end

/*!
 @class ATProtoNetworkTransportFactory

 @abstract Factory for creating platform-appropriate transport objects.

 @discussion Creates appropriate listener and connection implementations
 based on the current platform (macOS uses Network framework, Linux uses BSD sockets).
 */
@interface ATProtoNetworkTransportFactory : NSObject

/*!
 @method createListenerWithPort:

 @abstract Creates a listener bound to the specified port.

 @param port The port number to listen on (0 for ephemeral port).

 @return A listener instance, or nil if creation failed.

 @see ATProtoNetworkListener
 */
+ (id<ATProtoNetworkListener>)createListenerWithPort:(NSUInteger)port;

/*!
 @method createListenerWithHost:port:

 @abstract Creates a listener bound to the specified host+port.

 @discussion When host is nil, the listener binds to all interfaces (platform default).
 When host is non-nil, the listener should bind only to that interface (e.g. 127.0.0.1).

 @param host The local host/interface to bind to, or nil for all interfaces.

 @param port The port number to listen on (0 for ephemeral port).

 @return A listener instance, or nil if creation failed.
 */
+ (id<ATProtoNetworkListener>)createListenerWithHost:(nullable NSString *)host port:(NSUInteger)port;

/*!
 @method createConnectionWithHost:port:

 @abstract Creates an outbound connection to a remote host.

 @param host The hostname or IP address to connect to.

 @param port The port number to connect to.

 @return A connection instance, or nil if creation failed.

 @see ATProtoNetworkConnection
 */
+ (id<ATProtoNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port;

@end

NS_ASSUME_NONNULL_END
