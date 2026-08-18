// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayMetrics.h"

static NSString *RelayCanonicalSignatureFailureCategory(NSString *category) {
    static NSSet<NSString *> *allowedCategories;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowedCategories = [NSSet setWithArray:@[
            @"resolver-unavailable", @"did-resolution", @"did-document",
            @"signing-key", @"commit-block", @"commit-identity",
            @"signature-mismatch", @"unknown"
        ]];
    });
    return [allowedCategories containsObject:category] ? [category copy] : @"unknown";
}

@interface ATProtoRelayMetrics ()

@property (nonatomic, assign, readwrite) int64_t upstreamConnections;
@property (nonatomic, assign, readwrite) int64_t downstreamConnections;
@property (nonatomic, assign, readwrite) int64_t eventsReceived;
@property (nonatomic, assign, readwrite) int64_t eventsValidated;
@property (nonatomic, assign, readwrite) int64_t eventsInvalidated;
@property (nonatomic, assign, readwrite) int64_t eventsForwarded;
@property (nonatomic, assign, readwrite) int64_t eventsDropped;
@property (nonatomic, assign, readwrite) int64_t mstValidationSuccess;
@property (nonatomic, assign, readwrite) int64_t mstValidationFailure;
@property (nonatomic, assign, readwrite) int64_t signatureValidationSuccess;
@property (nonatomic, assign, readwrite) int64_t signatureValidationFailure;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *signatureValidationFailuresByCategory;
@property (nonatomic, assign, readwrite) int64_t continuityBaselines;
@property (nonatomic, assign, readwrite) int64_t continuityVerified;
@property (nonatomic, assign, readwrite) int64_t continuityFailures;
@property (nonatomic, assign, readwrite) int64_t syncResets;
@property (nonatomic, assign, readwrite) int64_t currentSequence;
@property (nonatomic, assign, readwrite) int64_t reconnectionCount;
@property (nonatomic, assign, readwrite) int64_t ingressCurrentEvents;
@property (nonatomic, assign, readwrite) int64_t ingressCurrentBytes;
@property (nonatomic, assign, readwrite) int64_t ingressPeakEvents;
@property (nonatomic, assign, readwrite) int64_t ingressPeakBytes;
@property (nonatomic, assign, readwrite) int64_t ingressRejectedTotal;
@property (nonatomic, assign, readwrite) int64_t ingressCancelledTotal;
@property (nonatomic, assign, readwrite) int64_t ingressPauseTotal;
@property (nonatomic, assign, readwrite) int64_t ingressResumeTotal;
@property (nonatomic, assign, readwrite) int64_t ingressAccountingFailures;

@end

@implementation ATProtoRelayMetrics {
    dispatch_queue_t _metricsQueue;
    // Per-upstream pause tracking: keyed by upstream URL, contains @{ @"pauseCount": @(N), @"pausedDurationMs": @(ms), @"pauseStartTime": @(timestamp) }
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_upstreamPauseMetrics;
    // Per-shard dispatch counts: keyed by shard index
    NSMutableDictionary<NSNumber *, NSNumber *> *_shardDispatchCounts;
    // Oldest accepted age gauge (latest value only)
    NSTimeInterval _ingressOldestAgeMs;
    // Queue delay histogram buckets: each key is a bucket boundary in ms (as NSNumber), value is cumulative count
    NSMutableDictionary<NSNumber *, NSNumber *> *_queueDelayBuckets;
    // Queue delay sum and count for histogram
    NSTimeInterval _queueDelaySumMs;
    uint64_t _queueDelayCountTotal;
}

+ (instancetype)sharedMetrics {
    static ATProtoRelayMetrics *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ATProtoRelayMetrics alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _metricsQueue = dispatch_queue_create("com.atproto.relay.metrics", DISPATCH_QUEUE_SERIAL);
        _signatureValidationFailuresByCategory = @{};
        _upstreamPauseMetrics = [NSMutableDictionary dictionary];
        _shardDispatchCounts = [NSMutableDictionary dictionary];
        _ingressOldestAgeMs = 0;
        _queueDelayBuckets = [NSMutableDictionary dictionary];
        // Initialize histogram buckets: 1ms, 10ms, 50ms, 100ms, 500ms, 1000ms, +Inf
        _queueDelayBuckets[@1] = @0;
        _queueDelayBuckets[@10] = @0;
        _queueDelayBuckets[@50] = @0;
        _queueDelayBuckets[@100] = @0;
        _queueDelayBuckets[@500] = @0;
        _queueDelayBuckets[@1000] = @0;
        // +Inf bucket represented by a special large value
        _queueDelayBuckets[@(UINT64_MAX)] = @0;
        _queueDelaySumMs = 0;
        _queueDelayCountTotal = 0;
    }
    return self;
}

#pragma mark - Connection Metrics

- (void)recordUpstreamConnected {
    dispatch_async(_metricsQueue, ^{
        self.upstreamConnections++;
    });
}

- (void)recordUpstreamDisconnected {
    dispatch_async(_metricsQueue, ^{
        if (self.upstreamConnections > 0) {
            self.upstreamConnections--;
        }
    });
}

- (void)recordDownstreamConnected {
    dispatch_async(_metricsQueue, ^{
        self.downstreamConnections++;
    });
}

- (void)recordDownstreamDisconnected {
    dispatch_async(_metricsQueue, ^{
        if (self.downstreamConnections > 0) {
            self.downstreamConnections--;
        }
    });
}

#pragma mark - Event Metrics

- (void)recordEventReceived {
    dispatch_async(_metricsQueue, ^{
        self.eventsReceived++;
    });
}

- (void)recordEventValidated {
    dispatch_async(_metricsQueue, ^{
        self.eventsValidated++;
    });
}

- (void)recordEventInvalidated:(NSString *)reason {
    dispatch_async(_metricsQueue, ^{
        self.eventsInvalidated++;
    });
}

- (void)recordEventForwarded {
    dispatch_async(_metricsQueue, ^{
        self.eventsForwarded++;
    });
}

- (void)recordEventDropped {
    dispatch_async(_metricsQueue, ^{
        self.eventsDropped++;
    });
}

#pragma mark - Validation Metrics

- (void)recordMSTValidationSuccess {
    dispatch_async(_metricsQueue, ^{
        self.mstValidationSuccess++;
    });
}

- (void)recordMSTValidationFailure {
    dispatch_async(_metricsQueue, ^{
        self.mstValidationFailure++;
    });
}

- (void)recordSignatureValidationSuccess {
    dispatch_async(_metricsQueue, ^{
        self.signatureValidationSuccess++;
    });
}

- (void)recordSignatureValidationFailure {
    [self recordSignatureValidationFailureWithCategory:@"unknown"];
}

- (void)recordSignatureValidationFailureWithCategory:(NSString *)category {
    NSString *stableCategory = RelayCanonicalSignatureFailureCategory(category);
    dispatch_async(_metricsQueue, ^{
        self.signatureValidationFailure++;
        NSMutableDictionary<NSString *, NSNumber *> *failures =
            [self.signatureValidationFailuresByCategory mutableCopy] ?: [NSMutableDictionary dictionary];
        int64_t count = [failures[stableCategory] longLongValue];
        failures[stableCategory] = @(count + 1);
        self.signatureValidationFailuresByCategory = [failures copy];
    });
}

- (void)recordContinuityBaseline {
    dispatch_async(_metricsQueue, ^{
        self.continuityBaselines++;
    });
}

- (void)recordContinuityVerified {
    dispatch_async(_metricsQueue, ^{
        self.continuityVerified++;
    });
}

- (void)recordContinuityFailure {
    dispatch_async(_metricsQueue, ^{
        self.continuityFailures++;
    });
}

- (void)recordSyncReset {
    dispatch_async(_metricsQueue, ^{
        self.syncResets++;
    });
}

#pragma mark - Sequence

- (void)recordSequence:(int64_t)seq {
    dispatch_async(_metricsQueue, ^{
        if (seq > self.currentSequence) {
            self.currentSequence = seq;
        }
    });
}

- (void)setCurrentSequence:(int64_t)seq {
    dispatch_async(_metricsQueue, ^{
        _currentSequence = seq;
    });
}

#pragma mark - Other

- (void)recordBackfillDuration:(NSTimeInterval)durationMs {
    // Could add histogram tracking here
}

- (void)recordReconnectionCount {
    dispatch_async(_metricsQueue, ^{
        self.reconnectionCount++;
    });
}

#pragma mark - Ingress Metrics

- (void)recordIngressAdmittedBytes:(uint64_t)bytes {
    dispatch_async(_metricsQueue, ^{
        self.ingressCurrentEvents++;
        self.ingressCurrentBytes += (int64_t)bytes;
        if (self.ingressCurrentEvents > self.ingressPeakEvents) {
            self.ingressPeakEvents = self.ingressCurrentEvents;
        }
        if (self.ingressCurrentBytes > self.ingressPeakBytes) {
            self.ingressPeakBytes = self.ingressCurrentBytes;
        }
    });
}

- (void)recordIngressRejected:(NSString *)reason {
    (void)reason;
    dispatch_async(_metricsQueue, ^{
        self.ingressRejectedTotal++;
    });
}

- (void)recordIngressReleasedBytes:(uint64_t)bytes reason:(RelayIngressReleaseReason)reason {
    dispatch_async(_metricsQueue, ^{
        if (self.ingressCurrentEvents > 0) {
            self.ingressCurrentEvents--;
        }
        if (bytes > 0) {
            self.ingressCurrentBytes = MAX((int64_t)0, self.ingressCurrentBytes - (int64_t)bytes);
        }
        if (reason == RelayIngressReleaseReasonCancelled ||
            reason == RelayIngressReleaseReasonDisconnect ||
            reason == RelayIngressReleaseReasonShutdown) {
            self.ingressCancelledTotal++;
        }
    });
}

- (void)recordIngressCancelled:(RelayIngressReleaseReason)reason {
    [self recordIngressReleasedBytes:0 reason:reason];
}

- (void)recordIngressHighWatermark {
    // Transition counters are recorded by upstream pause/resume hooks.
}

- (void)recordIngressLowWatermark {
}

- (void)recordIngressAccountingFailure:(NSString *)kind {
    (void)kind;
    dispatch_async(_metricsQueue, ^{
        self.ingressAccountingFailures++;
    });
}

- (void)recordIngressWorkerServiceTimeMs:(NSTimeInterval)milliseconds {
    (void)milliseconds;
}

- (void)recordIngressShardDispatch:(NSUInteger)shardIndex {
    dispatch_async(_metricsQueue, ^{
        NSNumber *shardKey = @(shardIndex);
        int64_t count = [self->_shardDispatchCounts[shardKey] longLongValue];
        self->_shardDispatchCounts[shardKey] = @(count + 1);
    });
}

- (void)recordIngressOldestAgeMs:(NSTimeInterval)ageMs {
    dispatch_async(_metricsQueue, ^{
        self->_ingressOldestAgeMs = ageMs;
    });
}

- (void)recordIngressQueueDelayMs:(NSTimeInterval)delayMs {
    dispatch_async(_metricsQueue, ^{
        self->_queueDelaySumMs += delayMs;
        self->_queueDelayCountTotal++;
        // Update histogram buckets cumulatively
        NSArray<NSNumber *> *buckets = [[self->_queueDelayBuckets allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [a compare:b];
        }];
        for (NSNumber *bucketLimit in buckets) {
            if (delayMs <= [bucketLimit doubleValue]) {
                uint64_t bucketCount = [self->_queueDelayBuckets[bucketLimit] unsignedLongLongValue];
                self->_queueDelayBuckets[bucketLimit] = @(bucketCount + 1);
            }
        }
    });
}

- (void)recordIngressUpstreamPause:(NSString *)upstreamURL {
    dispatch_async(_metricsQueue, ^{
        self.ingressPauseTotal++;
        NSMutableDictionary *upstreamMetrics = self->_upstreamPauseMetrics[upstreamURL];
        if (!upstreamMetrics) {
            upstreamMetrics = [NSMutableDictionary dictionary];
            self->_upstreamPauseMetrics[upstreamURL] = upstreamMetrics;
        }
        int64_t pauseCount = [upstreamMetrics[@"pauseCount"] longLongValue];
        upstreamMetrics[@"pauseCount"] = @(pauseCount + 1);
        upstreamMetrics[@"pauseStartTime"] = @([[NSDate date] timeIntervalSinceReferenceDate]);
    });
}

- (void)recordIngressUpstreamResume:(NSString *)upstreamURL {
    dispatch_async(_metricsQueue, ^{
        self.ingressResumeTotal++;
        NSMutableDictionary *upstreamMetrics = self->_upstreamPauseMetrics[upstreamURL];
        if (!upstreamMetrics) {
            upstreamMetrics = [NSMutableDictionary dictionary];
            self->_upstreamPauseMetrics[upstreamURL] = upstreamMetrics;
        }
        NSNumber *pauseStartTimeNum = upstreamMetrics[@"pauseStartTime"];
        if (pauseStartTimeNum) {
            NSTimeInterval pauseStartTime = [pauseStartTimeNum doubleValue];
            NSTimeInterval pausedDurationMs =
                ([[NSDate date] timeIntervalSinceReferenceDate] - pauseStartTime) * 1000.0;
            NSTimeInterval totalDurationMs = [upstreamMetrics[@"pausedDurationMs"] doubleValue];
            upstreamMetrics[@"pausedDurationMs"] = @(totalDurationMs + pausedDurationMs);
            [upstreamMetrics removeObjectForKey:@"pauseStartTime"];
        }
    });
}

#pragma mark - Prometheus Output

- (NSString *)renderPrometheusMetrics {
    __block NSString *output;
    dispatch_sync(_metricsQueue, ^{
        NSMutableString *metrics = [NSMutableString string];
        
        [metrics appendString:@"# HELP relay_upstream_connections Number of upstream PDS connections\n"];
        [metrics appendFormat:@"# TYPE relay_upstream_connections gauge\n"];
        [metrics appendFormat:@"relay_upstream_connections %lld\n\n", (long long)self.upstreamConnections];
        
        [metrics appendString:@"# HELP relay_downstream_connections Number of downstream consumer connections\n"];
        [metrics appendFormat:@"# TYPE relay_downstream_connections gauge\n"];
        [metrics appendFormat:@"relay_downstream_connections %lld\n\n", (long long)self.downstreamConnections];
        
        [metrics appendString:@"# HELP relay_events_received_total Total events received from upstreams\n"];
        [metrics appendFormat:@"# TYPE relay_events_received_total counter\n"];
        [metrics appendFormat:@"relay_events_received_total %lld\n\n", (long long)self.eventsReceived];
        
        [metrics appendString:@"# HELP relay_events_validated_total Total events that passed validation\n"];
        [metrics appendFormat:@"# TYPE relay_events_validated_total counter\n"];
        [metrics appendFormat:@"relay_events_validated_total %lld\n\n", (long long)self.eventsValidated];
        
        [metrics appendString:@"# HELP relay_events_forwarded_total Total events forwarded to downstreams\n"];
        [metrics appendFormat:@"# TYPE relay_events_forwarded_total counter\n"];
        [metrics appendFormat:@"relay_events_forwarded_total %lld\n\n", (long long)self.eventsForwarded];
        
        [metrics appendString:@"# HELP relay_events_dropped_total Total events dropped (validation failure in strict mode)\n"];
        [metrics appendFormat:@"# TYPE relay_events_dropped_total counter\n"];
        [metrics appendFormat:@"relay_events_dropped_total %lld\n\n", (long long)self.eventsDropped];
        
        [metrics appendString:@"# HELP relay_mst_validation_total MST validation results\n"];
        [metrics appendFormat:@"# TYPE relay_mst_validation_total counter\n"];
        [metrics appendFormat:@"relay_mst_validation_total{result=\"success\"} %lld\n", (long long)self.mstValidationSuccess];
        [metrics appendFormat:@"relay_mst_validation_total{result=\"failure\"} %lld\n\n", (long long)self.mstValidationFailure];
        
        [metrics appendString:@"# HELP relay_signature_validation_total Signature validation results\n"];
        [metrics appendFormat:@"# TYPE relay_signature_validation_total counter\n"];
        [metrics appendFormat:@"relay_signature_validation_total{result=\"success\"} %lld\n", (long long)self.signatureValidationSuccess];
        [metrics appendFormat:@"relay_signature_validation_total{result=\"failure\"} %lld\n\n", (long long)self.signatureValidationFailure];

        [metrics appendString:@"# HELP relay_signature_validation_failures_total Signature validation failures by stable category\n"];
        [metrics appendString:@"# TYPE relay_signature_validation_failures_total counter\n"];
        NSArray<NSString *> *signatureCategories =
            [[self.signatureValidationFailuresByCategory allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *category in signatureCategories) {
            [metrics appendFormat:@"relay_signature_validation_failures_total{category=\"%@\"} %lld\n",
                                  category,
                                  (long long)[self.signatureValidationFailuresByCategory[category] longLongValue]];
        }
        [metrics appendString:@"\n"];

        [metrics appendString:@"# HELP relay_continuity_total Repository continuity outcomes\n"];
        [metrics appendFormat:@"# TYPE relay_continuity_total counter\n"];
        [metrics appendFormat:@"relay_continuity_total{result=\"baseline\"} %lld\n", (long long)self.continuityBaselines];
        [metrics appendFormat:@"relay_continuity_total{result=\"verified\"} %lld\n", (long long)self.continuityVerified];
        [metrics appendFormat:@"relay_continuity_total{result=\"failure\"} %lld\n\n", (long long)self.continuityFailures];

        [metrics appendString:@"# HELP relay_sync_resets_total Repository state resets applied from sync events\n"];
        [metrics appendFormat:@"# TYPE relay_sync_resets_total counter\n"];
        [metrics appendFormat:@"relay_sync_resets_total %lld\n\n", (long long)self.syncResets];
        
        [metrics appendString:@"# HELP relay_current_sequence Current highest sequence number\n"];
        [metrics appendFormat:@"# TYPE relay_current_sequence gauge\n"];
        [metrics appendFormat:@"relay_current_sequence %lld\n\n", (long long)self.currentSequence];
        
        [metrics appendString:@"# HELP relay_reconnection_total Total reconnection attempts\n"];
        [metrics appendFormat:@"# TYPE relay_reconnection_total counter\n"];
        [metrics appendFormat:@"relay_reconnection_total %lld\n", (long long)self.reconnectionCount];

        [metrics appendString:@"\n# HELP relay_ingress_current_events Current admitted ingress events\n"];
        [metrics appendString:@"# TYPE relay_ingress_current_events gauge\n"];
        [metrics appendFormat:@"relay_ingress_current_events %lld\n\n", (long long)self.ingressCurrentEvents];

        [metrics appendString:@"# HELP relay_ingress_current_bytes Current admitted ingress bytes\n"];
        [metrics appendString:@"# TYPE relay_ingress_current_bytes gauge\n"];
        [metrics appendFormat:@"relay_ingress_current_bytes %lld\n\n", (long long)self.ingressCurrentBytes];

        [metrics appendString:@"# HELP relay_ingress_rejected_total Total ingress admissions rejected\n"];
        [metrics appendString:@"# TYPE relay_ingress_rejected_total counter\n"];
        [metrics appendFormat:@"relay_ingress_rejected_total %lld\n\n", (long long)self.ingressRejectedTotal];

        [metrics appendString:@"# HELP relay_ingress_accounting_failures_total Ingress accounting invariant failures\n"];
        [metrics appendString:@"# TYPE relay_ingress_accounting_failures_total counter\n"];
        [metrics appendFormat:@"relay_ingress_accounting_failures_total %lld\n", (long long)self.ingressAccountingFailures];

        [metrics appendString:@"\n# HELP relay_ingress_upstream_pause_total Per-upstream ingress pause count\n"];
        [metrics appendString:@"# TYPE relay_ingress_upstream_pause_total counter\n"];
        NSArray<NSString *> *upstreamURLs =
            [[self->_upstreamPauseMetrics allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *url in upstreamURLs) {
            NSMutableDictionary *metrics_for_url = self->_upstreamPauseMetrics[url];
            int64_t pauseCount = [metrics_for_url[@"pauseCount"] longLongValue];
            [metrics appendFormat:@"relay_ingress_upstream_pause_total{upstream=\"%@\"} %lld\n", url, (long long)pauseCount];
        }
        [metrics appendString:@"\n"];

        [metrics appendString:@"# HELP relay_ingress_upstream_paused_duration_ms_total Per-upstream cumulative paused duration in milliseconds\n"];
        [metrics appendString:@"# TYPE relay_ingress_upstream_paused_duration_ms_total counter\n"];
        for (NSString *url in upstreamURLs) {
            NSMutableDictionary *metrics_for_url = self->_upstreamPauseMetrics[url];
            NSTimeInterval pausedDurationMs = [metrics_for_url[@"pausedDurationMs"] doubleValue];
            [metrics appendFormat:@"relay_ingress_upstream_paused_duration_ms_total{upstream=\"%@\"} %.0f\n", url, pausedDurationMs];
        }
        [metrics appendString:@"\n"];

        [metrics appendString:@"# HELP relay_ingress_shard_dispatch_total Per-shard work item dispatch count\n"];
        [metrics appendString:@"# TYPE relay_ingress_shard_dispatch_total counter\n"];
        NSArray<NSNumber *> *shardIndices =
            [[self->_shardDispatchCounts allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [a compare:b];
        }];
        for (NSNumber *shardIndex in shardIndices) {
            uint64_t dispatchCount = [self->_shardDispatchCounts[shardIndex] unsignedLongLongValue];
            [metrics appendFormat:@"relay_ingress_shard_dispatch_total{shard=\"%lu\"} %llu\n",
                                  (unsigned long)[shardIndex unsignedLongValue],
                                  (unsigned long long)dispatchCount];
        }
        [metrics appendString:@"\n"];

        [metrics appendString:@"# HELP relay_ingress_oldest_accepted_age_ms Oldest admitted event age in milliseconds\n"];
        [metrics appendString:@"# TYPE relay_ingress_oldest_accepted_age_ms gauge\n"];
        [metrics appendFormat:@"relay_ingress_oldest_accepted_age_ms %.0f\n", self->_ingressOldestAgeMs];
        [metrics appendString:@"\n"];

        [metrics appendString:@"# HELP relay_ingress_queue_delay_ms_bucket Queue delay histogram buckets\n"];
        [metrics appendString:@"# TYPE relay_ingress_queue_delay_ms_bucket histogram\n"];
        NSArray<NSNumber *> *buckets =
            [[self->_queueDelayBuckets allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [a compare:b];
        }];
        for (NSNumber *bucketLimit in buckets) {
            uint64_t bucketCount = [self->_queueDelayBuckets[bucketLimit] unsignedLongLongValue];
            if ([bucketLimit unsignedLongLongValue] == UINT64_MAX) {
                [metrics appendFormat:@"relay_ingress_queue_delay_ms_bucket{le=\"+Inf\"} %llu\n", (unsigned long long)bucketCount];
            } else {
                [metrics appendFormat:@"relay_ingress_queue_delay_ms_bucket{le=\"%@\"} %llu\n", bucketLimit, (unsigned long long)bucketCount];
            }
        }
        [metrics appendFormat:@"relay_ingress_queue_delay_ms_sum %.0f\n", self->_queueDelaySumMs];
        [metrics appendFormat:@"relay_ingress_queue_delay_ms_count %llu\n", (unsigned long long)self->_queueDelayCountTotal];

        output = [metrics copy];
    });
    return output ?: @"";
}

- (NSDictionary *)snapshotDictionary {
    __block NSDictionary *snapshot;
    dispatch_sync(_metricsQueue, ^{
        snapshot = @{
            @"upstreamConnections": @(self.upstreamConnections),
            @"downstreamConnections": @(self.downstreamConnections),
            @"eventsReceived": @(self.eventsReceived),
            @"eventsValidated": @(self.eventsValidated),
            @"eventsInvalidated": @(self.eventsInvalidated),
            @"eventsForwarded": @(self.eventsForwarded),
            @"eventsDropped": @(self.eventsDropped),
            @"mstValidationSuccess": @(self.mstValidationSuccess),
            @"mstValidationFailure": @(self.mstValidationFailure),
            @"signatureValidationSuccess": @(self.signatureValidationSuccess),
            @"signatureValidationFailure": @(self.signatureValidationFailure),
            @"signatureValidationFailuresByCategory": self.signatureValidationFailuresByCategory ?: @{},
            @"continuityBaselines": @(self.continuityBaselines),
            @"continuityVerified": @(self.continuityVerified),
            @"continuityFailures": @(self.continuityFailures),
            @"syncResets": @(self.syncResets),
            @"currentSequence": @(self.currentSequence),
            @"reconnectionCount": @(self.reconnectionCount),
            @"ingressCurrentEvents": @(self.ingressCurrentEvents),
            @"ingressCurrentBytes": @(self.ingressCurrentBytes),
            @"ingressPeakEvents": @(self.ingressPeakEvents),
            @"ingressPeakBytes": @(self.ingressPeakBytes),
            @"ingressRejectedTotal": @(self.ingressRejectedTotal),
            @"ingressCancelledTotal": @(self.ingressCancelledTotal),
            @"ingressPauseTotal": @(self.ingressPauseTotal),
            @"ingressResumeTotal": @(self.ingressResumeTotal),
            @"ingressAccountingFailures": @(self.ingressAccountingFailures),
        };
    });
    return snapshot ?: @{};
}

@end
