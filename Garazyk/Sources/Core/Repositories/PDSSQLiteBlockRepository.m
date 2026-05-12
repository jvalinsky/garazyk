// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSQLiteBlockRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"

@implementation PDSSQLiteBlockRepository {
    PDSDatabasePool *_databasePool;
}

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - PDSBlockRepository

- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:block.repoDid block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor putBlock:block forDid:block.repoDid error:blockError];
    } error:error];
    return success;
}

- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error {
    if (blocks.count == 0) return YES;

    __block BOOL success = YES;
    NSMutableDictionary<NSString *, NSMutableArray<PDSDatabaseBlock *> *> *grouped = [NSMutableDictionary dictionary];
    for (PDSDatabaseBlock *block in blocks) {
        if (!grouped[block.repoDid]) grouped[block.repoDid] = [NSMutableArray array];
        [grouped[block.repoDid] addObject:block];
    }

    for (NSString *did in grouped) {
        [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            if (![transactor putBlocks:grouped[did] forDid:did error:blockError]) {
                success = NO;
            }
        } error:error];
        if (!success) break;
    }
    return success;
}

- (nullable PDSDatabaseBlock *)blockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    __block PDSDatabaseBlock *block = nil;
    [_databasePool readWithDid:repoDid block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        NSData *blockData = [reader getBlockForCID:cid forDid:repoDid error:blockError];
        if (blockData) {
            block = [[PDSDatabaseBlock alloc] init];
            block.cid = cid;
            block.repoDid = repoDid;
            block.blockData = blockData;
            block.size = blockData.length;
        }
    } error:error];
    return block;
}

- (NSArray<PDSDatabaseBlock *> *)blocksForRepo:(NSString *)repoDid limit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    __block NSArray *blocks = @[];
    [_databasePool readWithDid:repoDid block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        blocks = [reader listBlocksForDid:repoDid limit:limit offset:offset error:blockError];
    } error:error];
    return blocks;
}

- (NSInteger)blockCountForRepo:(NSString *)repoDid error:(NSError **)error {
    __block NSInteger count = 0;
    [_databasePool readWithDid:repoDid block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        count = [reader getBlockCountForDid:repoDid error:blockError];
    } error:error];
    return count;
}

- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:repoDid block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor deleteBlock:cid forDid:repoDid error:blockError];
    } error:error];
    return success;
}

@end
