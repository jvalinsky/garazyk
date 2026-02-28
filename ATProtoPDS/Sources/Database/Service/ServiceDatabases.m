#import "ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStore+Account.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Core/PDSDataPaths.h"
#import "Identity/ATProtoHandleValidator.h"
#import "App/PDSConfiguration.h"
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonDigest.h>
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

@interface PDSServiceDatabases ()

@property (nonatomic, strong, readwrite) PDSDatabasePool *servicePool;
@property (nonatomic, strong, readwrite) PDSDatabasePool *didCachePool;
@property (nonatomic, strong, readwrite) PDSDatabasePool *sequencerPool;
@property (nonatomic, copy) NSString *serviceDbPath;
@property (nonatomic, copy) NSString *didCacheDbPath;
@property (nonatomic, copy) NSString *sequencerDbPath;

@end

@implementation PDSServiceDatabases

+ (instancetype)sharedInstance {
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
    NSString *schemaSQL = [[PDSSchemaManager sharedManager] serviceSchemaSQL];
    return [self executeSQL:schemaSQL onPool:self.servicePool error:error];
}

- (BOOL)initializeDidCacheSchema:(NSError **)error {
    NSString *schemaSQL = [NSString stringWithFormat:@"%@;%@",
                           [[PDSSchemaManager sharedManager] serviceDIDCacheTableSchema],
                           @"CREATE INDEX IF NOT EXISTS idx_did_cache_expires ON did_cache(expires_at);"];
    return [self executeSQL:schemaSQL onPool:self.didCachePool error:error];
}

- (BOOL)initializeSequencerSchema:(NSError **)error {
    NSString *schemaSQL = [NSString stringWithFormat:@"%@;%@",
                           [[PDSSchemaManager sharedManager] serviceRepoSequenceTableSchema],
                           @"CREATE INDEX IF NOT EXISTS idx_repo_sequence_did ON repo_sequence(did);"];
    return [self executeSQL:schemaSQL onPool:self.sequencerPool error:error];
}

- (BOOL)executeSQL:(NSString *)sql onPool:(PDSDatabasePool *)pool error:(NSError **)error {
    PDSActorStore *store = [pool storeForDid:@"__service__" error:error];
    if (!store) return NO;
    
    char *errMsg = NULL;
    int result = sqlite3_exec(store.db, sql.UTF8String, NULL, NULL, &errMsg);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg]}];
        }
        sqlite3_free(errMsg);
        return NO;
    }
    
    return YES;
}

#pragma mark - Account Operations

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    NSError *txnError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store createAccount:account error:innerError];
    } error:&txnError];

    NSError *finalError = blockError ?: txnError;

    if (!success && finalError) {
        if (error) *error = finalError;
    }

    return success;
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

- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:nil];
    if (!store) {
        return nil;
    }

    NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
    __autoreleasing NSError *stmtError = nil;
    sqlite3_stmt *stmt = [store prepareStatement:sql error:&stmtError];
    if (!stmt) {
        if (error) *error = stmtError;
        return nil;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [store accountFromStatement:stmt];
    }

    [store finalizeStatement:stmt];
    return account;
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return nil;
    
    return [store getAccountByHandle:handle error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return nil;
    
    return [store getAccountByEmail:email error:error];
}

- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;

    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:nil];
    if (!store) {
        if (error) {
            *error = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to open service database"}];
        }
        return nil;
    }

    NSString *sql = @"SELECT a.* FROM accounts a "
                    @"INNER JOIN refresh_tokens rt ON a.did = rt.account_did "
                    @"WHERE rt.token = ? AND rt.expires_at > ?";
    __autoreleasing NSError *stmtError = nil;
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:&stmtError];
    if (!stmt) {
        if (error) *error = stmtError;
        return nil;
    }

    sqlite3_bind_text(stmt, 1, refreshToken.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [store accountFromStatement:stmt];
    }
    return account;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store updateAccount:account error:innerError];
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }
    
    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteAccount:did error:innerError];
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }
    
    return success;
}

- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return @[];
    
    return [store getAllAccountsWithError:error] ?: @[];
}

- (NSArray<PDSDatabaseAccount *> *)getAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return @[];
    
    // Fallback to getAllAccounts and filter if needed, or implement limit in ActorStore
    // For now, let's just use getAllAccounts for consistency if limit is not critical here
    NSArray *all = [store getAllAccountsWithError:error];
    if (!all) return @[];
    
    // Simple cursor implementation
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

- (BOOL)storeRefreshToken:(NSString *)token forAccount:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }
        
        sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);
        
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        NSUInteger refreshTokenTtl = config.refreshTokenTtlSeconds > 0 ? config.refreshTokenTtlSeconds : (30 * 24 * 60 * 60);
        sqlite3_bind_double(stmt, 4, [[NSDate dateWithTimeIntervalSinceNow:refreshTokenTtl] timeIntervalSince1970]);

        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

- (BOOL)deleteRefreshToken:(NSString *)token error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }

        sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

- (BOOL)deleteRefreshTokensForAccount:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }
        
        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

#pragma mark - Invite Code Operations

- (BOOL)createInviteCode:(NSString *)code
              forAccount:(NSString *)accountDid
               maxUses:(NSInteger)maxUses
                 error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO invite_codes (id, code, account_did, created_at, max_uses) "
                        @"VALUES (?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }
        
        NSString *uuid = [[NSUUID UUID] UUIDString];
        sqlite3_bind_text(stmt, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, code.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, [[NSDate date] timeIntervalSince1970]);
        sqlite3_bind_int64(stmt, 5, maxUses);

        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

- (nullable NSString *)getInviteCodeForAccount:(NSString *)accountDid error:(NSError **)error {
    __block NSString *code = nil;

    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:nil];
    if (!store) {
        if (error) {
            *error = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to open service database"}];
        }
        return nil;
    }

    NSString *sql = @"SELECT code FROM invite_codes WHERE account_did = ? AND disabled = 0 LIMIT 1";
    __autoreleasing NSError *stmtError = nil;
    sqlite3_stmt *stmt = [store prepareStatement:sql error:&stmtError];
    if (!stmt) {
        if (error) *error = stmtError;
        return nil;
    }

    sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        code = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
    }

    [store finalizeStatement:stmt];
    return code;
}

- (BOOL)useInviteCode:(NSString *)code error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"UPDATE invite_codes SET uses = uses + 1 WHERE code = ? AND disabled = 0";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }
        
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

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

#pragma mark - Reserved Handle Operations

- (BOOL)reserveHandle:(NSString *)handle error:(NSError **)error {
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle ?: @""];
    if (normalizedHandle.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing handle"}];
        }
        return NO;
    }

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

    if (!success && localError) {
        if (error) *error = localError;
    }
    return success;
}

- (BOOL)isHandleReserved:(NSString *)handle error:(NSError **)error {
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle ?: @""];
    if (normalizedHandle.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing handle"}];
        }
        return NO;
    }

    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return NO;

    NSString *sql = @"SELECT 1 FROM reserved_handles WHERE handle = ? LIMIT 1";
    __autoreleasing NSError *stmtError = nil;
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:&stmtError];
    if (!stmt) {
        if (error) *error = stmtError;
        return NO;
    }

    sqlite3_bind_text(stmt, 1, normalizedHandle.UTF8String, -1, SQLITE_TRANSIENT);
    BOOL reserved = (sqlite3_step(stmt) == SQLITE_ROW);
    
    return reserved;
}

#pragma mark - App Password Operations

- (nullable NSDictionary *)createAppPasswordForAccount:(NSString *)accountDid
                                                 name:(NSString *)name
                                           privileged:(BOOL)privileged
                                                error:(NSError **)error {
    if (accountDid.length == 0 || name.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing accountDid or name"}];
        }
        return nil;
    }

    __block NSDictionary *result = nil;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        NSString *password = appPasswordGenerateSecret();
        NSData *salt = appPasswordGenerateSalt();
        NSData *hash = appPasswordHash(password, salt);
        if (!hash) {
            if (innerError) {
                *innerError = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to hash app password"}];
            }
            return;
        }

        NSTimeInterval createdAt = [[NSDate date] timeIntervalSince1970];

        NSString *sql = @"INSERT INTO app_passwords (id, account_did, name, password_hash, password_salt, privileged, created_at) "
                        @"VALUES (?, ?, ?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;

        NSString *uuid = [[NSUUID UUID] UUIDString];
        sqlite3_bind_text(stmt, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, name.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 4, hash.bytes, (int)hash.length, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 5, salt.bytes, (int)salt.length, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 6, privileged ? 1 : 0);
        sqlite3_bind_double(stmt, 7, createdAt);

        if (sqlite3_step(stmt) != SQLITE_DONE) {
            if (innerError) {
                *innerError = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                                 code:sqlite3_errcode(store.db)
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to insert app password"}];
            }
            return;
        }

        NSString *createdAtString = [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:createdAt]];
        result = @{
            @"name": name,
            @"password": password,
            @"createdAt": createdAtString ?: @"",
            @"privileged": @(privileged)
        };
    } error:&localError];

    if (!result && localError) {
        if (error) *error = localError;
    }

    return result;
}

- (NSArray<NSDictionary *> *)listAppPasswordsForAccount:(NSString *)accountDid
                                                 error:(NSError **)error {
    if (accountDid.length == 0) return @[];

    __block NSMutableArray<NSDictionary *> *passwords = [NSMutableArray array];
    __block NSError *localError = nil;

    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;

        NSString *sql = @"SELECT name, created_at, privileged FROM app_passwords WHERE account_did = ? ORDER BY created_at DESC";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *nameText = (const char *)sqlite3_column_text(stmt, 0);
            double createdAt = sqlite3_column_double(stmt, 1);
            int privilegedFlag = sqlite3_column_int(stmt, 2);

            NSString *name = nameText ? [NSString stringWithUTF8String:nameText] : @"";
            NSString *createdAtString = [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:createdAt]] ?: @"";

            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = name;
            entry[@"createdAt"] = createdAtString;
            if (privilegedFlag != 0) {
                entry[@"privileged"] = @YES;
            }
            [passwords addObject:entry];
        }
    } error:&localError];

    if (localError && error) {
        *error = localError;
    }

    return passwords;
}

- (BOOL)revokeAppPasswordForAccount:(NSString *)accountDid
                               name:(NSString *)name
                              error:(NSError **)error {
    if (accountDid.length == 0 || name.length == 0) return NO;

    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        NSString *sql = @"DELETE FROM app_passwords WHERE account_did = ? AND name = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, name.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) != SQLITE_DONE) {
            return;
        }
        success = (sqlite3_changes(store.db) > 0);
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

- (BOOL)verifyAppPasswordForAccount:(NSString *)accountDid
                           password:(NSString *)password
                              error:(NSError **)error {
    if (accountDid.length == 0 || password.length == 0) return NO;

    __block BOOL matches = NO;
    __block NSError *localError = nil;

    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;

        NSString *sql = @"SELECT password_hash, password_salt FROM app_passwords WHERE account_did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const void *hashBytes = sqlite3_column_blob(stmt, 0);
            int hashLen = sqlite3_column_bytes(stmt, 0);
            const void *saltBytes = sqlite3_column_blob(stmt, 1);
            int saltLen = sqlite3_column_bytes(stmt, 1);
            if (!hashBytes || hashLen <= 0 || !saltBytes || saltLen <= 0) {
                continue;
            }

            NSData *storedHash = [NSData dataWithBytes:hashBytes length:(NSUInteger)hashLen];
            NSData *salt = [NSData dataWithBytes:saltBytes length:(NSUInteger)saltLen];
            NSData *candidate = appPasswordHash(password, salt);
            if (candidate && [candidate isEqualToData:storedHash]) {
                matches = YES;
                break;
            }
        }
    } error:&localError];

    if (localError && error) {
        *error = localError;
    }

    return matches;
}

#pragma mark - DID Cache Operations

- (void)cacheDID:(NSString *)did 
        document:(NSDictionary *)document 
      expiresAt:(NSDate *)expiresAt {
    [self.didCachePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        
        NSString *sql = @"INSERT OR REPLACE INTO did_cache (did, document, expires_at) VALUES (?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:nil];
        if (!stmt) return;
        
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:document options:0 error:&jsonError];
        if (jsonData) {
            sqlite3_bind_blob(stmt, 2, jsonData.bytes, (int)jsonData.length, SQLITE_TRANSIENT);
        }
        sqlite3_bind_double(stmt, 3, expiresAt.timeIntervalSince1970);
        
        sqlite3_step(stmt);
        [store finalizeStatement:stmt];
    } error:nil];
}

- (nullable NSDictionary *)resolveDID:(NSString *)did {
    __block NSDictionary *document = nil;
    
    [self.didCachePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        
        NSString *sql = @"SELECT document FROM did_cache WHERE did = ? AND expires_at > ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:nil];
        if (!stmt) return;
        
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const void *blob = sqlite3_column_blob(stmt, 0);
            int bytes = sqlite3_column_bytes(stmt, 0);
            NSData *jsonData = [NSData dataWithBytes:blob length:bytes];
            document = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        }
        
        [store finalizeStatement:stmt];
    } error:nil];
    
    return document;
}

#pragma mark - Event Persistence

- (BOOL)persistEvent:(int64_t)seq
                type:(NSString *)type
                data:(NSData *)data
               error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO events (seq, event_type, event_data, created_at) VALUES (?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }
        
        sqlite3_bind_int64(stmt, 1, seq);
        sqlite3_bind_text(stmt, 2, type.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 3, data.bytes, (int)data.length, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, [[NSDate date] timeIntervalSince1970]);
        
        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];
    
    if (!success && localError) {
        if (error) *error = localError;
    }
    
    return success;
}

- (nullable NSArray<NSDictionary *> *)getEventsSince:(int64_t)seq
                                              limit:(NSInteger)limit
                                              error:(NSError **)error {
    __block NSMutableArray *events = [NSMutableArray array];
    __block NSError *localError = nil;
    
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT seq, event_type, event_data, created_at FROM events WHERE seq > ? ORDER BY seq ASC LIMIT ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        
        sqlite3_bind_int64(stmt, 1, seq);
        sqlite3_bind_int64(stmt, 2, limit);
        
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            int64_t seqVal = sqlite3_column_int64(stmt, 0);
            NSString *type = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
            const void *dataBlob = sqlite3_column_blob(stmt, 2);
            int dataLen = sqlite3_column_bytes(stmt, 2);
            NSData *data = [NSData dataWithBytes:dataBlob length:dataLen];
            NSTimeInterval created = sqlite3_column_double(stmt, 3);
            
            [events addObject:@{
                @"seq": @(seqVal),
                @"type": type,
                @"data": data,
                @"created_at": [NSDate dateWithTimeIntervalSince1970:created]
            }];
        }
    } error:&localError];
    
    if (localError) {
        if (error) *error = localError;
        return nil;
    }
    
    return events;
}

- (int64_t)getMaxEventSequence:(NSError **)error {
    __block int64_t maxSeq = 0;
    __block NSError *localError = nil;
    
    [self.servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT MAX(seq) FROM events";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            if (sqlite3_column_type(stmt, 0) != SQLITE_NULL) {
                maxSeq = sqlite3_column_int64(stmt, 0);
            }
        }
    } error:&localError];
    
    if (localError) {
        if (error) *error = localError;
        return 0;
    }
    
    return maxSeq;
}

- (BOOL)pruneEventsBefore:(NSDate *)date error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM events WHERE created_at < ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }
        
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970);
        
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
            int changes = sqlite3_changes(store.db);
            // We could log this if logger was available here
            (void)changes; 
        }
    } error:&localError];
    
    if (!success && localError) {
        if (error) *error = localError;
    }
    
    return success;
}

#pragma mark - Cleanup

- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error {
    NSString *dbFilePath = [self.serviceDbPath stringByAppendingPathComponent:@"service.db"];
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbFilePath]];
    if (![db openWithError:error]) {
        return nil;
    }
    return db;
}

- (void)closeAll {
    [self.servicePool closeAll];
    [self.didCachePool closeAll];
    [self.sequencerPool closeAll];
}

@end
