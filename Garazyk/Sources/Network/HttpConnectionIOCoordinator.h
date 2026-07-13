// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpConnectionIOCoordinator.h

 @abstract Coordinates I/O and protocol driving for HTTP connections.

 @discussion Orchestrates the interaction between a network connection,
 HTTP protocol driver, and response sender. Manages the read loop,
 protocol event routing, and backpressure.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

/**
 * @abstract Defines the ATProtoNetworkConnection protocol contract.
 */
@protocol ATProtoNetworkConnection;
@class HttpProtocolDriver;
@class HttpResponseSender;
@class HttpRequest;

NS_ASSUME_NONNULL_BEGIN

/*!

 @abstract Callback when an HTTP request is ready for dispatch.

 @param request The parsed HTTP request.
 */
typedef void (^HttpIORequestReadyHandler)(HttpRequest *request);

/*!

 @abstract Callback when a protocol upgrade is requested.

 @param request The upgrade request.
 */
typedef void (^HttpIOUpgradeHandler)(HttpRequest *request);

/*!

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
/**
 * @abstract Performs the initWithConnection operation.
 */
- (instancetype)initWithConnection:(id<ATProtoNetworkConnection>)connection
                           protocol:(HttpProtocolDriver *)driver
                    responseSender:(HttpResponseSender *)sender;

/*!
 @method initWithConnection:protocol:responseSender:idleHeaderTimeout:aggregateHeaderTimeout:

 @abstract Initializes the coordinator with explicit HTTP header deadlines.

 @param idleHeaderTimeout Maximum time to wait for the next header byte while a receive is pending.
 @param aggregateHeaderTimeout Maximum time from the first byte of a header until that header completes.

 @discussion The ordinary initializer uses the production defaults (30 seconds for each deadline).
 This initializer exists so tests and callers with an explicit policy can inject different positive
 limits. The aggregate deadline does not reset as individual header bytes arrive.
 */
- (instancetype)initWithConnection:(id<ATProtoNetworkConnection>)connection
                           protocol:(HttpProtocolDriver *)driver
                    responseSender:(HttpResponseSender *)sender
                 idleHeaderTimeout:(NSTimeInterval)idleHeaderTimeout
            aggregateHeaderTimeout:(NSTimeInterval)aggregateHeaderTimeout NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Returns the operation result.
 */
- (instancetype)init NS_UNAVAILABLE;

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
