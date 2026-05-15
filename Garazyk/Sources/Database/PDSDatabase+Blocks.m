// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Blocks.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (Blocks)

- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:block.cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_STATIC);
    [self bindData:block.blockData toStatement:stmt index:3];
    if (block.contentType) {
        sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_int64(stmt, 5, block.size);
    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:block.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:errorCode];
        }
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (blocks.count == 0) {
        result = YES;
        return;
    }

    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    for (PDSDatabaseBlock *block in blocks) {
        [self bindData:block.cid toStatement:stmt index:1];
        sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_STATIC);
        [self bindData:block.blockData toStatement:stmt index:3];
        if (block.contentType) {
            sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_STATIC);
        } else {
            sqlite3_bind_null(stmt, 4);
        }
        sqlite3_bind_int64(stmt, 5, block.size);
        sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:block.createdAt].UTF8String, -1, SQLITE_STATIC);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            if (error) {
                NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
                *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:errorCode];
            }
            result = NO;
            return;
        }

        sqlite3_reset(stmt);
    }

    result = YES;

    return;
    }];
    return result;
}

- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM blocks WHERE cid = ? AND repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    [self bindData:cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseBlock *block = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        block = [self blockFromStatement:stmt];
    }

    result = block;

    return;
    }];
    return result;
}

- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM blocks WHERE repo_did = ? ORDER BY created_at ASC LIMIT ? OFFSET ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, limit);
    sqlite3_bind_int64(stmt, 3, offset);

    NSMutableArray *blocks = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseBlock *block = [self blockFromStatement:stmt];
        if (block) {
            [blocks addObject:block];
        }
    }

    result = blocks;

    return;
    }];
    return result;
}

- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error {
    __block NSInteger result = 0;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT COUNT(*) FROM blocks WHERE repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = 0;
        return;
    }

    sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_STATIC);

    NSInteger count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }

    result = count;

    return;
    }];
    return result;
}

- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM blocks WHERE cid = ? AND repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
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

    block.size = sqlite3_column_int64(stmt, 4);
    block.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 5))];

    return block;
}

@end
