// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Accounts.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
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
    @"password_salt, access_jwt, refresh_jwt, status, deactivated_at, created_at, updated_at, "
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

    ATProtoDBBindValue(stmt, 1, account.did);
    ATProtoDBBindValue(stmt, 2, account.handle);
    ATProtoDBBindValue(stmt, 3, account.email);
    ATProtoDBBindValue(stmt, 4, account.passwordHash);
    ATProtoDBBindValue(stmt, 5, account.passwordSalt);
    ATProtoDBBindValue(stmt, 6, account.accessJwt);
    ATProtoDBBindValue(stmt, 7, account.refreshJwt);
    ATProtoDBBindValue(stmt, 8, account.status ?: @"active");
    ATProtoDBBindValue(stmt, 9, account.deactivatedAt > 0 ? @(account.deactivatedAt) : nil);
    ATProtoDBBindValue(stmt, 10, [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:account.createdAt]]);
    ATProtoDBBindValue(stmt, 11, [NSDateFormatter atproto_stringFromDate:[NSDate date]]);
    ATProtoDBBindValue(stmt, 12, @(account.tfaEnabled));
    ATProtoDBBindValue(stmt, 13, account.tfaSecret);
    ATProtoDBBindValue(stmt, 14, account.recoveryCodes);
    ATProtoDBBindValue(stmt, 15, @(account.inviteEnabled));

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

    ATProtoDBBindValue(stmt, 1, account.handle);
    ATProtoDBBindValue(stmt, 2, account.email);
    ATProtoDBBindValue(stmt, 3, account.passwordHash);
    ATProtoDBBindValue(stmt, 4, account.passwordSalt);
    ATProtoDBBindValue(stmt, 5, account.accessJwt);
    ATProtoDBBindValue(stmt, 6, account.refreshJwt);
    ATProtoDBBindValue(stmt, 7, [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:account.updatedAt]]);

    // 2FA
    ATProtoDBBindValue(stmt, 8, @(account.tfaEnabled));
    ATProtoDBBindValue(stmt, 9, account.tfaSecret);
    ATProtoDBBindValue(stmt, 10, account.recoveryCodes);
    ATProtoDBBindValue(stmt, 11, @(account.inviteEnabled));

    // WHERE did = ?
    ATProtoDBBindValue(stmt, 12, account.did);

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

    // refresh_jwt is stored as BLOB in SQLite but passed as NSString.
    NSData *refreshTokenData = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoDBBindValue(stmt, 1, refreshTokenData);

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
        const char *errmsg = sqlite3_errmsg(self.db);
        GZ_LOG_DB_ERROR(@"getAccountsWithLimit: prepare failed: %s (SQL: %@)", errmsg, sql);
        if (error) *error = [self errorWithMessage:errmsg code:PDSDatabaseErrorQueryFailed];
        result = @[];
        return;
    }

    int idx = 1;
    if (afterDid) {
        ATProtoDBBindValue(stmt, idx++, afterDid);
    }
    ATProtoDBBindValue(stmt, idx, @(limit));

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

    ATProtoDBBindValue(stmt, 1, did);

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
    
    account.did = [self valueFromStatement:stmt columnIndex:0];
    account.handle = [self valueFromStatement:stmt columnIndex:1];
    account.email = [self valueFromStatement:stmt columnIndex:2];
    account.passwordHash = [self valueFromStatement:stmt columnIndex:3];
    account.passwordSalt = [self valueFromStatement:stmt columnIndex:4];
    account.accessJwt = [self valueFromStatement:stmt columnIndex:5];
    account.refreshJwt = [self valueFromStatement:stmt columnIndex:6];
    
    id status = [self valueFromStatement:stmt columnIndex:7];
    account.status = status ?: @"active";
    
    id deactivatedAt = [self valueFromStatement:stmt columnIndex:8];
    if (deactivatedAt) {
        account.deactivatedAt = [deactivatedAt doubleValue];
    }

    id createdAtStr = [self valueFromStatement:stmt columnIndex:9];
    if (createdAtStr) {
        account.createdAt = [NSDateFormatter atproto_dateFromString:createdAtStr].timeIntervalSince1970;
    }

    id updatedAtStr = [self valueFromStatement:stmt columnIndex:10];
    if (updatedAtStr) {
        account.updatedAt = [NSDateFormatter atproto_dateFromString:updatedAtStr].timeIntervalSince1970;
    }

    // 2FA
    account.tfaEnabled = ([[self valueFromStatement:stmt columnIndex:11] intValue] != 0);
    account.tfaSecret = [self valueFromStatement:stmt columnIndex:12];
    account.recoveryCodes = [self valueFromStatement:stmt columnIndex:13];
    account.inviteEnabled = ([[self valueFromStatement:stmt columnIndex:14] intValue] != 0);

    // Age assurance (columns 15, 16)
    account.ageAssurance = [self valueFromStatement:stmt columnIndex:15];
    account.ageVerifiedAt = [self valueFromStatement:stmt columnIndex:16];

    account.webauthnEnabled = ([[self valueFromStatement:stmt columnIndex:17] intValue] != 0);

    return account;
}

@end
