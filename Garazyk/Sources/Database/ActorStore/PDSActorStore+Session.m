// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSActorStore+Session.h"
#import "PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"

@implementation PDSActorStore (Session)

#pragma mark - Session Operations (Reader)

- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error {
    NSString *sql = @"SELECT account_did FROM refresh_tokens WHERE token = ? AND expires_at > ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[token, @([[NSDate date] timeIntervalSince1970])] error:error];
    if (results.count > 0) {
        return results.firstObject[@"account_did"];
    }
    return nil;
}

#pragma mark - Session Operations (Transactor)

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
    NSArray *params = @[
        token ?: @"",
        accountDid ?: @"",
        @([[NSDate date] timeIntervalSince1970]),
        @(expiresAt.timeIntervalSince1970)
    ];
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error {
    NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
    return [self.database executeParameterizedUpdate:sql params:@[token] error:error];
}

- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error {
    NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
    return [self.database executeParameterizedUpdate:sql params:@[accountDid] error:error];
}

@end
