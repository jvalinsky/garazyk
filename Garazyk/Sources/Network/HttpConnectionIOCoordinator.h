/*!
 @file HttpConnectionIOCoordinator.h

 @abstract Coordinates I/O and protocol driving for HTTP connections.

 @discussion Orchestrates the interaction between a network connection,
 HTTP protocol driver, and response sender. Manages the read loop,
 protocol event routing, and backpressure.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@protocol PDSNetworkConnection;
@class HttpProtocolDriver;
@class HttpResponseSender;
@class HttpRequest;

NS_ASSUME_NONNULL_BEGIN

/*!
 @typedef HttpIORequestReadyHandler

 @abstract Callback when an HTTP request is ready for dispatch.

 @param request The parsed HTTP request.
 */
typedef void (^HttpIORequestReadyHandler)(HttpRequest *request);

/*!
 @typedef HttpIOUpgradeHandler

 @abstract Callback when a protocol upgrade is requested.

 @param request The upgrade request.
 */
typedef void (^HttpIOUpgradeHandler)(HttpRequest *request);

/*!
 @typedef HttpIOErrorHandler

 @abstract Callback when a protocol or I/O error occurs.

 @param error The error details.
 */
typedef void (^HttpIOErrorHandler)(NSError *error);

/*!
 @class HttpConnectionIOCoordinator

 @abstract Coordinates HTTP request/response I/O and protocol driving.

 @discussion Manages the read loop from the network, feeds data to the
 protocol driver, routes events to handlers, and enforces backpressure.
 Uses a serial dispatch queue for thread-safe state management.
 */
@interface HttpConnectionIOCoordinator : NSObject

/*!
 @property requestReadyHandler

 @abstract Callback when a complete request is ready for dispatch.
 */
@property (nonatomic, copy, nullable) HttpIORequestReadyHandler requestReadyHandler;

/*!
 @property upgradeHandler

 @abstract Callback when an upgrade request is detected.
 */
@property (nonatomic, copy, nullable) HttpIOUpgradeHandler upgradeHandler;

/*!
 @property errorHandler

 @abstract Callback when a protocol error or I/O error occurs.
 */
@property (nonatomic, copy, nullable) HttpIOErrorHandler errorHandler;

/*!
 @property outputQueueSizeProvider

 @abstract Block to retrieve the current output queue size for backpressure checking.

 The coordinator calls this before scheduling the next read to check whether
 the response queue is backed up. If not provided, zero queue size is assumed.
 */
@property (nonatomic, copy, nullable) NSUInteger (^outputQueueSizeProvider)(void);

/*!
 @method initWithConnection:protocol:responseSender:

 @abstract Initializes the coordinator with its dependencies.

 @param connection The network connection to read from.
 @param driver The HTTP protocol driver to feed data to.
 @param sender The response sender for backpressure checking.

 @return An initialized coordinator.
 */
- (instancetype)initWithConnection:(id<PDSNetworkConnection>)connection
                           protocol:(HttpProtocolDriver *)driver
                       responseSender:(HttpResponseSender *)sender NS_DESIGNATED_INITIALIZER;

/*!
 @method start

 @abstract Begins the read loop and event processing.

 @discussion After calling this method, the coordinator will read from the
 connection and invoke handlers as events arrive.
 */
- (void)start;

/*!
 @method pause

 @abstract Pauses the read loop.

 @discussion Stops scheduling new reads; existing reads complete normally.
 */
- (void)pause;

/*!
 @method resume

 @abstract Resumes the read loop after a pause.

 @discussion Restarts read scheduling if currently paused.
 */
- (void)resume;

/*!
 @method close

 @abstract Closes the connection and stops all I/O.

 @discussion Stops the read loop and closes the underlying connection.
 */
- (void)close;

@end

NS_ASSUME_NONNULL_END
