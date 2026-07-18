// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Sessions.h"
#import "Database/PDSDatabase+Private.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (Sessions)

- (NSArray<NSDictionary *> *)listSessionsForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT token, session_id, created_at, expires_at FROM refresh_tokens WHERE account_did = ? ORDER BY created_at DESC";
    return [self executeParameterizedQuery:sql params:@[did] error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    if (!token || !sessionID || !did || !expiresAt) return NO;
    NSString *sql = @"INSERT INTO refresh_tokens (token, session_id, account_did, created_at, expires_at) VALUES (?, ?, ?, ?, ?) "
                     @"ON CONFLICT(token) DO UPDATE SET session_id=excluded.session_id, account_did=excluded.account_did, "
                     @"created_at=excluded.created_at, expires_at=excluded.expires_at";
    NSArray *params = @[
        token,
        sessionID,
        did,
        @([[NSDate date] timeIntervalSince1970]),
        @(expiresAt.timeIntervalSince1970)
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    NSString *sessionID = [[NSUUID UUID] UUIDString];
    return [self storeRefreshToken:token sessionID:sessionID forAccountDid:did expiresAt:expiresAt error:error];
}

- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return nil;
    NSString *sql = @"SELECT account_did, session_id FROM refresh_tokens WHERE token = ? AND expires_at > ?";
    double now = [[NSDate date] timeIntervalSince1970];
    NSArray *rows = [self executeParameterizedQuery:sql params:@[token, @(now)] error:error];
    if (rows.count > 0) {
        return rows.firstObject;
    }
    return nil;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error {
    NSDictionary *info = [self sessionInfoForRefreshToken:token error:error];
    return info[@"account_did"];
}

- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error {
    if (!sessionID || !did) return NO;
    NSString *sql = @"SELECT 1 FROM refresh_tokens WHERE session_id = ? AND account_did = ? AND expires_at > ? LIMIT 1";
    double now = [[NSDate date] timeIntervalSince1970];
    NSArray *rows = [self executeParameterizedQuery:sql params:@[sessionID, did, @(now)] error:error];
    return rows.count > 0;
}

- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error {
    NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
    return [self executeParameterizedUpdate:sql params:@[token] error:error];
}

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error {
    NSString *sql = @"DELETE FROM refresh_tokens WHERE session_id = ?";
    return [self executeParameterizedUpdate:sql params:@[sessionID] error:error];
}

- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
    return [self executeParameterizedUpdate:sql params:@[did] error:error];
}

- (NSArray<NSDictionary *> *)listAppPasswordsForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT id, name, privileged, created_at FROM app_passwords WHERE account_did = ? ORDER BY created_at DESC";
    return [self executeParameterizedQuery:sql params:@[did] error:error];
}

- (BOOL)revokeAppPassword:(NSString *)passwordId forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM app_passwords WHERE id = ? AND account_did = ?";
    return [self executeParameterizedUpdate:sql params:@[passwordId, did] error:error];
}

@end
