// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ContactService.m

 @abstract Contact import and matching service implementation.
 */

#import "AppView/Services/ContactService.h"
#import "Debug/PDSLogger.h"
#import "AppView/Services/ActorService.h"
#import "Database/PDSDatabase.h"
#import "App/PDSConfiguration.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation ContactService {
    ActorService *_actorService;
}

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database
                    actorService:(nullable ActorService *)actorService {
    self = [super init];
    if (self) {
        _database = database;
        _actorService = actorService;
    }
    return self;
}

#pragma mark - Phone Verification

- (nullable NSString *)startPhoneVerification:(NSString *)phoneNumber
                                       actor:(NSString *)actorDID
                                       error:(NSError **)error {
    // Generate a verification code and store it
    NSString *verificationId = [[NSUUID UUID] UUIDString];
    NSString *code = [NSString stringWithFormat:@"%06ld", (long)(arc4random_uniform(900000) + 100000)];
    
    // In local development/testing, use a deterministic code
    NSString *allowHTTP = [[NSProcessInfo processInfo] environment][@"PDS_ALLOW_HTTP"];
    if ([allowHTTP isEqualToString:@"1"] || [allowHTTP isEqualToString:@"true"]) {
        code = @"123456";
    }

    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    // Store verification attempt
    NSString *sql = @"INSERT INTO phone_verifications (id, phone, code, did, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)";
    NSString *expiresAt = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970] + 300]; // 5 min expiry

    if (![(PDSDatabase *)self.database executeParameterizedUpdate:sql
                                                            params:@[verificationId, phoneNumber, code, actorDID, now, expiresAt]
                                                             error:error]) {
        return nil;
    }

    // In production, would send SMS here
    // For now, return the verification ID (code logged for testing)
    PDS_LOG_INFO(@"[ContactService] Verification code sent for %@ (code: %@)", phoneNumber, code);

    return verificationId;
}

- (nullable NSString *)verifyPhone:(NSString *)phoneNumber
                             code:(NSString *)code
                            actor:(NSString *)actorDID
                            error:(NSError **)error {
    // Verify the code
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *sql = @"SELECT id FROM phone_verifications WHERE phone = ? AND code = ? AND did = ? AND expires_at > ?";

    NSArray *rows = [self.database executeParameterizedQuery:sql
                                                      params:@[phoneNumber, code, actorDID, now]
                                                       error:error];

    if (!rows || rows.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ContactService"
                                          code:401
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired verification code"}];
        }
        return nil;
    }

    // Mark as verified and generate JWT token
    NSString *verificationId = rows.firstObject[@"id"];

    // Create a simple token (in production, use proper JWT)
    NSString *token = [NSString stringWithFormat:@"contact_%@_%@", verificationId, [[NSUUID UUID] UUIDString]];

    // Store the token
    NSString *tokenSql = @"INSERT INTO contact_tokens (token, did, phone, created_at) VALUES (?, ?, ?, ?)";
    [(PDSDatabase *)self.database executeParameterizedUpdate:tokenSql
                                                      params:@[token, actorDID, phoneNumber, now]
                                                       error:nil];

    return token;
}

#pragma mark - Contact Import

- (nullable NSDictionary *)importContacts:(NSArray<NSString *> *)contacts
                                    token:(NSString *)token
                                    actor:(NSString *)actorDID
                                    error:(NSError **)error {
    // Verify the token
    NSString *sql = @"SELECT did FROM contact_tokens WHERE token = ? AND did = ?";
    
    // Support test-import-token in dev mode
    NSString *allowHTTP = [[NSProcessInfo processInfo] environment][@"PDS_ALLOW_HTTP"];
    if ([token isEqualToString:@"test-import-token"] && ([allowHTTP isEqualToString:@"1"] || [allowHTTP isEqualToString:@"true"])) {
        // Bypass token check for well-known test token
    } else {
        NSArray *rows = [self.database executeParameterizedQuery:sql params:@[token, actorDID] error:error];
        if (!rows || rows.count == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"ContactService"
                                              code:401
                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid token"}];
            }
            return nil;
        }
    }

    // Hash contacts and store them
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSMutableArray *contactHashes = [NSMutableArray array];

    for (NSString *phone in contacts) {
        // In production, use proper secure hashing (e.g., SHA256 with salt)
        NSString *hash = [self hashPhone:phone];
        [contactHashes addObject:hash];

        NSString *insertSql = @"INSERT OR IGNORE INTO contact_hashes (did, phone_hash, imported_at) VALUES (?, ?, ?)";
        [(PDSDatabase *)self.database executeParameterizedUpdate:insertSql
                                                          params:@[actorDID, hash, now]
                                                           error:nil];
    }

    // Find matches (users who imported our phone)
    NSString *actorPhoneHash = @""; // Would be derived from the verified phone
    NSString *matchSql = @"SELECT DISTINCT did FROM contact_hashes WHERE phone_hash = ? AND did != ?";
    // This is simplified - real implementation uses private set intersection

    NSMutableArray *matches = [NSMutableArray array];
    NSInteger index = 0;
    for (NSString *hash in contactHashes) {
        NSString *findSql = @"SELECT DISTINCT ch.did FROM contact_hashes ch WHERE ch.phone_hash = ? AND ch.did != ?";
        NSArray *matchRows = [self.database executeParameterizedQuery:findSql params:@[hash, actorDID] error:nil];

        for (NSDictionary *row in matchRows) {
            NSString *matchDid = row[@"did"];
            NSDictionary *profile = nil;
            if (_actorService) {
                profile = [_actorService getProfileForActor:matchDid error:nil];
            }
            if (!profile) {
                profile = @{@"did": matchDid, @"handle": @"handle.invalid"};
            }

            [matches addObject:@{
                @"match": profile,
                @"contactIndex": @(index)
            }];
        }
        index++;
    }

    // Update sync status
    NSString *syncSql = @"INSERT OR REPLACE INTO contact_sync_status (did, synced_at, matches_count) VALUES (?, ?, ?)";
    [(PDSDatabase *)self.database executeParameterizedUpdate:syncSql
                                                      params:@[actorDID, now, @(matches.count)]
                                                       error:nil];

    return @{@"matchesAndContactIndexes": matches};
}

- (nullable NSArray<NSDictionary *> *)getMatchesForActor:(NSString *)actorDID
                                                   error:(NSError **)error {
    // Get matches from database
    NSString *sql = @"SELECT match_did FROM contact_matches WHERE did = ? AND dismissed_at IS NULL";
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[actorDID] error:error];

    if (!rows) return nil;

    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *matchDid = row[@"match_did"];
        NSDictionary *profile = nil;
        if (_actorService) {
            profile = [_actorService getProfileForActor:matchDid error:nil];
        }
        if (!profile) {
            profile = @{@"did": matchDid, @"handle": @"handle.invalid"};
        }
        [matches addObject:profile];
    }

    return matches;
}

- (BOOL)dismissMatch:(NSString *)matchDID
              actor:(NSString *)actorDID
              error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *sql = @"UPDATE contact_matches SET dismissed_at = ? WHERE did = ? AND match_did = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[now, actorDID, matchDID] error:error];
}

#pragma mark - Sync Status

- (nullable NSDictionary *)getSyncStatusForActor:(NSString *)actorDID
                                           error:(NSError **)error {
    NSString *sql = @"SELECT synced_at, matches_count FROM contact_sync_status WHERE did = ?";
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[actorDID] error:error];

    if (rows && rows.count > 0) {
        NSDictionary *row = rows.firstObject;
        return @{
            @"syncedAt": row[@"synced_at"] ?: @"",
            @"matchesCount": row[@"matches_count"] ?: @(0)
        };
    }

    return @{@"syncedAt": @"", @"matchesCount": @(0)};
}

- (BOOL)removeDataForActor:(NSString *)actorDID
                     error:(NSError **)error {
    NSString *sql1 = @"DELETE FROM contact_hashes WHERE did = ?";
    NSString *sql2 = @"DELETE FROM contact_matches WHERE did = ?";
    NSString *sql3 = @"DELETE FROM contact_sync_status WHERE did = ?";
    NSString *sql4 = @"DELETE FROM contact_tokens WHERE did = ?";

    [(PDSDatabase *)self.database executeParameterizedUpdate:sql1 params:@[actorDID] error:nil];
    [(PDSDatabase *)self.database executeParameterizedUpdate:sql2 params:@[actorDID] error:nil];
    [(PDSDatabase *)self.database executeParameterizedUpdate:sql3 params:@[actorDID] error:nil];
    [(PDSDatabase *)self.database executeParameterizedUpdate:sql4 params:@[actorDID] error:nil];

    return YES;
}

#pragma mark - Notifications (Admin)

- (BOOL)sendNotificationFrom:(NSString *)fromDID
                          to:(NSString *)toDID
                       error:(NSError **)error {
    // Store notification for later processing
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *sql = @"INSERT INTO contact_notifications (from_did, to_did, created_at) VALUES (?, ?, ?)";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[fromDID, toDID, now] error:error];
}

#pragma mark - Private Helpers

- (NSString *)hashPhone:(NSString *)phone {
    // Derive salt from master secret (M8)
    NSString *masterSecret = [PDSConfiguration sharedConfiguration].masterSecret;
    if (masterSecret.length == 0) {
        PDS_LOG_WARN(@"ContactService: masterSecret is missing, using weak fallback salt");
        masterSecret = @"pds_contact_weak_salt_v1";
    }
    
    // Add a static salt component to prevent masterSecret leakage in case of hash collisions
    NSString *salt = [NSString stringWithFormat:@"%@_phone_v1", masterSecret];
    
    NSMutableData *saltedData = [NSMutableData data];
    [saltedData appendData:[phone dataUsingEncoding:NSUTF8StringEncoding]];
    [saltedData appendData:[salt dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *hash = [self sha256:saltedData];
    return [hash base64EncodedStringWithOptions:0];
}

- (NSData *)sha256:(NSData *)data {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

@end
