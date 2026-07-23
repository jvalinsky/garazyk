// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService+RepoInit.h"
#import "Repository/MST.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Repository/RepoCommit.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"

@implementation PDSRepositoryService (RepoInit)

#pragma mark - Repository Initialization

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

#pragma mark - Force Re-initialization

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

    GZ_LOG_SERVICE_DEBUG(@"Clearing repo_root for DID: %@", did);

    if (![store clearRepoRootWithError:error]) {
        GZ_LOG_SERVICE_ERROR(@"Failed to clear repo_root: %@", error ? *error : @"unknown");
        return NO;
    }

    return [self initializeRepoForDid:did error:error];
}

@end
