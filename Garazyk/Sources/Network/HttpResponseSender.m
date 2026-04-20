#import "Network/HttpResponseSender.h"

@implementation HttpResponseSender

- (BOOL)shouldTrimQueueWithCurrentSize:(NSUInteger)queueSize
                         highWaterMark:(NSUInteger)highWaterMark {
  return queueSize > highWaterMark;
}

- (NSUInteger)clampedQueueSizeAfterDequeue:(NSUInteger)queueSize
                                 itemBytes:(NSUInteger)itemBytes {
  return queueSize > itemBytes ? (queueSize - itemBytes) : 0;
}

@end
