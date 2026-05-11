// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file Http1PipelinePolicy.h

 @abstract Defines policy decisions for HTTP/1.x request pipelining behavior.

 @discussion Declares controls for whether sequential requests may be processed or must be serialized under current connection state. Encapsulates pipelining safety criteria separately from parser and business logic.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, Http1PipelineAction) {
    Http1PipelineActionDispatch,      // dispatch this request now
    Http1PipelineActionQueue,         // queue for later (pipeline full)
    Http1PipelineActionReadMore,      // connection idle, read more data
    Http1PipelineActionClose          // connection should close
};

@interface Http1PipelinePolicy : NSObject

@property (nonatomic, assign) NSUInteger maxPipelinedRequests; // default 4
@property (nonatomic, readonly) NSUInteger pendingDispatchCount;

// Called when a request has been fully parsed
- (Http1PipelineAction)requestParsed;

// Called when a queued request is about to be dispatched
- (void)requestDispatched;

// Called when a response has been completely sent
- (void)responseCompleted;

// Returns YES if we should read more data from the socket
- (BOOL)shouldReadMoreData;

// Reset state
- (void)reset;

@end

NS_ASSUME_NONNULL_END
