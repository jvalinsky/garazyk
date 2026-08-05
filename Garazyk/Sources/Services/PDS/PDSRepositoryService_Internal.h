// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService.h"
#import "Repository/MST.h"
#import "Database/Pool/DatabasePool.h"

@class MST;
@class PDSActorStore;
@class PDSDatabaseBlock;
@class PDSDatabaseRecord;
@class PDSDatabaseRepo;
@class RepoCommit;
@class ATProtoCID;
@class CARWriter;
@class CARBlock;
@class ATProtoSTARCommit;
@class ATProtoSTARL0Writer;
@class ATProtoSTARLiteWriter;
@class ATProtoCBORValue;
@class PDSBlockRepository;
@class PDSRepoRepository;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Declares repository-export helpers shared across PDSRepositoryService categories.
 * @discussion These helpers read actor-scoped repository state and assemble CAR blocks; they do
 * not authorize callers or mutate repository data.
 */
@interface PDSRepositoryService ()

/** @abstract Loads all persisted records for did through its actor store. */
- (NSArray<PDSDatabaseRecord *> *)loadAllRecordsForStore:(PDSActorStore *)store
                                                       did:(NSString *)did
                                                     error:(NSError **)error;
/** @abstract Reconstructs the repository MST from persisted repository blocks when available. */
- (nullable MST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error;
/** @abstract Builds an MST containing the supplied record collection/rkey-to-ATProtoCID entries. */
- (MST *)mstFromRecords:(NSArray<PDSDatabaseRecord *> *)records;
/** @abstract Returns serialized record block data when the record can be encoded for CAR export. */
- (nullable NSData *)recordBlockDataForRecord:(PDSDatabaseRecord *)record;
/** @abstract Wraps a ATProtoCID as the DAG-CBOR link value used by repository commits. */
- (ATProtoCBORValue *)cidLinkValueForCID:(ATProtoCID *)cid;
/** @abstract Loads the persisted head commit and its decoded metadata for the actor store. */
- (BOOL)loadStoredHeadCommitForDid:(NSString *)did
                              store:(PDSActorStore *)store
                          commitCID:(ATProtoCID * _Nullable * _Nonnull)commitCIDOut
                        commitBlock:(NSData * _Nullable * _Nonnull)commitBlockOut
                            dataCID:(ATProtoCID * _Nullable * _Nonnull)dataCIDOut
                                rev:(NSString * _Nullable * _Nonnull)revOut
                           isSigned:(BOOL *)isSignedOut;
/** @abstract Assembles a complete or incremental CAR writer rooted at did's head commit. */
- (nullable CARWriter *)buildRepoWriterForDid:(NSString *)did
                                         since:(nullable NSString *)sinceRev
                                         error:(NSError **)error;
/**
 * @abstract Loads and derives all state required to export a repository CAR.
 * @discussion Determines incremental-export boundaries and materializes metadata without changing
 * the repository. On YES, every nonnull output pointer describes the same head commit.
 */
- (BOOL)prepareRepoExportForDid:(NSString *)did
                          since:(nullable NSString *)sinceRev
                          store:(PDSActorStore * _Nullable * _Nonnull)storeOut
                            mst:(MST * _Nullable * _Nonnull)mstOut
                      commitCID:(ATProtoCID * _Nullable * _Nonnull)commitCIDOut
                    commitBlock:(NSData * _Nullable * _Nonnull)commitBlockOut
                 noChangesSince:(BOOL *)noChangesSinceOut
                 includeFullMST:(BOOL *)includeFullMSTOut
                 changedMSTKeys:(NSArray<NSString *> * _Nullable * _Nonnull)changedMSTKeysOut
                recordCIDStrings:(NSArray<NSString *> * _Nullable * _Nonnull)recordCIDStringsOut
                     recordByCID:(NSDictionary<NSString *, PDSDatabaseRecord *> * _Nullable * _Nonnull)recordByCIDOut
             materializedBlocks:(NSDictionary<NSString *, NSData *> * _Nullable * _Nonnull)materializedBlocksOut
                          error:(NSError **)error;
/** @abstract Emits full-MST blocks or proof-path blocks and optionally record blocks for CAR export. */
- (nullable NSArray<CARBlock *> *)mstBlocksForExport:(MST *)mst
                                       includeAllMST:(BOOL)includeAllMST
                                           proofKeys:(NSArray<NSString *> *)proofKeys
                                      recordProvider:(nullable MSTBlockProvider)recordProvider
                                                error:(NSError **)error;
/** @abstract Creates a block provider that prefers materialized data before actor-store records. */
- (MSTBlockProvider)recordProviderForDid:(NSString *)did
                       materializedBlocks:(nullable NSDictionary<NSString *, NSData *> *)materializedBlocks
                             recordByCID:(nullable NSDictionary<NSString *, PDSDatabaseRecord *> *)recordByCID;

@end

NS_ASSUME_NONNULL_END
