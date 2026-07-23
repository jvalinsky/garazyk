// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService+Export.h"
#import "Repository/CAR.h"
#import "Repository/STAR.h"
#import "Repository/CBOR.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Repository/MST.h"
#import "Repository/RepoCommit.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Core/Repositories/PDSBlockRepository.h"
#import "Core/Repositories/PDSRepoRepository.h"
#import "Core/MSTCacheManager.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"

@implementation PDSRepositoryService (Export)

#pragma mark - CAR Export

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

        MSTBlockProvider exportRecordProvider = [self recordProviderForDid:did
                                                          materializedBlocks:materializedBlocks
                                                                recordByCID:recordByCID];
        NSArray<CARBlock *> *mstBlocks = [self mstBlocksForExport:mst
                                                    includeAllMST:includeFullMST
                                                        proofKeys:changedMSTKeys ?: @[]
                                                 recordProvider:exportRecordProvider
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
    // Proof-only MST nodes; sparse proofs intentionally exclude records
    // (the relay/AKA flow consumes the MST proof, not the records themselves).
    NSArray<CARBlock *> *mstBlocks = [self mstBlocksForExport:mst
                                                includeAllMST:NO
                                                    proofKeys:proofKeys
                                             recordProvider:nil
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

    // Defensive against walker provider-missed records: the new pre-order
    // walker (gated by streamableCARBlockOrderingEnabled) emits records
    // interleaved with MST nodes; missing records here did not get into the
    // MST and need to be appended. With proof-only `includeAllMST=NO`,
    // remainingRecordCIDs generally contains every changed record.
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

    MSTBlockProvider exportRecordProvider = [self recordProviderForDid:did
                                                      materializedBlocks:materializedBlocks
                                                            recordByCID:recordByCID];
    NSArray<CARBlock *> *mstBlocks = [self mstBlocksForExport:mst
                                                includeAllMST:includeFullMST
                                                    proofKeys:changedMSTKeys ?: @[]
                                             recordProvider:exportRecordProvider
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

    // Defensive against walker provider-missed records: under Sync 1.1 the
    // pre-order walker (gated by streamableCARBlockOrderingEnabled) emits
    // every record interleaved with its MST node in the MST phase; here we
    // only retain records the walker dropped (i.e. records whose CID the
    // recordProvider could not resolve). In full-export mode this list is
    // typically empty; under proof-only / delta sync it carries the changes.
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
                    PDSActorStore *store = [strongSelf.databasePool storeForDid:did error:nil];
                    if (store) {
                        PDSDatabaseRecord *dbRec = [store getRecordByCID:cidString forDid:did error:nil];
                        if (dbRec) {
                            data = [strongSelf recordBlockDataForRecord:dbRec];
                        }
                    }
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

#pragma mark - STAR Format Export

- (nullable NSData *)getRepoContentsSTARL0:(NSString *)did
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

    if (noChangesSince) {
        // Empty tree: just the header with data: null
        STARCommit *commit = [self starCommitFromExport:did
                                             commitCID:commitCID
                                           commitBlock:commitBlock];
        STARL0Writer *writer = [[STARL0Writer alloc] initWithCommit:commit];
        return [writer serialize];
    }

    STARCommit *commit = [self starCommitFromExport:did
                                         commitCID:commitCID
                                       commitBlock:commitBlock];
    STARL0Writer *writer = [[STARL0Writer alloc] initWithCommit:commit];

    __weak typeof(self) weakSelf = self;
    __block NSDictionary<NSString *, PDSDatabaseRecord *> *capturedRecordByCID = [recordByCID copy];
    __block NSDictionary<NSString *, NSData *> *capturedMaterializedBlocks = [materializedBlocks copy];

    BOOL success = [writer writeFromMST:mst
                         blockProvider:^NSData * _Nullable(CID *cid) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        NSString *cidString = cid.stringValue;

        // Check materialized blocks first, then database
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
            PDSActorStore *store = [strongSelf.databasePool storeForDid:did error:nil];
            if (store) {
                PDSDatabaseRecord *dbRec = [store getRecordByCID:cidString forDid:did error:nil];
                if (dbRec) {
                    data = [strongSelf recordBlockDataForRecord:dbRec];
                }
            }
        }
        return data;
    } error:error];

    if (!success) return nil;
    return [writer serialize];
}

- (nullable NSData *)getRepoContentsSTARLite:(NSString *)did
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

    STARCommit *commit = [self starCommitFromExport:did
                                         commitCID:commitCID
                                       commitBlock:commitBlock];
    STARLiteWriter *writer = [[STARLiteWriter alloc] initWithCommit:commit];

    if (noChangesSince) {
        return [writer serialize];
    }

    __weak typeof(self) weakSelf = self;
    __block NSDictionary<NSString *, PDSDatabaseRecord *> *capturedRecordByCID = [recordByCID copy];
    __block NSDictionary<NSString *, NSData *> *capturedMaterializedBlocks = [materializedBlocks copy];

    BOOL success = [writer writeFromMST:mst
                         blockProvider:^NSData * _Nullable(CID *cid) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        NSString *cidString = cid.stringValue;

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
            PDSActorStore *store = [strongSelf.databasePool storeForDid:did error:nil];
            if (store) {
                PDSDatabaseRecord *dbRec = [store getRecordByCID:cidString forDid:did error:nil];
                if (dbRec) {
                    data = [strongSelf recordBlockDataForRecord:dbRec];
                }
            }
        }
        return data;
    } error:error];

    if (!success) return nil;
    return [writer serialize];
}

- (nullable PDSRepoChunkProducer)repoContentsSTARL0ChunkProducer:(NSString *)did
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

    STARCommit *commit = [self starCommitFromExport:did
                                         commitCID:commitCID
                                       commitBlock:commitBlock];

    __block NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    __block BOOL finished = NO;
    __block NSError *exportError = nil;

    // We can't easily do a true "async generator" in ObjC without threads,
    // so we'll run the traversal once and capture the chunks. 
    // This is still better than one giant NSData because we've already split it.
    // In a future version, we'd use a thread-safe queue.

    STARL0Writer *writer = [[STARL0Writer alloc] initWithCommit:commit outputBlock:^(NSData *chunk) {
        if (chunk.length > 0) {
            [chunks addObject:chunk];
        }
    }];

    __weak typeof(self) weakSelf = self;
    __block NSDictionary<NSString *, PDSDatabaseRecord *> *capturedRecordByCID = [recordByCID copy];
    __block NSDictionary<NSString *, NSData *> *capturedMaterializedBlocks = [materializedBlocks copy];

    BOOL success = [writer writeFromMST:mst
                         blockProvider:^NSData * _Nullable(CID *cid) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        NSString *cidString = cid.stringValue;
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
            PDSActorStore *store = [strongSelf.databasePool storeForDid:did error:nil];
            if (store) {
                PDSDatabaseRecord *dbRec = [store getRecordByCID:cidString forDid:did error:nil];
                if (dbRec) {
                    data = [strongSelf recordBlockDataForRecord:dbRec];
                }
            }
        }
        return data;
    } error:&exportError];

    if (!success) {
        if (error) *error = exportError;
        return nil;
    }

    __block NSUInteger chunkIndex = 0;
    return ^NSData * _Nullable (NSError **producerError) {
        (void)producerError;
        if (chunkIndex < chunks.count) {
            return chunks[chunkIndex++];
        }
        return nil;
    };
}

- (nullable PDSRepoChunkProducer)repoContentsSTARLiteChunkProducer:(NSString *)did
                                                              since:(nullable NSString *)sinceRev
                                                              error:(NSError **)error {
    NSData *starData = [self getRepoContentsSTARLite:did since:sinceRev error:error];
    if (!starData) return nil;

    __block BOOL sent = NO;
    return ^NSData * _Nullable (NSError **producerError) {
        (void)producerError;
        if (sent) return nil;
        sent = YES;
        return starData;
    };
}

- (STARCommit *)starCommitFromExport:(NSString *)did
                           commitCID:(CID *)commitCID
                         commitBlock:(NSData *)commitBlock {
    // Parse the commit block to extract rev, prev, sig, data
    CBORValue *commitValue = [CBORValue decode:commitBlock];
    NSString *rev = @"";
    CID *dataCID = nil;
    CID *prevCID = nil;
    NSData *sig = nil;

    if (commitValue && commitValue.type == CBORTypeMap) {
        CBORValue *revVal = commitValue.map[[CBORValue textString:@"rev"]];
        if (revVal && revVal.type == CBORTypeTextString) {
            rev = revVal.textString;
        }

        CBORValue *dataVal = commitValue.map[[CBORValue textString:@"data"]];
        if (dataVal && dataVal.type == CBORTypeTag) {
            NSData *cidBytes = dataVal.tagValue.byteString;
            if (cidBytes.length > 1) {
                dataCID = [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
            }
        }

        CBORValue *prevVal = commitValue.map[[CBORValue textString:@"prev"]];
        if (prevVal && prevVal.type == CBORTypeTag) {
            NSData *cidBytes = prevVal.tagValue.byteString;
            if (cidBytes.length > 1) {
                prevCID = [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
            }
        }

        CBORValue *sigVal = commitValue.map[[CBORValue textString:@"sig"]];
        if (sigVal && sigVal.type == CBORTypeByteString) {
            sig = sigVal.byteString;
        }
    }

    return [STARCommit commitWithDid:did
                             version:3
                               data:dataCID
                                rev:rev
                               prev:prevCID
                                sig:sig];
}

#pragma mark - Export State Preparation

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

    NSArray<PDSDatabaseRecord *> *records = nil;
    MST *mst = [self loadMSTForDid:did store:store error:error];
    if (!mst && error && *error) {
        return NO;
    }
    if (!mst) {
        records = [self loadAllRecordsForStore:store did:did error:error];
        if (!records && error && *error) {
            return NO;
        }
        mst = [self mstFromRecords:records ?: @[]];
    }
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

    if (records) {
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
                    if (recordCIDStringsOut) [recordCIDStrings addObject:cidString];
                    if (recordByCIDOut) recordByCID[cidString] = record;
                }
            }
        }
    } else if (deltaMode) {
        NSError *headerError = nil;
        NSArray<PDSDatabaseRecord *> *changedHeaders = [store listRecordHeadersSinceRev:sinceRev forDid:did limit:200000 offset:0 error:&headerError];
        if (!changedHeaders) {
            if (error) {
                *error = headerError ?: [NSError errorWithDomain:@"com.atproto.repo"
                                                            code:14
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to list changed record headers"}];
            }
            return NO;
        }
        for (PDSDatabaseRecord *record in changedHeaders) {
            if (record.rev.length == 0) {
                record.rev = defaultRecordRev;
                [recordsNeedingRevBackfill addObject:record];
            }

            BOOL recordChangedSince = ([record.rev compare:sinceRev] == NSOrderedDescending);
            BOOL blockChangedSince = (record.cid.length > 0 && [changedBlockCIDSet containsObject:record.cid]);
            if (recordChangedSince && record.collection.length > 0 && record.rkey.length > 0) {
                NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
                [changedMSTKeys addObject:key];
            }

            if (!(recordChangedSince || blockChangedSince)) {
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
            PDSDatabaseRecord *fullRecord = nil;
            if (!blockData) {
                fullRecord = [store getRecordByCID:record.cid forDid:did error:nil];
                if (fullRecord) {
                    blockData = [self recordBlockDataForRecord:fullRecord];
                    if (blockData) {
                        PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
                        block.cid = recordCID.bytes;
                        block.repoDid = did;
                        block.blockData = blockData;
                        block.contentType = @"application/vnd.ipld.dag-cbor";
                        block.size = (NSInteger)blockData.length;
                        block.createdAt = [NSDate date];
                        block.rev = fullRecord.rev ?: record.rev;
                        [newRecordBlocks addObject:block];
                    }
                }
            }

            if (blockData || existingBlock) {
                NSString *cidString = recordCID.stringValue;
                if (cidString.length > 0) {
                    if (recordCIDStringsOut) [recordCIDStrings addObject:cidString];
                    if (recordByCIDOut) {
                        if (!fullRecord) fullRecord = [store getRecordByCID:record.cid forDid:did error:nil];
                        if (fullRecord) recordByCID[cidString] = fullRecord;
                    }
                }
            }
        }
    } else if (recordCIDStringsOut) {
        const NSUInteger pageSize = 10000;
        NSUInteger offset = 0;
        const NSUInteger maxOffset = 200000;
        while (offset < maxOffset) {
            NSArray<NSString *> *page = [store listRecordCIDsForDid:did limit:pageSize offset:offset error:nil];
            if (!page || page.count == 0) break;
            for (NSString *c in page) {
                if (c.length > 0 && ![seenRecordCIDs containsObject:c]) {
                    [seenRecordCIDs addObject:c];
                    [recordCIDStrings addObject:c];
                }
            }
            if (page.count < pageSize) break;
            offset += pageSize;
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

#pragma mark - Stored Head Commit

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

#pragma mark - CAR Assembly Helpers

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
    MSTBlockProvider exportRecordProvider = [self recordProviderForDid:did
                                                      materializedBlocks:materializedBlocks
                                                            recordByCID:recordByCID];
    NSArray<CARBlock *> *mstBlocks = [self mstBlocksForExport:mst
                                                includeAllMST:includeFullMST
                                                    proofKeys:changedMSTKeys ?: @[]
                                             recordProvider:exportRecordProvider
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
            PDSDatabaseRecord *dbRec = [store getRecordByCID:cidString forDid:did error:nil];
            if (dbRec) {
                data = [self recordBlockDataForRecord:dbRec];
            }
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
                                      recordProvider:(nullable MSTBlockProvider)recordProvider
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
        // Sync 1.1 streamable CAR block ordering: pre-order DFS with records
        // interleaved at each entry. The BFS + post-MST-record-layout emit is
        // deliberately replaced here so consumers receive the spec-required
        // stream layout. The downstream recordCIDStrings loop remains as a
        // defensive fallback: any CID the walker silently skipped (record
        // provider returned nil) gets one more retry with the same 3-tier
        // chain before dedup drops it.
        NSError *mstError = nil;
        BOOL enumerated = [mst enumerateStreamableCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **blockError) {
            (void)blockError;
            return appendNode(cid, data);
        } recordProvider:recordProvider error:&mstError];
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

- (MSTBlockProvider)recordProviderForDid:(NSString *)did
                       materializedBlocks:(nullable NSDictionary<NSString *, NSData *> *)materializedBlocks
                             recordByCID:(nullable NSDictionary<NSString *, PDSDatabaseRecord *> *)recordByCID {
    // Captures by copy so lifetime is independent of the caller's stack frame.
    // The walker's record lookup is synchronous and self is alive during the
    // call; weakSelf-strongSelf still applied for defense in depth and to match
    // the convention used by the chunk-producer's phase 3 lookup chain.
    NSDictionary<NSString *, NSData *> *capturedMatBlocks = materializedBlocks ? [materializedBlocks copy] : @{};
    NSDictionary<NSString *, PDSDatabaseRecord *> *capturedRecByCID = recordByCID ? [recordByCID copy] : @{};
    NSString *capturedDid = [did copy];
    __weak typeof(self) weakSelf = self;
    return ^NSData * _Nullable(CID *cid) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        NSString *cidString = cid.stringValue;
        if (cidString.length == 0) return nil;
        // Three-tier lookup matches the chunk producer's phase 3 chain:
        //   1) just-materialized records (fastest, in-flight cache)
        //   2) persisted blocks (database-backed blockRepository)
        //   3) re-encode from the in-memory record (slowest fallback)
        NSData *data = capturedMatBlocks[cidString];
        if (!data) {
            PDSDatabaseBlock *block = [strongSelf.blockRepository blockWithCid:cid.bytes repoDid:capturedDid error:nil];
            data = block.blockData;
        }
        if (!data) {
            PDSDatabaseRecord *record = capturedRecByCID[cidString];
            data = record ? [strongSelf recordBlockDataForRecord:record] : nil;
        }
        if (!data) {
            PDSActorStore *store = [strongSelf.databasePool storeForDid:capturedDid error:nil];
            if (store) {
                PDSDatabaseRecord *dbRec = [store getRecordByCID:cidString forDid:capturedDid error:nil];
                if (dbRec) {
                    data = [strongSelf recordBlockDataForRecord:dbRec];
                }
            }
        }
        return data;
    };
}

@end
