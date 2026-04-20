#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HttpResponseSender : NSObject

- (BOOL)shouldTrimQueueWithCurrentSize:(NSUInteger)queueSize
                         highWaterMark:(NSUInteger)highWaterMark;

- (NSUInteger)clampedQueueSizeAfterDequeue:(NSUInteger)queueSize
                                 itemBytes:(NSUInteger)itemBytes;

@end

NS_ASSUME_NONNULL_END
