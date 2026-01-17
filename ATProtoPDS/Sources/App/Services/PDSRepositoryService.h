/*!
 @file PDSRepositoryService.h

 @abstract Repository management service layer.

 @discussion Provides high-level repository operations including MST loading,
 updates, commit processing, and repo synchronization. Coordinates between
 database pool and MST persistence layer.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@class MST;
@class CID;

/*!
 @class PDSRepositoryService

 @abstract Service for ATProto repository operations.

 @discussion PDSRepositoryService manages user repositories, providing access
 to Merkle Search Trees (MST) and commit processing. Repositories are stored
 per-DID with content-addressed blocks.

 Responsibilities:
 - Load and persist MST structures
 - Update repository records by key
 - Generate and apply repository commits
 - Retrieve repository contents and roots
 - Coordinate repo synchronization

 Thread-safety: Methods are thread-safe through database pool serialization.
 */
@interface PDSRepositoryService : NSObject

/*! Database pool - owner (PDSController) must outlive this service. */
@property (nonatomic, strong) PDSDatabasePool *databasePool;

/*!
 @method initWithDatabasePool:

 @abstract Initialize with database pool.

 @param databasePool Pool managing per-user database connections.
 @return Initialized repository service.
 */
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Repo Operations

/*!
 @method loadMSTForDid:error:

 @abstract Load Merkle Search Tree for a DID's repository.

 @discussion Loads the current MST structure from the repository database.
 The MST provides content-addressed record storage with cryptographic integrity.

 @param did Decentralized identifier of repository owner.
 @param error Error pointer for loading failures.
 @return MST instance or nil if repository doesn't exist or loading fails.
 */
- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;

/*!
 @method updateMSTForDid:key:cid:error:

 @abstract Update a single key in the repository MST.

 @discussion Updates or deletes a key-value entry in the MST. Passing nil
 for cid deletes the key. Changes are persisted to the repository database.

 @param did Decentralized identifier of repository owner.
 @param key Record key (e.g., "app.bsky.feed.post/123").
 @param cid Content identifier of record value, or nil to delete.
 @param error Error pointer for update failures.
 @return YES if update succeeded, NO on failure.
 */
- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable CID *)cid error:(NSError **)error;

/*!
 @method getRepoRoot:error:

 @abstract Get the root CID of a repository.

 @discussion Returns the CID of the repository's current commit, which
 references the MST root. Used for sync and verification.

 @param did Decentralized identifier of repository owner.
 @param error Error pointer for retrieval failures.
 @return CAR-encoded commit root data, or nil if not found.
 */
- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;

/*!
 @method getRepoContents:since:error:

 @abstract Get repository contents, optionally since a commit.

 @discussion Returns CAR-encoded repository data containing all blocks.
 If sinceCid is provided, returns only changes since that commit.

 @param did Decentralized identifier of repository owner.
 @param sinceCid Previous commit CID for incremental sync, or nil for full export.
 @param error Error pointer for export failures.
 @return CAR-encoded repository blocks, or nil on failure.
 */
- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error;

/*!
 @method updateRepo:commit:error:

 @abstract Apply a commit to update the repository.

 @discussion Processes a CAR-encoded commit, validates signature and structure,
 and applies changes to the repository database. Used for repo synchronization.

 @param did Decentralized identifier of repository owner.
 @param commitData CAR-encoded commit containing MST root and signature.
 @param error Error pointer for commit failures.
 @return YES if commit applied successfully, NO on validation or application failure.
 */
- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
