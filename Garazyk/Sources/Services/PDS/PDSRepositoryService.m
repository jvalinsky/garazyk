#import "PDSRepositoryService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Repository/MST.h"
#import "Repository/CAR.h"
#import "Repository/RepoCommit.h"
#import "Repository/CBOR.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Auth/CryptoUtils.h"
#import "Debug/PDSLogger.h"
#import "Core/Repositories/PDSBlockRepository.h"
#import "Core/Repositories/PDSRepoRepository.h"
#import "Core/MSTCacheManager.h"

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
                                                error:(NSError **)error;

@end

@implementation PDSRepositoryService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        self.databasePool = databasePool;
    }
    return self;
}

#pragma mark - Repo Operations

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    // Check shared cache first
    MST *cached = [[MSTCacheManager sharedManager] mstForDid:did];
    if (cached) return cached;

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) return nil;

    // Try incremental loading from repo blocks
    MST *mst = [self loadMSTFromRepoBlocksForDid:did store:store error:nil];
    if (mst) {
        [[MSTCacheManager sharedManager] setMST:mst forDid:did];
        return mst;
    }

    // Fallback: full rebuild from records
    NSArray<PDSDatabaseRecord *> *records = [self loadAllRecordsForStore:store did:did error:error];
    if (!records && error && *error) {
        return nil;
    }
    mst = [self mstFromRecords:records ?: @[]];
    if (mst) {
        [[MSTCacheManager sharedManager] setMST:mst forDid:did];
    }
    return mst;
}

- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable CID *)cid error:(NSError **)error {
    MST *mst = [self loadMSTForDid:did error:error];
    if (!mst) return NO;
    
    if (cid) {
        [mst put:key valueCID:cid subKey:nil];
    } else {
        [mst delete:key];
    }
    
    CID *repoRoot = mst.rootCID;
    if (!repoRoot) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute repo root CID"}];
        }
        return NO;
    }
    
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) return NO;
    
    __block BOOL success = NO;
    success = [self.repoRepository updateRepoRoot:did
                                         rootCid:[repoRoot bytes]
                                           error:error];
    
    return success;
}

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    PDS_LOG_DB_DEBUG(@"Looking up repo root for DID: %@", did);

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        PDS_LOG_DB_DEBUG(@"storeForDid returned nil for: %@", did);
        return nil;
    }
    
    NSData *rootData = nil;
    PDSDatabaseRepo *repo = [self.repoRepository repoForDid:did error:error];
    if (repo && repo.rootCid) {
        PDSDatabaseBlock *block = [self.blockRepository blockWithCid:repo.rootCid repoDid:did error:error];
        if (block) {
            rootData = block.blockData;
        }
    }

    return rootData;
}

- (nullable NSData *)getBlocksForDid:(NSString *)did cids:(NSArray<NSString *> *)cids error:(NSError **)error {
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) return nil;
    
    // Use first CID as root, or nil if none. CARWriter requires a root.
    CID *rootCid = nil;
    if (cids.count > 0) {
        rootCid = [CID cidFromString:cids.firstObject];
    }
    
    CARWriter *writer = [CARWriter writerWithRootCID:rootCid];
    
    __block BOOL success = YES;
    
    for (NSString *cidStr in cids) {
        CID *cid = [CID cidFromString:cidStr];
        if (!cid) continue;
        
        PDSDatabaseBlock *block = [self.blockRepository blockWithCid:cid.bytes repoDid:did error:nil];
        if (block && block.blockData) {
            [writer addBlock:[CARBlock blockWithCID:cid data:block.blockData]];
        }
    }
    
    if (!success) return nil;
    return [writer serialize];
}

- (nullable NSDictionary *)getLatestCommitForDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.sync"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Repo not found"}];
        }
        return nil;
    }

    // Fast path: use already-persisted signed head commit metadata.
    CID *storedCommitCID = nil;
    NSData *unusedCommitBlock = nil;
    CID *unusedDataCID = nil;
    NSString *storedCommitRev = nil;
    BOOL storedCommitIsSigned = NO;
    BOOL hasStoredHead = [self loadStoredHeadCommitForDid:did
                                                    store:store
                                                commitCID:&storedCommitCID
                                              commitBlock:&unusedCommitBlock
                                                  dataCID:&unusedDataCID
                                                      rev:&storedCommitRev
                                                 isSigned:&storedCommitIsSigned];
    if (hasStoredHead && storedCommitIsSigned && storedCommitCID.stringValue.length > 0) {
        NSString *rev = [store getRepoRevisionForDid:did error:nil];
        if (rev.length == 0) {
            rev = storedCommitRev ?: @"";
        }
        return @{@"cid": storedCommitCID.stringValue, @"rev": rev ?: @""};
    }

    // Slow path: rebuild export state, self-heal head commit if needed.
    MST *mst = nil;
    CID *commitCID = nil;
    NSData *commitBlock = nil;
    BOOL noChangesSince = NO;
    BOOL includeFullMST = YES;
    NSArray<NSString *> *changedMSTKeys = nil;
    NSArray<NSString *> *recordCIDStrings = nil;
    NSDictionary<NSString *, PDSDatabaseRecord *> *recordByCID = nil;
    NSDictionary<NSString *, NSData *> *materializedBlocks = nil;

    if (![self prepareRepoExportForDid:did
                                 since:nil
                                 store:&store
                                   mst:&mst
                             commitCID:&commitCID
                           commitBlock:&commitBlock
                        noChangesSince:&noChangesSince
                        includeFullMST:&includeFullMST
                        changedMSTKeys:&changedMSTKeys
                       recordCIDStrings:&recordCIDStrings
                            recordByCID:&recordByCID
                    materializedBlocks:&materializedBlocks
                                 error:error]) {
        return nil;
    }

    NSString *rev = [store getRepoRevisionForDid:did error:nil] ?: @"";
    return @{@"cid": commitCID.stringValue ?: @"", @"rev": rev};
}

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSString *)sinceRev error:(NSError **)error {
    CARWriter *writer = [self buildRepoWriterForDid:did since:sinceRev error:error];
    if (!writer) {
        return nil;
    }
    return [writer serialize];
}

- (BOOL)writeRepoContents:(NSString *)did since:(nullable NSString *)sinceRev toPath:(NSString *)path error:(NSError **)error {
    PDSActorStore *store = nil;
    MST *mst = nil;
    CID *commitCID = nil;
    NSData *commitBlock = nil;
    BOOL noChangesSince = NO;
    BOOL includeFullMST = YES;
    NSArray<NSString *> *changedMSTKeys = nil;
    NSArray<NSString *> *recordCIDStrings = nil;
    NSDictionary<NSString *, PDSDatabaseRecord *> *recordByCID = nil;
    NSDictionary<NSString *, NSData *> *materializedBlocks = nil;
    if (![self prepareRepoExportForDid:did
                                 since:sinceRev
                                 store:&store
                                   mst:&mst
                             commitCID:&commitCID
                           commitBlock:&commitBlock
                        noChangesSince:&noChangesSince
                        includeFullMST:&includeFullMST
                        changedMSTKeys:&changedMSTKeys
                       recordCIDStrings:&recordCIDStrings
                            recordByCID:&recordByCID
                    materializedBlocks:&materializedBlocks
                                 error:error]) {
        return NO;
    }

    if (![[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create repo CAR file"}];
        }
        return NO;
    }

    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fileHandle) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to open repo CAR file"}];
        }
        return NO;
    }

    @try {
        if (![CARWriter writeHeaderWithRootCID:commitCID toFileHandle:fileHandle error:error]) {
            [fileHandle closeFile];
            return NO;
        }

        if (noChangesSince) {
            [fileHandle closeFile];
            return YES;
        }

        if (![CARWriter writeBlock:[CARBlock blockWithCID:commitCID data:commitBlock]
                      toFileHandle:fileHandle
                             error:error]) {
            [fileHandle closeFile];
            return NO;
        }

        NSMutableSet<NSString *> *addedBlockCIDs = [NSMutableSet setWithObject:commitCID.stringValue];

        NSArray<CARBlock *> *mstBlocks = [self mstBlocksForExport:mst
                                                    includeAllMST:includeFullMST
                                                        proofKeys:changedMSTKeys ?: @[]
                                                            error:error];
        if (!mstBlocks) {
            [fileHandle closeFile];
            return NO;
        }
        for (CARBlock *block in mstBlocks) {
            NSString *cidString = block.cid.stringValue ?: @"";
            if (cidString.length == 0 || [addedBlockCIDs containsObject:cidString]) {
                continue;
            }
            [addedBlockCIDs addObject:cidString];
            if (![CARWriter writeBlock:block toFileHandle:fileHandle error:error]) {
                [fileHandle closeFile];
                return NO;
            }
        }

        for (NSString *cidString in recordCIDStrings) {
            if ([addedBlockCIDs containsObject:cidString]) {
                continue;
            }

            CID *cid = [CID cidFromString:cidString];
            if (!cid) {
                continue;
            }

            // Check materialized blocks first, then fall back to database
            NSData *data = materializedBlocks[cidString];
            if (!data) {
                PDSDatabaseBlock *block = [self.blockRepository blockWithCid:cid.bytes repoDid:did error:nil];
                data = block.blockData;
            }
            if (!data) {
                PDSDatabaseRecord *record = recordByCID[cidString];
                data = record ? [self recordBlockDataForRecord:record] : nil;
            }
            if (!data) {
                continue;
            }

            [addedBlockCIDs addObject:cidString];
            if (![CARWriter writeBlock:[CARBlock blockWithCID:cid data:data]
                          toFileHandle:fileHandle
                                 error:error]) {
                [fileHandle closeFile];
                return NO;
            }
        }

        [fileHandle closeFile];
        return YES;
    } @catch (NSException *exception) {
        [fileHandle closeFile];
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:9
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Failed to write repo CAR"}];
        }
        return NO;
    }
}

- (nullable PDSRepoChunkProducer)filteredRepoContentsChunkProducer:(NSString *)did
                                                              since:(nullable NSString *)sinceRev
                                                        collections:(NSArray<NSString *> *)collections
                                                              error:(NSError **)error {
    if (collections.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:14
                                     userInfo:@{NSLocalizedDescriptionKey: @"At least one collection is required"}];
        }
        return nil;
    }

    (void)sinceRev;

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) return nil;

    NSArray<PDSDatabaseRecord *> *allRecords = [self loadAllRecordsForStore:store did:did error:error];
    if (!allRecords && error && *error) {
        return nil;
    }

    MST *mst = [self mstFromRecords:allRecords ?: @[]];
    CID *mstRootCID = mst.rootCID;
    if (!mstRootCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute MST root"}];
        }
        return nil;
    }

    CID *storedCommitCID = nil;
    NSData *storedCommitBlock = nil;
    CID *storedDataCID = nil;
    NSString *storedCommitRev = nil;
    BOOL storedCommitIsSigned = NO;
    [self loadStoredHeadCommitForDid:did
                               store:store
                           commitCID:&storedCommitCID
                         commitBlock:&storedCommitBlock
                             dataCID:&storedDataCID
                                 rev:&storedCommitRev
                            isSigned:&storedCommitIsSigned];

    if (!storedCommitCID || !storedCommitBlock) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"No commit found for repository"}];
        }
        return nil;
    }

    NSSet<NSString *> *collectionSet = [NSSet setWithArray:collections];
    NSMutableArray<NSString *> *proofKeys = [NSMutableArray array];
    NSMutableArray<NSString *> *filteredRecordCIDs = [NSMutableArray array];
    NSMutableDictionary<NSString *, PDSDatabaseRecord *> *recordByCID = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *seenRecordCIDs = [NSMutableSet set];

    for (PDSDatabaseRecord *record in allRecords ?: @[]) {
        if (![collectionSet containsObject:record.collection]) {
            continue;
        }

        if (record.collection.length > 0 && record.rkey.length > 0) {
            NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
            [proofKeys addObject:key];
        }

        if (record.cid.length == 0 || [seenRecordCIDs containsObject:record.cid]) {
            continue;
        }
        [seenRecordCIDs addObject:record.cid];

        CID *recordCID = [CID cidFromString:record.cid];
        if (!recordCID) {
            continue;
        }

        NSString *cidString = recordCID.stringValue;
        if (cidString.length > 0) {
            [filteredRecordCIDs addObject:cidString];
            recordByCID[cidString] = record;
        }
    }

    NSData *headerChunk = [CARWriter encodedHeaderWithRootCID:storedCommitCID error:error];
    if (!headerChunk) {
        return nil;
    }

    NSData *commitChunk = [CARWriter encodedBlock:[CARBlock blockWithCID:storedCommitCID data:storedCommitBlock]
                                            error:error];
    if (!commitChunk) {
        return nil;
    }

    NSMutableSet<NSString *> *seenCIDs = [NSMutableSet set];
    if (storedCommitCID.stringValue.length > 0) {
        [seenCIDs addObject:storedCommitCID.stringValue];
    }

    NSMutableArray<NSData *> *mstChunks = [NSMutableArray array];
    NSArray<CARBlock *> *mstBlocks = [self mstBlocksForExport:mst
                                                includeAllMST:NO
                                                    proofKeys:proofKeys
                                                        error:error];
    if (!mstBlocks) {
        return nil;
    }

    for (CARBlock *block in mstBlocks) {
        NSString *cidString = block.cid.stringValue ?: @"";
        if (cidString.length == 0 || [seenCIDs containsObject:cidString]) {
            continue;
        }
        NSData *encoded = [CARWriter encodedBlock:block error:error];
        if (!encoded) {
            return nil;
        }
        [seenCIDs addObject:cidString];
        [mstChunks addObject:encoded];
    }

    NSMutableArray<NSString *> *remainingRecordCIDs = [NSMutableArray array];
    for (NSString *cidString in filteredRecordCIDs) {
        if (cidString.length == 0 || [seenCIDs containsObject:cidString]) {
            continue;
        }
        [seenCIDs addObject:cidString];
        [remainingRecordCIDs addObject:cidString];
    }

    NSArray<NSData *> *capturedMSTChunks = [mstChunks copy];
    NSArray<NSString *> *capturedRecordCIDs = [remainingRecordCIDs copy];
    NSDictionary<NSString *, PDSDatabaseRecord *> *capturedRecordByCID = [recordByCID copy];
    __weak typeof(self) weakSelf = self;
    __block NSUInteger phase = 0; // 0=header, 1=commit, 2=MST, 3=records, 4=done
    __block NSUInteger mstIndex = 0;
    __block NSUInteger recordIndex = 0;

    return ^NSData * _Nullable(NSError **producerError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (producerError) {
                *producerError = [NSError errorWithDomain:@"com.atproto.repo"
                                                     code:10
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Repository service deallocated during stream"}];
            }
            return nil;
        }

        if (phase == 4) {
            return nil;
        }

        if (phase == 0) {
            phase = 1;
            return headerChunk;
        }

        if (phase == 1) {
            phase = 2;
            return commitChunk;
        }

        if (phase == 2) {
            if (mstIndex < capturedMSTChunks.count) {
                NSData *chunk = capturedMSTChunks[mstIndex];
                mstIndex++;
                return chunk;
            }
            phase = 3;
        }

        if (phase == 3) {
            while (recordIndex < capturedRecordCIDs.count) {
                NSString *cidString = capturedRecordCIDs[recordIndex];
                recordIndex++;

                CID *cid = [CID cidFromString:cidString];
                if (!cid) {
                    continue;
                }

                NSData *data = nil;
                PDSDatabaseBlock *block = [strongSelf.blockRepository blockWithCid:cid.bytes repoDid:did error:nil];
                data = block.blockData;

                if (!data) {
                    PDSDatabaseRecord *record = capturedRecordByCID[cidString];
                    data = record ? [strongSelf recordBlockDataForRecord:record] : nil;
                }

                if (!data) {
                    continue;
                }

                return [CARWriter encodedBlock:[CARBlock blockWithCID:cid data:data] error:producerError];
            }
            phase = 4;
        }

        return nil;
    };
}

- (nullable PDSRepoChunkProducer)repoContentsChunkProducer:(NSString *)did
                                                    since:(nullable NSString *)sinceRev
                                                    error:(NSError **)error {
    PDSActorStore *store = nil;
    MST *mst = nil;
    CID *commitCID = nil;
    NSData *commitBlock = nil;
    BOOL noChangesSince = NO;
    BOOL includeFullMST = YES;
    NSArray<NSString *> *changedMSTKeys = nil;
    NSArray<NSString *> *recordCIDStrings = nil;
    NSDictionary<NSString *, PDSDatabaseRecord *> *recordByCID = nil;
    NSDictionary<NSString *, NSData *> *materializedBlocks = nil;
    if (![self prepareRepoExportForDid:did
                                 since:sinceRev
                                 store:&store
                                   mst:&mst
                             commitCID:&commitCID
                           commitBlock:&commitBlock
                        noChangesSince:&noChangesSince
                        includeFullMST:&includeFullMST
                        changedMSTKeys:&changedMSTKeys
                       recordCIDStrings:&recordCIDStrings
                            recordByCID:&recordByCID
                    materializedBlocks:&materializedBlocks
                                 error:error]) {
        return nil;
    }

    NSData *headerChunk = [CARWriter encodedHeaderWithRootCID:commitCID error:error];
    if (!headerChunk) {
        return nil;
    }

    if (noChangesSince) {
        __block BOOL sentHeader = NO;
        return ^NSData * _Nullable (NSError **producerError) {
            (void)producerError;
            if (sentHeader) {
                return nil;
            }
            sentHeader = YES;
            return headerChunk;
        };
    }

    NSData *commitChunk = [CARWriter encodedBlock:[CARBlock blockWithCID:commitCID data:commitBlock] error:error];
    if (!commitChunk) {
        return nil;
    }

    NSMutableSet<NSString *> *seenCIDs = [NSMutableSet set];
    if (commitCID.stringValue.length > 0) {
        [seenCIDs addObject:commitCID.stringValue];
    }

    NSMutableArray<NSData *> *mstChunks = [NSMutableArray array];

    NSArray<CARBlock *> *mstBlocks = [self mstBlocksForExport:mst
                                                includeAllMST:includeFullMST
                                                    proofKeys:changedMSTKeys ?: @[]
                                                        error:error];
    if (!mstBlocks) {
        return nil;
    }
    for (CARBlock *block in mstBlocks) {
        NSString *cidString = block.cid.stringValue ?: @"";
        if (cidString.length == 0 || [seenCIDs containsObject:cidString]) {
            continue;
        }

        NSData *encoded = [CARWriter encodedBlock:block error:error];
        if (!encoded) {
            return nil;
        }
        [seenCIDs addObject:cidString];
        [mstChunks addObject:encoded];
    }

    NSMutableArray<NSString *> *remainingRecordCIDs = [NSMutableArray array];
    for (NSString *cidString in recordCIDStrings) {
        if (cidString.length == 0 || [seenCIDs containsObject:cidString]) {
            continue;
        }
        [seenCIDs addObject:cidString];
        [remainingRecordCIDs addObject:cidString];
    }

    NSArray<NSData *> *capturedMSTChunks = [mstChunks copy];
    NSArray<NSString *> *capturedRecordCIDs = [remainingRecordCIDs copy];
    NSDictionary<NSString *, PDSDatabaseRecord *> *capturedRecordByCID = [recordByCID copy];
    NSDictionary<NSString *, NSData *> *capturedMaterializedBlocks = [materializedBlocks copy];
    __weak typeof(self) weakSelf = self;
    __block NSUInteger phase = 0; // 0=header, 1=commit, 2=MST, 3=records, 4=done
    __block NSUInteger mstIndex = 0;
    __block NSUInteger recordIndex = 0;

    return ^NSData * _Nullable (NSError **producerError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (producerError) {
                *producerError = [NSError errorWithDomain:@"com.atproto.repo"
                                                     code:10
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Repository service deallocated during stream"}];
            }
            return nil;
        }

        if (phase == 4) {
            return nil;
        }

        if (phase == 0) {
            phase = 1;
            return headerChunk;
        }

        if (phase == 1) {
            phase = 2;
            return commitChunk;
        }

        if (phase == 2) {
            if (mstIndex < capturedMSTChunks.count) {
                NSData *chunk = capturedMSTChunks[mstIndex];
                mstIndex++;
                return chunk;
            }
            phase = 3;
        }

        if (phase == 3) {
            while (recordIndex < capturedRecordCIDs.count) {
                NSString *cidString = capturedRecordCIDs[recordIndex];
                recordIndex++;

                CID *cid = [CID cidFromString:cidString];
                if (!cid) {
                    continue;
                }

                // Check materialized blocks first, then fall back to database
                NSData *data = capturedMaterializedBlocks[cidString];
                if (!data) {
                    PDSDatabaseBlock *block = [strongSelf.blockRepository blockWithCid:cid.bytes repoDid:did error:nil];
                    data = block.blockData;
                }
                if (!data) {
                    PDSDatabaseRecord *record = capturedRecordByCID[cidString];
                    data = record ? [strongSelf recordBlockDataForRecord:record] : nil;
                }
                if (!data) {
                    continue;
                }

                return [CARWriter encodedBlock:[CARBlock blockWithCID:cid data:data] error:producerError];
            }
            phase = 4;
        }

        return nil;
    };
}

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
                          error:(NSError **)error {
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) return NO;

    NSArray<PDSDatabaseRecord *> *records = [self loadAllRecordsForStore:store did:did error:error];
    if (!records && error && *error) {
        return NO;
    }

    MST *mst = [self mstFromRecords:records ?: @[]];
    CID *mstRootCID = mst.rootCID;
    if (!mstRootCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute MST root"}];
        }
        return NO;
    }

    NSString *storedRev = [store getRepoRevisionForDid:did error:nil];
    NSString *latestMutationRev = [store latestMutationRevisionWithError:nil];
    CID *storedCommitCID = nil;
    NSData *storedCommitBlock = nil;
    CID *storedDataCID = nil;
    NSString *storedCommitRev = nil;
    BOOL storedCommitIsSigned = NO;
    [self loadStoredHeadCommitForDid:did
                               store:store
                           commitCID:&storedCommitCID
                         commitBlock:&storedCommitBlock
                             dataCID:&storedDataCID
                                 rev:&storedCommitRev
                            isSigned:&storedCommitIsSigned];
    if (storedRev.length == 0 && storedCommitRev.length > 0) {
        storedRev = storedCommitRev;
    }

    BOOL rootChanged = (storedDataCID == nil) || ![storedDataCID isEqual:mstRootCID];
    BOOL revMissing = (storedRev.length == 0);
    NSString *currentRev = storedRev;
    if (rootChanged || revMissing) {
        if (latestMutationRev.length > 0) {
            currentRev = latestMutationRev;
        } else if (currentRev.length == 0) {
            currentRev = [TID tid].stringValue;
        }
    }
    NSString *defaultRecordRev = (storedRev.length > 0) ? storedRev : currentRev;

    BOOL hasSince = (sinceRev.length > 0);
    BOOL knownSince = NO;
    if (hasSince) {
        knownSince = [store repoRevisionExists:sinceRev error:nil];
        if (!knownSince) {
            knownSince = [store mutationRevisionExists:sinceRev error:nil];
        }
        if (!knownSince) {
            knownSince = [store blockRevisionExists:sinceRev error:nil];
        }
    }
    BOOL noChangesSince = (hasSince && [sinceRev isEqualToString:currentRev]);
    BOOL deltaMode = (hasSince && knownSince && !noChangesSince);

    NSMutableSet<NSString *> *changedBlockCIDSet = [NSMutableSet set];
    if (deltaMode) {
        NSError *blockListError = nil;
        NSArray<NSData *> *changedBlockCIDs = [store listBlockCIDsSinceRev:sinceRev
                                                                      limit:200000
                                                                      error:&blockListError];
        if (!changedBlockCIDs) {
            if (error) {
                *error = blockListError ?: [NSError errorWithDomain:@"com.atproto.repo"
                                                                code:13
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to list changed blocks"}];
            }
            return NO;
        }
        for (NSData *cidBytes in changedBlockCIDs) {
            CID *cid = [CID cidFromBytes:cidBytes];
            if (cid.stringValue.length > 0) {
                [changedBlockCIDSet addObject:cid.stringValue];
            }
        }
    }

    NSMutableArray<PDSDatabaseBlock *> *newRecordBlocks = [NSMutableArray array];
    NSMutableArray<PDSDatabaseRecord *> *recordsNeedingRevBackfill = [NSMutableArray array];
    NSMutableArray<NSString *> *recordCIDStrings = [NSMutableArray array];
    NSMutableDictionary<NSString *, PDSDatabaseRecord *> *recordByCID = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *seenRecordCIDs = [NSMutableSet set];
    NSMutableOrderedSet<NSString *> *changedMSTKeys = [NSMutableOrderedSet orderedSet];

    for (PDSDatabaseRecord *record in records) {
        if (record.rev.length == 0) {
            record.rev = defaultRecordRev;
            [recordsNeedingRevBackfill addObject:record];
        }

        BOOL recordChangedSince = (deltaMode && [record.rev compare:sinceRev] == NSOrderedDescending);
        BOOL blockChangedSince = (deltaMode && record.cid.length > 0 && [changedBlockCIDSet containsObject:record.cid]);
        if (recordChangedSince && record.collection.length > 0 && record.rkey.length > 0) {
            NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
            [changedMSTKeys addObject:key];
        }

        if (deltaMode && !(recordChangedSince || blockChangedSince)) {
            continue;
        }

        if (record.cid.length == 0 || [seenRecordCIDs containsObject:record.cid]) {
            continue;
        }
        [seenRecordCIDs addObject:record.cid];

        CID *recordCID = [CID cidFromString:record.cid];
        if (!recordCID) {
            continue;
        }

        PDSDatabaseBlock *existingBlock = [self.blockRepository blockWithCid:recordCID.bytes repoDid:did error:nil];
        NSData *blockData = existingBlock.blockData;
        if (!blockData) {
            blockData = [self recordBlockDataForRecord:record];
            if (blockData) {
                PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
                block.cid = recordCID.bytes;
                block.repoDid = did;
                block.blockData = blockData;
                block.contentType = @"application/vnd.ipld.dag-cbor";
                block.size = (NSInteger)blockData.length;
                block.createdAt = [NSDate date];
                block.rev = record.rev;
                [newRecordBlocks addObject:block];
            }
        }

        if (blockData) {
            NSString *cidString = recordCID.stringValue;
            if (cidString.length > 0) {
                [recordCIDStrings addObject:cidString];
                recordByCID[cidString] = record;
            }
        }
    }

    if (deltaMode) {
        NSError *tombstoneError = nil;
        NSArray<NSDictionary<NSString *, id> *> *tombstones = [store listRecordTombstonesSinceRev:sinceRev
                                                                                             limit:100000
                                                                                             error:&tombstoneError];
        if (!tombstones) {
            if (error) {
                *error = tombstoneError ?: [NSError errorWithDomain:@"com.atproto.repo"
                                                                code:11
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to list tombstones"}];
            }
            return NO;
        }
        for (NSDictionary<NSString *, id> *row in tombstones) {
            NSString *collection = [row[@"collection"] isKindOfClass:[NSString class]] ? row[@"collection"] : nil;
            NSString *rkey = [row[@"rkey"] isKindOfClass:[NSString class]] ? row[@"rkey"] : nil;
            if (collection.length == 0 || rkey.length == 0) {
                continue;
            }
            NSString *key = [NSString stringWithFormat:@"%@/%@", collection, rkey];
            [changedMSTKeys addObject:key];
        }
    }

    // Persist any newly materialized record blocks and rev backfills.
    // NOTE: We do *not* update repo_root here. The repo root must point at a signed Commit CID.
    if (newRecordBlocks.count > 0 || recordsNeedingRevBackfill.count > 0) {
        __block BOOL persisted = NO;
        [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            if (newRecordBlocks.count > 0 && ![transactor putBlocks:newRecordBlocks forDid:did error:blockError]) {
                persisted = NO;
                return;
            }

            for (PDSDatabaseRecord *record in recordsNeedingRevBackfill) {
                if (![transactor updateRecord:record forDid:did error:blockError]) {
                    persisted = NO;
                    return;
                }
            }
            persisted = YES;
        } error:error];

        if (!persisted) {
            return NO;
        }
    }

    // Try to load existing commit from repo_root
    // We expect repo_root to be the head Commit CID.
    RepoCommit *commit = nil;
    NSData *commitBlock = nil;
    CID *commitCID = nil;

    // If we have a signed stored commit and it matches the computed MST root, reuse it.
    if (storedCommitCID && storedCommitBlock.length > 0 && storedCommitIsSigned && storedDataCID && [storedDataCID isEqual:mstRootCID]) {
        commitCID = storedCommitCID;
        commitBlock = storedCommitBlock;
    } else {
        // Create and persist a signed commit that points at the computed MST root.
        // If the stored root was a valid signed commit, use it as "prev"; otherwise, start a new chain.
        CID *prevCommitCID = (storedCommitCID && storedCommitBlock.length > 0 && storedCommitIsSigned) ? storedCommitCID : nil;

        // Choose a revision that does not go backwards.
        NSString *revCandidate = currentRev;
        NSString *freshRev = [TID tid].stringValue;
        if (freshRev.length > 0 && [freshRev compare:revCandidate] == NSOrderedDescending) {
            revCandidate = freshRev;
        }
        if (storedRev.length > 0 && [storedRev compare:revCandidate] == NSOrderedDescending) {
            revCandidate = storedRev;
        }
        if (latestMutationRev.length > 0 && [latestMutationRev compare:revCandidate] == NSOrderedDescending) {
            revCandidate = latestMutationRev;
        }

        commit = [RepoCommit createCommitWithDid:did data:mstRootCID rev:revCandidate prev:prevCommitCID];

        NSError *signError = nil;
        NSData *signature = [store signData:[commit serialize] error:&signError];
        if (!signature) {
            if (error) {
                *error = signError ?: [NSError errorWithDomain:@"com.atproto.repo"
                                                         code:3
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign commit"}];
            }
            return NO;
        }
        commit.signature = signature;

        commitBlock = [commit serializeSigned];
        if (!commitBlock) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize signed commit"}];
            }
            return NO;
        }

        commitCID = [commit computeCID];
        if (!commitCID) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo"
                                             code:4
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute commit CID"}];
            }
            return NO;
        }

        PDSDatabaseBlock *commitDBBlock = [[PDSDatabaseBlock alloc] init];
        commitDBBlock.cid = commitCID.bytes;
        commitDBBlock.repoDid = did;
        commitDBBlock.blockData = commitBlock;
        commitDBBlock.contentType = @"application/vnd.ipld.dag-cbor";
        commitDBBlock.size = (NSInteger)commitBlock.length;
        commitDBBlock.createdAt = [NSDate date];
        commitDBBlock.rev = revCandidate;

        __block BOOL updated = NO;
        [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            if (![transactor putBlock:commitDBBlock forDid:did error:blockError]) {
                return;
            }
            updated = [transactor updateRepoRoot:did rootCid:commitCID.bytes rev:revCandidate error:blockError];
        } error:error];

        if (!updated) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo"
                                             code:5
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to persist new commit"}];
            }
            return NO;
        }
    }

    if (storeOut) *storeOut = store;
    if (mstOut) *mstOut = mst;
    if (commitCIDOut) *commitCIDOut = commitCID;
    if (commitBlockOut) *commitBlockOut = commitBlock;
    if (noChangesSinceOut) *noChangesSinceOut = noChangesSince;
    if (includeFullMSTOut) *includeFullMSTOut = !deltaMode;
    if (changedMSTKeysOut) *changedMSTKeysOut = [changedMSTKeys.array copy];
    if (recordCIDStringsOut) *recordCIDStringsOut = [recordCIDStrings copy];
    if (recordByCIDOut) *recordByCIDOut = [recordByCID copy];
    
    // Build dictionary of materialized blocks (CID string -> block data)
    if (materializedBlocksOut) {
        NSMutableDictionary<NSString *, NSData *> *materializedBlocks = [NSMutableDictionary dictionary];
        for (PDSDatabaseBlock *block in newRecordBlocks) {
            CID *cid = [CID cidFromBytes:block.cid];
            if (cid && block.blockData) {
                materializedBlocks[cid.stringValue] = block.blockData;
            }
        }
        *materializedBlocksOut = [materializedBlocks copy];
    }
    
    return YES;
}

- (BOOL)loadStoredHeadCommitForDid:(NSString *)did
                              store:(PDSActorStore *)store
                          commitCID:(CID * _Nullable * _Nonnull)commitCIDOut
                        commitBlock:(NSData * _Nullable * _Nonnull)commitBlockOut
                            dataCID:(CID * _Nullable * _Nonnull)dataCIDOut
                                rev:(NSString * _Nullable * _Nonnull)revOut
                           isSigned:(BOOL *)isSignedOut {
    if (commitCIDOut) {
        *commitCIDOut = nil;
    }
    if (commitBlockOut) {
        *commitBlockOut = nil;
    }
    if (dataCIDOut) {
        *dataCIDOut = nil;
    }
    if (revOut) {
        *revOut = nil;
    }
    if (isSignedOut) {
        *isSignedOut = NO;
    }

    NSData *storedRootBytes = [store getRepoRootForDid:did error:nil];
    CID *storedCommitCID = storedRootBytes ? [CID cidFromBytes:storedRootBytes] : nil;
    if (!storedCommitCID) {
        return NO;
    }

    NSData *storedCommitBlock = [store getBlockForCID:storedCommitCID.bytes forDid:did error:nil];
    if (storedCommitBlock.length == 0) {
        return NO;
    }

    NSError *decodeError = nil;
    id decoded = [ATProtoDagCBOR decodeData:storedCommitBlock error:&decodeError];
    if (![decoded isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSDictionary *map = (NSDictionary *)decoded;
    id versionVal = map[@"version"];
    NSString *commitDid = [map[@"did"] isKindOfClass:[NSString class]] ? map[@"did"] : nil;
    NSString *commitRev = [map[@"rev"] isKindOfClass:[NSString class]] ? map[@"rev"] : nil;
    if (![versionVal respondsToSelector:@selector(integerValue)] ||
        commitDid.length == 0 ||
        commitRev.length == 0 ||
        (did.length > 0 && ![commitDid isEqualToString:did])) {
        return NO;
    }

    CID *commitDataCID = nil;
    id dataVal = map[@"data"];
    if ([dataVal isKindOfClass:[CID class]]) {
        commitDataCID = (CID *)dataVal;
    } else if ([dataVal isKindOfClass:[NSString class]]) {
        commitDataCID = [CID cidFromString:(NSString *)dataVal];
    }

    BOOL isSigned = NO;
    id sigVal = map[@"sig"];
    if ([sigVal isKindOfClass:[NSData class]] && ((NSData *)sigVal).length > 0) {
        isSigned = YES;
    }

    if (commitCIDOut) {
        *commitCIDOut = storedCommitCID;
    }
    if (commitBlockOut) {
        *commitBlockOut = storedCommitBlock;
    }
    if (dataCIDOut) {
        *dataCIDOut = commitDataCID;
    }
    if (revOut) {
        *revOut = commitRev;
    }
    if (isSignedOut) {
        *isSignedOut = isSigned;
    }

    return YES;
}

- (nullable CARWriter *)buildRepoWriterForDid:(NSString *)did
                                         since:(nullable NSString *)sinceRev
                                         error:(NSError **)error {
    PDSActorStore *store = nil;
    MST *mst = nil;
    CID *commitCID = nil;
    NSData *commitBlock = nil;
    BOOL noChangesSince = NO;
    BOOL includeFullMST = YES;
    NSArray<NSString *> *changedMSTKeys = nil;
    NSArray<NSString *> *recordCIDStrings = nil;
    NSDictionary<NSString *, PDSDatabaseRecord *> *recordByCID = nil;
    NSDictionary<NSString *, NSData *> *materializedBlocks = nil;
    if (![self prepareRepoExportForDid:did
                                 since:sinceRev
                                 store:&store
                                   mst:&mst
                             commitCID:&commitCID
                           commitBlock:&commitBlock
                        noChangesSince:&noChangesSince
                        includeFullMST:&includeFullMST
                        changedMSTKeys:&changedMSTKeys
                       recordCIDStrings:&recordCIDStrings
                            recordByCID:&recordByCID
                    materializedBlocks:&materializedBlocks
                                 error:error]) {
        return nil;
    }

    CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
    if (noChangesSince) {
        return writer;
    }

    [writer addBlock:[CARBlock blockWithCID:commitCID data:commitBlock]];

    NSMutableSet<NSString *> *addedBlockCIDs = [NSMutableSet setWithObject:commitCID.stringValue];
    NSArray<CARBlock *> *mstBlocks = [self mstBlocksForExport:mst
                                                includeAllMST:includeFullMST
                                                    proofKeys:changedMSTKeys ?: @[]
                                                        error:error];
    if (!mstBlocks) {
        return nil;
    }
    for (CARBlock *block in mstBlocks) {
        NSString *cidString = block.cid.stringValue ?: @"";
        if (cidString.length == 0 || [addedBlockCIDs containsObject:cidString]) {
            continue;
        }
        [addedBlockCIDs addObject:cidString];
        [writer addBlock:block];
    }

    for (NSString *cidString in recordCIDStrings) {
        if ([addedBlockCIDs containsObject:cidString]) {
            continue;
        }

        CID *cid = [CID cidFromString:cidString];
        if (!cid) {
            continue;
        }

        // Check materialized blocks first, then fall back to database
        NSData *data = materializedBlocks[cidString];
        if (!data) {
            data = [store getBlockForCID:cid.bytes forDid:did error:nil];
        }
        if (!data) {
            PDSDatabaseRecord *record = recordByCID[cidString];
            data = record ? [self recordBlockDataForRecord:record] : nil;
        }
        if (!data) {
            continue;
        }

        [addedBlockCIDs addObject:cidString];
        [writer addBlock:[CARBlock blockWithCID:cid data:data]];
    }

    return writer;
}

- (nullable NSArray<CARBlock *> *)mstBlocksForExport:(MST *)mst
                                       includeAllMST:(BOOL)includeAllMST
                                           proofKeys:(NSArray<NSString *> *)proofKeys
                                                error:(NSError **)error {
    if (!mst) {
        return @[];
    }

    NSMutableArray<CARBlock *> *blocks = [NSMutableArray array];
    NSMutableSet<NSString *> *addedCIDs = [NSMutableSet set];

    BOOL (^appendNode)(CID *, NSData *) = ^BOOL(CID *cid, NSData *data) {
        NSString *cidString = cid.stringValue ?: @"";
        if (cidString.length == 0 || [addedCIDs containsObject:cidString] || data.length == 0) {
            return YES;
        }
        [addedCIDs addObject:cidString];
        [blocks addObject:[CARBlock blockWithCID:cid data:data]];
        return YES;
    };

    if (includeAllMST) {
        NSError *mstError = nil;
        BOOL enumerated = [mst enumerateNodeCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **blockError) {
            (void)blockError;
            return appendNode(cid, data);
        } error:&mstError];
        if (!enumerated) {
            if (error) {
                *error = mstError ?: [NSError errorWithDomain:@"com.atproto.repo"
                                                         code:5
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to export MST CAR"}];
            }
            return nil;
        }
        return [blocks copy];
    }

    CID *rootCID = mst.rootCID;
    NSData *rootData = [mst serializeToCBOR];
    if (!rootCID || !rootData) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:12
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize MST root"}];
        }
        return nil;
    }
    appendNode(rootCID, rootData);

    for (NSString *key in proofKeys) {
        if (key.length == 0) {
            continue;
        }
        NSArray<MSTNode *> *proofNodes = [mst getProofNodesForKey:key];
        if (!proofNodes) {
            continue;
        }
        for (MSTNode *node in proofNodes) {
            NSData *nodeData = [mst serializeNode:node];
            if (!nodeData) {
                continue;
            }
            CID *nodeCID = [CID cidWithDigest:[CID sha256Digest:nodeData] codec:0x71];
            if (!nodeCID) {
                continue;
            }
            appendNode(nodeCID, nodeData);
        }
    }

    return [blocks copy];
}

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error {
    return NO;
}

- (NSArray<PDSDatabaseRecord *> *)loadAllRecordsForStore:(PDSActorStore *)store
                                                      did:(NSString *)did
                                                    error:(NSError **)error {
    NSMutableArray<PDSDatabaseRecord *> *allRecords = [NSMutableArray array];
    const NSUInteger pageSize = 1000;
    NSUInteger offset = 0;
    const NSUInteger maxIterations = 1000; // Safety: max 1M records
    NSUInteger iterations = 0;

    while (iterations++ < maxIterations) {
        NSArray<PDSDatabaseRecord *> *page = [store listRecordsForDid:did
                                                                collection:nil
                                                                     limit:pageSize
                                                                    offset:offset
                                                                     error:error];
        if (!page) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo"
                                             code:6
                                          userInfo:@{NSLocalizedDescriptionKey: @"Failed to list repository records"}];
            }
            return nil;
        }

        [allRecords addObjectsFromArray:page];
        if (page.count < pageSize) {
            break;
        }
        offset += pageSize;
    }

    return allRecords;
}

- (nullable MST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error {
    return [MSTCacheManager loadMSTFromRepoBlocksForDid:did store:store error:error];
}

- (MST *)mstFromRecords:(NSArray<PDSDatabaseRecord *> *)records {
    MST *mst = [[MST alloc] init];
    for (PDSDatabaseRecord *record in records) {
        if (record.cid.length == 0 || record.collection.length == 0 || record.rkey.length == 0) {
            continue;
        }

        CID *cid = [CID cidFromString:record.cid];
        if (!cid) {
            continue;
        }

        NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
        [mst put:key valueCID:cid subKey:nil];
    }
    return mst;
}



- (nullable NSData *)recordBlockDataForRecord:(PDSDatabaseRecord *)record {
    if (!record.cid) {
        return nil;
    }

    // 1. Try to fetch from ipld_blocks first (canonical store)
    PDSActorStore *store = [self.databasePool storeForDid:record.did error:nil];
    if (store) {
        CID *cid = [CID cidFromString:record.cid];
        if (cid) {
            NSData *blockData = [store getBlockForCID:cid.bytes forDid:record.did error:nil];
            if (blockData.length > 0) {
                return blockData;
            }
        }
    }

    // 2. Fallback to materializing from JSON (legacy/self-healing)
    if (record.value.length == 0) {
        return nil;
    }

    NSData *jsonData = [record.value dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        return nil;
    }

    NSError *jsonError = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    if (!jsonObject || jsonError) {
        return nil;
    }

    NSError *cborError = nil;
    NSData *cborData = [ATProtoDagCBOR encodeJSONObject:jsonObject error:&cborError];
    if (!cborData || cborError) {
        return nil;
    }

    CID *expectedCID = [CID cidFromString:record.cid];
    if (!expectedCID) {
        return nil;
    }

    CID *actualCID = [CID cidWithDigest:[CID sha256Digest:cborData] codec:0x71];
    if (!actualCID || ![actualCID isEqualToCID:expectedCID]) {
        return nil;
    }

    return cborData;
}

- (CBORValue *)cidLinkValueForCID:(CID *)cid {
    NSMutableData *cidBytes = [NSMutableData dataWithCapacity:1 + cid.bytes.length];
    uint8_t marker = 0x00;
    [cidBytes appendBytes:&marker length:1];
    [cidBytes appendData:cid.bytes];
    return [CBORValue tag:42 value:[CBORValue byteString:cidBytes]];
}

- (BOOL)initializeRepoForDid:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing DID"}];
        }
        return NO;
    }

    NSData *existingRoot = [self getRepoRoot:did error:nil];
    if (existingRoot && existingRoot.length > 0) {
        return YES;
    }

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to get store for DID"}];
        }
        return NO;
    }

    MST *mst = [[MST alloc] init];
    CID *dataCID = mst.rootCID;
    if (!dataCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute empty MST root"}];
        }
        return NO;
    }

    NSString *rev = [[TID tid] stringValue];
    RepoCommit *commit = [RepoCommit createCommitWithDid:did
                                                    data:dataCID
                                                     rev:rev
                                                    prev:nil];

    NSData *signature = [store signData:[commit serialize] error:error];
    if (!signature) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign initial commit"}];
        }
        return NO;
    }
    commit.signature = signature;

    CID *commitCID = [commit computeCID];
    NSData *commitData = [commit serializeSigned];
    if (!commitData) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize initial commit"}];
        }
        return NO;
    }

    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = [commitCID bytes];
    block.blockData = commitData;
    block.size = commitData.length;
    block.rev = rev;

    __block BOOL success = NO;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        if (![transactor putBlock:block forDid:did error:blockError]) {
            return;
        }
        success = [transactor updateRepoRoot:did rootCid:[commitCID bytes] rev:rev error:blockError];
    } error:error];

    if (!success && error && !*error) {
        *error = [NSError errorWithDomain:@"PDSRepositoryService" code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to store initial commit"}];
    }

    return success;
}

- (BOOL)forceReinitializeRepoForDid:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing DID"}];
        }
        return NO;
    }

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to get store for DID"}];
        }
        return NO;
    }

    PDS_LOG_SERVICE_DEBUG(@"Clearing repo_root for DID: %@", did);

    if (![store clearRepoRootWithError:error]) {
        PDS_LOG_SERVICE_ERROR(@"Failed to clear repo_root: %@", error ? *error : @"unknown");
        return NO;
    }

    return [self initializeRepoForDid:did error:error];
}

@end
