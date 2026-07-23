// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService+Commit.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Core/CID.h"
#import "Core/Repositories/PDSBlockRepository.h"
#import "Core/Repositories/PDSRepoRepository.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"

@implementation PDSRepositoryService (Commit)

#pragma mark - Repo Root

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    GZ_LOG_DB_DEBUG(@"Looking up repo root for DID: %@", did);

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        GZ_LOG_DB_DEBUG(@"storeForDid returned nil for: %@", did);
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

#pragma mark - Head Info

- (nullable NSDictionary *)headInfoForDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        return nil;
    }

    // Read the stored signed head commit CID and rev from repo_root.
    // This is the fast path from getLatestCommitForDid, without the
    // self-healing fallback that loads all records and rebuilds the MST.
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

    // No signed head commit exists — return nil (caller should skip).
    return nil;
}

#pragma mark - Latest Commit

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
    if (![self prepareRepoExportForDid:did
                                 since:nil
                                 store:&store
                                   mst:&mst
                             commitCID:&commitCID
                           commitBlock:&commitBlock
                        noChangesSince:&noChangesSince
                        includeFullMST:&includeFullMST
                        changedMSTKeys:nil
                       recordCIDStrings:nil
                            recordByCID:nil
                    materializedBlocks:nil
                                 error:error]) {
        return nil;
    }

    NSString *rev = [store getRepoRevisionForDid:did error:nil] ?: @"";
    return @{@"cid": commitCID.stringValue ?: @"", @"rev": rev};
}

@end
