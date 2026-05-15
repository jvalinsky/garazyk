// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Blobs.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"

// Suppress -Wblock-capture-autoreleasing: all block captures in this file
// use dispatch_sync (via safeExecuteSync:), which completes before the
// method returns, so the autorelease pool is still valid.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (Blobs)

#pragma mark - Blobs

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO blobs (cid, did, mimeType, size, created_at) VALUES (?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:blob.cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, blob.did.UTF8String, -1, SQLITE_STATIC);
    if (blob.mimeType) {
        sqlite3_bind_text(stmt, 3, blob.mimeType.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    sqlite3_bind_int64(stmt, 4, blob.size);
    sqlite3_bind_text(stmt, 5, [self iso8601StringFromDate:blob.createdAt].UTF8String, -1, SQLITE_STATIC);

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

- (nullable PDSDatabaseBlob *)getBlobWithCid:(NSData *)cid error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM blobs WHERE cid = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    [self bindData:cid toStatement:stmt index:1];

    PDSDatabaseBlob *blob = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        blob = [self blobFromStatement:stmt];
    }

    result = blob;

    return;
    }];
    return result;
}

- (NSArray<PDSDatabaseBlob *> *)getBlobsForDid:(NSString *)did limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM blobs WHERE did = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, limit);
    sqlite3_bind_int64(stmt, 3, offset);

    NSMutableArray *blobs = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseBlob *blob = [self blobFromStatement:stmt];
        if (blob) {
            [blobs addObject:blob];
        }
    }

    result = blobs;

    return;
    }];
    return result;
}

- (NSInteger)getBlobCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger result = 0;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT COUNT(*) FROM blobs WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = 0;
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    NSInteger count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }

    result = count;

    return;
    }];
    return result;
}

- (BOOL)deleteBlob:(NSData *)cid error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM blobs WHERE cid = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:cid toStatement:stmt index:1];

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

- (PDSDatabaseBlob *)blobFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];

    int blobBytes = sqlite3_column_bytes(stmt, 0);
    if (blobBytes > 0) {
        blob.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:blobBytes];
    }

    blob.did = @((const char *)sqlite3_column_text(stmt, 1));

    const char *mimeTypeText = (const char *)sqlite3_column_text(stmt, 2);
    if (mimeTypeText) {
        blob.mimeType = @(mimeTypeText);
    }

    blob.size = sqlite3_column_int64(stmt, 3);
    blob.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 4))];

    return blob;
}

- (void)bindData:(nullable NSData *)data toStatement:(sqlite3_stmt *)stmt index:(int)index {
    [self safeExecuteSync:^{

    if (data && data.length > 0) {
        sqlite3_bind_blob(stmt, index, data.bytes, (int)data.length, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, index);
    }
    }];
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    if (!date) return @"";
    return [NSDateFormatter atproto_stringFromDate:date];
}

- (NSDate *)dateFromIso8601String:(NSString *)string {
    if (!string) return nil;
    return [NSDateFormatter atproto_dateFromString:string];
}

- (NSDate *)dateFromISO8601String:(NSString *)string {
    return [[NSDateFormatter atproto_iso8601Formatter] dateFromString:string];
}

@end
