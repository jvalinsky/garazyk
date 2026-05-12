// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSQLiteSessionRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStore+Session.h"
#import "Database/PDSDatabase.h"

@implementation PDSSQLiteSessionRepository {
    PDSDatabasePool *_databasePool;
}

- (instancetype)initWithServicePool:(PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - PDSSessionRepository

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid error:(NSError **)error {
    // Default expiration: 30 days
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:(30 * 24 * 60 * 60)];
    return [self storeRefreshToken:token forAccountDid:accountDid expiresAt:expiresAt error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store storeRefreshToken:token forAccountDid:accountDid expiresAt:expiresAt error:blockError];
    } error:error];
    return success;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block NSString *did = nil;
    [_databasePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        did = [store accountDidForRefreshToken:refreshToken error:blockError];
    } error:error];
    return did;
}

- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store revokeRefreshToken:token error:blockError];
    } error:error];
    return success;
}

- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store revokeAllRefreshTokensForAccountDid:accountDid error:blockError];
    } error:error];
    return success;
}

@end
