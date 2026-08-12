// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class AppViewConfiguration;
@class AppViewDatabase;
@class AppViewIngestEngine;
@class AppViewBackfillOrchestrator;
@class SyrenaMetrics;

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
 * status, and cheap database gauges (repo sync state counts, collection
 * counts, indexed collections, hook count).  No COUNT(*) scans on record
 * tables — those are polled from the admin route pack's existing handlers.
 */
@interface GZSyrenaAdminSnapshot : NSObject

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                         metrics:(SyrenaMetrics *)metrics
                   configuration:(AppViewConfiguration *)configuration
                    ingestEngine:(AppViewIngestEngine *)ingestEngine
         backfillOrchestrator:(nullable AppViewBackfillOrchestrator *)orchestrator NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Returns a dictionary snapshot suitable for the admin UI partials.
 *
 * Keys: health, uptimeSeconds, ingest, backfill, indexes, lexicons,
 *       hooks, storageBytes, rateLimitRejects.
 */
- (NSDictionary<NSString *, id> *)snapshot;

@end

NS_ASSUME_NONNULL_END
