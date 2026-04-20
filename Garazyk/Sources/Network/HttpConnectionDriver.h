#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpProtocolSession;

@interface HttpConnectionDriver : NSObject

- (BOOL)shouldBeginReadForSession:(HttpProtocolSession *)session
                  outputQueueSize:(NSUInteger)outputQueueSize
                     headerOpened:(NSTimeInterval)headerOpened
                              now:(NSTimeInterval)now
                    headerTimeout:(NSTimeInterval)headerTimeout;

- (BOOL)shouldResumeReadForSession:(HttpProtocolSession *)session
                   outputQueueSize:(NSUInteger)outputQueueSize;

@end

NS_ASSUME_NONNULL_END
