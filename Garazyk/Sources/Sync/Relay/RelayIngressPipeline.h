// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayIngressPipeline.h

 @abstract Bounded ordered ingress executor with admission and cursor seams.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <stdint.h>
#import "Sync/Relay/RelayIngressAdmission.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoRelayIngressConfiguration;
@class ATProtoRelayIngressPipeline;
@class ATProtoRelayMetrics;

typedef void (^RelayIngressProcessCompletion)(RelayIngressReleaseReason reason);
typedef void (^RelayIngressProcessBlock)(id event,
                                         NSString *upstreamURL,
                                         int64_t sequence,
                                         RelayIngressProcessCompletion completion);

@protocol RelayIngressBackpressureDelegate <NSObject>
- (void)ingressPipelineDidRequestPause:(ATProtoRelayIngressPipeline *)pipeline;
- (void)ingressPipelineDidRequestResume:(ATProtoRelayIngressPipeline *)pipeline;
@end

/**
 * @abstract Sharded ingress executor keyed by repository DID.
 */
@interface ATProtoRelayIngressPipeline : NSObject

@property (nonatomic, weak, nullable) id<RelayIngressBackpressureDelegate> backpressureDelegate;
@property (nonatomic, strong, readonly) ATProtoRelayIngressAdmission *admission;
@property (nonatomic, assign, readonly) int64_t lastReceivedSequence;
@property (nonatomic, assign, readonly) int64_t lastAdmittedSequence;
@property (nonatomic, assign, readonly) int64_t lastProcessedSequence;

- (instancetype)initWithConfiguration:(ATProtoRelayIngressConfiguration *)configuration
                              metrics:(nullable ATProtoRelayMetrics *)metrics
                         processBlock:(RelayIngressProcessBlock)processBlock NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (BOOL)submitEvent:(id)event
       encodedBytes:(uint64_t)encodedBytes
       orderingKey:(NSString *)orderingKey
      fromUpstream:(NSString *)upstreamURL
          sequence:(int64_t)sequence
             error:(NSError * _Nullable * _Nullable)error;

/*!
 Releases every admitted-but-not-yet-processed token belonging to
 @c upstreamURL with @c RelayIngressReleaseReasonDisconnect, freeing the
 admission backlog capacity those in-flight events were holding instead of
 waiting for their shard queue to reach them naturally. Per ADR 0039 section
 3, a disconnected-and-reconnected upstream redelivers from its last
 processed cursor, so these events will be redelivered and reprocessed after
 reconnect -- there is no correctness reason to keep holding their capacity
 hostage in the meantime. Does not touch pendingWorkItems/drain-group
 accounting: -dispatchWorkItem:toShard: remains the sole owner of that
 bookkeeping, and its own (now redundant) release call on these tokens
 double-releases harmlessly once the shard queue eventually reaches them.
 */
- (void)noteUpstreamDisconnected:(NSString *)upstreamURL;
- (int64_t)lastProcessedSequenceForUpstream:(NSString *)upstreamURL;

/*!
 Returns, for each upstream with at least one admitted-but-not-yet-released
 token outstanding, the sum of those tokens' @c encodedBytes -- i.e. the
 backlog bytes that upstream is contributing to the pipeline *right now*.
 Backed by the same per-upstream token tracking @c -noteUpstreamDisconnected:
 (F10) uses. Unlike a lifetime-cumulative counter, this reflects only
 currently outstanding backlog, which is the signal selective backpressure
 (see @c -ingressPipelineDidRequestPause: in @c RelayUpstreamManager, F11)
 needs: it identifies who is contributing to the backlog *now*, not who has
 historically sent the most bytes since connecting. Upstreams with no
 in-flight tokens are omitted from the result rather than reported as zero.
 */
- (NSDictionary<NSString *, NSNumber *> *)inFlightByteCountByUpstream;

/*!
 Marks the pipeline as shutting down and blocks the calling thread until
 every admitted-but-not-yet-released work item drains, or a bounded timeout
 elapses. @c completion is invoked with @c drained==YES when the group
 emptied cleanly, or @c NO when the timeout fired first -- callers must not
 treat a timeout as a successful drain. Unlike -waitForDrainForTesting (kept
 for existing test callers), this uses a dispatch_group rather than a
 run-loop busy-wait, so it works from any GCD context, not only one with an
 actively-spinning run loop.
 */
- (void)shutdownWithCompletion:(nullable void (^)(BOOL drained))completion;
- (void)waitForDrainForTesting;

+ (NSString *)orderingKeyForEvent:(id)event upstreamURL:(NSString *)upstreamURL;
+ (uint64_t)encodedByteLengthForEvent:(id)event;

@end

NS_ASSUME_NONNULL_END
