// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+WebAuthn.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (WebAuthn)

- (BOOL)storeWebAuthnCredential:(NSDictionary *)credential forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT INTO webauthn_credentials (id, account_did, credential_id, public_key_cose, sign_count, aaguid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET account_did=excluded.account_did, credential_id=excluded.credential_id, public_key_cose=excluded.public_key_cose, sign_count=excluded.sign_count, aaguid=excluded.aaguid, created_at=excluded.created_at";
    NSString *credentialId = [[NSUUID UUID] UUIDString];
    NSArray *params = @[
        credentialId,
        did,
        credential[@"credentialId"] ?: [NSNull null],
        credential[@"publicKey"] ?: [NSNull null],
        credential[@"signCount"] ?: @0,
        credential[@"aaguid"] ?: [NSNull null],
        [NSDateFormatter atproto_stringFromDate:[NSDate date]]
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (NSArray<NSDictionary *> *)getWebAuthnCredentialsForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT id, account_did, credential_id, public_key_cose, sign_count, aaguid, created_at FROM webauthn_credentials WHERE account_did = ?";
    NSArray *params = @[did];
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:params error:error];
    
    if (!rows) return @[];
    
    NSMutableArray *credentials = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *cred = [NSMutableDictionary dictionary];
        cred[@"id"] = row[@"id"];
        cred[@"accountDid"] = row[@"account_did"];
        cred[@"credentialId"] = row[@"credential_id"];
        cred[@"publicKey"] = row[@"public_key_cose"];
        cred[@"signCount"] = row[@"sign_count"];
        cred[@"aaguid"] = row[@"aaguid"];
        cred[@"createdAt"] = row[@"created_at"];
        [credentials addObject:cred];
    }
    return credentials;
}

- (BOOL)deleteWebAuthnCredential:(NSData *)credentialId forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM webauthn_credentials WHERE credential_id = ? AND account_did = ?";
    NSArray *params = @[credentialId, did];
    if (![self executeParameterizedUpdate:sql params:params error:error]) {
        return NO;
    }
    // executeParameterizedUpdate: only reports SQL errors, not match count -
    // a DELETE that matches nothing still "succeeds". Callers need to know
    // whether a credential actually existed.
    if (sqlite3_changes(self.db) == 0) {
        if (error) {
            *error = [self errorWithMessage:"No matching WebAuthn credential found" code:PDSDatabaseErrorNotFound];
        }
        return NO;
    }
    return YES;
}

- (BOOL)updateWebAuthnCredentialSignCount:(NSData *)credentialId forDid:(NSString *)did signCount:(uint32_t)signCount error:(NSError **)error {
    NSString *sql = @"UPDATE webauthn_credentials SET sign_count = ? WHERE credential_id = ? AND account_did = ?";
    NSArray *params = @[@(signCount), credentialId, did];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

@end
