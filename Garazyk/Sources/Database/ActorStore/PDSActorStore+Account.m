// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSActorStore+Account.m
 @abstract PDSActorStore category implementation for account-related database operations.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSActorStore+Account.h"
#import "Debug/GZLogger.h"
#import "PDSActorStoreInternal.h"
#import "Core/ATProtoError.h"
#import "Database/PDSDatabase.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Compat/PDSTypes.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// Force static linkers to retain this category object file in Linux builds.
void PDSActorStoreLinkAccountCategory(void) {}

@implementation PDSActorStore (Account)

#pragma mark - Account Operations (Reader)

- (nullable PDSDatabaseAccount *)getAccountForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[did] modelClass:[PDSDatabaseAccount class] error:error];
    return results.firstObject;
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE handle = ?";
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[normalizedHandle] modelClass:[PDSDatabaseAccount class] error:error];
    return results.firstObject;
}

- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE email = ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[email] modelClass:[PDSDatabaseAccount class] error:error];
    return results.firstObject;
}

- (nullable NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts ORDER BY created_at DESC";
    return [self.database executeParameterizedQuery:sql params:@[] modelClass:[PDSDatabaseAccount class] error:error] ?: @[];
}

- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    NSMutableString *sql = [@"SELECT * FROM accounts" mutableCopy];
    NSMutableArray *params = [NSMutableArray array];
    
    if (cursor.length > 0) {
        [sql appendString:@" WHERE did > ?"];
        [params addObject:cursor];
    }
    
    [sql appendString:@" ORDER BY did ASC LIMIT ?"];
    [params addObject:@(limit)];
    
    return [self.database executeParameterizedQuery:sql params:params modelClass:[PDSDatabaseAccount class] error:error] ?: @[];
}

#pragma mark - Account Operations (Transactor)

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    if (!account) {
        if (error) *error = [NSError errorWithDomain:@"PDSActorStore" code:1 userInfo:@{NSLocalizedDescriptionKey: @"account must not be nil"}];
        return NO;
    }

    NSString *sql = @"INSERT INTO accounts (did, handle, email, password_hash, password_salt, "
                     @"access_jwt, refresh_jwt, status, deactivated_at, created_at, updated_at, "
                     @"tfa_enabled, tfa_secret, recovery_codes, invite_enabled, "
                     @"age_assurance, age_verified_at, webauthn_enabled) "
                     @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:account.handle];
    NSArray *params = @[
        account.did ?: @"",
        normalizedHandle ?: @"",
        account.email ?: [NSNull null],
        account.passwordHash ?: [NSNull null],
        account.passwordSalt ?: [NSNull null],
        account.accessJwt ?: [NSNull null],
        account.refreshJwt ?: [NSNull null],
        account.status ?: @"active",
        account.deactivatedAt > 0 ? @(account.deactivatedAt) : [NSNull null],
        @(account.createdAt),
        @(account.updatedAt),
        @(account.tfaEnabled),
        account.tfaSecret ?: [NSNull null],
        account.recoveryCodes ?: [NSNull null],
        @(account.inviteEnabled),
        account.ageAssurance ?: [NSNull null],
        account.ageVerifiedAt ?: [NSNull null],
        @(account.webauthnEnabled)
    ];

    if (![self.database executeParameterizedUpdate:sql params:params error:error]) {
        return NO;
    }
    
    NSError *keyError = nil;
    if (![self generateSigningKeyForDid:account.did error:&keyError]) {
        GZ_LOG_WARN(@"[ActorStore] Failed to generate signing key for %@: %@", account.did, keyError);
    } else {
        GZ_LOG_INFO(@"[ActorStore] Generated signing key for %@", account.did);
    }

    return YES;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    NSString *sql = @"UPDATE accounts SET handle = ?, email = ?, password_hash = ?, "
                     @"password_salt = ?, access_jwt = ?, refresh_jwt = ?, status = ?, "
                     @"deactivated_at = ?, updated_at = ?, tfa_enabled = ?, tfa_secret = ?, "
                     @"recovery_codes = ?, invite_enabled = ?, age_assurance = ?, "
                     @"age_verified_at = ?, webauthn_enabled = ? WHERE did = ?";
    
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:account.handle];
    NSArray *params = @[
        normalizedHandle ?: @"",
        account.email ?: [NSNull null],
        account.passwordHash ?: [NSNull null],
        account.passwordSalt ?: [NSNull null],
        account.accessJwt ?: [NSNull null],
        account.refreshJwt ?: [NSNull null],
        account.status ?: @"active",
        account.deactivatedAt > 0 ? @(account.deactivatedAt) : [NSNull null],
        @(account.updatedAt),
        @(account.tfaEnabled),
        account.tfaSecret ?: [NSNull null],
        account.recoveryCodes ?: [NSNull null],
        @(account.inviteEnabled),
        account.ageAssurance ?: [NSNull null],
        account.ageVerifiedAt ?: [NSNull null],
        @(account.webauthnEnabled),
        account.did ?: @""
    ];
    
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM accounts WHERE did = ?";
    return [self.database executeParameterizedUpdate:sql params:@[did] error:error];
}

@end

#pragma clang diagnostic pop
