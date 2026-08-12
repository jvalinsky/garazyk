// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class GZAppViewConfiguration;
@class GZAppViewDatabase;
@class GZAppViewIngestEngine;
@class GZAppViewBackfillOrchestrator;
@class GZSyrenaMetrics;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Resolve the admin password from explicit path, env file, or env var.
 *
 * Precedence: @p explicitPath > SYRENA_ADMIN_PASSWORD_FILE > SYRENA_ADMIN_PASSWORD.
 * Returns nil when no password is configured (admin UI disabled).
 */
NSString * _Nullable GZSyrenaAdminPassword(NSString * _Nullable explicitPath);

/**
 * @abstract Bounded, immutable snapshot of Syrena (AppView) admin dashboard state.
 *
 * The snapshot composes metrics counters, ingest engine live state
 * (relayHealth, lagByRelay, throughput, isRunning), backfill orchestrator
 * status, coverage gauges, and cheap exception counts. No full-table scans
 * on record bodies for headline cards.
 */
@interface GZSyrenaAdminSnapshot : NSObject

- (instancetype)initWithDatabase:(nullable GZAppViewDatabase *)database
                         metrics:(GZSyrenaMetrics *)metrics
                   configuration:(GZAppViewConfiguration *)configuration
                    ingestEngine:(nullable GZAppViewIngestEngine *)ingestEngine
         backfillOrchestrator:(nullable GZAppViewBackfillOrchestrator *)orchestrator NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Returns a dictionary snapshot suitable for the admin UI partials.
 *
 * Keys: health, uptimeSeconds, lanes, ingest, backfill, coverage, indexes,
 *       lexicons, queries, exceptions, storageBytes, rateLimitRejects, config.
 */
- (NSDictionary<NSString *, id> *)snapshot;

/**
 * @abstract Bounded backfill queue rows for the Repo sync partial / queue refresh.
 */
- (NSDictionary<NSString *, id> *)queueWithStatus:(nullable NSString *)status
                                            limit:(NSInteger)limit
                                           cursor:(nullable NSString *)cursor;

- (NSDictionary<NSString *, id> *)enqueueDIDs:(NSArray<NSString *> *)dids;
- (NSDictionary<NSString *, id> *)retryDID:(NSString *)did;
- (NSDictionary<NSString *, id> *)cancelDID:(NSString *)did;
- (NSDictionary<NSString *, id> *)rebuildScope;

@end

NS_ASSUME_NONNULL_END
