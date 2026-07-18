// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class PDSDatabasePool;

/*!
 @class PDSCollectionMembershipPruner

 @abstract Periodically removes stale entries from the collection_membership
 materialized index.

 @discussion The collection_membership table is maintained on record
 create/update by PDSRecordService. Deletes trigger immediate pruning (if
 no records remain). This pruner acts as a safety net: it periodically
 scans all index entries and verifies each against its actor store,
 removing entries where the DID no longer has records in that collection.
 */
@interface PDSCollectionMembershipPruner : NSObject

/*!
 @method initWithServiceDatabases:userDatabasePool:intervalInSeconds:

 @param serviceDatabases Service databases for index access.
 @param userDatabasePool Pool for accessing per-user actor stores.
 @param interval Minimum interval between prune cycles in seconds
        (clamped to 300 minimum).
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                       userDatabasePool:(PDSDatabasePool *)userDatabasePool
                      intervalInSeconds:(NSTimeInterval)interval;

/*! Start periodic pruning. Safe to call multiple times. */
- (void)start;

/*! Stop periodic pruning and release the timer. */
- (void)stop;

/*! Trigger an immediate prune cycle (does not affect the schedule). */
- (void)pruneNow;

@end

NS_ASSUME_NONNULL_END
