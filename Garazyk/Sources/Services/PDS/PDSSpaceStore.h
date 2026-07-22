// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDSSpaceStoreErrorDomain;

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

typedef NS_ENUM(NSInteger, PDSSpaceWriteAction) {
  PDSSpaceWriteActionCreate = 1,
  PDSSpaceWriteActionUpdate,
  PDSSpaceWriteActionDelete,
};

/** A prepared record operation. Values are canonical DAG-CBOR bytes. */
@interface PDSSpaceWrite : NSObject

@property(nonatomic, readonly) PDSSpaceWriteAction action;
@property(nonatomic, readonly, copy) NSString *collection;
@property(nonatomic, readonly, copy) NSString *rkey;
@property(nonatomic, readonly, copy, nullable) NSString *cid;
@property(nonatomic, readonly, copy, nullable) NSData *value;

+ (instancetype)writeWithAction:(PDSSpaceWriteAction)action
                      collection:(NSString *)collection
                            rkey:(NSString *)rkey
                             cid:(nullable NSString *)cid
                           value:(nullable NSData *)value;

@end

/**
 * Isolated persistence for proposal-0016 data.
 *
 * This database is deliberately separate from PDSDatabase and ActorStore: no
 * public repository endpoint, firehose path, or public-repo migration opens
 * this file.  Each (space, author DID) pair owns an independent repo state.
 */
@interface PDSSpaceStore : NSObject

- (nullable instancetype)initWithDatabasePath:(NSString *)databasePath
                                        error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

/**
 * Creates a transactionally consistent SQLite backup at @c destinationPath.
 * The SQLite online-backup API includes committed WAL content without relying
 * on filesystem copying of an active database and its sidecars.
 */
- (BOOL)createOnlineBackupAtPath:(NSString *)destinationPath error:(NSError **)error;
- (void)close;

/** Creates an authority-owned space. Writer repositories materialize on first write. */
- (BOOL)createSpace:(NSString *)space
              owner:(BOOL)owner
              policy:(NSString *)policy
          managingApp:(nullable NSString *)managingApp
       appAccessType:(NSString *)appAccessType
           appAllowed:(NSArray<NSString *> *)appAllowed
                error:(NSError **)error;

/** Lazily materializes a writer's repo; it never implies membership. */
- (BOOL)ensureRepositoryForSpace:(NSString *)space
                          author:(NSString *)author
                           error:(NSError **)error;

- (nullable NSDictionary<NSString *, id> *)spaceInfoForURI:(NSString *)space
                                                       error:(NSError **)error;
- (NSArray<NSDictionary<NSString *, id> *> *)listSpacesWithLimit:(NSUInteger)limit
                                                            cursor:(nullable NSString *)cursor
                                                          authority:(nullable NSString *)authority
                                                               type:(nullable NSString *)type
                                                              error:(NSError **)error;
- (BOOL)updateSpace:(NSString *)space
              policy:(nullable NSString *)policy
          managingApp:(nullable NSString *)managingApp
       appAccessType:(nullable NSString *)appAccessType
           appAllowed:(nullable NSArray<NSString *> *)appAllowed
                error:(NSError **)error;
- (BOOL)markSpaceDeleted:(NSString *)space error:(NSError **)error;

/** Records an authenticated authority deletion notification for a replica. */
- (BOOL)markReplicatedSpaceDeleted:(NSString *)space error:(NSError **)error;

- (BOOL)addMember:(NSString *)did toSpace:(NSString *)space error:(NSError **)error;
- (BOOL)removeMember:(NSString *)did fromSpace:(NSString *)space error:(NSError **)error;
- (BOOL)isMember:(NSString *)did ofSpace:(NSString *)space error:(NSError **)error;
- (NSArray<NSString *> *)listMembersForSpace:(NSString *)space
                                         limit:(NSUInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

/**
 * Applies a complete repo commit atomically and advances only this writer's
 * 2048-byte LtHash state. Returns @{ rev, state, hash } on success.
 */
- (nullable NSDictionary<NSString *, id> *)applyWrites:(NSArray<PDSSpaceWrite *> *)writes
                                               toSpace:(NSString *)space
                                                author:(NSString *)author
                                                   rev:(nullable NSString *)rev
                                                 error:(NSError **)error;

- (nullable NSDictionary<NSString *, id> *)repositoryStateForSpace:(NSString *)space
                                                              author:(NSString *)author
                                                               error:(NSError **)error;

/** Local repo heads retried to their authorities after notification loss. */
- (NSArray<NSDictionary<NSString *, id> *> *)repositoriesForReconciliation:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)recordForSpace:(NSString *)space
                                                     author:(NSString *)author
                                                 collection:(NSString *)collection
                                                       rkey:(NSString *)rkey
                                                      error:(NSError **)error;
- (NSArray<NSDictionary<NSString *, id> *> *)recordsForSpace:(NSString *)space
                                                       author:(NSString *)author
                                                   collection:(nullable NSString *)collection
                                                        limit:(NSUInteger)limit
                                                       cursor:(nullable NSString *)cursor
                                                      reverse:(BOOL)reverse
                                                        error:(NSError **)error;
- (NSArray<NSDictionary<NSString *, id> *> *)repoOperationsForSpace:(NSString *)space
                                                               author:(NSString *)author
                                                                since:(nullable NSString *)since
                                                                limit:(NSUInteger)limit
                                                                 error:(NSError **)error;

/**
 * Stores a raw blob only in the permissioned-space database.  The returned
 * dictionary contains @c cid, @c mimeType, and @c size.  This intentionally
 * does not use PDSBlobService or any public-repository blob table.
 */
- (nullable NSDictionary<NSString *, id> *)storeBlobData:(NSData *)data
                                                 mimeType:(NSString *)mimeType
                                                  toSpace:(NSString *)space
                                                   author:(NSString *)author
                                                    error:(NSError **)error;

/** Returns the bytes and original MIME type for one author-scoped space blob. */
- (nullable NSDictionary<NSString *, id> *)blobForCID:(NSString *)cid
                                                space:(NSString *)space
                                               author:(NSString *)author
                                                error:(NSError **)error;

/** Authority-side writer set used as the remote sync boundary. */
- (BOOL)recordWriter:(NSString *)writer
              forSpace:(NSString *)space
                   rev:(NSString *)rev
                  hash:(NSData *)hash
                 error:(NSError **)error;
- (NSArray<NSDictionary<NSString *, id> *> *)writersForSpace:(NSString *)space
                                                        limit:(NSUInteger)limit
                                                       cursor:(nullable NSString *)cursor
                                                        error:(NSError **)error;

- (BOOL)recordCredentialRecipientForSpace:(NSString *)space
                                serviceDID:(NSString *)serviceDID
                           serviceEndpoint:(NSString *)serviceEndpoint
                                 expiresAt:(NSDate *)expiresAt
                                     error:(NSError **)error;
- (NSArray<NSDictionary<NSString *, id> *> *)credentialRecipientsForSpace:(NSString *)space
                                                                       error:(NSError **)error;

/** Atomically records a delegation jti. NO means it has already been consumed. */
- (BOOL)consumeDelegationID:(NSString *)jti
                  expiresAt:(NSDate *)expiresAt
                        now:(NSDate *)now
                      error:(NSError **)error;

/**
 * Atomically records a managing-app attestation jti, in its own replay table
 * (a remote app's key is an independent trust domain from delegation tokens
 * this PDS itself mints). NO means it has already been consumed.
 */
- (BOOL)consumeAppAttestationID:(NSString *)jti
                       expiresAt:(NSDate *)expiresAt
                             now:(NSDate *)now
                           error:(NSError **)error;

#pragma mark - Oplog pruning

/** Deletes oplog entries for a single repo, keeping at most @c keepCount
 *  distinct revisions.  Pass 0 to erase the entire oplog. */
- (BOOL)pruneOplogForSpace:(NSString *)space
                    author:(NSString *)author
          keepingRevisions:(NSUInteger)keepCount
                     error:(NSError **)error;

/** Prunes every repo's oplog in a single transaction. */
- (BOOL)pruneAllOplogsKeepingRevisions:(NSUInteger)keepCount
                                  error:(NSError **)error;

/** Prunes every repo's oplog and reports the number of removed entries. */
- (BOOL)pruneAllOplogsKeepingRevisions:(NSUInteger)keepCount
                         prunedEntries:(NSUInteger * _Nullable)prunedEntries
                                  error:(NSError **)error;

/** Returns @c { @"space", @"author" } for each distinct (space, author_did)
 *  pair that has at least one oplog entry. */
- (NSArray<NSDictionary<NSString *, id> *> *)repositoriesWithOplogs:(NSError **)error;

#pragma mark - CAR import (full-state recovery)

/**
 * Imports a full-state CAR produced by @c com.atproto.space.getRepo.
 *
 * The CAR must contain two roots: a signed commit and a DRISL index.
 * Each record block referenced by the index must be present.  The commit
 * signature and MAC are verified against @c publicKey before any data is
 * written.
 *
 * On success the existing repo state for this (space, author) pair is
 * atomically replaced and the oplog is truncated.
 */
- (BOOL)importRepoFromCAR:(NSData *)carData
                    space:(NSString *)space
                   author:(NSString *)author
          commitPublicKey:(NSData *)publicKey
                    error:(NSError **)error;

#pragma mark - Local record index (lightweight recovery diff)

/**
 * Returns a @c { "{collection}/{rkey}" → cid } dictionary for every record
 * in the repo.  Used by the reconciler to diff against a remote
 * @c listRecords(excludeValues=true) listing.
 */
- (nullable NSDictionary<NSString *, NSString *> *)recordIndexForSpace:(NSString *)space
                                                                author:(NSString *)author
                                                                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
