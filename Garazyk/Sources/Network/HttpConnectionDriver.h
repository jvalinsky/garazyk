/*!
 @file HttpConnectionDriver.h

 @abstract Coordinates per-connection HTTP processing lifecycle and dispatch handoff.

 @discussion Declares the driver contract that bridges low-level connection reads/writes with protocol parsing and request dispatch flow. Owns connection-level orchestration boundaries, not endpoint domain logic.
 */

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
