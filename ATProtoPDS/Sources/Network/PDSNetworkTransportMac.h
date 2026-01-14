/*!
 @file PDSNetworkTransportMac.h

 @abstract macOS Network framework implementation of PDS network transports.

 @discussion Provides concrete implementations of PDSNetworkConnection and
 PDSNetworkListener using the modern Network framework (nw_connection_t,
 nw_listener_t) available on macOS 10.14+ and iOS 12+.

 This file is only compiled on Apple platforms.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSNetworkTransport.h"
#import <Network/Network.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSNetworkConnectionMac

 @abstract Network framework connection implementation for macOS.

 @discussion Wraps nw_connection_t for secure, efficient connections
 with automatic TLS support and proper cancellation handling.

 @see PDSNetworkConnection
 */
@interface PDSNetworkConnectionMac : NSObject <PDSNetworkConnection>

/*!
 @method initWithConnection:

 @abstract Wraps an existing Network framework connection.

 @param connection The nw_connection_t to wrap.

 @return An initialized connection.
 */
- (instancetype)initWithConnection:(nw_connection_t)connection;

/*!
 @method initWithHost:port:

 @abstract Creates an outbound connection to a host.

 @param host The hostname or IP address.

 @param port The port number.

 @return An initialized connection (connection starts in Preparing state).
 */
- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port;

@end

/*!
 @class PDSNetworkListenerMac

 @abstract Network framework listener implementation for macOS.

 @discussion Wraps nw_listener_t for efficient, secure inbound connection
 acceptance with automatic TLS support.

 @see PDSNetworkListener
 */
@interface PDSNetworkListenerMac : NSObject <PDSNetworkListener>

/*!
 @method initWithPort:

 @abstract Creates a listener bound to the specified port.

 @param port The port number (0 for ephemeral port assignment).

 @return An initialized listener (starts in Waiting state).
 */
- (instancetype)initWithPort:(NSUInteger)port;

@end

NS_ASSUME_NONNULL_END
