#import "ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
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
        
        _serviceDbPath = [directory stringByAppendingPathComponent:@"service.sqlite"];
        _didCacheDbPath = [directory stringByAppendingPathComponent:@"did_cache.sqlite"];
        _sequencerDbPath = [directory stringByAppendingPathComponent:@"sequencer.sqlite"];
        
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
    NSString *schemaSQL = 
        @"CREATE TABLE IF NOT EXISTS accounts ("
        @"    did TEXT PRIMARY KEY,"
        @"    handle TEXT UNIQUE NOT NULL,"
        @"    email TEXT,"
        @"    password_hash BLOB,"
        @"    password_salt BLOB,"
        @"    access_jwt BLOB,"
        @"    refresh_jwt BLOB,"
        @"    created_at REAL NOT NULL,"
        @"    updated_at REAL NOT NULL"
        @");"
        
        @"CREATE TABLE IF NOT EXISTS invite_codes ("
        @"    id TEXT PRIMARY KEY,"
        @"    code TEXT NOT NULL UNIQUE,"
        @"    account_did TEXT NOT NULL,"
        @"    created_at REAL NOT NULL,"
        @"    uses INTEGER DEFAULT 0,"
        @"    max_uses INTEGER DEFAULT 1,"
        @"    disabled INTEGER DEFAULT 0"
        @");"
        
        @"CREATE TABLE IF NOT EXISTS refresh_tokens ("
        @"    token TEXT PRIMARY KEY,"
        @"    account_did TEXT NOT NULL,"
        @"    created_at REAL NOT NULL,"
        @"    expires_at REAL NOT NULL"
        @");"
        
        @"CREATE INDEX IF NOT EXISTS idx_accounts_handle ON accounts(handle);"
        @"CREATE INDEX IF NOT EXISTS idx_invite_codes_code ON invite_codes(code);"
        @"CREATE INDEX IF NOT EXISTS idx_refresh_tokens_account ON refresh_tokens(account_did);";
    
    return [self executeSQL:schemaSQL onPool:self.servicePool error:error];
}

- (BOOL)initializeDidCacheSchema:(NSError **)error {
    NSString *schemaSQL = 
        @"CREATE TABLE IF NOT EXISTS did_cache ("
        @"    did TEXT PRIMARY KEY,"
        @"    document BLOB NOT NULL,"
        @"    expires_at REAL NOT NULL"
        @");"
        
        @"CREATE INDEX IF NOT EXISTS idx_did_cache_expires ON did_cache(expires_at);";
    
    return [self executeSQL:schemaSQL onPool:self.didCachePool error:error];
}

- (BOOL)initializeSequencerSchema:(NSError **)error {
    NSString *schemaSQL = 
        @"CREATE TABLE IF NOT EXISTS repo_sequence ("
        @"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
        @"    did TEXT NOT NULL,"
        @"    root_cid BLOB NOT NULL,"
        @"    sequence_num INTEGER NOT NULL,"
        @"    created_at REAL NOT NULL"
        @");"
        
        @"CREATE INDEX IF NOT EXISTS idx_repo_sequence_did ON repo_sequence(did);"
        @"CREATE INDEX IF NOT EXISTS idx_repo_sequence_num ON repo_sequence(sequence_num);";
    
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
    
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store createAccount:account error:error];
    } error:error];
    
    return success;
}

- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    return [self.servicePool getAccount:did error:error];
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
    NSLog(@"[DEBUG] Looking up account by handle: %@", handle);
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
    
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store updateAccount:account error:error];
    } error:error];
    
    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteAccount:did error:error];
    } error:error];
    
    return success;
}

#pragma mark - Invite Code Operations

- (BOOL)createInviteCode:(NSString *)code 
              forAccount:(NSString *)accountDid
               maxUses:(NSInteger)maxUses
                 error:(NSError **)error {
    __block BOOL success = NO;
    
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO invite_codes (id, code, account_did, created_at, max_uses) "
                        @"VALUES (?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:error];
        if (!stmt) { success = NO; return; }
        
        NSString *uuid = [[NSUUID UUID] UUIDString];
        sqlite3_bind_text(stmt, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, code.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, [[NSDate date] timeIntervalSince1970]);
        sqlite3_bind_int64(stmt, 5, maxUses);
        
        success = (sqlite3_step(stmt) == SQLITE_DONE);
        [store finalizeStatement:stmt];
    } error:error];
    
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
    
    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"UPDATE invite_codes SET uses = uses + 1 WHERE code = ? AND disabled = 0";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:error];
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
    } error:error];
    
    return success;
}

#pragma mark - DID Cache Operations

- (void)cacheDID:(NSString *)did 
        document:(NSDictionary *)document 
      expiresAt:(NSDate *)expiresAt {
    [self.didCachePool transactWithDid:@"__did_cache__" block:^(id<PDSActorStoreTransactor> transactor) {
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
    
    [self.didCachePool readWithDid:@"__did_cache__" block:^id<PDSActorStoreReader> {
        PDSActorStore *store = (PDSActorStore *)self;
        
        NSString *sql = @"SELECT document FROM did_cache WHERE did = ? AND expires_at > ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:nil];
        if (!stmt) return nil;
        
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const void *blob = sqlite3_column_blob(stmt, 0);
            int bytes = sqlite3_column_bytes(stmt, 0);
            NSData *jsonData = [NSData dataWithBytes:blob length:bytes];
            document = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        }
        
        [store finalizeStatement:stmt];
        return store;
    } error:nil];
    
    return document;
}

#pragma mark - Cleanup

- (void)closeAll {
    [self.servicePool closeAll];
    [self.didCachePool closeAll];
    [self.sequencerPool closeAll];
}

@end
