/*!
 @file PLCMetrics.h

 @abstract Metrics collection for PLC operations.

 @discussion Provides Prometheus-style metrics for PLC DID operations
 including cache hits/misses, operation counts, and latency measurements.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PLCMetrics

 @abstract Metrics collector for PLC operations.

 @discussion Tracks:
 - Cache hits and misses (in-memory and persistent)
 - Operation submission counts by type
 - Verification success/failure counts
 - Resolution latency histograms
 */
@interface PLCMetrics : NSObject

+ (instancetype)sharedMetrics;

- (void)recordCacheHit;
- (void)recordCacheMiss;

- (void)recordMemcacheHit;
- (void)recordMemcacheHit;
- (void)recordMemcacheMiss;

- (void)recordRequest;
- (void)recordError;

- (void)recordOperation:(NSString *)operationType;
- (void)recordVerificationSuccess;
- (void)recordVerificationFailure;

- (void)recordResolutionLatency:(NSTimeInterval)latencyMs;

- (NSString *)renderMetrics;

@property (nonatomic, readonly) int64_t cacheHits;
@property (nonatomic, readonly) int64_t cacheMisses;
@property (nonatomic, readonly) int64_t memcacheHits;
@property (nonatomic, readonly) int64_t memcacheMisses;
@property (nonatomic, readonly) int64_t verificationSuccesses;
@property (nonatomic, readonly) int64_t verificationFailures;
@property (nonatomic, readonly) int64_t totalRequests;
@property (nonatomic, readonly) int64_t totalErrors;

@end

NS_ASSUME_NONNULL_END
