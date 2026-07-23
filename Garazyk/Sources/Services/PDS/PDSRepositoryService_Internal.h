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
@class CID;
@class CARWriter;
@class CARBlock;
@class STARCommit;
@class STARL0Writer;
@class STARLiteWriter;
@class CBORValue;
@class PDSBlockRepository;
@class PDSRepoRepository;

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepositoryService ()

- (NSArray<PDSDatabaseRecord *> *)loadAllRecordsForStore:(PDSActorStore *)store
                                                       did:(NSString *)did
                                                     error:(NSError **)error;
- (nullable MST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error;
- (MST *)mstFromRecords:(NSArray<PDSDatabaseRecord *> *)records;
- (nullable NSData *)recordBlockDataForRecord:(PDSDatabaseRecord *)record;
- (CBORValue *)cidLinkValueForCID:(CID *)cid;
- (BOOL)loadStoredHeadCommitForDid:(NSString *)did
                              store:(PDSActorStore *)store
                          commitCID:(CID * _Nullable * _Nonnull)commitCIDOut
                        commitBlock:(NSData * _Nullable * _Nonnull)commitBlockOut
                            dataCID:(CID * _Nullable * _Nonnull)dataCIDOut
                                rev:(NSString * _Nullable * _Nonnull)revOut
                           isSigned:(BOOL *)isSignedOut;
- (nullable CARWriter *)buildRepoWriterForDid:(NSString *)did
                                         since:(nullable NSString *)sinceRev
                                         error:(NSError **)error;
- (BOOL)prepareRepoExportForDid:(NSString *)did
                          since:(nullable NSString *)sinceRev
                          store:(PDSActorStore * _Nullable * _Nonnull)storeOut
                            mst:(MST * _Nullable * _Nonnull)mstOut
                      commitCID:(CID * _Nullable * _Nonnull)commitCIDOut
                    commitBlock:(NSData * _Nullable * _Nonnull)commitBlockOut
                 noChangesSince:(BOOL *)noChangesSinceOut
                 includeFullMST:(BOOL *)includeFullMSTOut
                 changedMSTKeys:(NSArray<NSString *> * _Nullable * _Nonnull)changedMSTKeysOut
                recordCIDStrings:(NSArray<NSString *> * _Nullable * _Nonnull)recordCIDStringsOut
                     recordByCID:(NSDictionary<NSString *, PDSDatabaseRecord *> * _Nullable * _Nonnull)recordByCIDOut
             materializedBlocks:(NSDictionary<NSString *, NSData *> * _Nullable * _Nonnull)materializedBlocksOut
                          error:(NSError **)error;
- (nullable NSArray<CARBlock *> *)mstBlocksForExport:(MST *)mst
                                       includeAllMST:(BOOL)includeAllMST
                                           proofKeys:(NSArray<NSString *> *)proofKeys
                                      recordProvider:(nullable MSTBlockProvider)recordProvider
                                                error:(NSError **)error;
- (MSTBlockProvider)recordProviderForDid:(NSString *)did
                       materializedBlocks:(nullable NSDictionary<NSString *, NSData *> *)materializedBlocks
                             recordByCID:(nullable NSDictionary<NSString *, PDSDatabaseRecord *> *)recordByCID;

@end

NS_ASSUME_NONNULL_END
