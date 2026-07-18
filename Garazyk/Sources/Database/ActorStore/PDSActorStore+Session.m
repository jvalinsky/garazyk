// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSActorStore+Session.h"
#import "PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"

@implementation PDSActorStore (Session)

#pragma mark - Session Operations (Reader)

- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return nil;
    NSString *sql = @"SELECT account_did, session_id FROM refresh_tokens WHERE token = ? AND expires_at > ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[token, @([[NSDate date] timeIntervalSince1970])] error:error];
    if (results.count > 0) {
        return results.firstObject;
    }
    return nil;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return nil;
    NSString *sql = @"SELECT account_did FROM refresh_tokens WHERE token = ? AND expires_at > ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[token, @([[NSDate date] timeIntervalSince1970])] error:error];
    if (results.count > 0) {
        return results.firstObject[@"account_did"];
    }
    return nil;
}

- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error {
    if (!sessionID || !did) return NO;
    NSString *sql = @"SELECT 1 FROM refresh_tokens WHERE session_id = ? AND account_did = ? AND expires_at > ? LIMIT 1";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[sessionID, did, @([[NSDate date] timeIntervalSince1970])] error:error];
    return results.count > 0;
}

#pragma mark - Session Operations (Transactor)

- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    if (!token || !sessionID || !accountDid || !expiresAt) return NO;
    NSString *sql = @"INSERT INTO refresh_tokens (token, session_id, account_did, created_at, expires_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(token) DO UPDATE SET session_id=excluded.session_id, account_did=excluded.account_did, created_at=excluded.created_at, expires_at=excluded.expires_at";
    NSArray *params = @[
        token,
        sessionID,
        accountDid,
        @([[NSDate date] timeIntervalSince1970]),
        @(expiresAt.timeIntervalSince1970)
    ];
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    if (!token || !accountDid) return NO;
    NSString *sql = @"INSERT INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?) ON CONFLICT(token) DO UPDATE SET account_did=excluded.account_did, created_at=excluded.created_at, expires_at=excluded.expires_at";
    NSArray *params = @[
        token ?: @"",
        accountDid ?: @"",
        @([[NSDate date] timeIntervalSince1970]),
        @(expiresAt.timeIntervalSince1970)
    ];
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return NO;
    NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
    return [self.database executeParameterizedUpdate:sql params:@[token] error:error];
}

- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error {
    if (!accountDid) return NO;
    NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
    return [self.database executeParameterizedUpdate:sql params:@[accountDid] error:error];
}

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error {
    if (!sessionID) return NO;
    NSString *sql = @"DELETE FROM refresh_tokens WHERE session_id = ?";
    return [self.database executeParameterizedUpdate:sql params:@[sessionID] error:error];
}

- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error {
    if (!did) return NO;
    NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
    return [self.database executeParameterizedUpdate:sql params:@[did] error:error];
}

@end
