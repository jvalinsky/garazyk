// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSQLiteRepoRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"
#import "Core/NSDateFormatter+ATProto.h"
#import <sqlite3.h>

@implementation PDSSQLiteRepoRepository {
    PDSDatabasePool *_servicePool;
}

- (instancetype)initWithServicePool:(PDSDatabasePool *)servicePool {
    self = [super init];
    if (self) {
        _servicePool = servicePool;
    }
    return self;
}

#pragma mark - PDSRepoRepository

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    __block BOOL success = NO;
    [_servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO repos (owner_did, root_cid, created_at, updated_at) VALUES (?, ?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, repo.ownerDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 2, repo.rootCid.bytes, (int)repo.rootCid.length, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, repo.createdAt.timeIntervalSince1970);
        sqlite3_bind_double(stmt, 4, repo.updatedAt.timeIntervalSince1970);

        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        } else {
            if (blockError) {
                *blockError = [NSError errorWithDomain:@"PDSSQLiteRepoRepository" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to insert repo"}];
            }
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error {
    __block BOOL success = NO;
    [_servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"UPDATE repos SET root_cid = ?, updated_at = ? WHERE owner_did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_blob(stmt, 1, rootCid.bytes, (int)rootCid.length, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, [NSDate date].timeIntervalSince1970);
        sqlite3_bind_text(stmt, 3, ownerDid.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (nullable PDSDatabaseRepo *)repoForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseRepo *repo = nil;
    [_servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM repos WHERE owner_did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            repo = [self repoFromStatement:stmt];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return repo;
}

- (nullable NSArray<PDSDatabaseRepo *> *)allReposWithError:(NSError **)error {
    __block NSMutableArray<PDSDatabaseRepo *> *repos = [NSMutableArray array];
    [_servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM repos";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PDSDatabaseRepo *repo = [self repoFromStatement:stmt];
            if (repo) [repos addObject:repo];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return [repos copy];
}

- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error {
    __block BOOL success = NO;
    [_servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM repos WHERE owner_did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, ownerDid.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (nullable PDSDatabaseRepo *)repoFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = @((const char *)sqlite3_column_text(stmt, 0));
    
    int blobBytes = sqlite3_column_bytes(stmt, 1);
    if (blobBytes > 0) {
        repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 1) length:blobBytes];
    }
    
    // Column 2 is collectionData in PDSDatabase.m but maybe not here?
    // Let's check Schema.h for 'repos' table columns.
    // owner_did (0), root_cid (1), created_at (2), updated_at (3)
    
    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 2);
    if (createdAtText) {
        repo.createdAt = [NSDateFormatter atproto_dateFromString:@(createdAtText)];
    }
    
    const char *updatedAtText = (const char *)sqlite3_column_text(stmt, 3);
    if (updatedAtText) {
        repo.updatedAt = [NSDateFormatter atproto_dateFromString:@(updatedAtText)];
    }
    
    return repo;
}

@end
