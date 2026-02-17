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

@interface PDSRepositoryService ()

- (NSArray<PDSDatabaseRecord *> *)loadAllRecordsForStore:(PDSActorStore *)store
                                                      did:(NSString *)did
                                                    error:(NSError **)error;
- (MST *)mstFromRecords:(NSArray<PDSDatabaseRecord *> *)records;
- (nullable NSData *)recordBlockDataForRecord:(PDSDatabaseRecord *)record;
- (CBORValue *)cidLinkValueForCID:(CID *)cid;
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
                          error:(NSError **)error;
- (nullable NSArray<CARBlock *> *)mstBlocksForExport:(MST *)mst
                                       includeAllMST:(BOOL)includeAllMST
                                           proofKeys:(NSArray<NSString *> *)proofKeys
                                                error:(NSError **)error;

@end

@implementation PDSRepositoryService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - Repo Operations

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;

    NSArray<PDSDatabaseRecord *> *records = [self loadAllRecordsForStore:store did:did error:error];
    if (!records && error && *error) {
        return nil;
    }
    return [self mstFromRecords:records ?: @[]];
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
    
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return NO;
    
    __block BOOL success = NO;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor updateRepoRoot:did
                                     rootCid:[repoRoot bytes]
                                         rev:[TID tid].stringValue
                                       error:blockError];
    } error:error];
    
    return success;
}

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    return [_databasePool getRepoRoot:did error:error];
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

            NSData *data = [store getBlockForCID:cid.bytes forDid:did error:nil];
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

                NSData *data = [store getBlockForCID:cid.bytes forDid:did error:nil];
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
                          error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
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

    NSData *storedRoot = [store getRepoRootForDid:did error:nil];
    NSString *storedRev = [store getRepoRevisionForDid:did error:nil];
    NSString *latestMutationRev = [store latestMutationRevisionWithError:nil];

    NSData *newRootBytes = mstRootCID.bytes;
    BOOL rootChanged = !storedRoot || ![storedRoot isEqualToData:newRootBytes];
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
    }
    BOOL noChangesSince = (hasSince && [sinceRev isEqualToString:currentRev]);
    BOOL deltaMode = (hasSince && knownSince && !noChangesSince);

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
        if (recordChangedSince && record.collection.length > 0 && record.rkey.length > 0) {
            NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
            [changedMSTKeys addObject:key];
        }

        if (deltaMode && !recordChangedSince) {
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

        NSData *blockData = [store getBlockForCID:recordCID.bytes forDid:did error:nil];
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

    if (rootChanged || revMissing || newRecordBlocks.count > 0 || recordsNeedingRevBackfill.count > 0) {
        __block BOOL persisted = NO;
        [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            if (![transactor updateRepoRoot:did rootCid:newRootBytes rev:currentRev error:blockError]) {
                persisted = NO;
                return;
            }

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
    NSData *rootBytes = [store getRepoRootForDid:did error:nil];
    CID *storedCommitCID = rootBytes ? [CID cidFromBytes:rootBytes] : nil;
    NSData *storedCommitBlock = nil;

    if (storedCommitCID) {
        // Fetch the block
        storedCommitBlock = [store getBlockForCID:[storedCommitCID bytes] forDid:did error:nil];
        if (storedCommitBlock) {
             // Decode and verify data CID matches our computed MST
             NSError *decodeError = nil;
             id decoded = [ATProtoDagCBOR decodeData:storedCommitBlock error:&decodeError];
             if ([decoded isKindOfClass:[NSDictionary class]]) {
                 NSDictionary *map = (NSDictionary *)decoded;
                 id dataVal = map[@"data"];
                 CID *storedDataCID = nil;
                 if ([dataVal isKindOfClass:[CID class]]) {
                     storedDataCID = (CID *)dataVal;
                 } else if ([dataVal isKindOfClass:[NSString class]]) {
                     storedDataCID = [CID cidFromString:(NSString *)dataVal];
                 }
                 
                 // If the stored commit's MST matches our computed MST, use the stored commit
                 if ((!storedDataCID && !mstRootCID) || [storedDataCID isEqual:mstRootCID]) {
                     // Match! Keep storedCommitBlock.
                 } else {
                     // Mismatch - likely concurrent update or non-deterministic MST.
                     // Fallback to creating a new commit.
                     storedCommitBlock = nil;
                 }
             } else {
                 storedCommitBlock = nil; // Invalid block
             }
        }
    }

    RepoCommit *commit = nil;
    NSData *commitBlock = nil;
    CID *commitCID = nil;

    if (storedCommitBlock && storedCommitCID) {
        commitBlock = storedCommitBlock;
        commitCID = storedCommitCID;
    } else {
        // Fallback: Create new commit
        commit = [RepoCommit createCommitWithDid:did
                                            data:mstRootCID
                                             rev:currentRev
                                            prev:storedCommitCID]; // Use stored ID (even if data mismatch) as prev
        
        // Attempt to sign with store key
        NSData *key = [store signingKeyPrivateBytesWithError:nil];
        if (key) {
             [commit signWithPrivateKey:key error:nil];
        }
        
        commitBlock = [commit serialize];
        if (!commitBlock) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to build commit block"}];
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

        NSData *data = [store getBlockForCID:cid.bytes forDid:did error:nil];
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

    while (YES) {
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

@end
