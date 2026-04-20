#import "Network/HttpProtocolSession.h"

@interface HttpProtocolSession ()
@property(nonatomic, strong, readwrite) Http1Parser *parser;
@property(nonatomic, strong, readwrite) Http1PipelinePolicy *pipelinePolicy;
@property(nonatomic, strong) NSMutableArray<HttpRequest *> *pendingRequests;
@property(nonatomic, assign) NSTimeInterval headerStartTime;
@end

@implementation HttpProtocolSession

- (instancetype)init {
  self = [super init];
  if (self) {
    _parser = [[Http1Parser alloc] init];
    _pipelinePolicy = [[Http1PipelinePolicy alloc] init];
    _pendingRequests = [NSMutableArray array];
    _headerStartTime = [NSDate timeIntervalSinceReferenceDate];
    _upgradedToWebSocket = NO;
  }
  return self;
}

- (NSArray<NSNumber *> *)feedData:(NSData *)data {
  if (self.upgradedToWebSocket) {
    return @[];
  }

  NSMutableArray<NSNumber *> *events = [NSMutableArray array];
  BOOL completeOrError = [self.parser feedData:data];

  if (!completeOrError) {
    return events;
  }

  Http1ParserError *parseError = [self.parser parseError];
  if (parseError) {
    [events addObject:@(HttpSessionEventError)];
    return events;
  }

  HttpRequest *request = [self.parser completedRequest];
  if (!request) {
    return events;
  }

  // Check for upgrade header
  if ([request headerForKey:@"upgrade"] != nil) {
    [events addObject:@(HttpSessionEventUpgrade)];
    // Driver will handle the actual upgrade logic
  }

  Http1PipelineAction action = [self.pipelinePolicy requestParsed];
  if (action == Http1PipelineActionDispatch || action == Http1PipelineActionQueue) {
    [self.pendingRequests addObject:request];
    [events addObject:@(HttpSessionEventRequestReady)];

    NSData *unconsumed = [self.parser unconsumedData];
    [self resetForNextRequest];

    // Recurse internally for pipelined data
    if (unconsumed.length > 0) {
      [events addObjectsFromArray:[self feedData:unconsumed]];
    }
  }

  return events;
}

- (nullable HttpRequest *)nextRequestToDispatch {
  if (self.pendingRequests.count > 0 && [self.pipelinePolicy shouldReadMoreData]) {
    HttpRequest *request = self.pendingRequests[0];
    [self.pendingRequests removeObjectAtIndex:0];
    [self.pipelinePolicy requestDispatched];
    return request;
  }
  return nil;
}

- (void)queueResponse:(HttpResponse *)response {
  // This just signals that a response was finished for the policy.
  // The driver still manages the actual network output queue (for now).
  [self.pipelinePolicy responseCompleted];
}

- (void)resetForNextRequest {
  [self.parser reset];
  self.headerStartTime = [NSDate timeIntervalSinceReferenceDate];
}

@end
