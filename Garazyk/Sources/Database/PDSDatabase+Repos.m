// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Repos.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Debug/GZLogger.h"

@implementation PDSDatabase (Repos)

#pragma mark - Repos

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT INTO repos (owner_did, root_cid, collection_data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, repo.ownerDid.UTF8String, -1, SQLITE_STATIC);
    [self bindData:repo.rootCid toStatement:stmt index:2];
    [self bindData:repo.collectionData toStatement:stmt index:3];
    sqlite3_bind_text(stmt, 4, [self iso8601StringFromDate:repo.createdAt].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, [self iso8601StringFromDate:repo.updatedAt].UTF8String, -1, SQLITE_STATIC);

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

- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"UPDATE repos SET root_cid = ?, updated_at = ? WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:rootCid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, ownerDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM repos WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseRepo *repo = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        repo = [self repoFromStatement:stmt];
    }

    result = repo;

    return;
    }];
    return result;
}

- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM repos ORDER BY updated_at DESC";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    NSMutableArray *repos = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRepo *repo = [self repoFromStatement:stmt];
        if (repo) {
            [repos addObject:repo];
        }
    }

    result = repos;

    return;
    }];
    return result;
}

- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM repos WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, ownerDid.UTF8String, -1, SQLITE_STATIC);

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

- (PDSDatabaseRepo *)repoFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = @((const char *)sqlite3_column_text(stmt, 0));
    
    int blobBytes = sqlite3_column_bytes(stmt, 1);
    if (blobBytes > 0) {
        repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 1) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 2);
    if (blobBytes > 0) {
        repo.collectionData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
    }
    
    repo.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 3))];
    repo.updatedAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 4))];
    
    return repo;
}

@end
