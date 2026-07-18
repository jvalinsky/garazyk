// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Blobs.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"

// Suppress -Wblock-capture-autoreleasing: all block captures in this file
// use dispatch_sync (via safeExecuteSync:), which completes before the
// method returns, so the autorelease pool is still valid.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (Blobs)

#pragma mark - Blobs

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error {
    NSString *sql = @"INSERT INTO blobs (cid, did, mimeType, size, created_at) VALUES (?, ?, ?, ?, ?) "
                     @"ON CONFLICT(cid) DO UPDATE SET did=excluded.did, mimeType=excluded.mimeType, "
                     @"size=excluded.size, created_at=excluded.created_at";
    NSArray *params = @[
        blob.cid ?: [NSNull null],
        blob.did ?: [NSNull null],
        blob.mimeType ?: [NSNull null],
        @(blob.size),
        [NSDateFormatter atproto_stringFromDate:blob.createdAt]
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (nullable PDSDatabaseBlob *)getBlobWithCid:(NSData *)cid error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blobs WHERE cid = ?";
    NSArray *results = [self executeParameterizedQuery:sql params:@[cid] modelClass:[PDSDatabaseBlob class] error:error];
    return results.firstObject;
}

- (NSArray<PDSDatabaseBlob *> *)getBlobsForDid:(NSString *)did limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blobs WHERE did = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";
    return [self executeParameterizedQuery:sql params:@[did, @(limit), @(offset)] modelClass:[PDSDatabaseBlob class] error:error] ?: @[];
}

- (NSInteger)getBlobCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger result = 0;
    [self safeExecuteSync:^{
        NSString *sql = @"SELECT COUNT(*) FROM blobs WHERE did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
            ATProtoDBBindValue(stmt, 1, did);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                result = [ATProtoDBColumnValue(stmt, 0) integerValue];
            }
        }
    }];
    return result;
}

- (BOOL)deleteBlob:(NSData *)cid error:(NSError **)error {
    NSString *sql = @"DELETE FROM blobs WHERE cid = ?";
    return [self executeParameterizedUpdate:sql params:@[cid] error:error];
}

- (PDSDatabaseBlob *)blobFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [self valueFromStatement:stmt columnIndex:0];
    blob.did = [self valueFromStatement:stmt columnIndex:1];
    blob.mimeType = [self valueFromStatement:stmt columnIndex:2];
    blob.size = [[self valueFromStatement:stmt columnIndex:3] longLongValue];
    
    id createdAtStr = [self valueFromStatement:stmt columnIndex:4];
    if (createdAtStr) {
        blob.createdAt = [[NSDateFormatter atproto_iso8601Formatter] dateFromString:createdAtStr];
    }
    return blob;
}

@end
