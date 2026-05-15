// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Sessions.h"
#import "Database/PDSDatabase+Private.h"
#import "Database/Utils/PDSSQLiteUtils.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (Sessions)

- (NSArray<NSDictionary *> *)listSessionsForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT token, created_at, expires_at FROM refresh_tokens WHERE account_did = ? ORDER BY created_at DESC";
    result = [self executeParameterizedQuery:sql params:@[did] error:error];
    return;
    }];
    return result;
}

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    if (!token || !did || !expiresAt) return NO;
    __block BOOL result = NO;
    [self safeExecuteSync:^{
        NSString *sql = @"INSERT OR REPLACE INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        NSTimeInterval expires = [expiresAt timeIntervalSince1970];
        result = [self executeParameterizedUpdate:sql params:@[token, did, @(now), @(expires)] error:error];
    }];
    return result;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error {
    if (!token) return nil;
    __block NSString *did = nil;
    [self safeExecuteSync:^{
        NSString *sql = @"SELECT account_did FROM refresh_tokens WHERE token = ? AND expires_at > ?";
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        NSArray *rows = [self executeParameterizedQuery:sql params:@[token, @(now)] error:error];
        if (rows.count > 0) {
            did = rows.firstObject[@"account_did"];
        }
    }];
    return did;
}

- (BOOL)revokeSession:(NSString *)token error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
    result = [self executeParameterizedUpdate:sql params:@[token] error:error];
    return;
    }];
    return result;
}

- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
    result = [self executeParameterizedUpdate:sql params:@[did] error:error];
    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)listAppPasswordsForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT id, name, privileged, created_at FROM app_passwords WHERE account_did = ? ORDER BY created_at DESC";
    result = [self executeParameterizedQuery:sql params:@[did] error:error];
    return;
    }];
    return result;
}

- (BOOL)revokeAppPassword:(NSString *)passwordId forDid:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM app_passwords WHERE id = ? AND account_did = ?";
    result = [self executeParameterizedUpdate:sql params:@[passwordId, did] error:error];
    return;
    }];
    return result;
}

@end
