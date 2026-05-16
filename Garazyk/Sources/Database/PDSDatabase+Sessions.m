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
    NSString *sql = @"SELECT token, created_at, expires_at FROM refresh_tokens WHERE account_did = ? ORDER BY created_at DESC";
    return [self executeParameterizedQuery:sql params:@[did] error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    if (!token || !did || !expiresAt) return NO;
    NSString *sql = @"INSERT OR REPLACE INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
    NSArray *params = @[
        token,
        did,
        [NSDateFormatter atproto_stringFromDate:[NSDate date]],
        [NSDateFormatter atproto_stringFromDate:expiresAt]
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return nil;
    NSString *sql = @"SELECT account_did FROM refresh_tokens WHERE token = ? AND expires_at > ?";
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSArray *rows = [self executeParameterizedQuery:sql params:@[token, now] error:error];
    if (rows.count > 0) {
        return rows.firstObject[@"account_did"];
    }
    return nil;
}

- (BOOL)revokeSession:(NSString *)token error:(NSError **)error {
    NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
    return [self executeParameterizedUpdate:sql params:@[token] error:error];
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
