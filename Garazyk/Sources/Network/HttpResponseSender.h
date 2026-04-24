/*!
 @file HttpResponseSender.h

 @abstract Manages HTTP response queueing, streaming, and backpressure.

 @discussion Encapsulates response queue management, including:
 - Queueing responses for serialization
 - Managing large file and generated chunk streaming
 - Calculating and enforcing backpressure limits

 This component separates response handling logic from connection management.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class HttpResponse;

NS_ASSUME_NONNULL_BEGIN

// Forward declare HttpQueuedResponse; full definition is in HttpServer.h
@class HttpQueuedResponse;

/*!
 @class HttpResponseSender

 @abstract Manages HTTP response queueing and transmission.

 @discussion Handles serialization of responses into queued items, manages
 backpressure by checking queue size, and coordinates with the I/O layer
 for transmission.
 */
@interface HttpResponseSender : NSObject

/*!
 @property maxQueueSize

 @abstract Maximum cumulative bytes in the response queue before backpressure.

 Default is 10MB.
 */
@property (nonatomic, assign) NSUInteger maxQueueSize;

/*!
 @property highWaterMark

 @abstract Threshold for backpressure alert (read limiting).

 Default is maxQueueSize.
 */
@property (nonatomic, assign) NSUInteger highWaterMark;


/*!
 @method shouldTrimQueueWithCurrentSize:highWaterMark:

 @abstract Checks if the queue has exceeded the high water mark.

 @param queueSize Current total bytes in queue.
 @param highWaterMark Backpressure threshold.

 @return YES if queue size exceeds high water mark.

 @discussion Used for read flow control: if true, pause reading.
 */
- (BOOL)shouldTrimQueueWithCurrentSize:(NSUInteger)queueSize
                         highWaterMark:(NSUInteger)highWaterMark;

/*!
 @method clampedQueueSizeAfterDequeue:itemBytes:

 @abstract Updates queue size after an item is dequeued.

 @param queueSize Current queue size.
 @param itemBytes Bytes in the item being removed.

 @return Updated queue size (clamped to 0).

 @discussion Safely subtracts item size from queue total.
 */
- (NSUInteger)clampedQueueSizeAfterDequeue:(NSUInteger)queueSize
                                 itemBytes:(NSUInteger)itemBytes;

/*!
 @method hasBackpressure:

 @abstract Checks if response queue has backed up.

 @param queueSize Current queue size.

 @return YES if queue is at or above high water mark.

 @discussion Used by HTTP driver to decide whether to read more data.
 */
- (BOOL)hasBackpressure:(NSUInteger)queueSize;

@end

NS_ASSUME_NONNULL_END
