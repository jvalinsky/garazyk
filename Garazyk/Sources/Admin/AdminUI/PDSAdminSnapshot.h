// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAdminSnapshot.h
 @abstract Bounded PDS overview snapshot for the embedded admin UI.
 */

#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPDSOverviewSnapshot.h"

@class PDSDatabase;
@class PDSDatabasePool;
@class PDSServiceDatabases;
@class ATProtoSubscribeReposHandler;

NS_ASSUME_NONNULL_BEGIN

/**
 Aggregates cheap, in-process PDS overview fields for `/admin/partials/pds-stats`.

 Counts come from existing admin COUNT(*) queries; database size uses in-connection
 PRAGMA page_count/page_size; pool size uses in-memory cache counters only.
 Never scans actor-store or blob directories.

 @c adminStatsSource must respond to @c getServerStatsWithError: (typically
 @c PDSAdminController / @c PDSAdminService).
 */
@interface GZPDSAdminSnapshot : NSObject <GZAdminUIPDSOverviewSnapshot>

- (instancetype)initWithDatabase:(PDSDatabase *)database
                 adminStatsSource:(nullable id)adminStatsSource
                 userDatabasePool:(nullable PDSDatabasePool *)userDatabasePool
                 serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
           subscribeReposHandler:(nullable ATProtoSubscribeReposHandler *)subscribeReposHandler
                        startedAt:(nullable NSDate *)startedAt NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/** Materialized overview dictionary for HTML rendering / DTO projection. */
- (NSDictionary<NSString *, id> *)snapshot;

@end

NS_ASSUME_NONNULL_END
