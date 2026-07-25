// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for PDSSpaceStore errors.
 */
extern NSString *const PDSSpaceStoreErrorDomain;

/**
 * @abstract Defines PDSSpaceStoreError values exposed by this API.
 */
typedef NS_ENUM(NSInteger, PDSSpaceStoreError) {
  PDSSpaceStoreErrorDatabase = 1,
  PDSSpaceStoreErrorInvalidWrite,
  PDSSpaceStoreErrorRecordAlreadyExists,
  PDSSpaceStoreErrorRecordNotFound,
  PDSSpaceStoreErrorSpaceAlreadyExists,
  PDSSpaceStoreErrorSpaceNotFound,
  PDSSpaceStoreErrorInvalidCAR,
  PDSSpaceStoreErrorCommitMismatch,
  PDSSpaceStoreErrorCommitSignature,
  PDSSpaceStoreErrorMissingBlock,
};

/**
 * @abstract Defines PDSSpaceWriteAction values exposed by this API.
 */
typedef NS_ENUM(NSInteger, PDSSpaceWriteAction) {
  PDSSpaceWriteActionCreate = 1,
  PDSSpaceWriteActionUpdate,
  PDSSpaceWriteActionDelete,
};

/**
 * @abstract A prepared record operation.
 * @discussion Values are canonical DAG-CBOR bytes.
 */
@interface PDSSpaceWrite : NSObject

@property(nonatomic, readonly) PDSSpaceWriteAction action;
@property(nonatomic, readonly, copy) NSString *collection;
@property(nonatomic, readonly, copy) NSString *rkey;
@property(nonatomic, readonly, copy, nullable) NSString *cid;
@property(nonatomic, readonly, copy, nullable) NSData *value;

/**
 * @abstract Creates a new space write operation.
 * @param action The write action (create, update, delete).
 * @param collection The record collection.
 * @param rkey The record key.
 * @param cid The content identifier.
 * @param value The raw record value.
 * @return A new write operation instance.
 */
+ (instancetype)writeWithAction:(PDSSpaceWriteAction)action
                      collection:(NSString *)collection
                            rkey:(NSString *)rkey
                             cid:(nullable NSString *)cid
                           value:(nullable NSData *)value;

@end

/**
 * @abstract Isolated persistence for proposal-0016 data.
 * @discussion This database is deliberately separate from PDSDatabase and ActorStore.
 * No public repository endpoint, firehose path, or public-repo migration opens
 * this file. Each (space, author DID) pair owns an independent repo state.
 */
@interface PDSSpaceStore : NSObject

/**
 * @abstract Initializes a space store at the given path.
 * @param databasePath The path to the SQLite database.
 * @param error Error pointer for initialization failures.
 * @return An initialized space store, or nil if initialization fails.
 */
- (nullable instancetype)initWithDatabasePath:(NSString *)databasePath
                                        error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Creates a transactionally consistent SQLite backup.
 * @discussion Uses the SQLite online-backup API to include committed WAL content.
 * @param destinationPath The path to the destination file.
 * @param error Error pointer for backup failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)createOnlineBackupAtPath:(NSString *)destinationPath error:(NSError **)error;

/**
 * @abstract Closes the database connection.
 */
- (void)close;

/**
 * @abstract Creates an authority-owned space.
 * @discussion Writer repositories materialize on their first write.
 * @param space The space identifier.
 * @param owner Whether the caller is the space owner.
 * @param policy The space policy.
 * @param managingApp The managing application identifier.
 * @param appAccessType The application access type.
 * @param appAllowed Array of allowed applications.
 * @param error Error pointer for creation failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)createSpace:(NSString *)space
              owner:(BOOL)owner
              policy:(NSString *)policy
          managingApp:(nullable NSString *)managingApp
       appAccessType:(NSString *)appAccessType
           appAllowed:(NSArray<NSString *> *)appAllowed
                error:(NSError **)error;

/**
 * @abstract Lazily materializes a writer's repository.
 * @discussion This does not imply or grant membership in the space.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param error Error pointer for materialization failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)ensureRepositoryForSpace:(NSString *)space
                          author:(NSString *)author
                           error:(NSError **)error;

/**
 * @abstract Retrieves information for a space.
 * @param space The space identifier.
 * @param error Error pointer for retrieval failures.
 * @return Dictionary of space information, or nil if not found.
 */
- (nullable NSDictionary<NSString *, id> *)spaceInfoForURI:(NSString *)space
                                                       error:(NSError **)error;

/**
 * @abstract Lists spaces.
 * @param limit Maximum number of spaces to return.
 * @param cursor Pagination cursor.
 * @param authority Optional authority identifier filter.
 * @param type Optional space type filter.
 * @param error Error pointer for listing failures.
 * @return Array of space dictionaries.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)listSpacesWithLimit:(NSUInteger)limit
                                                            cursor:(nullable NSString *)cursor
                                                          authority:(nullable NSString *)authority
                                                               type:(nullable NSString *)type
                                                              error:(NSError **)error;

/**
 * @abstract Updates space properties.
 * @param space The space identifier.
 * @param policy The new space policy.
 * @param managingApp The new managing application.
 * @param appAccessType The new app access type.
 * @param appAllowed The new allowed apps array.
 * @param error Error pointer for update failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)updateSpace:(NSString *)space
              policy:(nullable NSString *)policy
          managingApp:(nullable NSString *)managingApp
       appAccessType:(nullable NSString *)appAccessType
           appAllowed:(nullable NSArray<NSString *> *)appAllowed
                error:(NSError **)error;

/**
 * @abstract Marks a space as deleted.
 * @param space The space identifier.
 * @param error Error pointer for deletion failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)markSpaceDeleted:(NSString *)space error:(NSError **)error;

/**
 * @abstract Records an authenticated authority deletion notification for a replica.
 * @param space The space identifier.
 * @param error Error pointer for deletion failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)markReplicatedSpaceDeleted:(NSString *)space error:(NSError **)error;

/**
 * @abstract Adds a member to a space.
 * @param did The member's decentralized identifier.
 * @param space The space identifier.
 * @param error Error pointer for addition failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)addMember:(NSString *)did toSpace:(NSString *)space error:(NSError **)error;

/**
 * @abstract Removes a member from a space.
 * @param did The member's decentralized identifier.
 * @param space The space identifier.
 * @param error Error pointer for removal failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)removeMember:(NSString *)did fromSpace:(NSString *)space error:(NSError **)error;

/**
 * @abstract Checks if a DID is a member of a space.
 * @param did The decentralized identifier to check.
 * @param space The space identifier.
 * @param error Error pointer for check failures.
 * @return YES if member, NO if not member or on failure.
 */
- (BOOL)isMember:(NSString *)did ofSpace:(NSString *)space error:(NSError **)error;

/**
 * @abstract Lists members for a space.
 * @param space The space identifier.
 * @param limit Maximum number of members to return.
 * @param cursor Pagination cursor.
 * @param error Error pointer for listing failures.
 * @return Array of member DIDs.
 */
- (NSArray<NSString *> *)listMembersForSpace:(NSString *)space
                                         limit:(NSUInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

/**
 * @abstract Applies a complete repository commit atomically.
 * @discussion Advances only the specified writer's 2048-byte LtHash state.
 * @param writes Array of write operations.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param rev The previous commit revision.
 * @param error Error pointer for apply failures.
 * @return Dictionary containing rev, state, and hash on success, or nil on failure.
 */
- (nullable NSDictionary<NSString *, id> *)applyWrites:(NSArray<PDSSpaceWrite *> *)writes
                                               toSpace:(NSString *)space
                                                author:(NSString *)author
                                                   rev:(nullable NSString *)rev
                                                 error:(NSError **)error;

/**
 * @abstract Retrieves the repository state for a space and author.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param error Error pointer for retrieval failures.
 * @return Dictionary containing repository state, or nil if not found.
 */
- (nullable NSDictionary<NSString *, id> *)repositoryStateForSpace:(NSString *)space
                                                              author:(NSString *)author
                                                               error:(NSError **)error;

/**
 * @abstract Retrieves local repository heads that need reconciliation.
 * @param error Error pointer for retrieval failures.
 * @return Array of repository state dictionaries.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)repositoriesForReconciliation:(NSError **)error;

/**
 * @abstract Retrieves a single record.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param collection The record collection.
 * @param rkey The record key.
 * @param error Error pointer for retrieval failures.
 * @return Dictionary containing the record, or nil if not found.
 */
- (nullable NSDictionary<NSString *, id> *)recordForSpace:(NSString *)space
                                                     author:(NSString *)author
                                                 collection:(NSString *)collection
                                                       rkey:(NSString *)rkey
                                                      error:(NSError **)error;

/**
 * @abstract Lists records for a space and author.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param collection The optional collection to filter by.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor.
 * @param reverse Whether to reverse sort order.
 * @param error Error pointer for listing failures.
 * @return Array of record dictionaries.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)recordsForSpace:(NSString *)space
                                                       author:(NSString *)author
                                                   collection:(nullable NSString *)collection
                                                        limit:(NSUInteger)limit
                                                       cursor:(nullable NSString *)cursor
                                                      reverse:(BOOL)reverse
                                                        error:(NSError **)error;

/**
 * @abstract Retrieves repository operations.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param since The starting revision for operations.
 * @param limit Maximum number of operations to return.
 * @param error Error pointer for retrieval failures.
 * @return Array of operation dictionaries.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)repoOperationsForSpace:(NSString *)space
                                                               author:(NSString *)author
                                                                since:(nullable NSString *)since
                                                                limit:(NSUInteger)limit
                                                                 error:(NSError **)error;

/**
 * @abstract Stores raw blob data in the permissioned-space database.
 * @discussion The returned dictionary contains cid, mimeType, and size. This
 * intentionally does not use PDSBlobService or the public-repository blob table.
 * @param data The raw blob data.
 * @param mimeType The MIME type of the blob.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param error Error pointer for storage failures.
 * @return Dictionary containing blob metadata, or nil on failure.
 */
- (nullable NSDictionary<NSString *, id> *)storeBlobData:(NSData *)data
                                                 mimeType:(NSString *)mimeType
                                                  toSpace:(NSString *)space
                                                   author:(NSString *)author
                                                    error:(NSError **)error;

/**
 * @abstract Retrieves blob bytes and MIME type.
 * @param cid The content identifier of the blob.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param error Error pointer for retrieval failures.
 * @return Dictionary containing blob data and MIME type, or nil if not found.
 */
- (nullable NSDictionary<NSString *, id> *)blobForCID:(NSString *)cid
                                                space:(NSString *)space
                                               author:(NSString *)author
                                                error:(NSError **)error;

/**
 * @abstract Records an authority-side writer.
 * @discussion Used as the remote sync boundary.
 * @param writer The writer's decentralized identifier.
 * @param space The space identifier.
 * @param rev The writer's latest revision.
 * @param hash The writer's state hash.
 * @param error Error pointer for recording failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)recordWriter:(NSString *)writer
              forSpace:(NSString *)space
                   rev:(NSString *)rev
                  hash:(NSData *)hash
                 error:(NSError **)error;

/**
 * @abstract Lists writers for a space.
 * @param space The space identifier.
 * @param limit Maximum number of writers to return.
 * @param cursor Pagination cursor.
 * @param error Error pointer for listing failures.
 * @return Array of writer dictionaries.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)writersForSpace:(NSString *)space
                                                        limit:(NSUInteger)limit
                                                       cursor:(nullable NSString *)cursor
                                                        error:(NSError **)error;

/**
 * @abstract Records a credential recipient for a space.
 * @param space The space identifier.
 * @param serviceDID The service DID.
 * @param serviceEndpoint The service endpoint URL.
 * @param expiresAt The expiration date of the credential.
 * @param error Error pointer for recording failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)recordCredentialRecipientForSpace:(NSString *)space
                                serviceDID:(NSString *)serviceDID
                           serviceEndpoint:(NSString *)serviceEndpoint
                                 expiresAt:(NSDate *)expiresAt
                                     error:(NSError **)error;

/**
 * @abstract Lists credential recipients for a space.
 * @param space The space identifier.
 * @param error Error pointer for listing failures.
 * @return Array of credential recipient dictionaries.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)credentialRecipientsForSpace:(NSString *)space
                                                                       error:(NSError **)error;

/**
 * @abstract Atomically records a delegation token ID to prevent reuse.
 * @param jti The token identifier.
 * @param expiresAt The expiration date of the token.
 * @param now The current date.
 * @param error Error pointer for recording failures.
 * @return YES if successfully recorded, NO if the token was already consumed.
 */
- (BOOL)consumeDelegationID:(NSString *)jti
                  expiresAt:(NSDate *)expiresAt
                        now:(NSDate *)now
                      error:(NSError **)error;

/**
 * @abstract Atomically records a managing-app attestation ID to prevent reuse.
 * @discussion Uses its own replay table since remote app keys form an independent trust domain.
 * @param jti The token identifier.
 * @param expiresAt The expiration date of the token.
 * @param now The current date.
 * @param error Error pointer for recording failures.
 * @return YES if successfully recorded, NO if the token was already consumed.
 */
- (BOOL)consumeAppAttestationID:(NSString *)jti
                       expiresAt:(NSDate *)expiresAt
                             now:(NSDate *)now
                           error:(NSError **)error;

#pragma mark - Oplog pruning

/**
 * @abstract Prunes oplog entries for a single repository.
 * @discussion Deletes oplog entries, keeping at most the specified number of revisions.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param keepCount Number of revisions to keep (0 to erase all).
 * @param error Error pointer for pruning failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)pruneOplogForSpace:(NSString *)space
                    author:(NSString *)author
          keepingRevisions:(NSUInteger)keepCount
                     error:(NSError **)error;

/**
 * @abstract Prunes all repository oplogs in a single transaction.
 * @param keepCount Number of revisions to keep per repository.
 * @param error Error pointer for pruning failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)pruneAllOplogsKeepingRevisions:(NSUInteger)keepCount
                                  error:(NSError **)error;

/**
 * @abstract Prunes all repository oplogs and reports the number of removed entries.
 * @param keepCount Number of revisions to keep per repository.
 * @param prunedEntries Pointer to store the number of pruned entries.
 * @param error Error pointer for pruning failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)pruneAllOplogsKeepingRevisions:(NSUInteger)keepCount
                         prunedEntries:(NSUInteger * _Nullable)prunedEntries
                                  error:(NSError **)error;

/**
 * @abstract Retrieves repositories that contain oplog entries.
 * @param error Error pointer for retrieval failures.
 * @return Array of dictionaries containing space and author identifiers.
 */
- (NSArray<NSDictionary<NSString *, id> *> *)repositoriesWithOplogs:(NSError **)error;

#pragma mark - CAR import (full-state recovery)

/**
 * @abstract Imports a full-state CAR produced by com.atproto.space.getRepo.
 * @discussion The CAR must contain a signed commit and a DRISL index. Each record
 * block referenced by the index must be present. The commit signature and MAC are
 * verified against the public key before writing.
 *
 * On success, the existing repository state for this (space, author) pair is
 * atomically replaced and the oplog is truncated.
 * @param carData The CAR-encoded repository data.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param publicKey The public key for verifying the commit.
 * @param error Error pointer for import failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)importRepoFromCAR:(NSData *)carData
                    space:(NSString *)space
                   author:(NSString *)author
          commitPublicKey:(NSData *)publicKey
                    error:(NSError **)error;

#pragma mark - Local record index (lightweight recovery diff)

/**
 * @abstract Retrieves a collection-rkey to CID mapping for all records.
 * @discussion Used by the reconciler to diff against a remote
 * listRecords(excludeValues=true) listing.
 * @param space The space identifier.
 * @param author The writer's decentralized identifier.
 * @param error Error pointer for retrieval failures.
 * @return Dictionary mapping "{collection}/{rkey}" to cid strings, or nil on failure.
 */
- (nullable NSDictionary<NSString *, NSString *> *)recordIndexForSpace:(NSString *)space
                                                                author:(NSString *)author
                                                                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
