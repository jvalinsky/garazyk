// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpProtocolDriver.h

 @abstract Protocol-level coordination for HTTP/1.1 session management.

 @discussion Encapsulates HTTP parsing, session state, pipelining, and
 protocol events. This is a Sans-I/O component that takes raw bytes and
 returns events for the application layer to handle.

 Does not perform I/O itself; the caller is responsible for feeding data
 from the network and sending responses.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpProtocolSession;

NS_ASSUME_NONNULL_BEGIN

/*!

 @abstract Protocol-level events returned by the driver.
 */
typedef NS_ENUM(NSInteger, HttpProtocolEvent) {
    HttpProtocolEventRequestReady,      // A request is ready to dispatch
    HttpProtocolEventUpgradeRequested,  // Connection should upgrade (WebSocket)
    HttpProtocolEventProtocolError,     // Parse error or protocol violation
    HttpProtocolEventConnectionClose    // Connection should close
};

/*!
 @class HttpProtocolDriver

 @abstract Sans-I/O HTTP/1.1 protocol coordination.

 @discussion Manages the protocol session, feeds data, and generates events.
 The caller feeds raw bytes via feedData: and receives events via the returned
 array. The caller is responsible for sending responses and managing I/O.
 */
@interface HttpProtocolDriver : NSObject

/*!
 @property session

 @abstract The underlying protocol session (contains parser and pipeline policy).
 */
@property (nonatomic, readonly) HttpProtocolSession *session;

/*!
 @method feedData:

 @abstract Feeds raw bytes from the network into the protocol state machine.

 @param data The bytes received from the network.

 @return An array of NSNumber* values (cast to HttpProtocolEvent) indicating
 what the driver detected.

 @discussion Processes the data through the HTTP parser, coordinates with
 pipelining policy, and returns events. Multiple events may be returned
 for a single feed() call (e.g., RequestReady + another RequestReady).
 */
- (NSArray<NSNumber *> *)feedData:(NSData *)data;

/*!
 @method nextDispatchableRequest

 @abstract Retrieves the next request that is ready and allowed by policy.

 @return The request to dispatch, or nil if none are available or allowed.

 @discussion The caller should call this after receiving HttpProtocolEventRequestReady.
 Requests are held in the session's pending queue until pipelining policy allows.
 */
- (nullable HttpRequest *)nextDispatchableRequest;

/*!
 @method currentUpgradeRequest

 @abstract Returns the request that triggered an upgrade event.

 @return The request with the Upgrade header, or nil if no upgrade.
 */
- (nullable HttpRequest *)currentUpgradeRequest;

/*!
 @method currentParseError

 @abstract Returns the most recent protocol error, if any.

 @return The parser error details, or nil if no error.
 */
- (nullable NSError *)currentParseError;

/*!
 @method setRemoteAddressForRequests:

 @abstract Sets the remote peer IP address on all parsed requests.

 @param remoteAddress The remote IP or hostname (for logging/rate-limiting).

 @discussion Called after connection is established to tag all future
 requests with the peer address.
 */
- (void)setRemoteAddressForRequests:(nullable NSString *)remoteAddress;

/*!
 @method shouldContinueReading:outputQueueSize:headerAge:

 @abstract Determines whether more data should be read from the network.

 @param headerStartTime When the first byte of the current request header was received.
 @param outputQueueSize Current number of bytes in the response queue.
 @param headerTimeout Maximum age before header parse times out (in seconds).

 @return YES if reading should continue, NO if should pause or close.

 @discussion Implements backpressure by checking:
 - Whether pipelining policy allows reading
 - Whether response queue is backed up
 - Whether header parse has timed out
 */
- (BOOL)shouldContinueReading:(NSTimeInterval)headerStartTime
                outputQueueSize:(NSUInteger)outputQueueSize
                   headerTimeout:(NSTimeInterval)headerTimeout
                             now:(NSTimeInterval)now;

/*!
 @method pendingRequestCount

 @abstract Number of requests parsed but not yet fully responded to.

 @return Count of pending requests in the session.

 @discussion Used for backpressure calculation and debugging.
 */
- (NSUInteger)pendingRequestCount;

- (void)responseDidFinishSending;

@end

NS_ASSUME_NONNULL_END
