// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLC/PLCMetrics.h"
#import "Debug/PDSLogger.h"
#import "libkern/OSAtomic.h"

NS_ASSUME_NONNULL_BEGIN

@interface PLCMetrics () {
    dispatch_queue_t _metricsQueue;
}
@property (nonatomic, assign) int64_t cacheHits;
@property (nonatomic, assign) int64_t cacheMisses;
@property (nonatomic, assign) int64_t memcacheHits;
@property (nonatomic, assign) int64_t memcacheMisses;
@property (nonatomic, assign) int64_t verificationSuccesses;
@property (nonatomic, assign) int64_t verificationFailures;
@property (nonatomic, assign) int64_t totalRequests;
@property (nonatomic, assign) int64_t totalErrors;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *operationCounts;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *latencySamples;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *customGauges;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *customCounters;
@end

@implementation PLCMetrics

+ (instancetype)sharedMetrics {
    static PLCMetrics *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cacheHits = 0;
        _cacheMisses = 0;
        _memcacheHits = 0;
        _memcacheMisses = 0;
        _verificationSuccesses = 0;
        _verificationFailures = 0;
        _totalRequests = 0;
        _totalErrors = 0;
        _operationCounts = [NSMutableDictionary dictionary];
        _latencySamples = [NSMutableArray array];
        _customGauges = [NSMutableDictionary dictionary];
        _customCounters = [NSMutableDictionary dictionary];
        _metricsQueue = dispatch_queue_create("com.atproto.plc.metrics", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)recordCacheHit {
    OSAtomicIncrement64(&_cacheHits);
    PDS_LOG_CORE_DEBUG(@"PLC cache hit");
}

- (void)recordCacheMiss {
    OSAtomicIncrement64(&_cacheMisses);
    PDS_LOG_CORE_DEBUG(@"PLC cache miss");
}

- (void)recordMemcacheHit {
    OSAtomicIncrement64(&_memcacheHits);
    PDS_LOG_CORE_DEBUG(@"PLC memcache hit");
}

- (void)recordMemcacheMiss {
    OSAtomicIncrement64(&_memcacheMisses);
    PDS_LOG_CORE_DEBUG(@"PLC memcache miss");
}

- (void)recordRequest {
    OSAtomicIncrement64(&_totalRequests);
}

- (void)recordError {
    OSAtomicIncrement64(&_totalErrors);
    PDS_LOG_CORE_DEBUG(@"PLC error recorded");
}

- (void)recordOperation:(NSString *)operationType {
    dispatch_sync(_metricsQueue, ^{
        NSNumber *current = self.operationCounts[operationType] ?: @0;
        int64_t newValue = current.longLongValue + 1;
        self.operationCounts[operationType] = @(newValue);
    });
    PDS_LOG_CORE_DEBUG(@"PLC operation: %@", operationType ?: @"");
}

- (void)recordVerificationSuccess {
    OSAtomicIncrement64(&_verificationSuccesses);
    PDS_LOG_CORE_DEBUG(@"PLC verification success");
}

- (void)recordVerificationFailure {
    OSAtomicIncrement64(&_verificationFailures);
    PDS_LOG_CORE_DEBUG(@"PLC verification failure");
}

- (void)recordResolutionLatency:(NSTimeInterval)latencyMs {
    dispatch_sync(_metricsQueue, ^{
        [self.latencySamples addObject:@(latencyMs)];
        if (self.latencySamples.count > 1000) {
            [self.latencySamples removeObjectAtIndex:0];
        }
    });
}

- (void)setGauge:(NSString *)name value:(int64_t)value {
    dispatch_sync(_metricsQueue, ^{
        self.customGauges[name] = @(value);
    });
}

- (void)incrementCounter:(NSString *)name by:(int64_t)delta {
    dispatch_sync(_metricsQueue, ^{
        NSNumber *current = self.customCounters[name] ?: @0;
        self.customCounters[name] = @(current.longLongValue + delta);
    });
}

- (int64_t)cacheHits {
    return _cacheHits;
}

- (int64_t)cacheMisses {
    return _cacheMisses;
}

- (int64_t)memcacheHits {
    return _memcacheHits;
}

- (int64_t)memcacheMisses {
    return _memcacheMisses;
}

- (int64_t)verificationSuccesses {
    return _verificationSuccesses;
}

- (int64_t)verificationFailures {
    return _verificationFailures;
}

- (int64_t)totalRequests {
    return _totalRequests;
}

- (int64_t)totalErrors {
    return _totalErrors;
}

- (NSString *)renderMetrics {
    NSMutableString *output = [NSMutableString string];

    // Take a consistent snapshot with a single lock to avoid cross-collection inconsistency
    __block NSDictionary<NSString *, NSNumber *> *opCountsSnapshot = nil;
    __block NSArray<NSNumber *> *latencySnapshot = nil;
    __block NSDictionary<NSString *, NSNumber *> *gaugesSnapshot = nil;
    __block NSDictionary<NSString *, NSNumber *> *countersSnapshot = nil;

    dispatch_sync(_metricsQueue, ^{
        opCountsSnapshot = [self.operationCounts copy];
        latencySnapshot = [self.latencySamples copy];
        gaugesSnapshot = [self.customGauges copy];
        countersSnapshot = [self.customCounters copy];
    });

    [output appendString:@"# HELP plc_cache_hits_total Total number of cache hits\n"];
    [output appendString:@"# TYPE plc_cache_hits_total counter\n"];
    [output appendString:[NSString stringWithFormat:@"plc_cache_hits_total %lld\n\n", (long long)self.cacheHits]];

    [output appendString:@"# HELP plc_cache_misses_total Total number of cache misses\n"];
    [output appendString:@"# TYPE plc_cache_misses_total counter\n"];
    [output appendString:[NSString stringWithFormat:@"plc_cache_misses_total %lld\n\n", (long long)self.cacheMisses]];

    [output appendString:@"# HELP plc_memcache_hits_total Total number of memory cache hits\n"];
    [output appendString:@"# TYPE plc_memcache_hits_total counter\n"];
    [output appendString:[NSString stringWithFormat:@"plc_memcache_hits_total %lld\n\n", (long long)self.memcacheHits]];

    [output appendString:@"# HELP plc_memcache_misses_total Total number of memory cache misses\n"];
    [output appendString:@"# TYPE plc_memcache_misses_total counter\n"];
    [output appendString:[NSString stringWithFormat:@"plc_memcache_misses_total %lld\n\n", (long long)self.memcacheMisses]];

    [output appendString:@"# HELP plc_verification_successes_total Total number of successful verifications\n"];
    [output appendString:@"# TYPE plc_verification_successes_total counter\n"];
    [output appendString:[NSString stringWithFormat:@"plc_verification_successes_total %lld\n\n", (long long)self.verificationSuccesses]];

    [output appendString:@"# HELP plc_verification_failures_total Total number of failed verifications\n"];
    [output appendString:@"# TYPE plc_verification_failures_total counter\n"];
    [output appendString:[NSString stringWithFormat:@"plc_verification_failures_total %lld\n\n", (long long)self.verificationFailures]];

    [output appendString:@"# HELP plc_http_requests_total Total number of HTTP requests\n"];
    [output appendString:@"# TYPE plc_http_requests_total counter\n"];
    [output appendString:[NSString stringWithFormat:@"plc_http_requests_total %lld\n\n", (long long)self.totalRequests]];

    [output appendString:@"# HELP plc_http_errors_total Total number of HTTP errors\n"];
    [output appendString:@"# TYPE plc_http_errors_total counter\n"];
    [output appendString:[NSString stringWithFormat:@"plc_http_errors_total %lld\n\n", (long long)self.totalErrors]];

    [opCountsSnapshot enumerateKeysAndObjectsUsingBlock:^(NSString *opType, NSNumber *count, BOOL *stop) {
        NSString *sanitizedType = [opType stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        [output appendString:[NSString stringWithFormat:@"# HELP plc_operations_%@_total Total number of %@ operations\n", sanitizedType, opType]];
        [output appendString:[NSString stringWithFormat:@"# TYPE plc_operations_%@_total counter\n", sanitizedType]];
        [output appendString:[NSString stringWithFormat:@"plc_operations_%@_total %llu\n\n", sanitizedType, (unsigned long long)count.unsignedLongLongValue]];
    }];

    double avgLatency = 0;
    if (latencySnapshot.count > 0) {
        double sum = 0;
        for (NSNumber *latency in latencySnapshot) {
            sum += latency.doubleValue;
        }
        avgLatency = sum / latencySnapshot.count;
    }
    [output appendString:@"# HELP plc_resolution_latency_milliseconds Average resolution latency in milliseconds\n"];
    [output appendString:@"# TYPE plc_resolution_latency_milliseconds gauge\n"];
    [output appendString:[NSString stringWithFormat:@"plc_resolution_latency_milliseconds %.2f\n\n", avgLatency]];

    [gaugesSnapshot enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSNumber *value, BOOL *stop) {
        NSString *sanitized = [name stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        [output appendString:[NSString stringWithFormat:@"# HELP %@ gauge\n", sanitized]];
        [output appendString:[NSString stringWithFormat:@"# TYPE %@ gauge\n", sanitized]];
        [output appendString:[NSString stringWithFormat:@"%@ %lld\n\n", sanitized, (long long)value.longLongValue]];
    }];

    [countersSnapshot enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSNumber *value, BOOL *stop) {
        NSString *sanitized = [name stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        [output appendString:[NSString stringWithFormat:@"# HELP %@ Total\n", sanitized]];
        [output appendString:[NSString stringWithFormat:@"# TYPE %@ counter\n", sanitized]];
        [output appendString:[NSString stringWithFormat:@"%@ %lld\n\n", sanitized, (long long)value.longLongValue]];
    }];

    return [output copy];
}

@end

NS_ASSUME_NONNULL_END
