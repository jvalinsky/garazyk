// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PLCMetrics.h
 * @abstract Metrics collection for PLC operations.
 * @discussion Provides Prometheus-style metrics for PLC DID operations including cache hits/misses, operation counts, and latency measurements.
 */

#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Metrics collector for PLC operations.
 * @discussion Tracks:
 * - Cache hits and misses (in-memory and persistent)
 * - Operation submission counts by type
 * - Verification success/failure counts
 * - Resolution latency histograms
 */
@interface PLCMetrics : NSObject

/**
 * @abstract Returns the shared singleton metrics collector.
 */
+ (instancetype)sharedMetrics;

/** @abstract Records a general cache hit. */
- (void)recordCacheHit;
/** @abstract Records a general cache miss. */
- (void)recordCacheMiss;

/** @abstract Records an in-memory cache hit. */
- (void)recordMemcacheHit;
/** @abstract Records an in-memory cache miss. */
- (void)recordMemcacheMiss;

/** @abstract Records a generic request. */
- (void)recordRequest;
/** @abstract Records a generic error. */
- (void)recordError;

/**
 * @abstract Records an operation event.
 * @param operationType The type of the operation.
 */
- (void)recordOperation:(NSString *)operationType;
/** @abstract Records a successful verification. */
- (void)recordVerificationSuccess;
/** @abstract Records a verification failure. */
- (void)recordVerificationFailure;

/**
 * @abstract Records resolution latency.
 * @param latencyMs Latency in milliseconds.
 */
- (void)recordResolutionLatency:(NSTimeInterval)latencyMs;

/**
 * @abstract Sets a gauge metric.
 * @param name The metric name.
 * @param value The gauge value.
 */
- (void)setGauge:(NSString *)name value:(int64_t)value;
/**
 * @abstract Increments a counter metric.
 * @param name The metric name.
 * @param delta The increment amount.
 */
- (void)incrementCounter:(NSString *)name by:(int64_t)delta;

/**
 * @abstract Renders all metrics as a string.
 * @return Metrics output string.
 */
- (NSString *)renderMetrics;

/** @abstract Total cache hits. */
@property (nonatomic, readonly) int64_t cacheHits;
/** @abstract Total cache misses. */
@property (nonatomic, readonly) int64_t cacheMisses;
/** @abstract Total memcache hits. */
@property (nonatomic, readonly) int64_t memcacheHits;
/** @abstract Total memcache misses. */
@property (nonatomic, readonly) int64_t memcacheMisses;
/** @abstract Total verification successes. */
@property (nonatomic, readonly) int64_t verificationSuccesses;
/** @abstract Total verification failures. */
@property (nonatomic, readonly) int64_t verificationFailures;
/** @abstract Total request count. */
@property (nonatomic, readonly) int64_t totalRequests;
/** @abstract Total error count. */
@property (nonatomic, readonly) int64_t totalErrors;

@end

NS_ASSUME_NONNULL_END
