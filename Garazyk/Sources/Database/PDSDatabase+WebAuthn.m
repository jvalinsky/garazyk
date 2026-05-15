// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+WebAuthn.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (WebAuthn)

- (BOOL)storeWebAuthnCredential:(NSDictionary *)credential forDid:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO webauthn_credentials (id, account_did, credential_id, public_key_cose, sign_count, aaguid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    NSString *credentialId = [[NSUUID UUID] UUIDString];
    sqlite3_bind_text(stmt, 1, credentialId.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_STATIC);
    [self bindData:credential[@"credentialId"] toStatement:stmt index:3];
    [self bindData:credential[@"publicKey"] toStatement:stmt index:4];
    sqlite3_bind_int(stmt, 5, [credential[@"signCount"] intValue]);
    [self bindData:credential[@"aaguid"] toStatement:stmt index:6];
    sqlite3_bind_double(stmt, 7, [[NSDate date] timeIntervalSince1970]);

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

- (NSArray<NSDictionary *> *)getWebAuthnCredentialsForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM webauthn_credentials WHERE account_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    NSMutableArray *credentials = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *cred = [NSMutableDictionary dictionary];
        cred[@"id"] = @((const char *)sqlite3_column_text(stmt, 0));
        cred[@"accountDid"] = @((const char *)sqlite3_column_text(stmt, 1));

        int blobBytes = sqlite3_column_bytes(stmt, 2);
        if (blobBytes > 0) {
            cred[@"credentialId"] = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
        }
        blobBytes = sqlite3_column_bytes(stmt, 3);
        if (blobBytes > 0) {
            cred[@"publicKey"] = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:blobBytes];
        }
        cred[@"signCount"] = @(sqlite3_column_int(stmt, 4));

        blobBytes = sqlite3_column_bytes(stmt, 5);
        if (blobBytes > 0) {
            cred[@"aaguid"] = [NSData dataWithBytes:sqlite3_column_blob(stmt, 5) length:blobBytes];
        }
        cred[@"createdAt"] = @((const char *)sqlite3_column_text(stmt, 6));

        [credentials addObject:cred];
    }

    result = credentials;

    return;
    }];
    return result;
}

- (BOOL)deleteWebAuthnCredential:(NSData *)credentialId forDid:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM webauthn_credentials WHERE credential_id = ? AND account_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    [self bindData:credentialId toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_STATIC);

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

- (BOOL)updateWebAuthnCredentialSignCount:(NSData *)credentialId forDid:(NSString *)did signCount:(uint32_t)signCount error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"UPDATE webauthn_credentials SET sign_count = ? WHERE credential_id = ? AND account_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_int(stmt, 1, signCount);
    [self bindData:credentialId toStatement:stmt index:2];
    sqlite3_bind_text(stmt, 3, did.UTF8String, -1, SQLITE_STATIC);

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

@end
