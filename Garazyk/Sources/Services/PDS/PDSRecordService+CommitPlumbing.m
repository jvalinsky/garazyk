// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService+CommitPlumbing.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Repository/MST.h"
#import "Repository/RepoCommit.h"
#import "Repository/CBOR.h"
#import "Core/MSTCacheManager.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Core/Repositories/PDSRecordRepository.h"

@implementation PDSRecordService (CommitPlumbing)

#pragma mark - Commit Plumbing (MST & Signed Commits)

- (nullable CID *)computeRepoRootCIDForDid:(NSString *)did
                                      store:(PDSActorStore *)store
                                      error:(NSError **)error {
    MST *mst = [self loadRepoMSTForDid:did store:store error:error];
    if (!mst) {
        return nil;
    }

    CID *rootCID = mst.rootCID;
    if (!rootCID && error && !*error) {
        *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                     code:9
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute repository root"}];
    }
    return rootCID;
}

- (nullable MST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                         store:(PDSActorStore *)store
                                         error:(NSError **)error {
    return [MSTCacheManager loadMSTFromRepoBlocksForDid:did store:store error:error];
}

- (nullable MST *)loadRepoMSTForDid:(NSString *)did
                               store:(PDSActorStore *)store
                               error:(NSError **)error {
    MST *mst = [[MST alloc] init];
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
                *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                             code:8
                                          userInfo:@{NSLocalizedDescriptionKey: @"Failed to list repository records"}];
            }
            return nil;
        }

        for (PDSDatabaseRecord *record in page) {
            if (record.collection.length == 0 || record.rkey.length == 0 || record.cid.length == 0) {
                continue;
            }
            CID *recordCID = [CID cidFromString:record.cid];
            if (!recordCID) {
                continue;
            }
            NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
            [mst put:key valueCID:recordCID subKey:nil];
        }

        if (page.count < pageSize) {
            break;
        }
        offset += pageSize;
    }

    return mst;
}

- (nullable NSArray<PDSDatabaseBlock *> *)changedMSTBlocksForMST:(MST *)mst
                                                     changedKeys:(NSArray<NSString *> *)changedKeys
                                                            rev:(NSString *)rev
                                                          error:(NSError **)error {
    if (!mst) {
        return @[];
    }

    NSMutableDictionary<NSString *, PDSDatabaseBlock *> *blocksByCID = [NSMutableDictionary dictionary];

    BOOL (^appendBlock)(CID *, NSData *) = ^BOOL(CID *cid, NSData *data) {
        NSString *cidString = cid.stringValue ?: @"";
        if (cidString.length == 0 || data.length == 0) {
            return YES;
        }
        if (blocksByCID[cidString]) {
            return YES;
        }
        PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
        block.cid = cid.bytes;
        block.blockData = data;
        block.size = (NSInteger)data.length;
        block.createdAt = [NSDate date];
        block.rev = rev;
        blocksByCID[cidString] = block;
        return YES;
    };

    CID *rootCID = mst.rootCID;
    NSData *rootData = [mst serializeToCBOR];
    if (!rootCID || rootData.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRecordService"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize MST root"}];
        }
        return nil;
    }
    appendBlock(rootCID, rootData);

    for (NSString *key in changedKeys ?: @[]) {
        if (key.length == 0) {
            continue;
        }
        NSArray<MSTNode *> *proofNodes = [mst getProofNodesForKey:key];
        for (MSTNode *node in proofNodes ?: @[]) {
            NSData *nodeData = [mst serializeNode:node];
            if (nodeData.length == 0) {
                continue;
            }
            CID *nodeCID = [CID cidWithDigest:[CID sha256Digest:nodeData] codec:0x71];
            if (!nodeCID) {
                continue;
            }
            appendBlock(nodeCID, nodeData);
        }
    }

    return [blocksByCID.allValues copy];
}

- (nullable NSDictionary<NSString *, NSString *> *)refreshRepoRootMetadataForDid:(NSString *)did
                                                                    preferredRev:(nullable NSString *)preferredRev
                                                              mutationCIDsByKey:(nullable NSDictionary<NSString *, id> *)mutationCIDsByKey
                                                             mutationBlocksByCID:(nullable NSDictionary<NSString *, NSData *> *)mutationBlocksByCID
                                                                     changedKeys:(nullable NSArray<NSString *> *)changedKeys
                                                                           error:(NSError **)error {
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        GZ_LOG_ERROR(@"refreshRepoRootMetadata: Failed to get store for DID %@", did);
        return nil;
    }

    // Load or retrieve MST — no serial queue needed
    // Per-DID serialization is guaranteed by GZPerDidWriteDispatcher
    // MSTCacheManager uses MSTAtomicReference for thread-safe access
    MST *mst = [[MSTCacheManager sharedManager] mstForDid:did];
    if (!mst) {
        // Try incremental loading from stored repo blocks first
        NSError *loadError = nil;
        mst = [self loadMSTFromRepoBlocksForDid:did store:store error:&loadError];
        if (!mst) {
            // Fallback: full rebuild from records
            mst = [self loadRepoMSTForDid:did store:store error:&loadError];
        }
        if (!mst) {
            if (error && loadError) *error = loadError;
            return nil;
        }
    }

    // Apply mutations
    [mutationCIDsByKey enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        (void)stop;
        if (key.length == 0) {
            return;
        }

        if ([obj isKindOfClass:[NSNull class]]) {
            [mst delete:key];
            return;
        }

        NSString *cidString = [obj isKindOfClass:[NSString class]] ? (NSString *)obj : nil;
        CID *recordCID = (cidString.length > 0) ? [CID cidFromString:cidString] : nil;
        if (!recordCID) {
            return;
        }
        [mst put:key valueCID:recordCID subKey:nil];
    }];

    CID *dataCID = mst.rootCID;
    if (!dataCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRecordService"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute updated MST root"}];
        }
        [[MSTCacheManager sharedManager] removeMSTForDid:did];
        dispatch_sync(self.statsCacheQueue, ^{
            [self.statsCacheByDid removeObjectForKey:did];
        });
        return nil;
    }

    // Invalidate stats cache on successful write
    dispatch_sync(self.statsCacheQueue, ^{
        [self.statsCacheByDid removeObjectForKey:did];
    });

    NSString *rev = [store latestMutationRevisionWithError:nil];
    if (rev.length == 0) {
        rev = preferredRev;
    }
    if (rev.length == 0) {
        rev = [TID tid].stringValue;
    }

    NSData *prevCommitBytes = [store getRepoRootForDid:did error:nil];
    CID *prevCommitCID = prevCommitBytes ? [CID cidFromBytes:prevCommitBytes] : nil;

    RepoCommit *commit = [RepoCommit createCommitWithDid:did
                                                    data:dataCID
                                                     rev:rev
                                                    prev:prevCommitCID];

    NSError *signError = nil;
    NSData *signature = [store signData:[commit serialize] error:&signError];
    if (!signature) {
        [[MSTCacheManager sharedManager] removeMSTForDid:did];
        if (error && signError) *error = signError;
        return nil;
    }
    commit.signature = signature;

    CID *commitCID = [commit computeCID];
    NSData *commitData = [commit serializeSigned];
    if (!commitCID || commitData.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRecordService"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize signed commit"}];
        }
        [[MSTCacheManager sharedManager] removeMSTForDid:did];
        return nil;
    }

    PDSDatabaseBlock *commitBlock = [[PDSDatabaseBlock alloc] init];
    commitBlock.cid = [commitCID bytes];
    commitBlock.blockData = commitData;
    commitBlock.size = commitData.length;
    commitBlock.createdAt = [NSDate date];
    commitBlock.rev = rev;

    NSError *mstBlocksError = nil;
    NSArray<PDSDatabaseBlock *> *mstBlocks = [self changedMSTBlocksForMST:mst
                                                                changedKeys:changedKeys ?: @[]
                                                                       rev:rev
                                                                     error:&mstBlocksError];
    if (!mstBlocks) {
        [[MSTCacheManager sharedManager] removeMSTForDid:did];
        if (error && mstBlocksError) *error = mstBlocksError;
        return nil;
    }

    NSMutableArray<PDSDatabaseBlock *> *blocksToPersist = [NSMutableArray arrayWithObject:commitBlock];
    [blocksToPersist addObjectsFromArray:mstBlocks];

    // Add mutation blocks (the actual records)
    [mutationBlocksByCID enumerateKeysAndObjectsUsingBlock:^(NSString *cidStr, NSData *data, BOOL *stop) {
        CID *cid = [CID cidFromString:cidStr];
        if (cid && data.length > 0) {
            PDSDatabaseBlock *recordBlock = [[PDSDatabaseBlock alloc] init];
            recordBlock.cid = [cid bytes];
            recordBlock.blockData = data;
            recordBlock.size = data.length;
            recordBlock.createdAt = [NSDate date];
            recordBlock.rev = rev;
            [blocksToPersist addObject:recordBlock];
        }
    }];

    __block BOOL updated = NO;
    NSError *txError = nil;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        if (![transactor putBlocks:blocksToPersist forDid:did error:blockError]) {
            return;
        }
        updated = [transactor updateRepoRoot:did rootCid:[commitCID bytes] rev:rev error:blockError];
    } error:&txError];

    if (!updated) {
        [[MSTCacheManager sharedManager] removeMSTForDid:did];
        if (error) {
            if (txError) *error = txError;
            else *error = [NSError errorWithDomain:@"PDSRecordService"
                                              code:-4
                                          userInfo:@{NSLocalizedDescriptionKey: @"Failed to update repository head"}];
        }
        return nil;
    }

    [[MSTCacheManager sharedManager] setMST:mst forDid:did];
    return @{
        @"cid": commitCID.stringValue ?: @"",
        @"rev": rev ?: @""
    };
}

@end
