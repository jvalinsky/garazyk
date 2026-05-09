/*!
 @file AppViewDatabase.h

 @abstract AppView-owned SQLite database with checkpoint, backfill, and
 relevance-set tables.

 @discussion Manages a dedicated database file separate from PDS service
 databases. All AppView-specific persistent state lives here:
 - Global relay cursors (checkpoints)
 - Per-repo sync state (backfill state machine)
 - Pending deltas (live ops buffered during active backfill)
 - Relevance membership (interest-graph partial mode)
 - Raw event log (idempotent by seq for duplicate suppression)
 - Dead-letter table (invalid records that failed indexing)

 Schema is versioned and applied via runMigrations.

 Thread-safety: All public methods are safe to call from any thread.
 The underlying SQLite connection is serialized by the database pool.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppViewTypes.h"
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*! Error domain for AppView database operations. */
extern NSString * const AppViewDatabaseErrorDomain;

/*!
 @protocol AppViewRecordStore

 @abstract Internal durable record/event boundary for AppView indexing.
 */
@protocol AppViewRecordStore <NSObject>

/*!
 @method saveRepoSnapshotForDID:lastRev:records:blocks:error:

 @abstract Persist a verified repo snapshot before specialized materializers run.

 @discussion Each record dictionary must contain uri, collection, rkey, cid, and
 may contain value and subject_did. Each block dictionary must contain cid_data
 and block_data. The operation is transactional and also appends an internal
 historical event plus marks the repo synced.
 */
- (BOOL)saveRepoSnapshotForDID:(NSString *)did
                       lastRev:(NSString *)lastRev
                       records:(NSArray<NSDictionary *> *)records
                        blocks:(NSArray<NSDictionary *> *)blocks
                         error:(NSError **)error;

/*!
 @method appendStoredEventWithType:seq:did:rev:cid:rawEnvelope:error:

 @abstract Append a durable internal cursor event. Duplicate commit triples are
 ignored idempotently.
 */
- (BOOL)appendStoredEventWithType:(NSString *)eventType
                              seq:(int64_t)seq
                              did:(nullable NSString *)did
                              rev:(nullable NSString *)rev
                              cid:(nullable NSString *)cid
                      rawEnvelope:(NSData *)rawEnvelope
                            error:(NSError **)error;

/*!
 @method loadStoredEventsAfterCursor:limit:error:

 @abstract Read internal events after a durable cursor, ordered by cursor ASC.
 */
- (nullable NSArray<NSDictionary *> *)loadStoredEventsAfterCursor:(int64_t)cursor
                                                           limit:(NSInteger)limit
                                                           error:(NSError **)error;

/*!
 @method durableCursorForRelayURL:

 @abstract Last event seq durable for a relay connection.
 */
- (int64_t)durableCursorForRelayURL:(NSString *)relayURL;

/*!
 @method markDurableCursor:forRelayURL:

 @abstract Advance the in-memory durable cursor after storage succeeds.
 */
- (void)markDurableCursor:(int64_t)seq forRelayURL:(NSString *)relayURL;

@end

/*!
 @class AppViewDatabase
 
 @abstract Manages the AppView SQLite database.
 */
@interface AppViewDatabase : NSObject <PDSQueryDatabase, AppViewRecordStore>

/*!
 @method initWithPath:error:

 @abstract Open (or create) the AppView database at the given path.

 @param path   Absolute path to the SQLite file.
 @param error  On failure, describes the problem.
 @return Initialized instance, or nil on failure.
 */
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error;

/*!
 @method initInMemoryWithError:

 @abstract Open an in-memory AppView database (testing).
 */
- (nullable instancetype)initInMemoryWithError:(NSError **)error;

/*!
 @method runMigrations:

 @abstract Apply all pending schema migrations.

 @param error  Describes the first migration that failed.
 @return YES if all migrations succeeded (or no-op), NO on failure.
 */
- (BOOL)runMigrations:(NSError **)error;

#pragma mark - Checkpoint

/*!
 @method saveCheckpoint:error:

 @abstract Upsert the cursor for a relay URL.
 */
- (BOOL)saveCheckpoint:(AppViewCheckpoint *)checkpoint error:(NSError **)error;

/*!
 @method loadCheckpointForRelayURL:error:

 @abstract Load the last saved checkpoint for a relay URL.
 Returns nil if none exists yet.
 */
- (nullable AppViewCheckpoint *)loadCheckpointForRelayURL:(NSString *)relayURL
                                                    error:(NSError **)error;

#pragma mark - Repo Sync State

/*!
 @method upsertRepoSyncState:error:

 @abstract Insert or replace the sync state for a repo DID.
 */
- (BOOL)upsertRepoSyncState:(AppViewRepoSyncState *)state error:(NSError **)error;

/*!
 @method loadRepoSyncStateForDID:error:

 @abstract Return the current sync state for a DID. Returns nil if unknown.
 */
- (nullable AppViewRepoSyncState *)loadRepoSyncStateForDID:(NSString *)did
                                                     error:(NSError **)error;

/*!
 @method loadRepoSyncStatesWithStatus:limit:error:

 @abstract Return repos in the given status, ordered by error_count ASC then
 last_backfill_at ASC (fair scheduling). Used by the backfill scheduler.
 */
- (nullable NSArray<AppViewRepoSyncState *> *)loadRepoSyncStatesWithStatus:(AppViewRepoSyncStatus)status
                                                                     limit:(NSInteger)limit
                                                                     error:(NSError **)error;

/*!
 @method countRepoSyncStatesWithStatus:error:

 @abstract Return a count of repos in the given status.
 */
- (NSInteger)countRepoSyncStatesWithStatus:(AppViewRepoSyncStatus)status
                                      error:(NSError **)error;

/*!
 @method getRepoSyncState:error:

 @abstract Get sync state for a specific DID. Alias for loadRepoSyncStateForDID:.
 */
- (nullable AppViewRepoSyncState *)getRepoSyncState:(NSString *)did
                                             error:(NSError **)error;

/*!
 @method setRepoSyncState:error:

 @abstract Update sync state for a repo. Alias for upsertRepoSyncState:.
 */
- (BOOL)setRepoSyncState:(AppViewRepoSyncState *)state
                  error:(NSError **)error;

/*!
 @method markReposAsProcessing:error:

 @abstract Atomically transition a batch of DIDs from pending → processing.
 Returns the DIDs that were actually transitioned (already-processing are skipped).
 */
- (nullable NSArray<NSString *> *)markReposAsProcessing:(NSArray<NSString *> *)dids
                                                  error:(NSError **)error;

/*!
 @method markRepoSynced:lastRev:error:

 @abstract Transition a repo to synced with the given revision.
 */
- (BOOL)markRepoSynced:(NSString *)did lastRev:(NSString *)lastRev error:(NSError **)error;

/*!
 @method markRepoDirty:error:

 @abstract Transition a repo to dirty (gap detected, needs re-sync).
 */
- (BOOL)markRepoDirty:(NSString *)did error:(NSError **)error;

/*!
 @method recordBackfillError:message:error:

 @abstract Increment error_count and store error message; keep processing status.
 */
- (BOOL)recordBackfillError:(NSString *)did message:(NSString *)message error:(NSError **)error;

#pragma mark - Pending Deltas

/*!
 @method enqueuePendingDelta:error:

 @abstract Persist a live delta for a repo whose backfill is in-flight.
 Idempotent: duplicate (did, seq) pairs are silently ignored.
 */
- (BOOL)enqueuePendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error;

/*!
 @method dequeuePendingDeltasForDID:error:

 @abstract Return all pending deltas for a DID ordered by seq ASC,
 then delete them. Called once backfill completes for that DID.
 */
- (nullable NSArray<AppViewPendingDelta *> *)dequeuePendingDeltasForDID:(NSString *)did
                                                                  error:(NSError **)error;

/*!
 @method countPendingDeltasForDID:error:

 @abstract Return the count of queued deltas for a DID.
 */
- (NSInteger)countPendingDeltasForDID:(NSString *)did error:(NSError **)error;

#pragma mark - Event Log (raw ingest)

/*!
 @method logEvent:seq:did:rev:cid:rawEnvelope:error:

 @abstract Persist a raw ingest event.
 Idempotent: duplicate (did, rev, cid) are silently skipped.

 @param seq          Global relay sequence number.
 @param did          Repo DID (may be nil for non-commit events).
 @param rev          Commit revision (may be nil for identity/account events).
 @param cid          Commit CID (may be nil for non-commit events).
 @param rawEnvelope  Raw CBOR envelope bytes.
 */
- (BOOL)logEvent:(int64_t)seq
              did:(nullable NSString *)did
              rev:(nullable NSString *)rev
              cid:(nullable NSString *)cid
      rawEnvelope:(NSData *)rawEnvelope
            error:(NSError **)error;

/*!
 @method hasEventWithDID:rev:cid:

 @abstract Returns YES if this (did, rev, cid) triple has been seen before.
 Used for idempotency checks without a full DB round-trip.
 */
- (BOOL)hasEventWithDID:(nullable NSString *)did
                    rev:(nullable NSString *)rev
                    cid:(nullable NSString *)cid;

/*!
 @method pruneEventLogOlderThan:error:

 @abstract Delete raw events older than cutoff. Returns rows deleted.
 */
- (NSInteger)pruneEventLogOlderThan:(NSDate *)cutoff error:(NSError **)error;

#pragma mark - Relevance Set

/*!
 @method upsertRelevanceMembership:error:

 @abstract Insert or update a relevance membership entry.
 */
- (BOOL)upsertRelevanceMembership:(AppViewRelevanceMembership *)membership
                            error:(NSError **)error;

/*!
 @method loadRelevanceMembershipForDID:error:

 @abstract Return the membership entry for a DID, or nil if not a member.
 */
- (nullable AppViewRelevanceMembership *)loadRelevanceMembershipForDID:(NSString *)did
                                                                 error:(NSError **)error;

/*!
 @method isDIDRelevant:

 @abstract Fast membership check — returns YES if the DID is in the relevance
 set and the entry has not expired. Uses an in-memory bloom-filter-style cache
 populated at startup and updated on every upsert.
 */
- (BOOL)isDIDRelevant:(NSString *)did;

/*!
 @method pruneExpiredRelevanceMemberships:

 @abstract Delete expired entries and rebuild the in-memory cache.
 Returns count of entries removed.
 */
- (NSInteger)pruneExpiredRelevanceMemberships:(NSError **)error;

/*!
 @method loadAllRelevantDIDs:

 @abstract Return all currently-valid DID strings in the relevance set.
 */
- (nullable NSArray<NSString *> *)loadAllRelevantDIDs:(NSError **)error;

#pragma mark - Dead-Letter

/*!
 @method recordDeadLetterEvent:seq:did:rev:cid:rawRecord:validationError:error:

 @abstract Persist a record that failed lexicon validation or indexing.
 */
- (BOOL)recordDeadLetterEvent:(NSString *)collection
                          seq:(int64_t)seq
                          did:(NSString *)did
                          rev:(nullable NSString *)rev
                          cid:(nullable NSString *)cid
                    rawRecord:(NSData *)rawRecord
              validationError:(NSString *)validationError
                        error:(NSError **)error;

/*!
 @method saveRecordWithURI:did:collection:rkey:cid:value:subjectDid:error:
 @abstract Helper for indexers to materialze records.
 */
- (BOOL)saveRecordWithURI:(NSString *)uri
                     did:(NSString *)did
              collection:(NSString *)collection
                    rkey:(NSString *)rkey
                     cid:(NSString *)cid
                  handle:(nullable NSString *)handle
                   value:(nullable NSString *)value
              subjectDid:(nullable NSString *)subjectDid
                   error:(NSError **)error;

/*!
 @method saveBlockWithCid:repoDid:blockData:contentType:error:
 @abstract Helper for indexers to materialize blocks.
 */
- (BOOL)saveBlockWithCid:(NSData *)cid
                repoDid:(NSString *)repoDid
              blockData:(NSData *)blockData
            contentType:(nullable NSString *)contentType
                  error:(NSError **)error;

#pragma mark - Stats

/*!
 @method getTotalRecordsCountForCollection:error:
 @abstract Get total number of materialized records in a collection.
 */
- (NSInteger)getTotalRecordsCountForCollection:(NSString *)collection error:(NSError **)error;

/*!
 @method getTotalBlocksCountWithError:
 @abstract Get total number of materialized blocks.
 */
- (NSInteger)getTotalBlocksCountWithError:(NSError **)error;

#pragma mark - Generic Record Queries

/*!
 @method getRecordWithURI:did:collection:rkey:error:

 @abstract Retrieve a single record by its components.

 @param uri        The AT URI of the record.
 @param did        The DID of the repo.
 @param collection The collection NSID.
 @param rkey       The record key.
 @param error      On failure, describes the problem.

 @return Dictionary with uri, cid, value, did, collection, rkey; or nil if not found.
 */
- (nullable NSDictionary *)getRecordWithURI:(NSString *)uri
                                       did:(NSString *)did
                                collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                    error:(NSError **)error;

/*!
 @method listRecordsForCollection:did:limit:cursor:error:

 @abstract Paginated list of records in a collection, optionally filtered by DID.

 @param collection The collection NSID.
 @param did       Optional DID filter (nil for all repos).
 @param limit     Maximum records to return (1-100).
 @param cursor    Pagination cursor (nil for first page).
 @param error     On failure, describes the problem.

 @return Dictionary with "records" array and optional "cursor" for next page.
 */
- (nullable NSDictionary *)listRecordsForCollection:(NSString *)collection
                                                did:(nullable NSString *)did
                                              limit:(NSInteger)limit
                                             cursor:(nullable NSString *)cursor
                                              error:(NSError **)error;

/*!
 @method indexedCollectionsWithError:

 @abstract Return all collections that have indexed records.

 @return Array of collection NSID strings.
 */
- (nullable NSArray<NSString *> *)indexedCollectionsWithError:(NSError **)error;

/*!
 @method recordCountForCollection:error:

 @abstract Count records in a specific collection.

 @param collection The collection NSID.
 @param error      On failure, describes the problem.

 @return Count of records, or -1 on error.
 */
- (NSInteger)recordCountForCollection:(NSString *)collection error:(NSError **)error;

#pragma mark - Handle Resolution

/*!
 @method saveHandle:did:error:
 @abstract Update handle-to-DID mapping.
 */
- (BOOL)saveHandle:(NSString *)handle did:(NSString *)did error:(NSError **)error;

/*!
 @method resolveHandleToDID:error:
 @abstract Find DID for a given handle.
 */
- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error;

/*!
 @method resolveDIDToHandle:error:
 @abstract Find handle for a given DID.
 */
- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error;

#pragma mark - Lifecycle

/*! Close the database connection. */
- (void)close;

@end

NS_ASSUME_NONNULL_END
