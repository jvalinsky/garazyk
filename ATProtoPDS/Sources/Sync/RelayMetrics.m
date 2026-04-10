#import "Sync/RelayMetrics.h"

@interface RelayMetrics ()

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
@property (nonatomic, assign, readwrite) int64_t currentSequence;
@property (nonatomic, assign, readwrite) int64_t reconnectionCount;

@property (nonatomic, strong) dispatch_queue_t metricsQueue;

@end

@implementation RelayMetrics

+ (instancetype)sharedMetrics {
    static RelayMetrics *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RelayMetrics alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _metricsQueue = dispatch_queue_create("com.atproto.relay.metrics", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Connection Metrics

- (void)recordUpstreamConnected {
    dispatch_async(self.metricsQueue, ^{
        self.upstreamConnections++;
    });
}

- (void)recordUpstreamDisconnected {
    dispatch_async(self.metricsQueue, ^{
        if (self.upstreamConnections > 0) {
            self.upstreamConnections--;
        }
    });
}

- (void)recordDownstreamConnected {
    dispatch_async(self.metricsQueue, ^{
        self.downstreamConnections++;
    });
}

- (void)recordDownstreamDisconnected {
    dispatch_async(self.metricsQueue, ^{
        if (self.downstreamConnections > 0) {
            self.downstreamConnections--;
        }
    });
}

#pragma mark - Event Metrics

- (void)recordEventReceived {
    dispatch_async(self.metricsQueue, ^{
        self.eventsReceived++;
    });
}

- (void)recordEventValidated {
    dispatch_async(self.metricsQueue, ^{
        self.eventsValidated++;
    });
}

- (void)recordEventInvalidated:(NSString *)reason {
    dispatch_async(self.metricsQueue, ^{
        self.eventsInvalidated++;
    });
}

- (void)recordEventForwarded {
    dispatch_async(self.metricsQueue, ^{
        self.eventsForwarded++;
    });
}

- (void)recordEventDropped {
    dispatch_async(self.metricsQueue, ^{
        self.eventsDropped++;
    });
}

#pragma mark - Validation Metrics

- (void)recordMSTValidationSuccess {
    dispatch_async(self.metricsQueue, ^{
        self.mstValidationSuccess++;
    });
}

- (void)recordMSTValidationFailure {
    dispatch_async(self.metricsQueue, ^{
        self.mstValidationFailure++;
    });
}

- (void)recordSignatureValidationSuccess {
    dispatch_async(self.metricsQueue, ^{
        self.signatureValidationSuccess++;
    });
}

- (void)recordSignatureValidationFailure {
    dispatch_async(self.metricsQueue, ^{
        self.signatureValidationFailure++;
    });
}

#pragma mark - Sequence

- (void)recordSequence:(int64_t)seq {
    dispatch_async(self.metricsQueue, ^{
        if (seq > self.currentSequence) {
            self.currentSequence = seq;
        }
    });
}

- (void)setCurrentSequence:(int64_t)seq {
    dispatch_async(self.metricsQueue, ^{
        self.currentSequence = seq;
    });
}

#pragma mark - Other

- (void)recordBackfillDuration:(NSTimeInterval)durationMs {
    // Could add histogram tracking here
}

- (void)recordReconnectionCount {
    dispatch_async(self.metricsQueue, ^{
        self.reconnectionCount++;
    });
}

#pragma mark - Prometheus Output

- (NSString *)renderPrometheusMetrics {
    __block NSString *output;
    dispatch_sync(self.metricsQueue, ^{
        NSMutableString *metrics = [NSMutableString string];
        
        [metrics appendString:@"# HELP relay_upstream_connections Number of upstream PDS connections\n"];
        [metrics appendFormat:@"# TYPE relay_upstream_connections gauge\n"];
        [metrics appendFormat:@"relay_upstream_connections %lld\n\n", self.upstreamConnections];
        
        [metrics appendString:@"# HELP relay_downstream_connections Number of downstream consumer connections\n"];
        [metrics appendFormat:@"# TYPE relay_downstream_connections gauge\n"];
        [metrics appendFormat:@"relay_downstream_connections %lld\n\n", self.downstreamConnections];
        
        [metrics appendString:@"# HELP relay_events_received_total Total events received from upstreams\n"];
        [metrics appendFormat:@"# TYPE relay_events_received_total counter\n"];
        [metrics appendFormat:@"relay_events_received_total %lld\n\n", self.eventsReceived];
        
        [metrics appendString:@"# HELP relay_events_validated_total Total events that passed validation\n"];
        [metrics appendFormat:@"# TYPE relay_events_validated_total counter\n"];
        [metrics appendFormat:@"relay_events_validated_total %lld\n\n", self.eventsValidated];
        
        [metrics appendString:@"# HELP relay_events_forwarded_total Total events forwarded to downstreams\n"];
        [metrics appendFormat:@"# TYPE relay_events_forwarded_total counter\n"];
        [metrics appendFormat:@"relay_events_forwarded_total %lld\n\n", self.eventsForwarded];
        
        [metrics appendString:@"# HELP relay_events_dropped_total Total events dropped (validation failure in strict mode)\n"];
        [metrics appendFormat:@"# TYPE relay_events_dropped_total counter\n"];
        [metrics appendFormat:@"relay_events_dropped_total %lld\n\n", self.eventsDropped];
        
        [metrics appendString:@"# HELP relay_mst_validation_total MST validation results\n"];
        [metrics appendFormat:@"# TYPE relay_mst_validation_total counter\n"];
        [metrics appendFormat:@"relay_mst_validation_total{result=\"success\"} %lld\n", self.mstValidationSuccess];
        [metrics appendFormat:@"relay_mst_validation_total{result=\"failure\"} %lld\n\n", self.mstValidationFailure];
        
        [metrics appendString:@"# HELP relay_signature_validation_total Signature validation results\n"];
        [metrics appendFormat:@"# TYPE relay_signature_validation_total counter\n"];
        [metrics appendFormat:@"relay_signature_validation_total{result=\"success\"} %lld\n", self.signatureValidationSuccess];
        [metrics appendFormat:@"relay_signature_validation_total{result=\"failure\"} %lld\n\n", self.signatureValidationFailure];
        
        [metrics appendString:@"# HELP relay_current_sequence Current highest sequence number\n"];
        [metrics appendFormat:@"# TYPE relay_current_sequence gauge\n"];
        [metrics appendFormat:@"relay_current_sequence %lld\n\n", self.currentSequence];
        
        [metrics appendString:@"# HELP relay_reconnection_total Total reconnection attempts\n"];
        [metrics appendFormat:@"# TYPE relay_reconnection_total counter\n"];
        [metrics appendFormat:@"relay_reconnection_total %lld\n", self.reconnectionCount];
        
        output = [metrics copy];
    });
    return output ?: @"";
}

@end