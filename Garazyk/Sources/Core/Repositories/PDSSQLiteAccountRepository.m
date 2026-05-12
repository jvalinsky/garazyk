// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSQLiteAccountRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStore+Account.h"
#import "Database/PDSDatabase.h"

@implementation PDSSQLiteAccountRepository {
    PDSDatabasePool *_databasePool;
}

- (instancetype)initWithServicePool:(PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - PDSAccountRepository

- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        account = [reader getAccountForDid:did error:blockError];
    } error:error];
    return account;
}

- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    // Handle-based lookup needs to search across all actor databases or use a central index.
    // In this implementation, we assume handle lookup is done via the "__service__" store
    // or by iterating (less efficient). 
    [_databasePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        account = [store getAccountByHandle:handle error:blockError];
    } error:error];
    return account;
}

- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    [_databasePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        account = [store getAccountByEmail:email error:blockError];
    } error:error];
    return account;
}

- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        // Try update first, then create
        if (![transactor updateAccount:account error:nil]) {
            success = [transactor createAccount:account error:blockError];
        } else {
            success = YES;
        }
    } error:error];
    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor deleteAccount:did error:blockError];
    } error:error];
    return success;
}

- (NSArray<PDSDatabaseAccount *> *)listAccountsWithError:(NSError **)error {
    __block NSArray *accounts = @[];
    [_databasePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        accounts = [store getAllAccountsWithError:blockError];
    } error:error];
    return accounts;
}

@end
