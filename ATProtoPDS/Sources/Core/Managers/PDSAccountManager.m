/*!
 @file PDSAccountManager.m
 @abstract Implementation of PDSAccountManager.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSAccountManager.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/ActorStore/PDSActorStore+Account.h"
#import "Core/ATProtoError.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import <sqlite3.h>

@implementation PDSAccountManager {
    PDSDatabasePool *_servicePool;
}

- (instancetype)initWithServicePool:(PDSDatabasePool *)servicePool {
    self = [super init];
    if (self) {
        _servicePool = servicePool;
    }
    return self;
}

#pragma mark - PDSAccountRepository

- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;

    [_servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) {
            return;
        }

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [store accountFromStatement:stmt];
        }
        [store finalizeStatement:stmt];
    } error:error];

    return account;
}

- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;

    [_servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM accounts WHERE handle = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) {
            return;
        }

        sqlite3_bind_text(stmt, 1, handle.UTF8String, -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [store accountFromStatement:stmt];
        }
        [store finalizeStatement:stmt];
    } error:error];

    return account;
}

- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;

    [_servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM accounts WHERE email = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) {
            return;
        }

        sqlite3_bind_text(stmt, 1, email.UTF8String, -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [store accountFromStatement:stmt];
        }
        [store finalizeStatement:stmt];
    } error:error];

    return account;
}

- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;

    // We use a transaction to check for existence and then insert/update
    [_servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        
        // Check if exists
        NSString *checkSql = @"SELECT 1 FROM accounts WHERE did = ?";
        sqlite3_stmt *checkStmt = [store prepareStatement:checkSql error:nil];
        BOOL exists = NO;
        if (checkStmt) {
            sqlite3_bind_text(checkStmt, 1, account.did.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(checkStmt) == SQLITE_ROW) {
                exists = YES;
            }
            [store finalizeStatement:checkStmt];
        }

        if (exists) {
            success = [store updateAccount:account error:blockError];
        } else {
            success = [store createAccount:account error:blockError];
        }
    } error:error];

    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;

    [_servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteAccount:did error:blockError];
    } error:error];

    return success;
}

- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseAccount *> *accounts = [NSMutableArray array];

    [_servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql;
        if (cursor) {
            sql = @"SELECT * FROM accounts WHERE did > ? ORDER BY did ASC LIMIT ?";
        } else {
            sql = @"SELECT * FROM accounts ORDER BY did ASC LIMIT ?";
        }

        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) {
            return;
        }

        int idx = 1;
        if (cursor) {
            sqlite3_bind_text(stmt, idx++, cursor.UTF8String, -1, SQLITE_TRANSIENT);
        }
        sqlite3_bind_int(stmt, idx, (int)limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PDSDatabaseAccount *account = [store accountFromStatement:stmt];
            if (account) {
                [accounts addObject:account];
            }
        }
        [store finalizeStatement:stmt];
    } error:error];

    return [accounts copy];
}

@end
