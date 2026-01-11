#import "ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Schema/PDSSchemaManager.h"
#import <sqlite3.h>

NSString * const PDSServiceDatabasesErrorDomain = @"com.atproto.pds.service.databases";

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
        NSString *dir = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory 
                                                                 inDomains:NSUserDomainMask].firstObject 
                    path];
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
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:directory]) {
            [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        _serviceDbPath = [directory stringByAppendingPathComponent:@"service"];
        _didCacheDbPath = [directory stringByAppendingPathComponent:@"did_cache"];
        _sequencerDbPath = [directory stringByAppendingPathComponent:@"sequencer"];
        
        _servicePool = [[PDSDatabasePool alloc] initWithDbDirectory:_serviceDbPath maxSize:serviceMaxSize];
        _didCachePool = [[PDSDatabasePool alloc] initWithDbDirectory:_didCacheDbPath maxSize:didCacheMaxSize];
        _sequencerPool = [[PDSDatabasePool alloc] initWithDbDirectory:_sequencerDbPath maxSize:sequencerMaxSize];
        
        [self initializeServiceSchema:nil];
        [self initializeDidCacheSchema:nil];
        [self initializeSequencerSchema:nil];
    }
    return self;
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
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store createAccount:account error:&localError];
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

- (BOOL)createAccounts:(NSArray<PDSDatabaseAccount *> *)accounts error:(NSError **)error {
    __block BOOL success = YES;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        for (PDSDatabaseAccount *account in accounts) {
            BOOL accountSuccess = [store createAccount:account error:&localError];
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

    NSString *sql = @"SELECT * FROM accounts WHERE handle = ?";
    __autoreleasing NSError *stmtError = nil;
    sqlite3_stmt *stmt = [store prepareStatement:sql error:&stmtError];
    if (!stmt) {
        if (error) *error = stmtError;
        return nil;
    }

    sqlite3_bind_text(stmt, 1, handle.UTF8String, -1, SQLITE_TRANSIENT);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [store accountFromStatement:stmt];
    }

    [store finalizeStatement:stmt];
    return account;
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
                    @"WHERE rt.token = ?";
    __autoreleasing NSError *stmtError = nil;
    sqlite3_stmt *stmt = [store prepareStatement:sql error:&stmtError];
    if (!stmt) {
        if (error) *error = stmtError;
        return nil;
    }

    sqlite3_bind_text(stmt, 1, refreshToken.UTF8String, -1, SQLITE_TRANSIENT);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [store accountFromStatement:stmt];
    }

    [store finalizeStatement:stmt];
    return account;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store updateAccount:account error:&localError];
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }
    
    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteAccount:did error:&localError];
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }
    
    return success;
}

- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return @[];
    NSArray *accounts = [db getAllAccountsWithError:error];
    [db close];
    return accounts ?: @[];
}

#pragma mark - Refresh Token Operations

- (BOOL)storeRefreshToken:(NSString *)token forAccount:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:&localError];
        if (!stmt) { success = NO; return; }
        
        sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);
        sqlite3_bind_double(stmt, 4, [[NSDate dateWithTimeIntervalSinceNow:30 * 24 * 60 * 60] timeIntervalSince1970]);

        success = (sqlite3_step(stmt) == SQLITE_DONE);
        [store finalizeStatement:stmt];
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}

- (BOOL)deleteRefreshTokensForAccount:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:&localError];
        if (!stmt) { success = NO; return; }
        
        sqlite3_bind_text(stmt, 1, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        success = (sqlite3_step(stmt) == SQLITE_DONE);
        [store finalizeStatement:stmt];
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

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO invite_codes (id, code, account_did, created_at, max_uses) "
                        @"VALUES (?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:&localError];
        if (!stmt) { success = NO; return; }
        
        NSString *uuid = [[NSUUID UUID] UUIDString];
        sqlite3_bind_text(stmt, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, code.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, [[NSDate date] timeIntervalSince1970]);
        sqlite3_bind_int64(stmt, 5, maxUses);

        success = (sqlite3_step(stmt) == SQLITE_DONE);
        [store finalizeStatement:stmt];
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

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"UPDATE invite_codes SET uses = uses + 1 WHERE code = ? AND disabled = 0";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:&localError];
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

#pragma mark - DID Cache Operations

- (void)cacheDID:(NSString *)did 
        document:(NSDictionary *)document 
      expiresAt:(NSDate *)expiresAt {
    [self.didCachePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
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
    
    [self.didCachePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader) {
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
