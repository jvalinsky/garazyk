/*!
 @file AppViewRelevanceSet.h

 @abstract Interest-graph partial mode: manages the relevance set R.

 @discussion The relevance set R is the set of DIDs for which the AppView
 will materialize heavy views (timelines, threads, notifications, etc.).

 R is built from:
  1. Seed DIDs (explicitly configured, permanent membership).
  2. Allowlist DIDs (explicitly configured, permanent membership).
  3. Follows of seeds (dynamic, expires after ttlHours).
  4. Recent interaction expansion (DID interacted with by an R-member,
     expires after ttlHours).

 Membership is persisted in the AppViewDatabase relevance table and an
 in-memory NSSet is kept for fast O(1) isDIDRelevant: checks.

 Thread-safety: All public methods are safe to call from any thread.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppView/Server/AppViewTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;

/*!
 @interface AppViewRelevanceSet

 @abstract Manages the interest-graph relevance set for partial-mode operation.
 */
@interface AppViewRelevanceSet : NSObject

/*! TTL in hours for dynamic memberships (follows-of-seeds, recent interactions). Default 168 (7 days). */
@property (nonatomic, assign) NSUInteger ttlHours;

/*!
 @method initWithDatabase:seedDIDs:allowlist:ttlHours:

 @param database   AppView database for persisting membership.
 @param seedDIDs   Permanent seed DIDs.
 @param allowlist  Permanent allowlist DIDs.
 @param ttlHours   TTL for dynamic memberships.
 */
- (instancetype)initWithDatabase:(AppViewDatabase *)database
                        seedDIDs:(NSArray<NSString *> *)seedDIDs
                       allowlist:(NSArray<NSString *> *)allowlist
                        ttlHours:(NSUInteger)ttlHours;

/*!
 @method isDIDRelevant:

 @abstract Fast in-memory check — O(1). Returns YES if DID is in R and not expired.
 */
- (BOOL)isDIDRelevant:(NSString *)did;

/*!
 @method addDID:reason:

 @abstract Add a DID to R with the given reason and configured TTL (if dynamic).
 Persists to database. Thread-safe.
 */
- (void)addDID:(NSString *)did reason:(AppViewRelevanceReason)reason;

/*!
 @method addDIDs:reason:

 @abstract Batch add. Thread-safe.
 */
- (void)addDIDs:(NSArray<NSString *> *)dids reason:(AppViewRelevanceReason)reason;

/*!
 @method expandFromFollowsOf:

 @abstract For a DID that is in R, look up its follows and add them as
 AppViewRelevanceReasonFollowOfSeed entries. Enqueues a backfill for each
 newly-added DID if it is not already synced.

 @param did  DID whose follows should be expanded.
 */
- (void)expandFromFollowsOf:(NSString *)did;

/*!
 @method recordInteraction:withDID:

 @abstract Record that an R-member (actorDID) interacted with targetDID.
 Adds targetDID to R as AppViewRelevanceReasonRecentInteraction.
 */
- (void)recordInteraction:(NSString *)actorDID withDID:(NSString *)targetDID;

/*!
 @method pruneExpired

 @abstract Remove expired entries from the database and rebuild the in-memory cache.
 Returns number of entries removed.
 */
- (NSInteger)pruneExpired;

/*!
 @method rebuild

 @abstract Re-seed all permanent entries (seeds + allowlist) and rebuild the
 in-memory cache from the database. Call on startup after migrations.
 */
- (void)rebuild;

/*!
 @method allRelevantDIDs

 @abstract Return all valid DID strings in R. May be large in full-network mode.
 */
- (NSArray<NSString *> *)allRelevantDIDs;

@end

NS_ASSUME_NONNULL_END
