// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSActorStore+Account.m
 @abstract PDSActorStore category implementation for account-related database operations.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSActorStore+Account.h"
#import "Debug/PDSLogger.h"
#import "PDSActorStoreInternal.h"
#import "Core/ATProtoError.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/PDSDatabase.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Compat/PDSTypes.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// Force static linkers to retain this category object file in Linux builds.
void PDSActorStoreLinkAccountCategory(void) {}

@implementation PDSActorStore (Account)

#pragma mark - Account Operations (Reader)

- (nullable PDSDatabaseAccount *)getAccountForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [self accountFromStatement:stmt];
        }
    };

    if (dispatch_get_specific(kPDSActorStoreQueueKey)) {
        workBlock();
    } else {
        dispatch_sync(self.transactionQueue, workBlock);
    }

    if (error && blockError) {
        *error = blockError;
    }
    return account;
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT * FROM accounts WHERE handle = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&blockError];
        if (!stmt) return;

        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];
        sqlite3_bind_text(stmt, 1, normalizedHandle.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [self accountFromStatement:stmt];
        }
    };

    if (dispatch_get_specific(kPDSActorStoreQueueKey)) {
        workBlock();
    } else {
        dispatch_sync(self.transactionQueue, workBlock);
    }

    if (error && blockError) {
        *error = blockError;
    }
    return account;
}

- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT * FROM accounts WHERE email = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, email.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [self accountFromStatement:stmt];
        }
    };

    if (dispatch_get_specific(kPDSActorStoreQueueKey)) {
        workBlock();
    } else {
        dispatch_sync(self.transactionQueue, workBlock);
    }

    if (error && blockError) {
        *error = blockError;
    }
    return account;
}

- (nullable NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    __block NSMutableArray<PDSDatabaseAccount *> *accounts = [NSMutableArray array];
    __block NSError *blockError = nil;
    
    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT * FROM accounts ORDER BY created_at DESC";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PDSDatabaseAccount *account = [self accountFromStatement:stmt];
            if (account) {
                [accounts addObject:account];
            }
        }
    };

    if (dispatch_get_specific(kPDSActorStoreQueueKey)) {
        workBlock();
    } else {
        dispatch_sync(self.transactionQueue, workBlock);
    }

    if (error && blockError) {
        *error = blockError;
    }
    return [accounts copy];
}

- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
    account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
    
    int col = 2;
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, col)];
    }
    col++;
    
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, col) 
                                              length:sqlite3_column_bytes(stmt, col)];
    }
    col++;
    
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, col) 
                                              length:sqlite3_column_bytes(stmt, col)];
    }
    col++;
    
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.accessJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, col) 
                                           length:sqlite3_column_bytes(stmt, col)];
    }
    col++;
    
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.refreshJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, col) 
                                            length:sqlite3_column_bytes(stmt, col)];
    }
    col++;
    
    // Parse ISO8601 date
    if (sqlite3_column_type(stmt, col) == SQLITE_FLOAT || sqlite3_column_type(stmt, col) == SQLITE_INTEGER) {
        account.createdAt = sqlite3_column_double(stmt, col);
    } else if (sqlite3_column_type(stmt, col) == SQLITE_TEXT) {
        const char *text = (const char *)sqlite3_column_text(stmt, col);
        if (text) {
            NSDateFormatter *fmt = [NSDateFormatter atproto_iso8601Formatter];
            account.createdAt = [[fmt dateFromString:@(text)] timeIntervalSince1970];
        }
    }
    col++;

    if (sqlite3_column_type(stmt, col) == SQLITE_FLOAT || sqlite3_column_type(stmt, col) == SQLITE_INTEGER) {
        account.updatedAt = sqlite3_column_double(stmt, col);
    } else if (sqlite3_column_type(stmt, col) == SQLITE_TEXT) {
        const char *text = (const char *)sqlite3_column_text(stmt, col);
        if (text) {
            NSDateFormatter *fmt = [NSDateFormatter atproto_iso8601Formatter];
            account.updatedAt = [[fmt dateFromString:@(text)] timeIntervalSince1970];
        }
    }
    
    return account;
}

#pragma mark - Account Operations (Transactor)

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    NSString *sql = @"INSERT INTO accounts (did, handle, email, password_hash, password_salt, "
                     @"access_jwt, refresh_jwt, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    sqlite3_bind_text(stmt, 1, account.did.UTF8String, -1, SQLITE_TRANSIENT);
    
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:account.handle];
    sqlite3_bind_text(stmt, 2, normalizedHandle.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (account.email) {
        sqlite3_bind_text(stmt, 3, account.email.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    
    if (account.passwordHash) {
        sqlite3_bind_blob(stmt, 4, account.passwordHash.bytes, (int)account.passwordHash.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    
    if (account.passwordSalt) {
        sqlite3_bind_blob(stmt, 5, account.passwordSalt.bytes, (int)account.passwordSalt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 5);
    }
    
    if (account.accessJwt) {
        sqlite3_bind_blob(stmt, 6, account.accessJwt.bytes, (int)account.accessJwt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 6);
    }
    
    if (account.refreshJwt) {
        sqlite3_bind_blob(stmt, 7, account.refreshJwt.bytes, (int)account.refreshJwt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 7);
    }
    
    sqlite3_bind_double(stmt, 8, account.createdAt);
    sqlite3_bind_double(stmt, 9, account.updatedAt);
    
    int stepResult = sqlite3_step(stmt);
    BOOL success = (stepResult == SQLITE_DONE);
    if (!success) {
        int sqliteCode = sqlite3_extended_errcode(self.db);
        NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(self.db)];
        
        if (error) {
            BOOL isConstraintViolation = (sqliteCode == SQLITE_CONSTRAINT_UNIQUE ||
                                          sqliteCode == SQLITE_CONSTRAINT_PRIMARYKEY ||
                                          sqliteCode == SQLITE_CONSTRAINT_FOREIGNKEY ||
                                          sqliteCode == SQLITE_CONSTRAINT_CHECK ||
                                          sqliteCode == SQLITE_CONSTRAINT_NOTNULL);
            if (isConstraintViolation) {
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeAlreadyExists
                                           message:@"Account already exists"
                                          userInfo:@{@"sqlite_code": @(sqliteCode),
                                                   @"sqlite_message": errorMsg ?: @""}];
            } else {
                *error = [self errorWithSQLiteResult:sqliteCode
                                             message:@"Failed to insert account"];
            }
        }
        return NO;
    }
    
    NSError *keyError = nil;
    if (![self generateSigningKeyForDid:account.did error:&keyError]) {
        PDS_LOG_WARN(@"[ActorStore] Failed to generate signing key for %@: %@", account.did, keyError);
    } else {
        PDS_LOG_INFO(@"[ActorStore] Generated signing key for %@", account.did);
    }

    return YES;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    NSString *sql = @"UPDATE accounts SET handle = ?, email = ?, password_hash = ?, "
                     @"password_salt = ?, access_jwt = ?, refresh_jwt = ?, updated_at = ? WHERE did = ?";
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    int idx = 1;
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:account.handle];
    sqlite3_bind_text(stmt, idx++, normalizedHandle.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (account.email) {
        sqlite3_bind_text(stmt, idx++, account.email.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    if (account.passwordHash) {
        sqlite3_bind_blob(stmt, idx++, account.passwordHash.bytes, (int)account.passwordHash.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    if (account.passwordSalt) {
        sqlite3_bind_blob(stmt, idx++, account.passwordSalt.bytes, (int)account.passwordSalt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    if (account.accessJwt) {
        sqlite3_bind_blob(stmt, idx++, account.accessJwt.bytes, (int)account.accessJwt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    if (account.refreshJwt) {
        sqlite3_bind_blob(stmt, idx++, account.refreshJwt.bytes, (int)account.refreshJwt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    sqlite3_bind_double(stmt, idx++, account.updatedAt);
    sqlite3_bind_text(stmt, idx, account.did.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    
    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM accounts WHERE did = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    
    return success;
}

@end

#pragma clang diagnostic pop
