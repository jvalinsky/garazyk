#import "PLC/PLCMetrics.h"
#import "Debug/PDSLogger.h"
#ifndef GNUSTEP
#import <libkern/OSAtomic.h>
#else
// Linux: use C11 atomics instead of OSAtomic
#include <stdatomic.h>
#define OSAtomicIncrement64(ptr) (atomic_fetch_add((_Atomic(int64_t) *)(ptr), 1) + 1)
#endif

NS_ASSUME_NONNULL_BEGIN

@interface PLCMetrics ()
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
    @synchronized(self.operationCounts) {
        NSNumber *current = self.operationCounts[operationType] ?: @0;
        int64_t newValue = current.longLongValue + 1;
        self.operationCounts[operationType] = @(newValue);
    }
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
    @synchronized(self.latencySamples) {
        [self.latencySamples addObject:@(latencyMs)];
    if (self.latencySamples.count > 1000) {
        [self.latencySamples removeObjectAtIndex:0];
    }
    }
    PDS_LOG_CORE_DEBUG(@"PLC resolution latency: %.2fms", latencyMs);
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
    
    @synchronized(self.operationCounts) {
        [self.operationCounts enumerateKeysAndObjectsUsingBlock:^(NSString *opType, NSNumber *count, BOOL *stop) {
            NSString *sanitizedType = [opType stringByReplacingOccurrencesOfString:@"." withString:@"_"];
            [output appendString:[NSString stringWithFormat:@"# HELP plc_operations_%@_total Total number of %@ operations\n", sanitizedType, opType]];
            [output appendString:[NSString stringWithFormat:@"# TYPE plc_operations_%@_total counter\n", sanitizedType]];
            [output appendString:[NSString stringWithFormat:@"plc_operations_%@_total %llu\n\n", sanitizedType, (unsigned long long)count.unsignedLongLongValue]];
        }];
    }
    
    double avgLatency = 0;
    @synchronized(self.latencySamples) {
        if (self.latencySamples.count > 0) {
            double sum = 0;
            for (NSNumber *latency in self.latencySamples) {
                sum += latency.doubleValue;
            }
            avgLatency = sum / self.latencySamples.count;
        }
    }
    [output appendString:@"# HELP plc_resolution_latency_milliseconds Average resolution latency in milliseconds\n"];
    [output appendString:@"# TYPE plc_resolution_latency_milliseconds gauge\n"];
    [output appendString:[NSString stringWithFormat:@"plc_resolution_latency_milliseconds %.2f\n", avgLatency]];
    
    return [output copy];
}

@end

NS_ASSUME_NONNULL_END
