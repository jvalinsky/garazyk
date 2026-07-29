// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRecordService_Internal.h

 @abstract Internal class extension and private method signatures for PDSRecordService.

 @discussion Provides the private properties and method declarations shared across
 all PDSRecordService category files. Not to be imported by external callers.
 */

#import "PDSRecordService.h"
#import "Compat/PDSTypes.h"
#import "Core/GZPerDidWriteDispatcher.h"

@class PDSActorStore;
@class PDSDatabaseBlock;
@class RepoCommit;
@class PDSDatabaseRecord;
@class PDSSQLiteRecordRepository;

/** @abstract Transactional actor-store operations used while committing a serialized write. */
@protocol PDSActorStoreTransactor;
/** @abstract Read-only actor-store operations used by record-service helpers. */
@protocol PDSActorStoreReader;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Declares PDSRecordService state and helpers shared by implementation categories.
 * @discussion Repository mutations are serialized per DID before the methods that change records,
 * MST state, and commit metadata are called.
 */
@interface PDSRecordService ()

/** @abstract Per-DID statistics cache, protected by statsCacheQueue. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *statsCacheByDid;
/** @abstract Serial queue that protects statsCacheByDid. */
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t statsCacheQueue;
/** @abstract Per-DID serializer that prevents concurrent repository mutations for one actor. */
@property (nonatomic, strong) GZPerDidWriteDispatcher *writeDispatcher;

#pragma mark - Shared Private Methods

/** @abstract Runs block in the serial mutation lane for did and waits for it to complete. */
- (void)_dispatchWriteForDid:(NSString *)did block:(void (^)(void))block;

/** @abstract Authorizes actorDid to mutate targetDid, returning an error when the identities differ. */
- (BOOL)checkAuthorizationForDid:(NSString *)targetDid actorDid:(NSString *)actorDid error:(NSError **)error;

/**
 * @abstract Applies already-authorized writes while the caller holds the DID's mutation lane.
 * @discussion Validates the optional swap commit before building operations, then persists record,
 * block, MST, and commit-root changes through the actor-store transaction.
 * @return Apply-writes result metadata, or nil when validation or persistence fails.
 */
- (nullable NSDictionary *)_applyWritesSerialized:(NSArray<NSDictionary *> *)writes
                                         forDid:(NSString *)did
                                       actorDid:(NSString *)actorDid
                                 validationMode:(PDSValidationMode)mode
                                     swapCommit:(nullable NSString *)swapCommit
                                          error:(NSError **)error;

/** @abstract Rebuilds a repository MST from the actor's stored records. */
- (nullable MST *)loadRepoMSTForDid:(NSString *)did
                               store:(PDSActorStore *)store
                               error:(NSError **)error;

/** @abstract Computes the current MST root CID for a DID from its actor store. */
- (nullable CID *)computeRepoRootCIDForDid:(NSString *)did
                                      store:(PDSActorStore *)store
                                      error:(NSError **)error;

/**
 * @abstract Updates the MST, signed commit, persisted blocks, and repository root after mutations.
 * @discussion Must run in the DID's serialized write lane. It reloads or rebuilds cached MST state,
 * applies the supplied CID mutations, signs a new commit, and writes blocks and root atomically.
 * @return Metadata for the new repository root, or nil when loading, signing, or the transaction fails.
 */
- (nullable NSDictionary<NSString *, NSString *> *)refreshRepoRootMetadataForDid:(NSString *)did
                                                                    preferredRev:(nullable NSString *)preferredRev
                                                              mutationCIDsByKey:(nullable NSDictionary<NSString *, id> *)mutationCIDsByKey
                                                             mutationBlocksByCID:(nullable NSDictionary<NSString *, NSData *> *)mutationBlocksByCID
                                                                     changedKeys:(nullable NSArray<NSString *> *)changedKeys
                                                                           error:(NSError **)error;

/**
 * @abstract Materializes the updated MST root and proof-path nodes for changed record keys.
 * @discussion Returned blocks are deduplicated by CID and carry rev for transactional persistence.
 */
- (nullable NSArray<PDSDatabaseBlock *> *)changedMSTBlocksForMST:(MST *)mst
                                                     changedKeys:(NSArray<NSString *> *)changedKeys
                                                            rev:(NSString *)rev
                                                          error:(NSError **)error;

/** @abstract Enforces the target post's threadgate policy before accepting a reply record. */
- (BOOL)validateThreadgateForReplyRecord:(NSDictionary *)record
                              collection:(NSString *)collection
                               authorDID:(NSString *)authorDID
                                   error:(NSError **)error;

/** @abstract Loads the threadgate record controlling replies to postURI, if one exists. */
- (nullable NSDictionary *)threadgateRecordForPostURI:(NSString *)postURI
                                            authorDID:(NSString *)authorDID
                                                error:(NSError **)error;

/** @abstract Returns whether authorDID follows targetDID for threadgate follower checks. */
- (BOOL)authorDID:(NSString *)authorDID hasFollowForDID:(NSString *)targetDID error:(NSError **)error;

/** @abstract Produces the canonical CID string for record block data, or an error on failure. */
- (NSString *)generateCIDForData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
