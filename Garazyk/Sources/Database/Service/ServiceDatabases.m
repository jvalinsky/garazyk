#import "ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/ActorStore/PDSActorStore+Account.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Database/Migrations/PDSMigrationManager.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Core/PDSDataPaths.h"
#import "Identity/ATProtoHandleValidator.h"
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonDigest.h>
#import "Debug/PDSLogger.h"
#import <sqlite3.h>

NSString * const PDSServiceDatabasesErrorDomain = @"com.atproto.pds.service.databases";

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
@property (nonatomic, copy) NSString *serviceDbPath;
@property (nonatomic, copy) NSString *didCacheDbPath;
@property (nonatomic, copy) NSString *sequencerDbPath;
@property (nonatomic, strong) PDSDatabase *serviceDb;

@end

@implementation PDSServiceDatabases

+ (instancetype)sharedInstance {
    PDS_LOG_WARN(@"PDSServiceDatabases sharedInstance is deprecated - use initWithDirectory:serviceMaxSize:didCacheMaxSize:sequencerMaxSize: instead");
    static PDSServiceDatabases *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if defined(__APPLE__)
        NSString *dir = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory 
                                                                 inDomains:NSUserDomainMask].firstObject 
                    path];
#else
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".local/share"];
#endif
        NSString *pdsDir = [dir stringByAppendingPathComponent:@"ATProtoPDS"];
        shared = [[PDSServiceDatabases alloc] initWithDirectory:pdsDir 
                                                    serviceMaxSize:100
                                                   didCacheMaxSize:1000 
                                                 sequencerMaxSize:100];
    });
    return shared;
}

- (instancetype)initWithDirectory:(NSString *)directory 
                     serviceMaxSize:(NSUInteger)serviceMaxSize
                   didCacheMaxSize:(NSUInteger)didCacheMaxSize
                 sequencerMaxSize:(NSUInteger)sequencerMaxSize {
    self = [super init];
    if (self) {
        PDSDataPaths *paths = [PDSDataPaths pathsForBaseDirectory:directory];
        [paths createDirectoriesWithError:nil];

        _serviceDbPath = paths.serviceDirectory;
        _didCacheDbPath = paths.didCacheDirectory;
        _sequencerDbPath = paths.sequencerDirectory;
        
        _servicePool = [[PDSDatabasePool alloc] initWithDbDirectory:_serviceDbPath maxSize:serviceMaxSize];
        _didCachePool = [[PDSDatabasePool alloc] initWithDbDirectory:_didCacheDbPath maxSize:didCacheMaxSize];
        _sequencerPool = [[PDSDatabasePool alloc] initWithDbDirectory:_sequencerDbPath maxSize:sequencerMaxSize];
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
    if (![migrationManager migrateDatabase:store.db error:&migrationError]) {
        PDS_LOG_DB_ERROR(@"Service database migration failed: %@", migrationError);
        if (error) *error = migrationError;
        return NO;
    }

    PDS_LOG_DB_INFO(@"Service database schema migration complete (version %ld)", (long)[migrationManager currentVersion:store.db]);
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
        if (!store.db) {
            if (innerError) {
                *innerError = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                                  code:SQLITE_ERROR
                                              userInfo:@{NSLocalizedDescriptionKey: @"Database not open"}];
            }
            success = NO;
            return;
        }

        char *errMsg = NULL;
        int result = sqlite3_exec(store.db, sql.UTF8String, NULL, NULL, &errMsg);

        if (result != SQLITE_OK) {
            if (innerError) {
                *innerError = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                                  code:result
                                              userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg]}];
            }
            sqlite3_free(errMsg);
            success = NO;
        }
    } error:error];
    return success;
}

#pragma mark - Account Operations

- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    PDSDatabaseAccount *existing = [self accountForDid:account.did error:nil];
    if (existing) {
        return [self updateAccount:account error:error];
    }
    
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store createAccount:account error:innerError];
    } error:&localError];
    if (error) *error = localError;
    return success;
}

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    return [self saveAccount:account error:error];
}

- (BOOL)createAccounts:(NSArray<PDSDatabaseAccount *> *)accounts error:(NSError **)error {
    __block BOOL success = YES;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        for (PDSDatabaseAccount *account in accounts) {
            BOOL accountSuccess = [store createAccount:account error:innerError];
            if (!accountSuccess) {
                success = NO;
                break;
            }
        }
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error {
    return [self getAccountByDid:did error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        account = [reader getAccountForDid:did error:innerError];
    } error:error];
    return account;
}

- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error {
    return [self getAccountByHandle:handle error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return nil;
    return [store getAccountByHandle:handle error:error];
}

- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error {
    return [self getAccountByEmail:email error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return nil;
    return [store getAccountByEmail:email error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT a.* FROM accounts a "
                         @"INNER JOIN refresh_tokens rt ON a.did = rt.account_did "
                         @"WHERE rt.token = ? AND rt.expires_at > ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, refreshToken.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [store accountFromStatement:stmt];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return account;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    PDSDatabaseAccount *account = [self getAccountByRefreshToken:refreshToken error:error];
    return account.did;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store updateAccount:account error:innerError];
    } error:&localError];
    if (error) *error = localError;
    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteAccount:did error:innerError];
    } error:&localError];
    if (error) *error = localError;
    return success;
}

- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return @[];
    return [store getAllAccountsWithError:error] ?: @[];
}

- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    return [self getAccountsWithLimit:limit cursor:cursor error:error];
}

- (NSArray<PDSDatabaseAccount *> *)getAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return @[];
    NSArray *all = [store getAllAccountsWithError:error];
    if (!all) return @[];
    if (cursor) {
        NSUInteger index = [all indexOfObjectPassingTest:^BOOL(PDSDatabaseAccount *obj, NSUInteger idx, BOOL *stop) {
            return [obj.did isEqualToString:cursor];
        }];
        if (index != NSNotFound && index + 1 < all.count) {
            all = [all subarrayWithRange:NSMakeRange(index + 1, MIN((NSUInteger)limit, all.count - index - 1))];
        } else {
            all = @[];
        }
    } else if (all.count > (NSUInteger)limit) {
        all = [all subarrayWithRange:NSMakeRange(0, (NSUInteger)limit)];
    }
    return all;
}

#pragma mark - Refresh Token Operations

- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid error:(NSError **)error {
    return [self storeRefreshToken:token forAccount:accountDid error:error];
}

- (BOOL)storeRefreshToken:(NSString *)token forAccount:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);
        NSUInteger refreshTokenTtl = self.refreshTokenTTLSeconds > 0 ? self.refreshTokenTTLSeconds : (30 * 24 * 60 * 60);
        sqlite3_bind_double(stmt, 4, [[NSDate dateWithTimeIntervalSinceNow:refreshTokenTtl] timeIntervalSince1970]);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];
    if (error) *error = localError;
    return success;
}

- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error {
    return [self deleteRefreshToken:token error:error];
}

- (BOOL)deleteRefreshToken:(NSString *)token error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];
    if (error) *error = localError;
    return success;
}

- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error {
    return [self deleteRefreshTokensForAccount:accountDid error:error];
}

- (BOOL)deleteRefreshTokensForAccount:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];
    if (error) *error = localError;
    return success;
}

- (NSArray<NSDictionary *> *)listRefreshTokenSessionsForAccountDid:(NSString *)accountDid
                                                             error:(NSError **)error {
    if (accountDid.length == 0) {
        return @[];
    }

    __block NSMutableArray<NSDictionary *> *sessions = [NSMutableArray array];
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT token, account_did, created_at, expires_at "
                        @"FROM refresh_tokens "
                        @"WHERE account_did = ? AND expires_at > ? "
                        @"ORDER BY created_at DESC";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
            const unsigned char *didText = sqlite3_column_text(stmt, 1);
            if (!tokenText || !didText) {
                continue;
            }

            NSString *token = [NSString stringWithUTF8String:(const char *)tokenText];
            NSString *did = [NSString stringWithUTF8String:(const char *)didText];
            NSTimeInterval createdAt = sqlite3_column_double(stmt, 2);
            NSTimeInterval expiresAt = sqlite3_column_double(stmt, 3);
            NSString *createdAtString = [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:createdAt]] ?: @"";
            NSString *expiresAtString = [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:expiresAt]] ?: @"";

            [sessions addObject:@{
                @"id": refreshTokenSessionID(token),
                @"did": did ?: @"",
                @"createdAt": createdAtString,
                @"expiresAt": expiresAtString
            }];
        }
    } error:error];

    return [sessions copy];
}

- (BOOL)revokeRefreshTokenSessionForAccountDid:(NSString *)accountDid
                                     sessionID:(NSString *)sessionID
                                         error:(NSError **)error {
    if (accountDid.length == 0 || sessionID.length == 0) {
        return NO;
    }

    __block BOOL revoked = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *selectSQL = @"SELECT token FROM refresh_tokens WHERE account_did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *selectStmt = [store prepareStatement:selectSQL error:innerError];
        if (!selectStmt) return;

        sqlite3_bind_text(selectStmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);

        NSString *matchingToken = nil;
        while (sqlite3_step(selectStmt) == SQLITE_ROW) {
            const unsigned char *tokenText = sqlite3_column_text(selectStmt, 0);
            if (!tokenText) {
                continue;
            }
            NSString *candidate = [NSString stringWithUTF8String:(const char *)tokenText];
            if ([refreshTokenSessionID(candidate) isEqualToString:sessionID]) {
                matchingToken = candidate;
                break;
            }
        }

        if (matchingToken.length == 0) {
            return;
        }

        NSString *deleteSQL = @"DELETE FROM refresh_tokens WHERE account_did = ? AND token = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *deleteStmt = [store prepareStatement:deleteSQL error:innerError];
        if (!deleteStmt) return;

        sqlite3_bind_text(deleteStmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(deleteStmt, 2, matchingToken.UTF8String, -1, SQLITE_TRANSIENT);
        revoked = (sqlite3_step(deleteStmt) == SQLITE_DONE && sqlite3_changes(store.db) > 0);
    } error:&localError];

    if (error) {
        *error = localError;
    }
    return revoked;
}

#pragma mark - Invite Code Operations

- (BOOL)createInviteCode:(NSString *)code forAccount:(NSString *)accountDid maxUses:(NSInteger)maxUses error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO invite_codes (id, code, account_did, created_at, max_uses) VALUES (?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, [[NSUUID UUID] UUIDString].UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, code.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, [[NSDate date] timeIntervalSince1970]);
        sqlite3_bind_int64(stmt, 5, maxUses);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];
    if (error) *error = localError;
    return success;
}

- (nullable NSString *)getInviteCodeForAccount:(NSString *)accountDid error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return nil;
    NSString *sql = @"SELECT code FROM invite_codes WHERE account_did = ? AND disabled = 0 LIMIT 1";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:error];
    if (!stmt) return nil;
    sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
    NSString *code = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        code = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
    }
    return code;
}

- (BOOL)useInviteCode:(NSString *)code error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"UPDATE invite_codes SET uses = uses + 1 WHERE code = ? AND disabled = 0";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, code.UTF8String, -1, SQLITE_TRANSIENT);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
        [store finalizeStatement:stmt];
        if (success) {
            sql = @"UPDATE invite_codes SET disabled = 1 WHERE code = ? AND uses >= max_uses";
            stmt = [store prepareStatement:sql error:nil];
            if (stmt) {
                sqlite3_bind_text(stmt, 1, code.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_step(stmt);
                [store finalizeStatement:stmt];
            }
        }
    } error:&localError];
    if (error) *error = localError;
    return success;
}

#pragma mark - Reserved Handle Operations

- (BOOL)reserveHandle:(NSString *)handle error:(NSError **)error {
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle ?: @""];
    if (normalizedHandle.length == 0) return NO;
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT OR IGNORE INTO reserved_handles (handle, created_at) VALUES (?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, normalizedHandle.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];
    if (error) *error = localError;
    return success;
}

- (BOOL)isHandleReserved:(NSString *)handle error:(NSError **)error {
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle ?: @""];
    if (normalizedHandle.length == 0) return NO;
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return NO;
    NSString *sql = @"SELECT 1 FROM reserved_handles WHERE handle = ? LIMIT 1";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:error];
    if (!stmt) return NO;
    sqlite3_bind_text(stmt, 1, normalizedHandle.UTF8String, -1, SQLITE_TRANSIENT);
    return (sqlite3_step(stmt) == SQLITE_ROW);
}

#pragma mark - App Password Operations

- (nullable NSDictionary *)createAppPasswordForAccount:(NSString *)accountDid name:(NSString *)name privileged:(BOOL)privileged error:(NSError **)error {
    if (accountDid.length == 0 || name.length == 0) return nil;
    __block NSDictionary *result = nil;
    __block NSError *localError = nil;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *password = appPasswordGenerateSecret();
        NSData *salt = appPasswordGenerateSalt();
        NSData *hash = appPasswordHash(password, salt);
        if (!hash) return;
        NSTimeInterval createdAt = [[NSDate date] timeIntervalSince1970];
        NSString *sql = @"INSERT INTO app_passwords (id, account_did, name, password_hash, password_salt, privileged, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, [[NSUUID UUID] UUIDString].UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, name.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 4, hash.bytes, (int)hash.length, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 5, salt.bytes, (int)salt.length, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 6, privileged ? 1 : 0);
        sqlite3_bind_double(stmt, 7, createdAt);
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            result = @{@"name": name, @"password": password, @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:createdAt]] ?: @"", @"privileged": @(privileged)};
        }
    } error:&localError];
    if (error) *error = localError;
    return result;
}

- (NSArray<NSDictionary *> *)listAppPasswordsForAccount:(NSString *)accountDid error:(NSError **)error {
    if (accountDid.length == 0) return @[];
    __block NSMutableArray<NSDictionary *> *passwords = [NSMutableArray array];
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT name, created_at, privileged FROM app_passwords WHERE account_did = ? ORDER BY created_at DESC";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSString *name = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
            double createdAt = sqlite3_column_double(stmt, 1);
            int privileged = sqlite3_column_int(stmt, 2);
            [passwords addObject:@{@"name": name, @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:createdAt]] ?: @"", @"privileged": @(privileged != 0)}];
        }
    } error:error];
    return passwords;
}

- (BOOL)revokeAppPasswordForAccount:(NSString *)accountDid name:(NSString *)name error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM app_passwords WHERE account_did = ? AND name = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, name.UTF8String, -1, SQLITE_TRANSIENT);
        success = (sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(store.db) > 0);
    } error:error];
    return success;
}

- (BOOL)verifyAppPasswordForAccount:(NSString *)accountDid password:(NSString *)password error:(NSError **)error {
    if (accountDid.length == 0 || password.length == 0) return NO;
    __block BOOL matches = NO;
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT password_hash, password_salt FROM app_passwords WHERE account_did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSData *storedHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:sqlite3_column_bytes(stmt, 0)];
            NSData *salt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 1) length:sqlite3_column_bytes(stmt, 1)];
            NSData *candidate = appPasswordHash(password, salt);
            if (candidate && [candidate isEqualToData:storedHash]) { matches = YES; break; }
        }
    } error:error];
    return matches;
}

#pragma mark - DID Cache Operations

- (void)cacheDID:(NSString *)did document:(NSDictionary *)document expiresAt:(NSDate *)expiresAt {
    [self.didCachePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT OR REPLACE INTO did_cache (did, document, expires_at) VALUES (?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:nil];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:document options:0 error:nil];
        if (jsonData) sqlite3_bind_blob(stmt, 2, jsonData.bytes, (int)jsonData.length, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, expiresAt.timeIntervalSince1970);
        sqlite3_step(stmt);
    } error:nil];
}

- (nullable NSDictionary *)resolveDID:(NSString *)did {
    __block NSDictionary *document = nil;
    [self.didCachePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT document FROM did_cache WHERE did = ? AND expires_at > ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:nil];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            NSData *jsonData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:sqlite3_column_bytes(stmt, 0)];
            document = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        }
    } error:nil];
    return document;
}

#pragma mark - Event Persistence

- (BOOL)logHostingEvent:(NSString *)did type:(NSString *)type details:(nullable NSDictionary *)details createdBy:(nullable NSString *)createdBy error:(NSError **)error {
    __block BOOL success = NO;
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO hosting_events (did, event_type, details_json, created_by, created_at) VALUES (?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, type.UTF8String, -1, SQLITE_TRANSIENT);
        if (details) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:details options:0 error:nil];
            if (jsonData) sqlite3_bind_text(stmt, 3, [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding].UTF8String, -1, SQLITE_TRANSIENT);
            else sqlite3_bind_null(stmt, 3);
        } else sqlite3_bind_null(stmt, 3);
        if (createdBy) sqlite3_bind_text(stmt, 4, createdBy.UTF8String, -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(stmt, 4);
        sqlite3_bind_double(stmt, 5, [[NSDate date] timeIntervalSince1970]);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:error];
    return success;
}

- (nullable NSArray<NSDictionary *> *)listHostingEventsForDID:(nullable NSString *)did
                                                        limit:(NSInteger)limit
                                                       offset:(NSInteger)offset
                                                        error:(NSError **)error {
    __block NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    __block NSError *queryError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        
        NSMutableString *sql = [@"SELECT id, did, event_type, details_json, created_by, created_at FROM hosting_events" mutableCopy];
        NSMutableArray *params = [NSMutableArray array];
        
        if (did) {
            [sql appendString:@" WHERE did = ?"];
            [params addObject:did];
        }
        
        [sql appendString:@" ORDER BY id DESC LIMIT ? OFFSET ?"];
        [params addObject:@(limit)];
        [params addObject:@(offset)];
        
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        
        for (int i = 0; i < params.count; i++) {
            id val = params[i];
            if ([val isKindOfClass:[NSString class]]) {
                sqlite3_bind_text(stmt, i + 1, [val UTF8String], -1, SQLITE_TRANSIENT);
            } else if ([val isKindOfClass:[NSNumber class]]) {
                sqlite3_bind_int64(stmt, i + 1, [val longLongValue]);
            }
        }
        
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            row[@"id"] = @(sqlite3_column_int64(stmt, 0));
            
            const char *didVal = (const char *)sqlite3_column_text(stmt, 1);
            if (didVal) row[@"did"] = [NSString stringWithUTF8String:didVal];
            
            const char *typeVal = (const char *)sqlite3_column_text(stmt, 2);
            if (typeVal) row[@"event_type"] = [NSString stringWithUTF8String:typeVal];
            
            const char *detailsVal = (const char *)sqlite3_column_text(stmt, 3);
            if (detailsVal) {
                NSString *json = [NSString stringWithUTF8String:detailsVal];
                NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *details = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                row[@"details"] = details ?: @{};
            }
            
            const char *createdByVal = (const char *)sqlite3_column_text(stmt, 4);
            if (createdByVal) row[@"created_by"] = [NSString stringWithUTF8String:createdByVal];
            
            NSTimeInterval createdAt = sqlite3_column_double(stmt, 5);
            row[@"created_at"] = [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:createdAt]];
            
            [results addObject:[row copy]];
        }
    } error:&queryError];

    if (error && queryError) *error = queryError;
    return results;
}

- (BOOL)persistEvent:(int64_t)seq
 type:(NSString *)type data:(NSData *)data error:(NSError **)error {
    // Defense-in-depth: warn if seq is invalid (should be positive per ATProto spec)
    if (seq <= 0) {
        PDS_LOG_SYNC_WARN(@"persistEvent called with invalid seq=%lld for type=%@; "
                           @"this indicates a sequence number bug", (long long)seq, type);
    }
    __block BOOL success = NO;
    [self.sequencerPool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO events (seq, event_type, event_data, created_at) VALUES (?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_int64(stmt, 1, seq);
        sqlite3_bind_text(stmt, 2, type.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 3, data.bytes, (int)data.length, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, [[NSDate date] timeIntervalSince1970]);
        int rc = sqlite3_step(stmt);
        success = (rc == SQLITE_DONE);
        if (!success && innerError) {
            NSString *message = [NSString stringWithFormat:@"Failed to persist event: %s", sqlite3_errmsg(store.db)];
            *innerError = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                              code:rc
                                          userInfo:@{NSLocalizedDescriptionKey: message}];
        }
    } error:error];
    return success;
}

- (nullable NSArray<NSDictionary *> *)getEventsSince:(int64_t)seq limit:(NSInteger)limit error:(NSError **)error {
    __block NSMutableArray *events = [NSMutableArray array];
    [self.sequencerPool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT seq, event_type, event_data, created_at FROM events WHERE seq > ? ORDER BY seq ASC LIMIT ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_int64(stmt, 1, seq);
        sqlite3_bind_int64(stmt, 2, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            int64_t seqVal = sqlite3_column_int64(stmt, 0);
            NSString *type = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
            NSData *data = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:sqlite3_column_bytes(stmt, 2)];
            NSTimeInterval created = sqlite3_column_double(stmt, 3);
            [events addObject:@{@"seq": @(seqVal), @"type": type, @"data": data, @"created_at": [NSDate dateWithTimeIntervalSince1970:created]}];
        }
    } error:error];
    return events;
}

- (int64_t)getMaxEventSequence:(NSError **)error {
    __block int64_t maxSeq = 0;
    [self.sequencerPool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT MAX(seq) FROM events";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        if (sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL) {
            maxSeq = sqlite3_column_int64(stmt, 0);
        }
    } error:error];
    return maxSeq;
}

- (BOOL)pruneEventsBefore:(NSDate *)date error:(NSError **)error {
    __block BOOL success = NO;
    [self.sequencerPool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM events WHERE created_at < ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:error];
    return success;
}

#pragma mark - Cleanup

- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error {
    if (self.serviceDb && self.serviceDb.isOpen) {
        return self.serviceDb;
    }

    NSString *dbFilePath = [self.serviceDbPath stringByAppendingPathComponent:@"service.db"];
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbFilePath]];
    if (![db openWithError:error]) {
        self.serviceDb = nil;
        return nil;
    }
    self.serviceDb = db;
    return self.serviceDb;
}

- (nullable sqlite3 *)serviceDatabase {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:nil];
    return store ? store.db : NULL;
}

- (void)closeAll {
    [self.serviceDb close];
    self.serviceDb = nil;
    [self.servicePool closeAll];
    [self.didCachePool closeAll];
    [self.sequencerPool closeAll];
}

@end
