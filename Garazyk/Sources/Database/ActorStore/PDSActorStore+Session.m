// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSActorStore+Session.h"
#import "PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"

@implementation PDSActorStore (Session)

#pragma mark - Session Operations (Reader)

- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return nil;
    // §4.3: Enhanced query with family_id and rotated_at. Only succeeds when
    // V18 migration has been applied (tombstoned_at column exists). If the
    // query fails (pre-V18 database), fall back to the basic query. If the
    // query succeeds but returns no results (token is tombstoned or missing),
    // do NOT fall back — the tombstoned_at filter is authoritative.
    NSString *v18SQL = @"SELECT account_did, session_id, family_id, rotated_at FROM refresh_tokens WHERE token = ? AND expires_at > ? AND tombstoned_at IS NULL";
    NSError *v18Error = nil;
    NSArray *results = [self.database executeParameterizedQuery:v18SQL params:@[token, @([[NSDate date] timeIntervalSince1970])] error:&v18Error];
    if (results.count > 0) {
        return results.firstObject;
    }
    // Only fall back when V18 columns don't exist (query error), not when the
    // enhanced query ran and the token was filtered out by tombstoned_at.
    if (v18Error) {
        NSString *basicSQL = @"SELECT account_did, session_id FROM refresh_tokens WHERE token = ? AND expires_at > ?";
        results = [self.database executeParameterizedQuery:basicSQL params:@[token, @([[NSDate date] timeIntervalSince1970])] error:error];
        if (results.count > 0) {
            return results.firstObject;
        }
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
    return [self storeRefreshToken:token sessionID:sessionID forAccountDid:accountDid expiresAt:expiresAt familyId:nil error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt familyId:(nullable NSString *)familyId error:(NSError **)error {
    if (!token || !sessionID || !accountDid || !expiresAt) return NO;
    // If no family_id, use the legacy INSERT (without family_id column) for
    // backward compatibility with pre-V18 databases.
    if (familyId.length == 0) {
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
    NSString *sql = @"INSERT INTO refresh_tokens (token, session_id, account_did, created_at, expires_at, family_id) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(token) DO UPDATE SET session_id=excluded.session_id, account_did=excluded.account_did, created_at=excluded.created_at, expires_at=excluded.expires_at, family_id=excluded.family_id";
    NSArray *params = @[
        token,
        sessionID,
        accountDid,
        @([[NSDate date] timeIntervalSince1970]),
        @(expiresAt.timeIntervalSince1970),
        familyId
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

- (BOOL)rotateRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return NO;
    // Atomically mark this token as rotated. Only matches rows where
    // rotated_at IS NULL, so repeated calls are no-ops. The caller
    // detects reuse from the sessionInfo rotated_at field before
    // calling this method — this update is the atomic marker.
    // Note: executeParameterizedUpdate: returns YES on SQL success
    // even for 0-row updates; the caller's SELECT-based check
    // (sessionInfo[@"rotated_at"]) handles the reuse detection.
    NSString *sql = @"UPDATE refresh_tokens SET rotated_at = ? WHERE token = ? AND rotated_at IS NULL";
    return [self.database executeParameterizedUpdate:sql params:@[@([[NSDate date] timeIntervalSince1970]), token] error:error];
}

- (BOOL)tombstoneRefreshTokenFamily:(NSString *)familyId error:(NSError **)error {
    if (!familyId || familyId.length == 0) return NO;
    NSString *sql = @"UPDATE refresh_tokens SET tombstoned_at = ? WHERE family_id = ? AND tombstoned_at IS NULL";
    return [self.database executeParameterizedUpdate:sql params:@[@([[NSDate date] timeIntervalSince1970]), familyId] error:error];
}

- (BOOL)isRefreshTokenFamilyTombstoned:(NSString *)familyId error:(NSError **)error {
    if (!familyId || familyId.length == 0) return NO;
    NSString *sql = @"SELECT 1 FROM refresh_tokens WHERE family_id = ? AND tombstoned_at IS NOT NULL LIMIT 1";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[familyId] error:error];
    return results.count > 0;
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
