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

- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid error:(NSError **)error {
    // Default expiration: 30 days
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:(30 * 24 * 60 * 60)];
    return [self storeRefreshToken:token sessionID:sessionID forAccountDid:accountDid expiresAt:expiresAt error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSDatabase *db = (PDSDatabase *)transactor;
        success = [db storeRefreshToken:token sessionID:sessionID forAccountDid:accountDid expiresAt:expiresAt error:blockError];
    } error:error];
    return success;
}

- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block NSDictionary *info = nil;
    [_databasePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSDatabase *db = (PDSDatabase *)reader;
        info = [db sessionInfoForRefreshToken:refreshToken error:blockError];
    } error:error];
    return info;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    NSDictionary *info = [self sessionInfoForRefreshToken:refreshToken error:error];
    return info[@"account_did"];
}

- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error {
    __block BOOL active = NO;
    [_databasePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSDatabase *db = (PDSDatabase *)reader;
        active = [db isSessionActive:sessionID forAccountDid:did error:blockError];
    } error:error];
    return active;
}

- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSDatabase *db = (PDSDatabase *)transactor;
        success = [db revokeRefreshToken:token error:blockError];
    } error:error];
    return success;
}

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSDatabase *db = (PDSDatabase *)transactor;
        success = [db revokeSession:sessionID error:blockError];
    } error:error];
    return success;
}

- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSDatabase *db = (PDSDatabase *)transactor;
        success = [db revokeAllSessionsForDid:accountDid error:blockError];
    } error:error];
    return success;
}

@end
