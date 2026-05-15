// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Accounts.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Debug/GZLogger.h"
#import "Core/NSDateFormatter+ATProto.h"

// Suppress -Wblock-capture-autoreleasing: all block captures in this file
// use dispatch_sync (via safeExecuteSync:), which completes before the
// method returns, so the autorelease pool is still valid.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

// Explicit column list for accounts table (prevents index-shift bugs
// when ALTER TABLE adds columns in different orders on migrated vs.
// fresh databases).
static NSString *const kAccountsColumns = @"did, handle, email, password_hash, "
    @"password_salt, access_jwt, refresh_jwt, created_at, updated_at, "
    @"tfa_enabled, tfa_secret, recovery_codes, invite_enabled, "
    @"age_assurance, age_verified_at, webauthn_enabled";

@implementation PDSDatabase (Accounts)

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    // Validate handle
    if (![ATProtoHandleValidator validateHandle:account.handle error:error]) {
        result = NO;
        return;
    }
    account.handle = [ATProtoHandleValidator normalizeHandle:account.handle];

    NSString *sql = @"INSERT INTO accounts (did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, status, deactivated_at, created_at, updated_at, tfa_enabled, tfa_secret, recovery_codes, invite_enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, account.did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, account.handle.UTF8String, -1, SQLITE_STATIC);
    if (account.email) {
        sqlite3_bind_text(stmt, 3, account.email.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    [self bindData:account.passwordHash toStatement:stmt index:4];
    [self bindData:account.passwordSalt toStatement:stmt index:5];
    [self bindData:account.accessJwt toStatement:stmt index:6];
    [self bindData:account.refreshJwt toStatement:stmt index:7];
    sqlite3_bind_text(stmt, 8, account.status.UTF8String ?: "active", -1, SQLITE_STATIC);
    if (account.deactivatedAt > 0) {
        sqlite3_bind_double(stmt, 9, account.deactivatedAt);
    } else {
        sqlite3_bind_null(stmt, 9);
    }
    sqlite3_bind_text(stmt, 10, [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSince1970:account.createdAt]].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 11, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);
    // 2FA columns (defaults)
    sqlite3_bind_int(stmt, 12, account.tfaEnabled ? 1 : 0);
    [self bindData:account.tfaSecret toStatement:stmt index:13];
    [self bindData:account.recoveryCodes toStatement:stmt index:14];
    sqlite3_bind_int(stmt, 15, account.inviteEnabled ? 1 : 0);

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

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    // Validate handle
    if (![ATProtoHandleValidator validateHandle:account.handle error:error]) {
        result = NO;
        return;
    }
    account.handle = [ATProtoHandleValidator normalizeHandle:account.handle];

    NSString *sql = @"UPDATE accounts SET handle = ?, email = ?, password_hash = ?, password_salt = ?, access_jwt = ?, refresh_jwt = ?, updated_at = ?, tfa_enabled = ?, tfa_secret = ?, recovery_codes = ?, invite_enabled = ? WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, account.handle.UTF8String, -1, SQLITE_STATIC);
    if (account.email) {
        sqlite3_bind_text(stmt, 2, account.email.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 2);
    }
    [self bindData:account.passwordHash toStatement:stmt index:3];
    [self bindData:account.passwordSalt toStatement:stmt index:4];
    [self bindData:account.accessJwt toStatement:stmt index:5];
    [self bindData:account.refreshJwt toStatement:stmt index:6];
    sqlite3_bind_text(stmt, 7, [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSince1970:account.updatedAt]].UTF8String, -1, SQLITE_STATIC);

    // 2FA
    sqlite3_bind_int(stmt, 8, account.tfaEnabled ? 1 : 0);
    [self bindData:account.tfaSecret toStatement:stmt index:9];
    [self bindData:account.recoveryCodes toStatement:stmt index:10];
    sqlite3_bind_int(stmt, 11, account.inviteEnabled ? 1 : 0);

    // WHERE did = ?
    sqlite3_bind_text(stmt, 12, account.did.UTF8String, -1, SQLITE_STATIC);

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

- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE did = ?", kAccountsColumns];
    NSArray *results = [self executeParameterizedQuery:sql params:@[did] modelClass:[PDSDatabaseAccount class] error:error];
    return results.firstObject;
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE handle = ?", kAccountsColumns];
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];
    NSArray *results = [self executeParameterizedQuery:sql params:@[normalizedHandle] modelClass:[PDSDatabaseAccount class] error:error];
    return results.firstObject;
}

- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error {
    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE email = ?", kAccountsColumns];
    NSArray *results = [self executeParameterizedQuery:sql params:@[email] modelClass:[PDSDatabaseAccount class] error:error];
    return results.firstObject;
}

- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE refresh_jwt = ?", kAccountsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    // Convert NSString refreshToken to NSData for BLOB comparison
    NSData *refreshTokenData = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    sqlite3_bind_blob(stmt, 1, refreshTokenData.bytes, (int)refreshTokenData.length, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    result = account;

    return;
    }];
    return result;
}



- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts ORDER BY created_at DESC", kAccountsColumns];
    return [self executeParameterizedQuery:sql params:@[] modelClass:[PDSDatabaseAccount class] error:error] ?: @[];
}

- (NSArray<PDSDatabaseAccount *> *)getAccountsWithLimit:(NSInteger)limit afterDid:(nullable NSString *)afterDid error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = afterDid
        ? [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE did > ? ORDER BY did ASC LIMIT ?", kAccountsColumns]
        : [NSString stringWithFormat:@"SELECT %@ FROM accounts ORDER BY did ASC LIMIT ?", kAccountsColumns];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    int idx = 1;
    if (afterDid) {
        sqlite3_bind_text(stmt, idx++, afterDid.UTF8String, -1, SQLITE_TRANSIENT);
    }
    sqlite3_bind_int64(stmt, idx, (sqlite3_int64)limit);

    NSMutableArray *accounts = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseAccount *account = [self accountFromStatement:stmt];
        if (account) {
            [accounts addObject:account];
        }
    }

    result = accounts;

    return;
    }];
    return result;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM accounts WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

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

- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @((const char *)sqlite3_column_text(stmt, 0));
    account.handle = @((const char *)sqlite3_column_text(stmt, 1));

    const char *emailText = (const char *)sqlite3_column_text(stmt, 2);
    if (emailText) {
        account.email = @(emailText);
    }

    int blobBytes = sqlite3_column_bytes(stmt, 3);
    if (blobBytes > 0) {
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:blobBytes];
    }

    blobBytes = sqlite3_column_bytes(stmt, 4);
    if (blobBytes > 0) {
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:blobBytes];
    }

    blobBytes = sqlite3_column_bytes(stmt, 5);
    if (blobBytes > 0) {
        account.accessJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 5) length:blobBytes];
    }

    blobBytes = sqlite3_column_bytes(stmt, 6);
    if (blobBytes > 0) {
        account.refreshJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 6) length:blobBytes];
    }

    const char *statusText = (const char *)sqlite3_column_text(stmt, 7);
    if (statusText) {
        account.status = @(statusText);
    } else {
        account.status = @"active";
    }

    if (sqlite3_column_type(stmt, 8) != SQLITE_NULL) {
        account.deactivatedAt = sqlite3_column_double(stmt, 8);
    }

    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 9);
    if (createdAtText) {
        account.createdAt = [NSDateFormatter atproto_dateFromString:@(createdAtText)].timeIntervalSince1970;
    }

    const char *updatedAtText = (const char *)sqlite3_column_text(stmt, 10);
    if (updatedAtText) {
        account.updatedAt = [NSDateFormatter atproto_dateFromString:@(updatedAtText)].timeIntervalSince1970;
    }

    // 2FA
    account.tfaEnabled = (sqlite3_column_int(stmt, 11) != 0);

    blobBytes = sqlite3_column_bytes(stmt, 12);
    if (blobBytes > 0) {
        account.tfaSecret = [NSData dataWithBytes:sqlite3_column_blob(stmt, 12) length:blobBytes];
    }

    blobBytes = sqlite3_column_bytes(stmt, 13);
    if (blobBytes > 0) {
        account.recoveryCodes = [NSData dataWithBytes:sqlite3_column_blob(stmt, 13) length:blobBytes];
    }

    account.inviteEnabled = (sqlite3_column_int(stmt, 14) != 0);

    // Age assurance (columns 15, 16)
    const char *ageAssuranceText = (const char *)sqlite3_column_text(stmt, 15);
    if (ageAssuranceText) {
        account.ageAssurance = @(ageAssuranceText);
    }

    const char *ageVerifiedAtText = (const char *)sqlite3_column_text(stmt, 16);
    if (ageVerifiedAtText) {
        account.ageVerifiedAt = @(ageVerifiedAtText);
    }

    account.webauthnEnabled = (sqlite3_column_int(stmt, 17) != 0);

    return account;
}

@end
