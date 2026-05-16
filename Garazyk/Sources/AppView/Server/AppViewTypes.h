// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewTypes.h

 @abstract Core value types for the standalone AppView server.

 @discussion Defines the fundamental data types shared across all AppView
 planes (ingest, indexing, query). These are plain structs and enums —
 no Objective-C objects, no allocations.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Repo Sync State

/*!

 @abstract State machine for per-repo backfill lifecycle.

 @constant AppViewRepoSyncStatusPending    Repo is known but not yet backfilled.
 @constant AppViewRepoSyncStatusProcessing Backfill worker is actively fetching.
 @constant AppViewRepoSyncStatusSynced     Backfill complete; live deltas apply.
 @constant AppViewRepoSyncStatusDirty      Synced but a gap was detected; needs re-sync.
 */
typedef NS_ENUM(NSInteger, AppViewRepoSyncStatus) {
    AppViewRepoSyncStatusPending    = 0,
    AppViewRepoSyncStatusProcessing = 1,
    AppViewRepoSyncStatusSynced     = 2,
    AppViewRepoSyncStatusDirty      = 3,
};

/*!
 @interface AppViewRepoSyncState

 @abstract Persistent per-repo backfill state.
 */
@interface AppViewRepoSyncState : NSObject <NSCopying>

/*! DID of the repository. */
@property (nonatomic, copy)   NSString *did;

/*! Current sync status. */
@property (nonatomic, assign) AppViewRepoSyncStatus status;

/*! Last known revision (CID string). Nil if not yet synced. */
@property (nonatomic, copy, nullable) NSString *lastRev;

/*! Wall-clock time of last successful backfill completion. */
@property (nonatomic, strong, nullable) NSDate *lastBackfillAt;

/*! Consecutive error count (reset on success). */
@property (nonatomic, assign) NSInteger errorCount;

/*! Human-readable last error message. */
@property (nonatomic, copy, nullable) NSString *lastError;

- (instancetype)initWithDID:(NSString *)did;

@end

#pragma mark - Global Cursor Checkpoint

/*!
 @interface AppViewCheckpoint

 @abstract Durable cursor for the global subscribeRepos stream.

 @discussion The AppView persists this checkpoint periodically so that on
 restart it can resume from the last confirmed position rather than replaying
 the full network history.
 */
@interface AppViewCheckpoint : NSObject <NSCopying>

/*! Relay URL this checkpoint belongs to. */
@property (nonatomic, copy) NSString *relayURL;

/*! Global sequence number (inclusive — this event has been processed). */
@property (nonatomic, assign) int64_t seq;

/*! Wall-clock time this checkpoint was saved. */
@property (nonatomic, strong) NSDate *savedAt;

- (instancetype)initWithRelayURL:(NSString *)relayURL seq:(int64_t)seq;

@end

#pragma mark - Pending Repo Delta

/*!
 @interface AppViewPendingDelta

 @abstract A live ingest event queued for a repo whose backfill is in-flight.

 @discussion When a commit arrives for a repo in AppViewRepoSyncStatusProcessing
 state, the event is not immediately materialized. Instead it is stored here and
 replayed (in sequence order) once the backfill completes.
 */
@interface AppViewPendingDelta : NSObject

/*! DID of the repo. */
@property (nonatomic, copy)   NSString *did;

/*! Global sequence number of the ingest event. */
@property (nonatomic, assign) int64_t  seq;

/*! CID of the commit (used for idempotency). */
@property (nonatomic, copy)   NSString *commitCID;

/*! Revision string of the commit. */
@property (nonatomic, copy)   NSString *rev;

/*! Raw CBOR-encoded event envelope. */
@property (nonatomic, strong) NSData   *rawEnvelope;

/*! Time the delta was enqueued. */
@property (nonatomic, strong) NSDate   *enqueuedAt;

- (instancetype)initWithDID:(NSString *)did
                        seq:(int64_t)seq
                  commitCID:(NSString *)commitCID
                        rev:(NSString *)rev
                rawEnvelope:(NSData *)rawEnvelope;

@end

#pragma mark - Relevance Membership

/*!

 @abstract Why a DID is in the relevance set R.

 @constant AppViewRelevanceReasonSeed           Explicitly configured seed DID.
 @constant AppViewRelevanceReasonAllowlist       Explicitly configured allowlist entry.
 @constant AppViewRelevanceReasonFollowOfSeed    Follows a seed DID.
 @constant AppViewRelevanceReasonRecentInteraction Interacted with an R-member recently.
 */
typedef NS_ENUM(NSInteger, AppViewRelevanceReason) {
    AppViewRelevanceReasonSeed              = 0,
    AppViewRelevanceReasonAllowlist         = 1,
    AppViewRelevanceReasonFollowOfSeed      = 2,
    AppViewRelevanceReasonRecentInteraction = 3,
};

/*!
 @interface AppViewRelevanceMembership

 @abstract A single entry in the interest-graph relevance set.
 */
@interface AppViewRelevanceMembership : NSObject

/*! DID that is a member. */
@property (nonatomic, copy)   NSString *did;

/*! Primary reason for membership. */
@property (nonatomic, assign) AppViewRelevanceReason reason;

/*! Expiration date. nil = permanent (seeds and allowlist). */
@property (nonatomic, strong, nullable) NSDate *expiresAt;

/*! Time the membership was recorded. */
@property (nonatomic, strong) NSDate *addedAt;

- (instancetype)initWithDID:(NSString *)did
                     reason:(AppViewRelevanceReason)reason
                  expiresAt:(nullable NSDate *)expiresAt;

/*! Returns YES if this membership has not yet expired. */
- (BOOL)isValid;

@end

NS_ASSUME_NONNULL_END
