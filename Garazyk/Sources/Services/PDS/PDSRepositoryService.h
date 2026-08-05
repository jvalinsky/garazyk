// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSRepositoryService.h
 *
 * @abstract Repository management service layer.
 *
 * @discussion Provides high-level repository operations including MST loading,
 * updates, commit processing, and repo synchronization. Coordinates between
 * database pool and MST persistence layer.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Pull-based producer that returns the next repository export chunk.
 */
typedef NSData * _Nullable (^PDSRepoChunkProducer)(NSError **error);

@class PDSDatabasePool;
@class PDSActorStore;

@class MST;
@class ATProtoCID;

/**
 * @abstract Defines the PDSBlockRepository protocol contract.
 */
@protocol PDSBlockRepository;
@protocol PDSRepoRepository;
@protocol PDSRecordRepository;

/**
 * @abstract Service for ATProto repository operations.
 *
 * @discussion PDSRepositoryService manages user repositories, providing access
 * to Merkle Search Trees (MST) and commit processing. Repositories are stored
 * per-DID with content-addressed blocks.
 *
 * Responsibilities:
 * - Load and persist MST structures
 * - Update repository records by key
 * - Generate and apply repository commits
 * - Retrieve repository contents and roots
 * - Coordinate repo synchronization
 *
 * Thread-safety: Methods are thread-safe through database pool serialization.
 */
@interface PDSRepositoryService : NSObject

/**
 * @abstract Block repository.
 */
@property (nonatomic, strong) id<PDSBlockRepository> blockRepository;

/**
 * @abstract Repo metadata repository.
 */
@property (nonatomic, strong) id<PDSRepoRepository> repoRepository;

/**
 * @abstract Database pool.
 * @discussion The owner (PDSController) must outlive this service.
 */
@property (nonatomic, strong) PDSDatabasePool *databasePool;

/**
 * @abstract Initializes the service with a database pool.
 * @param databasePool Pool managing per-user database connections.
 * @return Initialized repository service.
 */
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Repo Operations

/**
 * @abstract Loads the Merkle Search Tree for a repository DID.
 * @discussion Loads the current MST structure from the repository database.
 * The MST provides content-addressed record storage with cryptographic integrity.
 * @param did Decentralized identifier of repository owner.
 * @param error Error pointer for loading failures.
 * @return MST instance or nil if repository doesn't exist or loading fails.
 */
- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Loads the Merkle Search Tree for a repository DID, reusing an already-open actor store.
 * @discussion Same as loadMSTForDid:error: but reuses the caller's store handle
 * to avoid a redundant pool lookup and SQLite open. Callers that already have an
 * open PDSActorStore for the same DID (e.g. for commit block or record block
 * operations) should prefer this method to eliminate duplicate store opens.
 * @param did Decentralized identifier of repository owner.
 * @param store Already-open actor store for the same DID.
 * @param error Error pointer for loading failures.
 * @return MST instance or nil if loading fails.
 */
- (nullable MST *)loadMSTForDid:(NSString *)did store:(PDSActorStore *)store error:(NSError **)error;

/**
 * @abstract Updates or deletes a key in a repository MST.
 * @discussion Updates or deletes a key-value entry in the MST. Passing nil
 * for cid deletes the key. Changes are persisted to the repository database.
 * @param did Decentralized identifier of repository owner.
 * @param key Record key (e.g., "app.bsky.feed.post/123").
 * @param cid Content identifier of record value, or nil to delete.
 * @param error Error pointer for update failures.
 * @return YES if update succeeded, NO on failure.
 */
- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable ATProtoCID *)cid error:(NSError **)error;

/**
 * @abstract Returns the repository root data for a DID.
 * @discussion Returns the ATProtoCID of the repository's current commit, which
 * references the MST root. Used for sync and verification.
 * @param did Decentralized identifier of repository owner.
 * @param error Error pointer for retrieval failures.
 * @return CAR-encoded commit root data, or nil if not found.
 */
- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;

/**
 * @abstract Exports repository contents as CAR data.
 * @discussion Returns CAR-encoded repository data containing all blocks.
 * If sinceRev is provided, returns only changes since that revision.
 * @param did Decentralized identifier of repository owner.
 * @param sinceRev Previous commit revision for incremental sync, or nil for full export.
 * @param error Error pointer for export failures.
 * @return CAR-encoded repository blocks, or nil on failure.
 */
- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSString *)sinceRev error:(NSError **)error;

/**
 * @abstract Writes repository contents directly to a CAR file.
 * @discussion Builds repository export and writes it to disk without building a
 * single concatenated response blob in memory.
 * @param did Decentralized identifier of repository owner.
 * @param sinceRev Previous commit revision for incremental sync, or nil for full export.
 * @param path Output file path.
 * @param error Error pointer for export failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)writeRepoContents:(NSString *)did since:(nullable NSString *)sinceRev toPath:(NSString *)path error:(NSError **)error;

/**
 * @abstract Creates a chunk producer for CAR repository contents.
 * @discussion The returned block emits the next CAR payload chunk on each call.
 * It returns nil with no error at end-of-stream.
 * @param did Decentralized identifier of repository owner.
 * @param sinceRev Previous commit revision for incremental sync, or nil for full export.
 * @param error Error pointer for export preparation failures.
 * @return Chunk producer block or nil on failure.
 */
- (nullable PDSRepoChunkProducer)repoContentsChunkProducer:(NSString *)did
                                                    since:(nullable NSString *)sinceRev
                                                    error:(NSError **)error;

/**
 * @abstract Exports repository contents as STAR-L0 data.
 * @discussion Returns STAR-L0 encoded repository data. STAR-L0 preserves the
 * MST structure and enables streaming verification with reduced archive size
 * (~80% fewer CIDs than CAR).
 * @param did Decentralized identifier of repository owner.
 * @param sinceRev Previous commit revision for incremental sync, or nil for full export.
 * @param error Error pointer for export failures.
 * @return STAR-L0 encoded repository data, or nil on failure.
 */
- (nullable NSData *)getRepoContentsSTARL0:(NSString *)did
                                     since:(nullable NSString *)sinceRev
                                     error:(NSError **)error;

/**
 * @abstract Exports repository contents as STAR-lite data.
 * @discussion Returns STAR-lite encoded repository data. STAR-lite is a flat
 * key-record encoding with no MST structure, providing the best compression
 * ratio.
 * @param did Decentralized identifier of repository owner.
 * @param sinceRev Previous commit revision for incremental sync, or nil for full export.
 * @param error Error pointer for export failures.
 * @return STAR-lite encoded repository data, or nil on failure.
 */
- (nullable NSData *)getRepoContentsSTARLite:(NSString *)did
                                       since:(nullable NSString *)sinceRev
                                       error:(NSError **)error;

/**
 * @abstract Creates a chunk producer for STAR-L0 repository contents.
 * @discussion The returned block emits the next STAR-L0 payload chunk on each call.
 * It returns nil with no error at end-of-stream.
 * @param did Decentralized identifier of repository owner.
 * @param sinceRev Previous commit revision for incremental sync, or nil for full export.
 * @param error Error pointer for export preparation failures.
 * @return Chunk producer block or nil on failure.
 */
- (nullable PDSRepoChunkProducer)repoContentsSTARL0ChunkProducer:(NSString *)did
                                                            since:(nullable NSString *)sinceRev
                                                            error:(NSError **)error;

/**
 * @abstract Creates a chunk producer for STAR-lite repository contents.
 * @discussion The returned block emits the next STAR-lite payload chunk on each call.
 * It returns nil with no error at end-of-stream.
 * @param did Decentralized identifier of repository owner.
 * @param sinceRev Previous commit revision for incremental sync, or nil for full export.
 * @param error Error pointer for export preparation failures.
 * @return Chunk producer block or nil on failure.
 */
- (nullable PDSRepoChunkProducer)repoContentsSTARLiteChunkProducer:(NSString *)did
                                                              since:(nullable NSString *)sinceRev
                                                              error:(NSError **)error;

/**
 * @abstract Creates a chunk producer for collection-filtered CAR repository contents.
 * @discussion The returned CAR contains only records matching the specified collections.
 * Includes the commit block, MST proof nodes for matching keys, and the record blocks.
 * A consumer can verify the commit signature and reconstruct just the requested subtree.
 * @param did Decentralized identifier of repository owner.
 * @param sinceRev Previous commit revision for incremental sync, or nil for full export.
 * @param collections Array of collection NSIDs to include (e.g., ["app.bsky.feed.post"]).
 * @param error Error pointer for export preparation failures.
 * @return Chunk producer block or nil on failure.
 */
- (nullable PDSRepoChunkProducer)filteredRepoContentsChunkProducer:(NSString *)did
                                                              since:(nullable NSString *)sinceRev
                                                        collections:(NSArray<NSString *> *)collections
                                                              error:(NSError **)error;

/**
 * @abstract Applies a repository commit for the supplied DID.
 * @discussion Processes a CAR-encoded commit, validates signature and structure,
 * and applies changes to the repository database. Used for repo synchronization.
 * @param did Decentralized identifier of repository owner.
 * @param commitData CAR-encoded commit containing MST root and signature.
 * @param error Error pointer for commit failures.
 * @return YES if commit applied successfully, NO on validation or application failure.
 */
- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error;

/**
 * @abstract Returns CAR data containing the requested blocks.
 * @param did Repository DID.
 * @param cids Array of ATProtoCID strings to fetch.
 * @param error Error pointer.
 * @return CAR data with requested blocks.
 */
- (nullable NSData *)getBlocksForDid:(NSString *)did cids:(NSArray<NSString *> *)cids error:(NSError **)error;

/**
 * @abstract Gets the latest commit ATProtoCID and revision from stored head commit metadata.
 * @discussion Lightweight lookup: reads the stored signed head commit ATProtoCID and rev
 * from the repo_root table without loading all records, rebuilding the MST, or
 * signing a new commit. Returns nil when no signed head commit exists, which is
 * distinct from getLatestCommitForDid's self-healing fallback.
 *
 * Use this for listRepos/listReposByCollection where per-account throughput matters
 * and the full export preparation in getLatestCommitForDid is too expensive.
 * @param did Repository DID.
 * @param error Error pointer.
 * @return Dictionary with @"cid" (string) and @"rev" (string), or nil if no stored head exists.
 */
- (nullable NSDictionary *)headInfoForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Returns the latest commit ATProtoCID and revision for a DID.
 * @param did Repository DID.
 * @param error Error pointer.
 * @return Dictionary with @"cid" (string) and @"rev" (string).
 */
- (nullable NSDictionary *)getLatestCommitForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Initializes an empty repository for a DID.
 * @discussion Creates an initial empty commit for the repository, allowing
 * the account to be visible via listRepos and sync endpoints.
 * @param did Decentralized identifier of repository owner.
 * @param error Error pointer for initialization failures.
 * @return YES if initialization succeeded, NO on failure.
 */
- (BOOL)initializeRepoForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Reinitializes a repository after clearing corrupted root state.
 * @discussion Deletes the existing repo_root entry and creates a new initial
 * commit. Use this to repair repositories with missing blocks or other
 * corruption.
 * @param did Decentralized identifier of repository owner.
 * @param error Error pointer for initialization failures.
 * @return YES if initialization succeeded, NO on failure.
 */
- (BOOL)forceReinitializeRepoForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
