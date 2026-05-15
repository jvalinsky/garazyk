// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Records.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

static NSString *const kRecordsColumns = @"uri, did, collection, rkey, cid, "
    @"value, subject_did, created_at, indexed_at";

@implementation PDSDatabase (Records)

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM records WHERE uri = ?", kRecordsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseRecord *record = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        record = [self recordFromStatement:stmt];
    }

    result = record;

    return;
    }];
    return result;
}

- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, record.uri.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, record.did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, record.collection.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, record.rkey.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, record.cid.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:record.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        GZ_LOG_DB_ERROR(@"Failed to save record: %s (SQLite code: %d, URI: %@)",
                         sqlite3_errmsg(self.db), rc, record.uri);
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

- (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT %@ FROM records WHERE did = ?", kRecordsColumns];
    NSMutableArray *params = [NSMutableArray arrayWithObject:did];

    if (collection.length > 0) {
        [sql appendString:@" AND collection = ?"];
        [params addObject:collection];
    }

    [sql appendString:@" ORDER BY created_at DESC"];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);
    if (collection.length > 0) {
        sqlite3_bind_text(stmt, 2, collection.UTF8String, -1, SQLITE_STATIC);
    }

    NSMutableArray *records = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRecord *record = [self recordFromStatement:stmt];
        if (record) {
            [records addObject:record];
        }
    }

    result = records;

    return;
    }];
    return result;
}

- (PDSDatabaseRecord *)recordFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = @((const char *)sqlite3_column_text(stmt, 0));
    record.did = @((const char *)sqlite3_column_text(stmt, 1));
    record.collection = @((const char *)sqlite3_column_text(stmt, 2));
    record.rkey = @((const char *)sqlite3_column_text(stmt, 3));
    record.cid = @((const char *)sqlite3_column_text(stmt, 4));

    const char *valueText = (const char *)sqlite3_column_text(stmt, 5);
    if (valueText) {
        record.value = @(valueText);
    }

    const char *revText = (const char *)sqlite3_column_text(stmt, 6);
    if (revText) {
        record.rev = @(revText);
    }

    const char *subjectDidText = (const char *)sqlite3_column_text(stmt, 7);
    if (subjectDidText) {
        record.subjectDid = @(subjectDidText);
    }

    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 8);
    if (createdAtText) {
        record.createdAt = [[NSDateFormatter atproto_iso8601Formatter] dateFromString:@(createdAtText)];
    }

    const char *indexedAtText = (const char *)sqlite3_column_text(stmt, 9);
    if (indexedAtText) {
        record.indexedAt = [[NSDateFormatter atproto_iso8601Formatter] dateFromString:@(indexedAtText)];
    }

    return record;
}

@end
