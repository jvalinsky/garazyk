// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file Http1PipelinePolicy.h

 @abstract Defines policy decisions for HTTP/1.x request pipelining behavior.

 @discussion Declares controls for whether sequential requests may be processed or must be serialized under current connection state. Encapsulates pipelining safety criteria separately from parser and business logic.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Decisions returned by the HTTP/1.x pipelining policy.
 */
typedef NS_ENUM(NSInteger, Http1PipelineAction) {
    /** Dispatch this request immediately. */
    Http1PipelineActionDispatch,      // dispatch this request now
    /** Queue this request because the pipeline is full. */
    Http1PipelineActionQueue,         // queue for later (pipeline full)
    /** Read more bytes because the connection is idle. */
    Http1PipelineActionReadMore,      // connection idle, read more data
    /** Close the connection. */
    Http1PipelineActionClose          // connection should close
};

/**
 * @abstract Tracks HTTP/1.x pipelining capacity for one connection.
 */
@interface Http1PipelinePolicy : NSObject

/** Maximum number of pipelined requests allowed before queueing. */
@property (nonatomic, assign) NSUInteger maxPipelinedRequests; // default 4
/** Number of parsed requests pending dispatch or response completion. */
@property (nonatomic, readonly) NSUInteger pendingDispatchCount;

/** Records a fully parsed request and returns the next pipeline action. */
- (Http1PipelineAction)requestParsed;

/** Records that a queued request is about to be dispatched. */
- (void)requestDispatched;

/** Records that a response has been completely sent. */
- (void)responseCompleted;

/** Returns whether the connection should continue reading request bytes. */
- (BOOL)shouldReadMoreData;

/** Resets policy state for a fresh connection lifecycle. */
- (void)reset;

@end

NS_ASSUME_NONNULL_END
