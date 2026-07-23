// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepositoryService (Export)

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSString *)sinceRev error:(NSError **)error;
- (BOOL)writeRepoContents:(NSString *)did since:(nullable NSString *)sinceRev toPath:(NSString *)path error:(NSError **)error;
- (nullable PDSRepoChunkProducer)filteredRepoContentsChunkProducer:(NSString *)did
                                                              since:(nullable NSString *)sinceRev
                                                        collections:(NSArray<NSString *> *)collections
                                                              error:(NSError **)error;
- (nullable PDSRepoChunkProducer)repoContentsChunkProducer:(NSString *)did
                                                    since:(nullable NSString *)sinceRev
                                                    error:(NSError **)error;
- (nullable NSData *)getRepoContentsSTARL0:(NSString *)did
                                     since:(nullable NSString *)sinceRev
                                     error:(NSError **)error;
- (nullable NSData *)getRepoContentsSTARLite:(NSString *)did
                                       since:(nullable NSString *)sinceRev
                                       error:(NSError **)error;
- (nullable PDSRepoChunkProducer)repoContentsSTARL0ChunkProducer:(NSString *)did
                                                             since:(nullable NSString *)sinceRev
                                                             error:(NSError **)error;
- (nullable PDSRepoChunkProducer)repoContentsSTARLiteChunkProducer:(NSString *)did
                                                               since:(nullable NSString *)sinceRev
                                                               error:(NSError **)error;
- (STARCommit *)starCommitFromExport:(NSString *)did
                           commitCID:(CID *)commitCID
                         commitBlock:(NSData *)commitBlock;
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
