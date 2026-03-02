#import "Network/Http1PipelinePolicy.h"

@implementation Http1PipelinePolicy

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxPipelinedRequests = 4;
        _pendingDispatchCount = 0;
    }
    return self;
}

- (Http1PipelineAction)requestParsed {
    if (self.pendingDispatchCount < self.maxPipelinedRequests) {
        return Http1PipelineActionDispatch;
    } else {
        return Http1PipelineActionQueue;
    }
}

- (void)requestDispatched {
    _pendingDispatchCount++;
}

- (void)responseCompleted {
    if (_pendingDispatchCount > 0) {
        _pendingDispatchCount--;
    }
}

- (BOOL)shouldReadMoreData {
    return (self.pendingDispatchCount < self.maxPipelinedRequests);
}

- (void)reset {
    _pendingDispatchCount = 0;
}

@end
