// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpResponseSender.m

 @abstract Implements response emission behavior for HTTP connection write paths.

 @discussion Handles serialization and write-side response delivery behavior after handler execution, including output framing expectations for the HTTP layer. Does not decide routing or endpoint business results.
 */

#import "Network/HttpResponseSender.h"

@implementation HttpResponseSender

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxQueueSize = 10 * 1024 * 1024;  // 10MB default
        _highWaterMark = 10 * 1024 * 1024;
    }
    return self;
}

- (BOOL)shouldTrimQueueWithCurrentSize:(NSUInteger)queueSize
                         highWaterMark:(NSUInteger)highWaterMark {
    return queueSize > highWaterMark;
}

- (NSUInteger)clampedQueueSizeAfterDequeue:(NSUInteger)queueSize
                                 itemBytes:(NSUInteger)itemBytes {
    return queueSize > itemBytes ? (queueSize - itemBytes) : 0;
}

- (BOOL)hasBackpressure:(NSUInteger)queueSize {
    return queueSize >= self.highWaterMark;
}

@end
