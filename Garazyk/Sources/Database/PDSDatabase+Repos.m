// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Repos.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"

@implementation PDSDatabase (Repos)

#pragma mark - Repos

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    NSString *sql = @"INSERT INTO repos (owner_did, root_cid, collection_data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";
    NSArray *params = @[
        repo.ownerDid ?: [NSNull null],
        repo.rootCid ?: [NSNull null],
        repo.collectionData ?: [NSNull null],
        [NSDateFormatter atproto_stringFromDate:repo.createdAt],
        [NSDateFormatter atproto_stringFromDate:repo.updatedAt]
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error {
    NSString *sql = @"UPDATE repos SET root_cid = ?, updated_at = ? WHERE owner_did = ?";
    NSArray *params = @[
        rootCid ?: [NSNull null],
        [NSDateFormatter atproto_stringFromDate:[NSDate date]],
        ownerDid ?: [NSNull null]
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT * FROM repos WHERE owner_did = ?";
    NSArray *results = [self executeParameterizedQuery:sql params:@[did] modelClass:[PDSDatabaseRepo class] error:error];
    return results.firstObject;
}

- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error {
    NSString *sql = @"SELECT * FROM repos ORDER BY updated_at DESC";
    return [self executeParameterizedQuery:sql params:@[] modelClass:[PDSDatabaseRepo class] error:error] ?: @[];
}

- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error {
    NSString *sql = @"DELETE FROM repos WHERE owner_did = ?";
    return [self executeParameterizedUpdate:sql params:@[ownerDid] error:error];
}

- (PDSDatabaseRepo *)repoFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = [self valueFromStatement:stmt columnIndex:0];
    repo.rootCid = [self valueFromStatement:stmt columnIndex:1];
    repo.collectionData = [self valueFromStatement:stmt columnIndex:2];
    
    id createdAtStr = [self valueFromStatement:stmt columnIndex:3];
    if (createdAtStr) {
        repo.createdAt = [NSDateFormatter atproto_dateFromString:createdAtStr];
    }
    
    id updatedAtStr = [self valueFromStatement:stmt columnIndex:4];
    if (updatedAtStr) {
        repo.updatedAt = [NSDateFormatter atproto_dateFromString:updatedAtStr];
    }
    
    return repo;
}

@end
