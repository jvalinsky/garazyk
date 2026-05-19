// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/ActorStore/PDSActorStore+Account.h"
#import "Database/ActorStore/PDSActorStore+Session.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Database/Migrations/PDSMigrationManager.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Core/ATProtoDataPaths.h"
#import "Identity/ATProtoHandleValidator.h"
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonDigest.h>
#import "Debug/GZLogger.h"

NSString * const PDSServiceDatabasesErrorDomain = @"com.atproto.pds.service.databases";

#pragma mark - Helper Functions

static NSData *appPasswordGenerateSalt(void) {
    NSMutableData *salt = [NSMutableData dataWithLength:32];
    [[NSUUID UUID] getUUIDBytes:salt.mutableBytes];
    return salt;
}

static NSData *appPasswordHash(NSString *password, NSData *salt) {
    const uint32_t iterations = 600000;
    const size_t derivedKeyLength = 32;
    unsigned char derivedKey[32];

    int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      password.UTF8String,
                                      (size_t)password.length,
                                      salt.bytes,
                                      (size_t)salt.length,
                                      kCCPRFHmacAlgSHA256,
                                      iterations,
                                      derivedKey,
                                      derivedKeyLength);
    if (result != kCCSuccess) {
        return nil;
    }

    return [NSData dataWithBytes:derivedKey length:derivedKeyLength];
}

static NSString *appPasswordGenerateSecret(void) {
    static NSString *const kAlphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    NSMutableString *secret = [NSMutableString string];
    for (NSUInteger groupIndex = 0; groupIndex < 4; groupIndex++) {
        if (groupIndex > 0) {
            [secret appendString:@"-"];
        }
        for (NSUInteger i = 0; i < 4; i++) {
            unichar c = [kAlphabet characterAtIndex:arc4random_uniform((uint32_t)kAlphabet.length)];
            [secret appendFormat:@"%C", c];
        }
    }
    return secret;
}

static NSString *refreshTokenSessionID(NSString *refreshToken) {
    NSData *tokenData = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    if (!tokenData) {
        return @"";
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(tokenData.bytes, (CC_LONG)tokenData.length, digest);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex copy];
}

@interface PDSServiceDatabases ()

@property (nonatomic, strong, readwrite) PDSDatabasePool *servicePool;
@property (nonatomic, strong, readwrite) PDSDatabasePool *didCachePool;
@property (nonatomic, strong, readwrite) PDSDatabasePool *sequencerPool;
@property (nonatomic, strong, readwrite) PDSDatabasePool *userDatabasePool;

@property (nonatomic, copy) NSString *serviceDbPath;
@property (nonatomic, copy) NSString *didCacheDbPath;
@property (nonatomic, copy) NSString *sequencerDbPath;

@end

@implementation PDSServiceDatabases

- (instancetype)initWithDirectory:(NSString *)directory 
                     serviceMaxSize:(NSUInteger)serviceMaxSize
                   didCacheMaxSize:(NSUInteger)didCacheMaxSize
                 sequencerMaxSize:(NSUInteger)sequencerMaxSize {
    self = [super init];
    if (self) {
        ATProtoDataPaths *paths = [ATProtoDataPaths pathsForBaseDirectory:directory];
        [paths createDirectoriesWithError:nil];

        _serviceDbPath = paths.serviceDirectory;
        _didCacheDbPath = paths.didCacheDirectory;
        _sequencerDbPath = paths.sequencerDirectory;
        
        _servicePool = [[PDSDatabasePool alloc] initWithDbDirectory:_serviceDbPath maxSize:serviceMaxSize];
        _didCachePool = [[PDSDatabasePool alloc] initWithDbDirectory:_didCacheDbPath maxSize:didCacheMaxSize];
        _sequencerPool = [[PDSDatabasePool alloc] initWithDbDirectory:_sequencerDbPath maxSize:sequencerMaxSize];
        _userDatabasePool = [[PDSDatabasePool alloc] initWithDbDirectory:directory maxSize:100]; // Base directory for user shards
        
        _refreshTokenTTLSeconds = 30 * 24 * 60 * 60;
        
        [self applyPerformancePragmasOnPool:_servicePool];
        [self applyPerformancePragmasOnPool:_didCachePool];
        [self applyPerformancePragmasOnPool:_sequencerPool];
        
        [self initializeServiceSchema:nil];
        [self initializeDidCacheSchema:nil];
        [self initializeSequencerSchema:nil];
    }
    return self;
}

#pragma mark - Database Configuration

- (void)applyPerformancePragmasOnPool:(PDSDatabasePool *)pool {
    static NSString *const pragmaSQL =
        @"PRAGMA journal_mode=WAL;"
        @"PRAGMA synchronous=NORMAL;"
        @"PRAGMA cache_size=-32000;"
        @"PRAGMA temp_store=MEMORY;";
    [self executeSQL:pragmaSQL onPool:pool error:nil];
}

#pragma mark - Schema Initialization

- (BOOL)initializeServiceSchema:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return NO;

    PDSMigrationManager *migrationManager = [PDSMigrationManager serviceDatabaseMigrationManager];
    NSError *migrationError = nil;
    if (![migrationManager migrateDatabase:[store.database internalSQLiteHandle] error:&migrationError]) {
        GZ_LOG_DB_ERROR(@"Service database migration failed: %@", migrationError);
        if (error) *error = migrationError;
        return NO;
    }

    GZ_LOG_DB_INFO(@"Service database schema migration complete");
    return YES;
}

- (BOOL)initializeDidCacheSchema:(NSError **)error {
    NSString *schemaSQL = [NSString stringWithFormat:@"%@;%@",
                           [[PDSSchemaManager sharedManager] serviceDIDCacheTableSchema],
                           @"CREATE INDEX IF NOT EXISTS idx_did_cache_expires ON did_cache(expires_at);"];
    return [self executeSQL:schemaSQL onPool:self.didCachePool error:error];
}

- (BOOL)initializeSequencerSchema:(NSError **)error {
    NSString *schemaSQL = [NSString stringWithFormat:@"%@;%@;%@;%@",
                           [[PDSSchemaManager sharedManager] serviceRepoSequenceTableSchema],
                           [[PDSSchemaManager sharedManager] serviceEventsTableSchema],
                           @"CREATE INDEX IF NOT EXISTS idx_repo_sequence_did ON repo_sequence(did);",
                           @"CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at);"];
    return [self executeSQL:schemaSQL onPool:self.sequencerPool error:error];
}

- (BOOL)executeSQL:(NSString *)sql onPool:(PDSDatabasePool *)pool error:(NSError **)error {
    __block BOOL success = YES;
    [pool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store.database executeUnsafeRawSQL:sql error:innerError];
    } error:error];
    return success;
}

#pragma mark - Account Management

- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        if (![transactor updateAccount:account error:nil]) {
            success = [transactor createAccount:account error:innerError];
        } else {
            success = YES;
        }
    } error:error];
    return success;
}

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        success = [transactor createAccount:account error:innerError];
    } error:error];
    return success;
}

- (BOOL)createAccounts:(NSArray<PDSDatabaseAccount *> *)accounts error:(NSError **)error {
    __block BOOL success = YES;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        for (PDSDatabaseAccount *account in accounts) {
            if (![transactor createAccount:account error:innerError]) {
                success = NO;
                break;
            }
        }
    } error:error];
    return success;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        success = [transactor updateAccount:account error:innerError];
    } error:error];
    return success;
}

- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error {
    return [self getAccountByDid:did error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        account = [store getAccountForDid:did error:innerError];
    } error:error];
    return account;
}

- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error {
    return [self getAccountByHandle:handle error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        account = [store getAccountByHandle:handle error:innerError];
    } error:error];
    return account;
}

- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error {
    return [self getAccountByEmail:email error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        account = [store getAccountByEmail:email error:innerError];
    } error:error];
    return account;
}

- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    NSString *did = [self accountDidForRefreshToken:refreshToken error:error];
    if (!did) return nil;
    return [self getAccountByDid:did error:error];
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        success = [transactor deleteAccount:did error:innerError];
    } error:error];
    return success;
}

- (nullable NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    __block NSArray *accounts = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        accounts = [store getAllAccountsWithError:innerError];
    } error:error];
    return accounts;
}

- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    return [self getAccountsWithLimit:limit cursor:cursor error:error];
}

- (nullable NSArray<PDSDatabaseAccount *> *)getAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    NSArray *all = [self getAllAccountsWithError:error];
    if (!all) return nil;
    
    if (cursor) {
        NSUInteger index = [all indexOfObjectPassingTest:^BOOL(PDSDatabaseAccount *obj, NSUInteger idx, BOOL *stop) {
            return [obj.did isEqualToString:cursor];
        }];
        if (index != NSNotFound && index + 1 < all.count) {
            NSUInteger start = index + 1;
            NSUInteger len = MIN((NSUInteger)limit, all.count - start);
            return [all subarrayWithRange:NSMakeRange(start, len)];
        } else {
            return @[];
        }
    } else {
        NSUInteger len = MIN((NSUInteger)limit, all.count);
        return [all subarrayWithRange:NSMakeRange(0, len)];
    }
}

#pragma mark - Refresh Tokens

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid error:(NSError **)error {
    NSUInteger ttl = self.refreshTokenTTLSeconds > 0 ? self.refreshTokenTTLSeconds : (30 * 24 * 60 * 60);
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:ttl];
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store storeRefreshToken:token forAccountDid:accountDid expiresAt:expiresAt error:innerError];
    } error:error];
    return success;
}

- (BOOL)storeRefreshToken:(NSString *)token forAccount:(NSString *)accountDid error:(NSError **)error {
    return [self storeRefreshToken:token forAccountDid:accountDid error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid error:(NSError **)error {
    NSUInteger ttl = self.refreshTokenTTLSeconds > 0 ? self.refreshTokenTTLSeconds : (30 * 24 * 60 * 60);
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:ttl];
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store storeRefreshToken:token sessionID:sessionID forAccountDid:accountDid expiresAt:expiresAt error:innerError];
    } error:error];
    return success;
}

- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block NSDictionary *info = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        info = [store sessionInfoForRefreshToken:refreshToken error:innerError];
    } error:error];
    return info;
}

- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error {
    __block BOOL active = NO;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        active = [store isSessionActive:sessionID forAccountDid:did error:innerError];
    } error:error];
    return active;
}

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store revokeSession:sessionID error:innerError];
    } error:error];
    return success;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block NSString *did = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        did = [store accountDidForRefreshToken:refreshToken error:innerError];
    } error:error];
    return did;
}

- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store revokeRefreshToken:token error:innerError];
    } error:error];
    return success;
}

- (BOOL)deleteRefreshToken:(NSString *)token error:(NSError **)error {
    return [self revokeRefreshToken:token error:error];
}

- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store revokeAllRefreshTokensForAccountDid:accountDid error:innerError];
    } error:error];
    return success;
}

- (BOOL)deleteRefreshTokensForAccount:(NSString *)accountDid error:(NSError **)error {
    return [self revokeAllRefreshTokensForAccountDid:accountDid error:error];
}

- (NSArray<NSDictionary *> *)listRefreshTokenSessionsForAccountDid:(NSString *)accountDid
                                                             error:(NSError **)error {
    if (accountDid.length == 0) return @[];
    __block NSMutableArray *sessions = [NSMutableArray array];
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT token, account_did, created_at, expires_at FROM refresh_tokens WHERE account_did = ? AND expires_at > ? ORDER BY created_at DESC";
        NSArray *params = @[accountDid, @([[NSDate date] timeIntervalSince1970])];
        NSArray<NSDictionary *> *results = [store.database executeParameterizedQuery:sql params:params error:innerError];
        for (NSDictionary *row in results) {
            NSString *token = row[@"token"];
            [sessions addObject:@{
                @"id": refreshTokenSessionID(token),
                @"did": row[@"account_did"] ?: @"",
                @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:[row[@"created_at"] doubleValue]]] ?: @"",
                @"expiresAt": [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:[row[@"expires_at"] doubleValue]]] ?: @""
            }];
        }
    } error:error];
    return sessions;
}

- (BOOL)revokeRefreshTokenSessionForAccountDid:(NSString *)accountDid
                                     sessionID:(NSString *)sessionID
                                         error:(NSError **)error {
    __block BOOL revoked = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSArray *results = [store.database executeParameterizedQuery:@"SELECT token FROM refresh_tokens WHERE account_did = ?" params:@[accountDid] error:innerError];
        for (NSDictionary *row in results) {
            NSString *token = row[@"token"];
            if ([refreshTokenSessionID(token) isEqualToString:sessionID]) {
                revoked = [store revokeRefreshToken:token error:innerError];
                break;
            }
        }
    } error:error];
    return revoked;
}

#pragma mark - Invite Codes

- (BOOL)createInviteCode:(NSString *)code forAccount:(NSString *)accountDid maxUses:(NSInteger)maxUses error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO invite_codes (id, code, account_did, created_at, max_uses) VALUES (?, ?, ?, ?, ?)";
        success = [store.database executeParameterizedUpdate:sql params:@[[[NSUUID UUID] UUIDString], code, accountDid, @([[NSDate date] timeIntervalSince1970]), @(maxUses)] error:innerError];
    } error:error];
    return success;
}

- (nullable NSString *)getInviteCodeForAccount:(NSString *)accountDid error:(NSError **)error {
    __block NSString *code = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSArray *results = [store.database executeParameterizedQuery:@"SELECT code FROM invite_codes WHERE account_did = ? AND disabled = 0 LIMIT 1" params:@[accountDid] error:innerError];
        code = results.firstObject[@"code"];
    } error:error];
    return code;
}

- (BOOL)useInviteCode:(NSString *)code error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store.database executeParameterizedUpdate:@"UPDATE invite_codes SET uses = uses + 1 WHERE code = ? AND disabled = 0" params:@[code] error:innerError];
        if (success) {
            [store.database executeParameterizedUpdate:@"UPDATE invite_codes SET disabled = 1 WHERE code = ? AND uses >= max_uses" params:@[code] error:nil];
        }
    } error:error];
    return success;
}

#pragma mark - Reserved Handles

- (BOOL)reserveHandle:(NSString *)handle error:(NSError **)error {
    NSString *normalized = [ATProtoHandleValidator normalizeHandle:handle ?: @""];
    if (normalized.length == 0) return NO;
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store.database executeParameterizedUpdate:@"INSERT OR IGNORE INTO reserved_handles (handle, created_at) VALUES (?, ?)" params:@[normalized, @([[NSDate date] timeIntervalSince1970])] error:innerError];
    } error:error];
    return success;
}

- (BOOL)isHandleReserved:(NSString *)handle error:(NSError **)error {
    NSString *normalized = [ATProtoHandleValidator normalizeHandle:handle ?: @""];
    if (normalized.length == 0) return NO;
    __block BOOL reserved = NO;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSArray *results = [store.database executeParameterizedQuery:@"SELECT 1 FROM reserved_handles WHERE handle = ? LIMIT 1" params:@[normalized] error:innerError];
        reserved = (results.count > 0);
    } error:error];
    return reserved;
}

#pragma mark - App Passwords

- (nullable NSDictionary *)createAppPasswordForAccount:(NSString *)accountDid name:(NSString *)name privileged:(BOOL)privileged error:(NSError **)error {
    if (accountDid.length == 0 || name.length == 0) return nil;
    __block NSDictionary *result = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *password = appPasswordGenerateSecret();
        NSData *salt = appPasswordGenerateSalt();
        NSData *hash = appPasswordHash(password, salt);
        if (!hash) return;
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSString *sql = @"INSERT INTO app_passwords (id, account_did, name, password_hash, password_salt, privileged, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";
        if ([store.database executeParameterizedUpdate:sql params:@[[[NSUUID UUID] UUIDString], accountDid, name, hash, salt, @(privileged), @(now)] error:innerError]) {
            result = @{
                @"name": name,
                @"password": password,
                @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:now]] ?: @"",
                @"privileged": @(privileged)
            };
        }
    } error:error];
    return result;
}

- (NSArray<NSDictionary *> *)listAppPasswordsForAccount:(NSString *)accountDid error:(NSError **)error {
    __block NSMutableArray *passwords = [NSMutableArray array];
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSArray *results = [store.database executeParameterizedQuery:@"SELECT name, created_at, privileged FROM app_passwords WHERE account_did = ? ORDER BY created_at DESC" params:@[accountDid] error:innerError];
        for (NSDictionary *row in results) {
            [passwords addObject:@{
                @"name": row[@"name"] ?: @"",
                @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:[row[@"created_at"] doubleValue]]] ?: @"",
                @"privileged": @([row[@"privileged"] boolValue])
            }];
        }
    } error:error];
    return passwords;
}

- (BOOL)revokeAppPasswordForAccount:(NSString *)accountDid name:(NSString *)name error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store.database executeParameterizedUpdate:@"DELETE FROM app_passwords WHERE account_did = ? AND name = ?" params:@[accountDid, name] error:innerError];
    } error:error];
    return success;
}

- (BOOL)verifyAppPasswordForAccount:(NSString *)accountDid password:(NSString *)password error:(NSError **)error {
    __block BOOL matches = NO;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSArray *results = [store.database executeParameterizedQuery:@"SELECT password_hash, password_salt FROM app_passwords WHERE account_did = ?" params:@[accountDid] error:innerError];
        for (NSDictionary *row in results) {
            NSData *storedHash = row[@"password_hash"];
            NSData *salt = row[@"password_salt"];
            NSData *candidate = appPasswordHash(password, salt);
            if (candidate && [candidate isEqualToData:storedHash]) {
                matches = YES;
                break;
            }
        }
    } error:error];
    return matches;
}

#pragma mark - DID Cache

- (void)cacheDID:(NSString *)did document:(NSDictionary *)document expiresAt:(NSDate *)expiresAt {
    [self.didCachePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:document options:0 error:nil];
        [store.database executeParameterizedUpdate:@"INSERT OR REPLACE INTO did_cache (did, document, expires_at) VALUES (?, ?, ?)" params:@[did, jsonData ?: [NSNull null], @(expiresAt.timeIntervalSince1970)] error:nil];
    } error:nil];
}

- (nullable NSDictionary *)resolveDID:(NSString *)did {
    __block NSDictionary *document = nil;
    [self.didCachePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSArray *results = [store.database executeParameterizedQuery:@"SELECT document FROM did_cache WHERE did = ? AND expires_at > ?" params:@[did, @([[NSDate date] timeIntervalSince1970])] error:nil];
        if (results.count > 0) {
            document = [NSJSONSerialization JSONObjectWithData:results.firstObject[@"document"] options:0 error:nil];
        }
    } error:nil];
    return document;
}

- (NSArray<NSDictionary *> *)enumerateValidCachedDIDsWithError:(NSError **)error {
    __block NSMutableArray *results = [NSMutableArray array];
    [self.didCachePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSArray *rows = [store.database executeParameterizedQuery:@"SELECT did, document FROM did_cache WHERE expires_at > ?" params:@[@([[NSDate date] timeIntervalSince1970])] error:innerError];
        for (NSDictionary *row in rows) {
            NSDictionary *doc = [NSJSONSerialization JSONObjectWithData:row[@"document"] options:0 error:nil];
            if (doc) {
                [results addObject:@{@"did": row[@"did"], @"document": doc}];
            }
        }
    } error:error];
    return results;
}

#pragma mark - Event Persistence

- (BOOL)logHostingEvent:(NSString *)did type:(NSString *)type details:(nullable NSDictionary *)details createdBy:(nullable NSString *)createdBy error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSData *json = details ? [NSJSONSerialization dataWithJSONObject:details options:0 error:nil] : nil;
        NSString *jsonStr = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
        success = [store.database executeParameterizedUpdate:@"INSERT INTO hosting_events (did, event_type, details_json, created_by, created_at) VALUES (?, ?, ?, ?, ?)" params:@[did, type, jsonStr ?: [NSNull null], createdBy ?: [NSNull null], @([[NSDate date] timeIntervalSince1970])] error:innerError];
    } error:error];
    return success;
}

- (nullable NSArray<NSDictionary *> *)listHostingEventsForDID:(nullable NSString *)did
                                                        limit:(NSInteger)limit
                                                       offset:(NSInteger)offset
                                                        error:(NSError **)error {
    __block NSMutableArray *results = [NSMutableArray array];
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSMutableString *sql = [@"SELECT id, did, event_type, details_json, created_by, created_at FROM hosting_events" mutableCopy];
        NSMutableArray *params = [NSMutableArray array];
        if (did) {
            [sql appendString:@" WHERE did = ?"];
            [params addObject:did];
        }
        [sql appendString:@" ORDER BY id DESC LIMIT ? OFFSET ?"];
        [params addObject:@(limit)];
        [params addObject:@(offset)];
        NSArray *rows = [store.database executeParameterizedQuery:sql params:params error:innerError];
        for (NSDictionary *row in rows) {
            NSMutableDictionary *mRow = [row mutableCopy];
            if (row[@"details_json"] && row[@"details_json"] != [NSNull null]) {
                NSData *data = [row[@"details_json"] dataUsingEncoding:NSUTF8StringEncoding];
                mRow[@"details"] = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] ?: @{};
            }
            mRow[@"created_at"] = [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:[row[@"created_at"] doubleValue]]];
            [results addObject:mRow];
        }
    } error:error];
    return results;
}

- (BOOL)persistEvent:(int64_t)seq type:(NSString *)type data:(NSData *)data error:(NSError **)error {
    __block BOOL success = NO;
    [self.sequencerPool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store.database executeParameterizedUpdate:@"INSERT INTO events (seq, event_type, event_data, created_at) VALUES (?, ?, ?, ?)" params:@[@(seq), type, data, @([[NSDate date] timeIntervalSince1970])] error:innerError];
    } error:error];
    return success;
}

- (nullable NSArray<NSDictionary *> *)getEventsSince:(int64_t)seq limit:(NSInteger)limit error:(NSError **)error {
    __block NSMutableArray *events = [NSMutableArray array];
    [self.sequencerPool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSArray *rows = [store.database executeParameterizedQuery:@"SELECT seq, event_type, event_data, created_at FROM events WHERE seq > ? ORDER BY seq ASC LIMIT ?" params:@[@(seq), @(limit)] error:innerError];
        for (NSDictionary *row in rows) {
            [events addObject:@{
                @"seq": row[@"seq"],
                @"type": row[@"event_type"],
                @"data": row[@"event_data"],
                @"created_at": [NSDate dateWithTimeIntervalSince1970:[row[@"created_at"] doubleValue]]
            }];
        }
    } error:error];
    return events;
}

- (int64_t)getMaxEventSequence:(NSError **)error {
    __block int64_t maxSeq = 0;
    [self.sequencerPool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSArray *results = [store.database executeParameterizedQuery:@"SELECT MAX(seq) as max_seq FROM events" params:@[] error:innerError];
        if (results.count > 0 && results.firstObject[@"max_seq"] != [NSNull null]) {
            maxSeq = [results.firstObject[@"max_seq"] longLongValue];
        }
    } error:error];
    return maxSeq;
}

- (BOOL)pruneEventsBefore:(NSDate *)date error:(NSError **)error {
    __block BOOL success = NO;
    [self.sequencerPool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store.database executeParameterizedUpdate:@"DELETE FROM events WHERE created_at < ?" params:@[@(date.timeIntervalSince1970)] error:innerError];
    } error:error];
    return success;
}

#pragma mark - Lifecycle

- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    return store.database;
}

- (nullable void *)serviceDatabase {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:nil];
    return store ? [store.database internalSQLiteHandle] : NULL;
}

- (void)closeAll {
    [self.servicePool closeAll];
    [self.didCachePool closeAll];
    [self.sequencerPool closeAll];
    [self.userDatabasePool closeAll];
}

@end
