#import "Network/HttpConnectionDriver.h"

#import "Network/HttpProtocolSession.h"

@implementation HttpConnectionDriver

- (BOOL)shouldBeginReadForSession:(HttpProtocolSession *)session
                  outputQueueSize:(NSUInteger)outputQueueSize
                     headerOpened:(NSTimeInterval)headerOpened
                              now:(NSTimeInterval)now
                    headerTimeout:(NSTimeInterval)headerTimeout {
  if (session.upgradedToWebSocket) {
    return NO;
  }
  if (session.pendingDispatchCount > 0 || outputQueueSize > 0) {
    return NO;
  }
  if (now - headerOpened > headerTimeout) {
    return NO;
  }
  return YES;
}

- (BOOL)shouldResumeReadForSession:(HttpProtocolSession *)session
                   outputQueueSize:(NSUInteger)outputQueueSize {
  return outputQueueSize == 0 && [session shouldReadMoreData];
}

@end
