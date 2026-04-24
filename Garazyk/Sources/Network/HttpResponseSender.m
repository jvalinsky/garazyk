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
