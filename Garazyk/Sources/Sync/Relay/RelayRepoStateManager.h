// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayRepoStateManager.h

 @abstract Tracks repository state for the relay.

 @discussion
    RelayRepoStateManager tracks:
    - Current root CID for each repo
    - Last sequence number for each repo
    - Repo status (active, desynchronized, etc.)
    
    Sync v1.1 account statuses:
    - desynchronized: out-of-sync with current revision
    - in-progress: actively synchronizing
    - throttled: temporary failure

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Sync status tracked for a repository known to the relay.
 */
typedef NS_ENUM(NSInteger, RelayRepoStatus) {
    /** The repository is current enough to serve normally. */
    RelayRepoStatusActive,
    /** The relay has detected that its view of the repository is stale. */
    RelayRepoStatusDesynchronized,
    /** The repository is actively being synchronized. */
    RelayRepoStatusInProgress,
    /** Synchronization is delayed because the upstream is temporarily unavailable. */
    RelayRepoStatusThrottled,
    /** The repository has been removed and should not be served as active. */
    RelayRepoStatusTombstoned
};

/**
 * @abstract Maintains per-repository relay cursor, root, revision, and status state.
 */
@interface RelayRepoStateManager : NSObject

/**
 * @abstract Creates an empty repository state manager.
 */
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Records the latest commit state for a repository.
 * @param repoDID The repository DID that emitted the commit.
 * @param rootCID The repository root CID after the commit.
 * @param rev The repository revision string after the commit.
 * @param seq The firehose sequence number for the commit event.
 */
- (void)handleCommitForRepo:(NSString *)repoDID
                       root:(NSString *)rootCID
                         rev:(NSString *)rev
                         seq:(int64_t)seq;

/**
 * @abstract Marks that an identity event was received for a repository.
 * @param repoDID The repository DID associated with the identity event.
 */
- (void)handleIdentityEventForRepo:(NSString *)repoDID;

/**
 * @abstract Updates the tracked status for a repository account event.
 * @param repoDID The repository DID associated with the account event.
 * @param status The new relay status for the repository.
 */
- (void)handleAccountEventForRepo:(NSString *)repoDID status:(RelayRepoStatus)status;

/**
 * @abstract Marks a repository as tombstoned.
 * @param repoDID The repository DID to tombstone.
 */
- (void)handleTombstoneForRepo:(NSString *)repoDID;

/**
 * @abstract Returns the latest known root CID for a repository.
 * @param repoDID The repository DID to query.
 * @return The root CID, or nil when the repository is unknown.
 */
- (nullable NSString *)rootCIDForRepo:(NSString *)repoDID;

/**
 * @abstract Returns the latest known revision for a repository.
 * @param repoDID The repository DID to query.
 * @return The revision string, or nil when the repository is unknown.
 */
- (nullable NSString *)revForRepo:(NSString *)repoDID;

/**
 * @abstract Returns the last sequence cursor seen for a repository.
 * @param repoDID The repository DID to query.
 * @return The last sequence number, or zero when no cursor is tracked.
 */
- (int64_t)cursorForRepo:(NSString *)repoDID;

/**
 * @abstract Returns the current relay status for a repository.
 * @param repoDID The repository DID to query.
 * @return The tracked status for the repository.
 */
- (RelayRepoStatus)statusForRepo:(NSString *)repoDID;

/**
 * @abstract Returns all repository DIDs currently tracked by the manager.
 */
- (NSArray<NSString *> *)allRepos;

/**
 * @abstract Returns the number of tracked repositories.
 */
- (NSUInteger)repoCount;

/**
 * @abstract Persists the in-memory repository state.
 */
- (void)persistState;

/**
 * @abstract Loads previously persisted repository state.
 * @param error Receives load or decode failures.
 * @return YES when persisted state was loaded.
 */
- (BOOL)loadState:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
