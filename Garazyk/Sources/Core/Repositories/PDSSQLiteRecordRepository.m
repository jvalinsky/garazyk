// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSQLiteRecordRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"

@implementation PDSSQLiteRecordRepository {
    PDSDatabasePool *_databasePool;
}

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - PDSRecordRepository

- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:record.did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor putRecord:record forDid:record.did error:blockError];
    } error:error];
    return success;
}

- (nullable PDSDatabaseRecord *)recordForUri:(NSString *)uri did:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseRecord *record = nil;
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        record = [reader getRecord:uri forDid:did error:blockError];
    } error:error];
    return record;
}

- (NSArray<PDSDatabaseRecord *> *)recordsForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error {
    __block NSArray *records = @[];
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        // limit:0 usually means no limit in our app logic or high limit
        records = [reader listRecordsForDid:did collection:collection limit:1000 offset:0 error:blockError];
    } error:error];
    return records;
}

- (BOOL)deleteRecord:(NSString *)uri did:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor deleteRecord:uri forDid:did error:blockError];
    } error:error];
    return success;
}

@end
