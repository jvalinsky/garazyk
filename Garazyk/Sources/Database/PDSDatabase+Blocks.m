// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Blocks.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (Blocks)

- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    NSArray *params = @[
        block.cid ?: [NSNull null],
        block.repoDid ?: [NSNull null],
        block.blockData ?: [NSNull null],
        block.contentType ?: [NSNull null],
        @(block.size),
        [NSDateFormatter atproto_stringFromDate:block.createdAt]
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error {
    if (blocks.count == 0) return YES;
    __block BOOL result = NO;
    [self safeExecuteSync:^{
        NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
            return;
        }

        for (PDSDatabaseBlock *block in blocks) {
            ATProtoDBBindValue(stmt, 1, block.cid);
            ATProtoDBBindValue(stmt, 2, block.repoDid);
            ATProtoDBBindValue(stmt, 3, block.blockData);
            ATProtoDBBindValue(stmt, 4, block.contentType);
            ATProtoDBBindValue(stmt, 5, @(block.size));
            ATProtoDBBindValue(stmt, 6, [NSDateFormatter atproto_stringFromDate:block.createdAt]);

            if (sqlite3_step(stmt) != SQLITE_DONE) {
                if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
                return;
            }
            sqlite3_reset(stmt);
        }
        result = YES;
    }];
    return result;
}

- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blocks WHERE cid = ? AND repo_did = ?";
    NSArray *results = [self executeParameterizedQuery:sql params:@[cid, repoDid] modelClass:[PDSDatabaseBlock class] error:error];
    return results.firstObject;
}

- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blocks WHERE repo_did = ? ORDER BY created_at ASC LIMIT ? OFFSET ?";
    return [self executeParameterizedQuery:sql params:@[repoDid, @(limit), @(offset)] modelClass:[PDSDatabaseBlock class] error:error] ?: @[];
}

- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error {
    __block NSInteger result = 0;
    [self safeExecuteSync:^{
        NSString *sql = @"SELECT COUNT(*) FROM blocks WHERE repo_did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
            ATProtoDBBindValue(stmt, 1, repoDid);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                result = [ATProtoDBColumnValue(stmt, 0) integerValue];
            }
        }
    }];
    return result;
}

- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    NSString *sql = @"DELETE FROM blocks WHERE cid = ? AND repo_did = ?";
    return [self executeParameterizedUpdate:sql params:@[cid, repoDid] error:error];
}

- (PDSDatabaseBlock *)blockFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = [self valueFromStatement:stmt columnIndex:0];
    block.repoDid = [self valueFromStatement:stmt columnIndex:1];
    block.blockData = [self valueFromStatement:stmt columnIndex:2];
    block.contentType = [self valueFromStatement:stmt columnIndex:3];
    block.size = [[self valueFromStatement:stmt columnIndex:4] longLongValue];
    
    id createdAtStr = [self valueFromStatement:stmt columnIndex:5];
    if (createdAtStr) {
        block.createdAt = [[NSDateFormatter atproto_iso8601Formatter] dateFromString:createdAtStr];
    }
    return block;
}

@end
