// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSQLiteBlockRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"
#import "Core/NSDateFormatter+ATProto.h"
#import <sqlite3.h>

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
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at, rev) VALUES (?, ?, ?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_blob(stmt, 1, block.cid.bytes, (int)block.cid.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 3, block.blockData.bytes, (int)block.blockData.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 5, (int)block.size);
        sqlite3_bind_double(stmt, 6, block.createdAt.timeIntervalSince1970);
        sqlite3_bind_text(stmt, 7, block.rev.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error {
    if (blocks.count == 0) return YES;
    
    // Group blocks by DID to use one transaction per database
    NSMutableDictionary<NSString *, NSMutableArray<PDSDatabaseBlock *> *> *grouped = [NSMutableDictionary dictionary];
    for (PDSDatabaseBlock *block in blocks) {
        if (!grouped[block.repoDid]) grouped[block.repoDid] = [NSMutableArray array];
        [grouped[block.repoDid] addObject:block];
    }

    __block BOOL allSuccess = YES;
    for (NSString *did in grouped) {
        [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            PDSActorStore *store = (PDSActorStore *)transactor;
            NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at, rev) VALUES (?, ?, ?, ?, ?, ?, ?)";
            sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
            if (!stmt) {
                allSuccess = NO;
                return;
            }

            for (PDSDatabaseBlock *block in grouped[did]) {
                sqlite3_reset(stmt);
                sqlite3_bind_blob(stmt, 1, block.cid.bytes, (int)block.cid.length, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_blob(stmt, 3, block.blockData.bytes, (int)block.blockData.length, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 5, (int)block.size);
                sqlite3_bind_double(stmt, 6, block.createdAt.timeIntervalSince1970);
                sqlite3_bind_text(stmt, 7, block.rev.UTF8String, -1, SQLITE_TRANSIENT);

                if (sqlite3_step(stmt) != SQLITE_DONE) {
                    allSuccess = NO;
                    break;
                }
            }
            [store finalizeStatement:stmt];
        } error:error];
        if (!allSuccess) break;
    }
    return allSuccess;
}

- (nullable PDSDatabaseBlock *)blockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    __block PDSDatabaseBlock *block = nil;
    [_databasePool readWithDid:repoDid block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM blocks WHERE cid = ? AND repo_did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            block = [self blockFromStatement:stmt];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return block;
}

- (nullable NSArray<PDSDatabaseBlock *> *)blocksForRepo:(NSString *)repoDid 
                                                  limit:(NSInteger)limit 
                                                 offset:(NSInteger)offset 
                                                  error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseBlock *> *blocks = [NSMutableArray array];
    [_databasePool readWithDid:repoDid block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM blocks WHERE repo_did = ? LIMIT ? OFFSET ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, (int)limit);
        sqlite3_bind_int(stmt, 3, (int)offset);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PDSDatabaseBlock *block = [self blockFromStatement:stmt];
            if (block) [blocks addObject:block];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return [blocks copy];
}

- (NSInteger)blockCountForRepo:(NSString *)repoDid error:(NSError **)error {
    __block NSInteger count = 0;
    [_databasePool readWithDid:repoDid block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT COUNT(*) FROM blocks WHERE repo_did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int(stmt, 0);
        }
        [store finalizeStatement:stmt];
    } error:error];
    return count;
}

- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:repoDid block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM blocks WHERE cid = ? AND repo_did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (PDSDatabaseBlock *)blockFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    
    int blobBytes = sqlite3_column_bytes(stmt, 0);
    if (blobBytes > 0) {
        block.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:blobBytes];
    }
    
    block.repoDid = @((const char *)sqlite3_column_text(stmt, 1));
    
    blobBytes = sqlite3_column_bytes(stmt, 2);
    if (blobBytes > 0) {
        block.blockData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
    }
    
    const char *contentTypeText = (const char *)sqlite3_column_text(stmt, 3);
    if (contentTypeText) {
        block.contentType = @(contentTypeText);
    }
    
    block.size = sqlite3_column_int(stmt, 4);
    
    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 5);
    if (createdAtText) {
        block.createdAt = [NSDateFormatter atproto_dateFromString:@(createdAtText)];
    }
    
    const char *revText = (const char *)sqlite3_column_text(stmt, 6);
    if (revText) {
        block.rev = @(revText);
    }
    
    return block;
}

@end
