// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file GZBeskidMetrics.h
 * @abstract Thread-safe monotonic counters, entry gauges, and bounded
 *           upstream-host aggregation for the Beskid edge cache.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GZBeskidMetrics : NSObject

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

/// @name Firehose invalidation
- (void)setFirehoseConnected:(BOOL)connected;
- (void)recordFirehoseInvalidation:(NSString *)type;
- (void)recordFirehoseReconnect;
- (void)recordFirehoseParseError;
- (void)recordIdentityDelete;

/** Event entered a handler with a usable DID (`commit` / `identity` / `account`). */
- (void)recordFirehoseEventReceived:(NSString *)type;
/**
 Purge outcome: `precise` (path/key delete), `fallback` (DID-wide purge),
 or `dropped` (DB failure).
 */
- (void)recordFirehoseInvalidationApplied:(NSString *)outcome;
/** Milliseconds from handler start to first successful purge in that event. */
- (void)recordFirehosePurgeLatencyMillis:(int64_t)ms;
/** Soft-mark a DID so a subsequent origin GET can be attributed. */
- (void)markInvalidationForDID:(NSString *)did;
/**
 Counts an origin GET attributable to a recent invalidation mark for `did`.
 Returns YES when a mark was consumed.
 */
- (BOOL)consumeInvalidationAttributionForDID:(NSString *)did
                                      toHost:(NSString *)host;

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
