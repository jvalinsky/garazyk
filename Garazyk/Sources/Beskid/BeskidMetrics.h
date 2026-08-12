// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file BeskidMetrics.h
 * @abstract Thread-safe monotonic counters, entry gauges, and bounded
 *           upstream-host aggregation for the Beskid edge cache.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BeskidMetrics : NSObject

/// @name Cache counters
- (void)recordRecordHit;
- (void)recordRecordMiss;
- (void)recordRecordExpiredRead;
- (void)recordRecordWriteWithExpiresAt:(int64_t)expiresAt;
- (void)recordRecordDelete;

- (void)recordIdentityHit;
- (void)recordIdentityMiss;
- (void)recordIdentityExpiredRead;
- (void)recordIdentityWriteWithExpiresAt:(int64_t)expiresAt;

/// @name Rate limiting
- (void)recordRateLimitReject;

/// @name Upstream counters (bounded per-host, cap 32)
- (void)recordUpstreamRequestToHost:(NSString *)host;
- (void)recordUpstreamSuccessToHost:(NSString *)host latencyMillis:(int64_t)latencyMillis;
- (void)recordUpstreamFailureToHost:(NSString *)host;

/// @name Entry gauges (one-time seed at startup; live-entries maintained
///       by write/delete/expired-read operations)
- (void)seedEntryGaugesWithRecordCount:(NSUInteger)recordCount
                        identityCount:(NSUInteger)identityCount;

/// @name Snapshot
- (NSDictionary<NSString *, id> *)snapshotDictionary;

@end

NS_ASSUME_NONNULL_END
