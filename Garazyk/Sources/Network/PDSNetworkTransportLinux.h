/*!
 @file PDSNetworkTransportLinux.h

 @abstract Linux/BSD socket implementation of PDS network transports.

 @discussion Provides concrete implementations of PDSNetworkConnection and
 PDSNetworkListener using BSD sockets and libdispatch for event handling.

 This file is only compiled on Linux targets (GNUstep).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSNetworkTransport.h"
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSNetworkConnectionLinux

 @abstract BSD socket-based connection implementation for Linux.

 @discussion Handles TCP connections using non-blocking BSD sockets with
 dispatch_source for I/O event notification.

 @see PDSNetworkConnection
 */
@interface PDSNetworkConnectionLinux : NSObject <PDSNetworkConnection>

/*!
 @method initWithHost:port:

 @abstract Creates an outbound connection to a host.

 @param host The hostname or IP address.

 @param port The port number.

 @return An initialized connection (connection starts in Preparing state).
 */
- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port;

/*!
 @method initWithSocket:address:

 @abstract Wraps an existing socket descriptor.

 @param sockfd The file descriptor to wrap.

 @param address The peer's address string.

 @return An initialized connection (connection starts in Ready state).
 */
- (instancetype)initWithSocket:(int)sockfd address:(NSString *)address;

@end

/*!
 @class PDSNetworkListenerLinux

 @abstract BSD socket-based listener implementation for Linux.

 @discussion Listens on a TCP port using non-blocking BSD sockets with
 dispatch_source for incoming connection notification.

 @see PDSNetworkListener
 */
@interface PDSNetworkListenerLinux : NSObject <PDSNetworkListener>

/*!
 @method initWithPort:

 @abstract Creates a listener bound to the specified port.

 @param port The port number (0 for ephemeral port assignment).

 @return An initialized listener (starts in Waiting state).
 */
- (instancetype)initWithPort:(NSUInteger)port;

/*!
 @method initWithHost:port:

 @abstract Creates a listener bound to the specified host+port.

 @discussion This is used for local-only listeners (e.g. 127.0.0.1) where binding
 to all interfaces is undesirable.

 @param host The local host/interface to bind to, or nil for all interfaces.

 @param port The port number (0 for ephemeral port assignment).

 @return An initialized listener (starts in Waiting state).
 */
- (instancetype)initWithHost:(nullable NSString *)host port:(NSUInteger)port;

@end

NS_ASSUME_NONNULL_END
