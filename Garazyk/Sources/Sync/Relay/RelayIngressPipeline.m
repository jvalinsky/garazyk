// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayIngressPipeline.h"
#import "Sync/Relay/RelayIngressConfiguration.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Firehose/Firehose.h"
#import "Debug/GZLogger.h"

// Bound on how long -shutdownWithCompletion: blocks waiting for in-flight
// work items to drain before reporting a timeout instead of a clean drain.
static const NSTimeInterval RelayIngressPipelineShutdownDrainTimeout = 5.0;

static void *RelayIngressPipelineControlQueueKey = &RelayIngressPipelineControlQueueKey;

typedef struct {
    id event;
    NSString *upstreamURL;
    int64_t sequence;
    ATProtoRelayIngressAdmissionToken *token;
    NSTimeInterval submittedAt;
} RelayIngressWorkItem;

@interface ATProtoRelayIngressPipeline ()
@property (nonatomic, strong) ATProtoRelayIngressConfiguration *configuration;
@property (nonatomic, weak, nullable) ATProtoRelayMetrics *metrics;
@property (nonatomic, copy) RelayIngressProcessBlock processBlock;
@property (nonatomic, strong) ATProtoRelayIngressAdmission *admission;
@property (nonatomic, strong) NSArray<dispatch_queue_t> *shardQueues;
@property (nonatomic, assign, readwrite) int64_t lastReceivedSequence;
@property (nonatomic, assign, readwrite) int64_t lastAdmittedSequence;
@property (nonatomic, assign, readwrite) int64_t lastProcessedSequence;
@property (nonatomic, assign) BOOL shuttingDown;
@property (nonatomic, assign) NSUInteger pendingWorkItems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastProcessedByUpstream;
@end

@implementation ATProtoRelayIngressPipeline {
    dispatch_queue_t _controlQueue;
    // Entered once per admitted work item (in -submitEvent:...) and left
    // exactly once when that item's fate is decided (shutdown-drop,
    // no-processBlock-drop, or normal completion in -dispatchWorkItem:
    // toShard:). Lets -shutdownWithCompletion: block deterministically
    // until every admitted item has actually been released, instead of
    // busy-polling pendingWorkItems via the run loop.
    dispatch_group_t _drainGroup;
    // Tokens for work items that have been admitted (in -submitEvent:...)
    // but not yet had their fate decided by -dispatchWorkItem:toShard:,
    // keyed by upstream URL. Confined to _controlQueue exactly like
    // _lastProcessedByUpstream. Lets -noteUpstreamDisconnected: release a
    // disconnected upstream's still-in-flight tokens (F10) without touching
    // pendingWorkItems/_drainGroup, which stay the exclusive responsibility
    // of -dispatchWorkItem:toShard:.
    NSMutableDictionary<NSString *, NSMutableSet<ATProtoRelayIngressAdmissionToken *> *> *_inFlightTokensByUpstream;
}

+ (NSString *)orderingKeyForEvent:(id)event upstreamURL:(NSString *)upstreamURL {
    if ([event isKindOfClass:[ATProtoFirehoseCommitEvent class]]) {
        return ((ATProtoFirehoseCommitEvent *)event).repo ?: upstreamURL;
    }
    if ([event isKindOfClass:[ATProtoFirehoseIdentityEvent class]]) {
        return ((ATProtoFirehoseIdentityEvent *)event).did ?: upstreamURL;
    }
    if ([event isKindOfClass:[ATProtoFirehoseAccountEvent class]]) {
        return ((ATProtoFirehoseAccountEvent *)event).did ?: upstreamURL;
    }
    if ([event isKindOfClass:[ATProtoFirehoseSyncEvent class]]) {
        return ((ATProtoFirehoseSyncEvent *)event).did ?: upstreamURL;
    }
    if ([event isKindOfClass:[ATProtoFirehoseRawEvent class]]) {
        ATProtoFirehoseRawEvent *raw = (ATProtoFirehoseRawEvent *)event;
        id repo = raw.payload[@"repo"];
        if ([repo isKindOfClass:[NSString class]] && [(NSString *)repo length] > 0) {
            return repo;
        }
        id did = raw.payload[@"did"];
        if ([did isKindOfClass:[NSString class]] && [(NSString *)did length] > 0) {
            return did;
        }
    }
    return upstreamURL.length > 0 ? upstreamURL : @"__global__";
}

// Decoded-cost multiplier (finding F13): the wire-encoded byte length alone undercounts the
// actual heap cost of holding a *decoded* event object in the backlog while it waits on a
// shard queue. RelayIngressDecodedCostBenchmarkTests (Garazyk/Tests/Sync/) measured this via
// RSS delta across batches of realistic events: commit events -- the dominant contributor to
// real ingress backlog bytes, since identity/account/sync events are comparatively tiny and
// low-volume -- came back at ~4-5x wireFrameLength (3.90x for 100 KB blocks, 4.75x for 10 KB
// blocks; smaller per-event fixed overhead is proportionally larger against a smaller block
// size, hence the smaller blocks showing the higher ratio). Identity/account/sync events
// measured well under 1x, so applying this multiplier uniformly stays conservative for them
// too -- their absolute byte cost is negligible relative to the byte cap either way, so
// over-counting them by the same factor doesn't meaningfully shrink real capacity for the
// events that actually matter. 5 rounds up from the higher observed commit ratio (4.75).
static const uint64_t kRelayIngressDecodedCostMultiplier = 5;

static uint64_t RelayIngressWireByteLengthForEvent(id event) {
    if ([event isKindOfClass:[ATProtoFirehoseCommitEvent class]]) {
        NSUInteger length = ((ATProtoFirehoseCommitEvent *)event).wireFrameLength;
        if (length > 0) {
            return (uint64_t)length;
        }
    }
    if ([event isKindOfClass:[ATProtoFirehoseIdentityEvent class]]) {
        NSUInteger length = ((ATProtoFirehoseIdentityEvent *)event).wireFrameLength;
        if (length > 0) {
            return (uint64_t)length;
        }
    }
    if ([event isKindOfClass:[ATProtoFirehoseAccountEvent class]]) {
        NSUInteger length = ((ATProtoFirehoseAccountEvent *)event).wireFrameLength;
        if (length > 0) {
            return (uint64_t)length;
        }
    }
    if ([event isKindOfClass:[ATProtoFirehoseSyncEvent class]]) {
        NSUInteger length = ((ATProtoFirehoseSyncEvent *)event).wireFrameLength;
        if (length > 0) {
            return (uint64_t)length;
        }
    }
    if ([event isKindOfClass:[ATProtoFirehoseRawEvent class]]) {
        return (uint64_t)((ATProtoFirehoseRawEvent *)event).frameData.length;
    }
    if ([event isKindOfClass:[ATProtoFirehoseCommitEvent class]]) {
        ATProtoFirehoseCommitEvent *commit = (ATProtoFirehoseCommitEvent *)event;
        uint64_t estimate = (uint64_t)commit.blocks.length + 4096;
        return MAX((uint64_t)1, estimate);
    }
    return 1024;
}

+ (uint64_t)encodedByteLengthForEvent:(id)event {
    return RelayIngressWireByteLengthForEvent(event) * kRelayIngressDecodedCostMultiplier;
}

- (NSUInteger)shardIndexForOrderingKey:(NSString *)orderingKey {
    if (self.configuration.shardCount <= 1) {
        return 0;
    }
    NSUInteger hash = (NSUInteger)orderingKey.hash;
    return hash % self.configuration.shardCount;
}

- (instancetype)initWithConfiguration:(ATProtoRelayIngressConfiguration *)configuration
                              metrics:(ATProtoRelayMetrics *)metrics
                         processBlock:(RelayIngressProcessBlock)processBlock {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _metrics = metrics;
        _processBlock = [processBlock copy];
        _admission = [[ATProtoRelayIngressAdmission alloc] initWithConfiguration:configuration
                                                                         metrics:metrics];
        _controlQueue = dispatch_queue_create("com.atproto.relay.ingress.control",
                                              DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_controlQueue,
                                    RelayIngressPipelineControlQueueKey,
                                    (__bridge void *)self,
                                    NULL);
        _drainGroup = dispatch_group_create();
        _lastProcessedByUpstream = [NSMutableDictionary dictionary];
        _inFlightTokensByUpstream = [NSMutableDictionary dictionary];

        NSMutableArray<dispatch_queue_t> *queues = [NSMutableArray arrayWithCapacity:configuration.shardCount];
        for (NSUInteger shard = 0; shard < configuration.shardCount; shard++) {
            const char *label = [[NSString stringWithFormat:@"com.atproto.relay.ingress.shard.%lu",
                                    (unsigned long)shard] UTF8String];
            dispatch_queue_t queue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);
            [queues addObject:queue];
        }
        _shardQueues = [queues copy];

        __weak typeof(self) weakSelf = self;
        _admission.onHighWatermark = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            id<RelayIngressBackpressureDelegate> delegate = strongSelf.backpressureDelegate;
            if (delegate) {
                [delegate ingressPipelineDidRequestPause:strongSelf];
            }
        };
        _admission.onLowWatermark = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            id<RelayIngressBackpressureDelegate> delegate = strongSelf.backpressureDelegate;
            if (delegate) {
                [delegate ingressPipelineDidRequestResume:strongSelf];
            }
        };
    }
    return self;
}

- (void)performOnControlQueue:(dispatch_block_t)block {
    if (dispatch_get_specific(RelayIngressPipelineControlQueueKey) == (__bridge void *)self) {
        block();
    } else {
        dispatch_sync(_controlQueue, block);
    }
}

// Custom getters only (setters stay auto-synthesized): every write to these
// three properties already happens from inside a _controlQueue-confined
// block (see -submitEvent:... and -dispatchWorkItem:toShard:), but the
// default getter does not go through the queue, so an external caller --
// e.g. a test reading pipeline.lastProcessedSequence, or a future caller of
// lastReceivedSequence/lastAdmittedSequence -- would race the async writes.
// -performOnControlQueue:'s self-detection guard matters here specifically
// because these getters are also called internally from code that is
// *already* running on _controlQueue (the compare-then-set checks at lines
// below); a plain dispatch_sync from there would deadlock.
- (int64_t)lastReceivedSequence {
    __block int64_t value = 0;
    [self performOnControlQueue:^{
        value = self->_lastReceivedSequence;
    }];
    return value;
}

- (int64_t)lastAdmittedSequence {
    __block int64_t value = 0;
    [self performOnControlQueue:^{
        value = self->_lastAdmittedSequence;
    }];
    return value;
}

- (int64_t)lastProcessedSequence {
    __block int64_t value = 0;
    [self performOnControlQueue:^{
        value = self->_lastProcessedSequence;
    }];
    return value;
}

- (void)dispatchWorkItem:(RelayIngressWorkItem)item toShard:(NSUInteger)shardIndex {
    // Record shard dispatch immediately
    [self.metrics recordIngressShardDispatch:shardIndex];

    dispatch_queue_t shardQueue = self.shardQueues[shardIndex];
    dispatch_async(shardQueue, ^{
        if (self.shuttingDown) {
            NSError *releaseError = nil;
            [self.admission releaseToken:item.token
                                  reason:RelayIngressReleaseReasonShutdown
                                   error:&releaseError];
            dispatch_async(self->_controlQueue, ^{
                [self removeInFlightToken:item.token forUpstream:item.upstreamURL];
                if (self.pendingWorkItems > 0) {
                    self.pendingWorkItems--;
                }
                dispatch_group_leave(self->_drainGroup);
            });
            return;
        }

        NSTimeInterval queuedAt = [[NSDate date] timeIntervalSinceReferenceDate];
        // Compute real queue delay: time from submission to shard queue dispatch
        NSTimeInterval queueDelayMs = (queuedAt - item.submittedAt) * 1000.0;
        [self.metrics recordIngressQueueDelayMs:queueDelayMs];

        RelayIngressProcessBlock processBlock = self.processBlock;
        if (!processBlock) {
            NSError *releaseError = nil;
            [self.admission releaseToken:item.token
                                  reason:RelayIngressReleaseReasonRejected
                                   error:&releaseError];
            dispatch_async(self->_controlQueue, ^{
                [self removeInFlightToken:item.token forUpstream:item.upstreamURL];
                if (self.pendingWorkItems > 0) {
                    self.pendingWorkItems--;
                }
                dispatch_group_leave(self->_drainGroup);
            });
            return;
        }

        processBlock(item.event, item.upstreamURL, item.sequence, ^(RelayIngressReleaseReason reason) {
            NSTimeInterval serviceMs =
                ([[NSDate date] timeIntervalSinceReferenceDate] - queuedAt) * 1000.0;
            [self.metrics recordIngressWorkerServiceTimeMs:serviceMs];
            NSError *releaseError = nil;
            [self.admission releaseToken:item.token reason:reason error:&releaseError];
            dispatch_async(self->_controlQueue, ^{
                [self removeInFlightToken:item.token forUpstream:item.upstreamURL];
                if (item.sequence > self.lastProcessedSequence) {
                    self.lastProcessedSequence = item.sequence;
                }
                int64_t previous = [self.lastProcessedByUpstream[item.upstreamURL] longLongValue];
                if (item.sequence > previous) {
                    self.lastProcessedByUpstream[item.upstreamURL] = @(item.sequence);
                }
                if (self.pendingWorkItems > 0) {
                    self.pendingWorkItems--;
                }
                dispatch_group_leave(self->_drainGroup);
            });
        });
    });
}

- (BOOL)submitEvent:(id)event
       encodedBytes:(uint64_t)encodedBytes
       orderingKey:(NSString *)orderingKey
      fromUpstream:(NSString *)upstreamURL
          sequence:(int64_t)sequence
             error:(NSError * _Nullable * _Nullable)error {
    __block BOOL accepted = NO;
    __block NSError *localError = nil;
    dispatch_sync(_controlQueue, ^{
        if (self.shuttingDown) {
            localError = [NSError errorWithDomain:RelayIngressAdmissionErrorDomain
                                              code:RelayIngressAdmissionErrorCodeRejected
                                          userInfo:@{NSLocalizedDescriptionKey: @"Ingress pipeline is shutting down"}];
            return;
        }
        if (sequence > self.lastReceivedSequence) {
            self.lastReceivedSequence = sequence;
        }

        ATProtoRelayIngressAdmissionToken *token =
            [self.admission admitEncodedBytes:encodedBytes
                                  upstreamURL:upstreamURL
                                     sequence:sequence
                                        error:&localError];
        if (!token) {
            return;
        }
        if (sequence > self.lastAdmittedSequence) {
            self.lastAdmittedSequence = sequence;
        }

        RelayIngressWorkItem item = {
            .event = event,
            .upstreamURL = [upstreamURL copy],
            .sequence = sequence,
            .token = token,
            .submittedAt = [[NSDate date] timeIntervalSinceReferenceDate],
        };
        self.pendingWorkItems++;
        dispatch_group_enter(self->_drainGroup);
        NSMutableSet<ATProtoRelayIngressAdmissionToken *> *inFlight = self->_inFlightTokensByUpstream[item.upstreamURL];
        if (!inFlight) {
            inFlight = [NSMutableSet set];
            self->_inFlightTokensByUpstream[item.upstreamURL] = inFlight;
        }
        [inFlight addObject:token];
        accepted = YES;
        NSUInteger shardIndex = [self shardIndexForOrderingKey:orderingKey ?: upstreamURL];
        [self dispatchWorkItem:item toShard:shardIndex];
    });
    if (error) {
        *error = localError;
    }
    return accepted;
}

// Must be called from _controlQueue. Removes a single token from the
// in-flight tracking set, deleting the upstream's entry entirely once it is
// empty so -noteUpstreamDisconnected: has nothing to iterate for upstreams
// with no outstanding work.
- (void)removeInFlightToken:(ATProtoRelayIngressAdmissionToken *)token forUpstream:(NSString *)upstreamURL {
    NSMutableSet<ATProtoRelayIngressAdmissionToken *> *inFlight = self->_inFlightTokensByUpstream[upstreamURL];
    if (!inFlight) {
        return;
    }
    [inFlight removeObject:token];
    if (inFlight.count == 0) {
        [self->_inFlightTokensByUpstream removeObjectForKey:upstreamURL];
    }
}

- (void)noteUpstreamDisconnected:(NSString *)upstreamURL {
    // Fire-and-forget: the only callsite (RelayUpstreamManager, from inside
    // its own dispatch_async on _managerQueue) does not need to block on
    // this completing, and a plain async avoids adding a cross-queue
    // synchronous hop.
    dispatch_async(_controlQueue, ^{
        NSMutableSet<ATProtoRelayIngressAdmissionToken *> *inFlight = self->_inFlightTokensByUpstream[upstreamURL];
        if (inFlight.count == 0) {
            return;
        }
        // Snapshot before iterating: -releaseToken:reason:error: does not
        // mutate this set itself, but iterate a copy defensively so nothing
        // here depends on that staying true.
        for (ATProtoRelayIngressAdmissionToken *token in [inFlight copy]) {
            NSError *releaseError = nil;
            // -dispatchWorkItem:toShard: remains the sole owner of
            // pendingWorkItems/_drainGroup bookkeeping; this only releases
            // the admission-backlog capacity early. When the shard queue
            // eventually reaches this same token, its own releaseToken:
            // call double-releases harmlessly (records a metric, returns
            // NO) -- see ATProtoRelayIngressAdmission's double-release
            // guard.
            [self.admission releaseToken:token
                                  reason:RelayIngressReleaseReasonDisconnect
                                   error:&releaseError];
        }
        [self->_inFlightTokensByUpstream removeObjectForKey:upstreamURL];
    });
}

- (int64_t)lastProcessedSequenceForUpstream:(NSString *)upstreamURL {
    __block int64_t sequence = 0;
    dispatch_sync(_controlQueue, ^{
        sequence = [self.lastProcessedByUpstream[upstreamURL] longLongValue];
    });
    return sequence;
}

- (NSDictionary<NSString *, NSNumber *> *)inFlightByteCountByUpstream {
    NSMutableDictionary<NSString *, NSNumber *> *totals = [NSMutableDictionary dictionary];
    [self performOnControlQueue:^{
        for (NSString *upstreamURL in self->_inFlightTokensByUpstream) {
            uint64_t total = 0;
            for (ATProtoRelayIngressAdmissionToken *token in self->_inFlightTokensByUpstream[upstreamURL]) {
                total += token.encodedBytes;
            }
            totals[upstreamURL] = @(total);
        }
    }];
    return totals;
}

- (void)shutdownWithCompletion:(void (^)(BOOL drained))completion {
    dispatch_sync(_controlQueue, ^{
        self.shuttingDown = YES;
    });
    // Deterministic drain: every admitted item enters _drainGroup in
    // -submitEvent:... and leaves it exactly once its fate is decided in
    // -dispatchWorkItem:toShard:. dispatch_group_wait blocks the calling
    // thread (any GCD context, no run loop required) until the group is
    // empty or the bound elapses, unlike the run-loop-pumping busy-wait
    // -waitForDrainForTesting uses.
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(RelayIngressPipelineShutdownDrainTimeout * NSEC_PER_SEC));
    long waitResult = dispatch_group_wait(_drainGroup, timeout);
    BOOL drained = (waitResult == 0);
    if (!drained) {
        GZ_LOG_SYNC_WARN(@"RelayIngressPipeline: shutdown drain timed out after %.1fs with %lu pending work item(s)",
                         RelayIngressPipelineShutdownDrainTimeout,
                         (unsigned long)self.pendingWorkItems);
    }
    if (completion) {
        completion(drained);
    }
}

- (void)waitForDrainForTesting {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        __block NSUInteger pending = 0;
        dispatch_sync(_controlQueue, ^{
            pending = self.pendingWorkItems;
        });
        if (pending == 0 &&
            [self.admission currentEventCount] == 0 &&
            [self.admission currentByteCount] == 0) {
            return;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

@end
