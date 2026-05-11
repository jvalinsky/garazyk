// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file Http1PipelinePolicy.m

 @abstract Implements HTTP/1.x pipelining policy evaluation for connection safety.

 @discussion Applies protocol-aware checks to determine safe request pipeline handling on a connection. Centralizes policy decisions while leaving parsing, transport I/O, and endpoint execution to other layers.
 */

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
