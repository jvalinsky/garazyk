// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSQLiteRepoRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"

@implementation PDSSQLiteRepoRepository {
    PDSDatabasePool *_databasePool;
}

- (instancetype)initWithServicePool:(PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - PDSRepoRepository

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:repo.ownerDid block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor createRepo:repo error:blockError];
    } error:error];
    return success;
}

- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:ownerDid block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor updateRepoRoot:ownerDid rootCid:rootCid error:blockError];
    } error:error];
    return success;
}

- (nullable PDSDatabaseRepo *)repoForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseRepo *repo = nil;
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        repo = [reader getRepoForDid:did error:blockError];
    } error:error];
    return repo;
}

- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:ownerDid block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor deleteRepo:ownerDid error:blockError];
    } error:error];
    return success;
}

- (nullable NSArray<PDSDatabaseRepo *> *)allReposWithError:(NSError **)error {
    return [_databasePool getAllReposWithError:error];
}

@end
