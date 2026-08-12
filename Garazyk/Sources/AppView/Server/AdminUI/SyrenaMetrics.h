// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Thread-safe counters for the Syrena (AppView) admin dashboard.
 *
 * All recording methods are safe to call from any thread (ingest delegate,
 * backfill delegate, query handlers, etc.).  The snapshot method produces a
 * point-in-time dictionary safe for the admin UI partial pipeline.
 */
@interface SyrenaMetrics : NSObject

#pragma mark - Ingest counters

- (void)recordIngestEvent;
- (void)recordIngestCommit;
- (void)recordIngestOp;
- (void)recordIngestDelete;
- (void)recordIngestIdentity;
- (void)recordIngestError;

#pragma mark - Backfill counters

- (void)recordBackfillCompleted;
- (void)recordBackfillFailed;
- (void)recordBackfillEnqueued:(NSUInteger)count;

#pragma mark - Query counters

- (void)recordQuery:(NSString *)family;
- (void)recordQueryError;

#pragma mark - Rate-limit / rejection

- (void)recordRateLimitReject;

#pragma mark - Snapshot

/**
 * @abstract Returns a point-in-time dictionary of all counter values.
 *
 * Key paths match the shape expected by GZSyrenaAdminUIPack HTML renderers.
 */
- (NSDictionary<NSString *, id> *)snapshotDictionary;

@end

NS_ASSUME_NONNULL_END
