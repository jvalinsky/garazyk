// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Exports actor repositories as CAR, STARL0, and STARLite streams.
 * @discussion Export helpers read actor-scoped repository state without authorizing a caller. The
 * caller is responsible for access control and for consuming a chunk producer serially.
 */
@interface PDSRepositoryService (Export)

/** @abstract Serializes did's repository into a complete or incremental CAR payload. */
- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSString *)sinceRev error:(NSError **)error;
/**
 * @abstract Streams a complete or incremental CAR export to path.
 * @discussion Creates or truncates path before writing; failures can therefore leave a partial file.
 */
- (BOOL)writeRepoContents:(NSString *)did since:(nullable NSString *)sinceRev toPath:(NSString *)path error:(NSError **)error;
/**
 * @abstract Returns a single-consumer CAR chunk producer filtered to one or more collections.
 * @discussion The current filtered export produces proof-path MST blocks and matching records;
 * sinceRev is accepted for interface compatibility but is not applied.
 */
- (nullable PDSRepoChunkProducer)filteredRepoContentsChunkProducer:(NSString *)did
                                                              since:(nullable NSString *)sinceRev
                                                        collections:(NSArray<NSString *> *)collections
                                                              error:(NSError **)error;
/** @abstract Returns a single-consumer CAR chunk producer for complete or incremental export. */
- (nullable PDSRepoChunkProducer)repoContentsChunkProducer:(NSString *)did
                                                    since:(nullable NSString *)sinceRev
                                                    error:(NSError **)error;
/** @abstract Serializes the repository into a STARL0 archive payload. */
- (nullable NSData *)getRepoContentsSTARL0:(NSString *)did
                                     since:(nullable NSString *)sinceRev
                                     error:(NSError **)error;
/** @abstract Serializes the repository into a STARLite archive payload. */
- (nullable NSData *)getRepoContentsSTARLite:(NSString *)did
                                       since:(nullable NSString *)sinceRev
                                       error:(NSError **)error;
/** @abstract Returns a single-consumer STARL0 archive chunk producer. */
- (nullable PDSRepoChunkProducer)repoContentsSTARL0ChunkProducer:(NSString *)did
                                                             since:(nullable NSString *)sinceRev
                                                             error:(NSError **)error;
/** @abstract Returns a single-consumer STARLite archive chunk producer. */
- (nullable PDSRepoChunkProducer)repoContentsSTARLiteChunkProducer:(NSString *)did
                                                               since:(nullable NSString *)sinceRev
                                                               error:(NSError **)error;
/** @abstract Decodes the repository head commit into the STAR archive representation. */
- (STARCommit *)starCommitFromExport:(NSString *)did
                           commitCID:(CID *)commitCID
                         commitBlock:(NSData *)commitBlock;
/**
 * @abstract Loads and derives all state required for a CAR export.
 * @discussion On success, output pointers describe one repository head and whether a full MST or
 * changed proof paths are required. The method reads state only and does not authorize access.
 */
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
/** @abstract Loads the stored head commit, data root, revision, and signature state for did. */
- (BOOL)loadStoredHeadCommitForDid:(NSString *)did
                              store:(PDSActorStore *)store
                          commitCID:(CID * _Nullable * _Nonnull)commitCIDOut
                        commitBlock:(NSData * _Nullable * _Nonnull)commitBlockOut
                            dataCID:(CID * _Nullable * _Nonnull)dataCIDOut
                                rev:(NSString * _Nullable * _Nonnull)revOut
                           isSigned:(BOOL *)isSignedOut;
/** @abstract Builds a CAR writer rooted at did's stored head commit. */
- (nullable CARWriter *)buildRepoWriterForDid:(NSString *)did
                                         since:(nullable NSString *)sinceRev
                                         error:(NSError **)error;
/** @abstract Produces full-MST or proof-path blocks and optional record blocks for an export. */
- (nullable NSArray<CARBlock *> *)mstBlocksForExport:(MST *)mst
                                       includeAllMST:(BOOL)includeAllMST
                                           proofKeys:(NSArray<NSString *> *)proofKeys
                                      recordProvider:(nullable MSTBlockProvider)recordProvider
                                                error:(NSError **)error;
/** @abstract Returns a provider that reads materialized blocks before falling back to stored records. */
- (MSTBlockProvider)recordProviderForDid:(NSString *)did
                       materializedBlocks:(nullable NSDictionary<NSString *, NSData *> *)materializedBlocks
                             recordByCID:(nullable NSDictionary<NSString *, PDSDatabaseRecord *> *)recordByCID;

@end

NS_ASSUME_NONNULL_END
