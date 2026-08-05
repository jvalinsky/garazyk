// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayRepoStateManager.h

 @abstract Tracks repository state for the relay.

 @discussion
    RelayRepoStateManager tracks:
    - Current signed commit ATProtoCID and MST data-root ATProtoCID for each repo
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
 * @abstract Result of atomically checking and applying a repository commit.
 */
typedef NS_ENUM(NSInteger, RelayRepoAdvanceResult) {
    /** No prior authenticated data root existed; the event established it. */
    RelayRepoAdvanceResultBaselineEstablished,
    /** The event continued the stored revision and data-root chain. */
    RelayRepoAdvanceResultAdvanced,
    /** The event revision was not newer than the stored revision. */
    RelayRepoAdvanceResultStale,
    /** The event omitted continuity fields; it was accepted as a new baseline. */
    RelayRepoAdvanceResultUnverifiableAdvanced,
    /** The event's ``since`` revision did not match the stored revision. */
    RelayRepoAdvanceResultSinceMismatch,
    /** The event's ``prevData`` did not match the stored MST data root. */
    RelayRepoAdvanceResultPrevDataMismatch
};

/**
 * @abstract Maintains per-repository relay cursor, root, revision, and status state.
 */
@interface RelayRepoStateManager : NSObject

/**
 * @abstract Creates an empty in-memory repository state manager.
 */
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Creates a repository state manager backed by an on-disk SQLite database.
 * @param dataDir The directory in which the relay state database is stored.
 * @param error   Receives database-open failures.
 */
- (nullable instancetype)initWithDataDir:(NSString *)dataDir
                                   error:(NSError **)error NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Records the latest commit state for a repository.
 * @param repoDID The repository DID that emitted the commit.
 * @param rootCID The signed repository commit ATProtoCID after the commit.
 * @param rev The repository revision string after the commit.
 * @param seq The firehose sequence number for the commit event.
 */
- (void)handleCommitForRepo:(NSString *)repoDID
                       root:(NSString *)rootCID
                         rev:(NSString *)rev
                         seq:(int64_t)seq;

/**
 * @abstract Records a structurally validated repository commit as the current baseline.
 * @param repoDID Repository DID.
 * @param commitCID Signed repository commit-object ATProtoCID.
 * @param dataCID MST data-root ATProtoCID from the signed commit object.
 * @param rev Repository revision.
 * @param seq Upstream firehose sequence.
 */
- (void)handleCommitForRepo:(NSString *)repoDID
                  commitCID:(NSString *)commitCID
                    dataCID:(nullable NSString *)dataCID
                        rev:(NSString *)rev
                        seq:(int64_t)seq;

/**
 * @abstract Atomically validates continuity and advances repository state.
 *
 * The next event's ``prevData`` is compared with the stored signed commit
 * object's ``data`` ATProtoCID. It is never compared with the signed commit ATProtoCID.
 */
- (RelayRepoAdvanceResult)advanceRepo:(NSString *)repoDID
                                since:(nullable NSString *)since
                             prevData:(nullable NSString *)prevDataCID
                            commitCID:(NSString *)commitCID
                              dataCID:(nullable NSString *)dataCID
                                  rev:(NSString *)rev
                                  seq:(int64_t)seq;

/**
 * @abstract Observes a commit head from ``com.atproto.sync.listRepos``.
 *
 * Inventory contains a commit ATProtoCID and revision but no MST data root. Existing
 * live state is not regressed by an older inventory response.
 */
- (void)observeInventoryForRepo:(NSString *)repoDID
                      commitCID:(NSString *)commitCID
                            rev:(NSString *)rev
                         active:(BOOL)active;

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
 * @abstract Returns the latest known signed commit ATProtoCID for a repository.
 * @param repoDID The repository DID to query.
 * @return The signed commit ATProtoCID, or nil when the repository is unknown.
 */
- (nullable NSString *)rootCIDForRepo:(NSString *)repoDID;

/** Returns the current signed repository commit-object ATProtoCID. */
- (nullable NSString *)commitCIDForRepo:(NSString *)repoDID;

/** Returns the current MST data-root ATProtoCID extracted from the signed commit. */
- (nullable NSString *)dataCIDForRepo:(NSString *)repoDID;

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
 * @abstract Compatibility alias for the current MST data-root ATProtoCID.
 *
 * This method's historical implementation conflated commit CIDs with MST data
 * roots. New code must use ``dataCIDForRepo:``.
 * @param repoDID The repository DID to query.
 * @return The current MST data-root ATProtoCID, or nil when unknown.
 */
- (nullable NSString *)prevDataCIDForRepo:(NSString *)repoDID
    __attribute__((deprecated("Use dataCIDForRepo:; relay state stores the current signed commit data root")));

/**
 * @abstract Synchronizes the in-memory state to the on-disk database.
 *
 *  When the manager was initialised with ``initWithDataDir:error:`` this writes
 *  all tracked repository records to SQLite.  For an in-memory manager created
 *  via ``init`` this is a no-op.
 */
- (void)persistState;

/**
 * @abstract Loads previously persisted repository state from the on-disk database.
 *
 *  When the manager was initialised with ``initWithDataDir:error:`` this reads
 *  all stored records into the in-memory dictionaries.  For an in-memory manager
 *  this is a no-op returning YES.
 *
 * @param error Receives database-read failures.
 * @return YES when the state was loaded (or when operating in-memory).
 */
- (BOOL)loadState:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
