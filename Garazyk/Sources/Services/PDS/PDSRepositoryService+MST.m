// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService+MST.h"
#import "Repository/MST.h"
#import "Core/CID.h"
#import "Repository/MSTCacheManager.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Core/Repositories/PDSBlockRepository.h"
#import "Core/Repositories/PDSRepoRepository.h"

@implementation PDSRepositoryService (ATProtoMST)

#pragma mark - ATProtoMST Loading

- (nullable ATProtoMST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    ATProtoMST *cached = [[ATProtoMSTCacheManager sharedManager] mstForDid:did];
    if (cached) return cached;

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) return nil;

    return [self loadMSTForDid:did store:store error:error];
}

- (nullable ATProtoMST *)loadMSTForDid:(NSString *)did store:(PDSActorStore *)store error:(NSError **)error {
    // Check shared cache first
    ATProtoMST *cached = [[ATProtoMSTCacheManager sharedManager] mstForDid:did];
    if (cached) return cached;

    // Try incremental loading from repo blocks
    ATProtoMST *mst = [self loadMSTFromRepoBlocksForDid:did store:store error:nil];
    if (mst) {
        [[ATProtoMSTCacheManager sharedManager] setMST:mst forDid:did];
        return mst;
    }

    // Fallback: full rebuild from records
    NSArray<PDSDatabaseRecord *> *records = [self loadAllRecordsForStore:store did:did error:error];
    if (!records && error && *error) {
        return nil;
    }
    mst = [self mstFromRecords:records ?: @[]];
    if (mst) {
        [[ATProtoMSTCacheManager sharedManager] setMST:mst forDid:did];
    }
    return mst;
}

- (nullable ATProtoMST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error {
    return [ATProtoMSTCacheManager loadMSTFromRepoBlocksForDid:did store:store error:error];
}

#pragma mark - ATProtoMST Update

- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable ATProtoCID *)cid error:(NSError **)error {
    ATProtoMST *mst = [self loadMSTForDid:did error:error];
    if (!mst) return NO;
    
    if (cid) {
        [mst put:key valueCID:cid subKey:nil];
    } else {
        [mst delete:key];
    }
    
    ATProtoCID *repoRoot = mst.rootCID;
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

#pragma mark - ATProtoMST Construction

- (ATProtoMST *)mstFromRecords:(NSArray<PDSDatabaseRecord *> *)records {
    ATProtoMST *mst = [[ATProtoMST alloc] init];
    for (PDSDatabaseRecord *record in records) {
        if (record.cid.length == 0 || record.collection.length == 0 || record.rkey.length == 0) {
            continue;
        }

        ATProtoCID *cid = [ATProtoCID cidFromString:record.cid];
        if (!cid) {
            continue;
        }

        NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
        [mst put:key valueCID:cid subKey:nil];
    }
    return mst;
}

@end
