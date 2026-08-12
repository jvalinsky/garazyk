// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Aggregates video-service runtime state into a bounded,
 *          materialized snapshot for the admin UI dashboard.
 *
 * @discussion The snapshot is populated from backend-client data (health,
 *             job list, quotas) in centralized mode.  When embedded in the
 *             jelcz binary it can also accept worker and database references
 *             for direct worker/queue counters without hitting the PDS.
 *
 *             The snapshot is immutable after construction — refresh replaces
 *             the instance.
 */
@interface JelczAdminSnapshot : NSObject

/**
 * @abstract Create a snapshot from the three backend data sources.
 *
 * @param health   Result of fetchVideoHealth (status, version, etc.).
 * @param jobs     Result of fetchVideoJobsWithState:nil (array of job dicts).
 * @param quotas   Result of fetchVideoUploadLimits (upload/duration limits).
 */
- (instancetype)initWithHealth:(NSDictionary *)health
                          jobs:(NSArray<NSDictionary *> *)jobs
                        quotas:(NSDictionary *)quotas;

/**
 * @abstract The materialized snapshot dictionary suitable for HTML rendering.
 *
 * Keys: health, worker, queue (countsByState, depth, oldestAgeSeconds),
 *       throughput (completed24h, failed24h), storage, config (limits,
 *       hlsVariants, storageBackend), pdsUploadHealth.
 */
@property (nonatomic, readonly) NSDictionary *snapshot;

/// "healthy" | "degraded" | "unreachable"
@property (nonatomic, readonly) NSString *healthStatus;

/// Total job count across all states.
@property (nonatomic, readonly) NSUInteger totalJobs;

/// Per-state counts: pending, processing, transcoding, thumbnail, completed, failed.
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *countsByState;

/// Keys allowed in job-detail rendering. All other keys are redacted.
+ (NSSet<NSString *> *)jobDetailAllowlist;

/// Keys that must never appear in any rendered output.
+ (NSSet<NSString *> *)sensitiveKeys;

@end

NS_ASSUME_NONNULL_END
