#import "PDSRepositoryService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Repository/MST.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Core/TID.h"

@interface PDSRepositoryService ()

- (NSArray<PDSDatabaseRecord *> *)loadAllRecordsForStore:(PDSActorStore *)store
                                                      did:(NSString *)did
                                                    error:(NSError **)error;
- (MST *)mstFromRecords:(NSArray<PDSDatabaseRecord *> *)records;
- (nullable NSData *)buildCommitBlockForDid:(NSString *)did
                                        rev:(NSString *)rev
                                    dataCID:(CID *)dataCID;
- (nullable NSData *)recordBlockDataForRecord:(PDSDatabaseRecord *)record;
- (CBORValue *)cidLinkValueForCID:(CID *)cid;
- (nullable CARWriter *)buildRepoWriterForDid:(NSString *)did
                                         since:(nullable NSString *)sinceRev
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
    CARWriter *writer = [self buildRepoWriterForDid:did since:sinceRev error:error];
    if (!writer) {
        return NO;
    }
    return [writer writeToPath:path error:error];
}

- (nullable CARWriter *)buildRepoWriterForDid:(NSString *)did
                                         since:(nullable NSString *)sinceRev
                                         error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;

    NSArray<PDSDatabaseRecord *> *records = [self loadAllRecordsForStore:store did:did error:error];
    if (!records && error && *error) {
        return nil;
    }

    MST *mst = [self mstFromRecords:records ?: @[]];
    CID *mstRootCID = mst.rootCID;
    if (!mstRootCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute MST root"}];
        }
        return nil;
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

    NSMutableDictionary<NSString *, NSData *> *recordBlocksByCID = [NSMutableDictionary dictionary];
    NSMutableArray<PDSDatabaseBlock *> *newRecordBlocks = [NSMutableArray array];
    NSMutableArray<PDSDatabaseRecord *> *recordsNeedingRevBackfill = [NSMutableArray array];
    NSMutableSet<NSString *> *seenRecordCIDs = [NSMutableSet set];

    for (PDSDatabaseRecord *record in records) {
        if (record.rev.length == 0) {
            record.rev = defaultRecordRev;
            [recordsNeedingRevBackfill addObject:record];
        }

        if (deltaMode && [record.rev compare:sinceRev] != NSOrderedDescending) {
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
            recordBlocksByCID[recordCID.stringValue] = blockData;
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
            return nil;
        }
    }

    NSData *commitBlock = [self buildCommitBlockForDid:did rev:currentRev dataCID:mstRootCID];
    if (!commitBlock) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to build commit block"}];
        }
        return nil;
    }

    CID *commitCID = [CID cidWithDigest:[CID sha256Digest:commitBlock] codec:0x71];
    if (!commitCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute commit CID"}];
        }
        return nil;
    }

    CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
    if (noChangesSince) {
        return writer;
    }

    [writer addBlock:[CARBlock blockWithCID:commitCID data:commitBlock]];

    NSError *mstCarError = nil;
    NSData *mstCarData = [mst exportCAR];
    CARReader *mstReader = mstCarData ? [CARReader readFromData:mstCarData error:&mstCarError] : nil;
    if (!mstReader) {
        if (error) {
            *error = mstCarError ?: [NSError errorWithDomain:@"com.atproto.repo"
                                                        code:5
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to export MST CAR"}];
        }
        return nil;
    }

    NSMutableSet<NSString *> *addedBlockCIDs = [NSMutableSet setWithObject:commitCID.stringValue];
    for (CARBlock *block in mstReader.blocks) {
        if ([addedBlockCIDs containsObject:block.cid.stringValue]) {
            continue;
        }
        [addedBlockCIDs addObject:block.cid.stringValue];
        [writer addBlock:block];
    }

    for (NSString *cidString in recordBlocksByCID) {
        if ([addedBlockCIDs containsObject:cidString]) {
            continue;
        }

        CID *cid = [CID cidFromString:cidString];
        NSData *data = recordBlocksByCID[cidString];
        if (!cid || !data) {
            continue;
        }

        [addedBlockCIDs addObject:cidString];
        [writer addBlock:[CARBlock blockWithCID:cid data:data]];
    }

    return writer;
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

- (nullable NSData *)buildCommitBlockForDid:(NSString *)did
                                        rev:(NSString *)rev
                                    dataCID:(CID *)dataCID {
    NSMutableDictionary<CBORValue *, CBORValue *> *commitMap = [NSMutableDictionary dictionary];
    commitMap[[CBORValue textString:@"did"]] = [CBORValue textString:did];
    commitMap[[CBORValue textString:@"version"]] = [CBORValue unsignedInteger:3];
    commitMap[[CBORValue textString:@"rev"]] = [CBORValue textString:rev];
    commitMap[[CBORValue textString:@"data"]] = [self cidLinkValueForCID:dataCID];
    return [[CBORValue map:commitMap] encode];
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
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:jsonObject error:&cborError];
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
