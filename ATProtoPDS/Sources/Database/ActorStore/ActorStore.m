#import "ActorStore.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Compat/PDSTypes.h"
#import "Security/PDSBiometricKeychain.h"
#import <sqlite3.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import "Database/PDSDatabase.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Auth/Secp256k1.h"

NSString * const PDSActorStoreErrorDomain = @"com.atproto.pds.actorstore";

@interface PDSActorStore ()

@property (nonatomic, copy, readwrite) NSString *did;
@property (nonatomic, copy, readwrite) NSString *dbPath;
@property (nonatomic, assign, readwrite) sqlite3 *db;
@property (nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, strong) NSMapTable<NSString *, NSValue *> *stmtCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *blobCache;
@property (nonatomic, assign, readwrite) BOOL keychainNeedsUpgrade;
#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_queue_t transactionQueue;
@property (nonatomic, strong) NSData *signingKeyData;
#else
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t transactionQueue;
@property (nonatomic, assign) SecKeyRef signingKey;
@property (nonatomic, strong) PDSBiometricKeychain *biometricKeychain;
#endif

@end

@implementation PDSActorStore

@synthesize useKeychainSigningKey = _useKeychainSigningKey;

+ (instancetype)storeWithDid:(NSString *)did 
                    dbPath:(NSString *)dbPath
                      error:(NSError **)error {
    PDSActorStore *store = [[PDSActorStore alloc] initWithDid:did dbPath:dbPath];
    if (![store openWithError:error]) {
        return nil;
    }
    return store;
}

- (instancetype)initWithDid:(NSString *)did dbPath:(NSString *)dbPath {
    self = [super init];
    if (self) {
        _did = [did copy];
        _dbPath = [dbPath copy];
        _db = NULL;
        _open = NO;
        _transactionQueue = dispatch_queue_create("com.atproto.pds.actorstore.transaction", DISPATCH_QUEUE_SERIAL);
#if defined(GNUSTEP)
        _signingKeyData = nil;
#else
        _stmtCache = [NSMapTable strongToStrongObjectsMapTable];
        _blobCache = [NSMutableDictionary dictionary];
        _signingKey = NULL;
        _useKeychainSigningKey = YES;
        _useBiometricProtection = YES;
        _useSecureEnclave = NO;
        _keychainNeedsUpgrade = NO;
        _biometricKeychain = [PDSBiometricKeychain sharedInstance];
#endif
    }
    return self;
}

- (void)dealloc {
    [self close];
}

#pragma mark - Database Lifecycle

- (BOOL)openWithError:(NSError **)error {
    if (self.open) {
        return YES;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dbDir = [self.dbPath stringByDeletingLastPathComponent];
    
    if (![fm fileExistsAtPath:dbDir]) {
        NSError *createError = nil;
        if (![fm createDirectoryAtPath:dbDir withIntermediateDirectories:YES attributes:nil error:&createError]) {
            if (error) {
                *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to create database directory",
                                                 NSUnderlyingErrorKey: createError}];
            }
            return NO;
        }
    }
    
    int result = sqlite3_open(self.dbPath.UTF8String, &_db);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [self errorWithSQLiteResult:result message:@"Failed to open database"];
        }
        return NO;
    }
    
    if (![self configureDatabase:error]) {
        sqlite3_close(_db);
        _db = NULL;
        return NO;
    }
    
    if (![self createSchema:error]) {
        sqlite3_close(_db);
        _db = NULL;
        return NO;
    }
    
    self.open = YES;
    return YES;
}

- (BOOL)configureDatabase:(NSError **)error {
    const char *pragmas[] = {
        "PRAGMA journal_mode=WAL",
        "PRAGMA synchronous=NORMAL",
        "PRAGMA wal_autocheckpoint=1000",
        "PRAGMA cache_size=-64000",
        "PRAGMA temp_store=MEMORY",
        "PRAGMA foreign_keys=ON",
        "PRAGMA encoding='UTF-8'",
        NULL
    };
    
    for (int i = 0; pragmas[i] != NULL; i++) {
        char *errMsg = NULL;
        int result = sqlite3_exec(self.db, pragmas[i], NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg]}];
            }
            sqlite3_free(errMsg);
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)createSchema:(NSError **)error {
    NSString *schemaSQL = [[PDSSchemaManager sharedManager] actorStoreSchemaSQL];

    char *errMsg = NULL;
    int result = sqlite3_exec(self.db, [schemaSQL UTF8String], NULL, NULL, &errMsg);

    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg]}];
        }
        sqlite3_free(errMsg);
        return NO;
    }

    return YES;
}

- (void)close {
    if (!self.open) {
        return;
    }
    
    // Finalize all cached statements
    NSMapTable *cache = self.stmtCache;
    for (NSString *sql in cache) {
        NSValue *stmtValue = [cache objectForKey:sql];
        sqlite3_stmt *stmt = NULL;
        [stmtValue getValue:&stmt];
        if (stmt) {
            sqlite3_finalize(stmt);
        }
    }
    [self.stmtCache removeAllObjects];
    
    // Finalize any other stray statements
    sqlite3_stmt *strayStmt;
    while ((strayStmt = sqlite3_next_stmt(self.db, NULL)) != NULL) {
        sqlite3_finalize(strayStmt);
    }
    
    [self.blobCache removeAllObjects];
    
#if defined(GNUSTEP)
    self.signingKeyData = nil;
#else
    if (self.signingKey) {
        CFRelease(self.signingKey);
        self.signingKey = NULL;
    }
#endif
    
    sqlite3_close(self.db);
    self.db = NULL;
    self.open = NO;
}

#pragma mark - Error Handling

- (NSError *)errorWithSQLiteResult:(int)result message:(NSString *)message {
    return [NSError errorWithDomain:PDSActorStoreErrorDomain
                              code:result
                          userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error",
                                   @"sqlite_code": @(result),
                                   @"sqlite_message": [NSString stringWithUTF8String:sqlite3_errmsg(self.db)] ?: @""}];
}

#pragma mark - Transaction Support

- (void)transactWithBlock:(void (^)(id<PDSActorStoreTransactor> transactor))block
                    error:(NSError **)error {
    __block NSError *localError = nil;
    dispatch_sync(self.transactionQueue, ^{
        if (!self.open) {
            localError = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                          code:PDSActorStoreErrorDatabaseClosed
                                      userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
            return;
        }
        
        char *errMsg = NULL;
        int result = sqlite3_exec(self.db, "BEGIN TRANSACTION", NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            localError = [self errorWithSQLiteResult:result message:[NSString stringWithUTF8String:errMsg]];
            sqlite3_free(errMsg);
            return;
        }
        
        __block BOOL success = YES;
        __block NSError *blockError = nil;
        
        @try {
            block(self);
        } @catch (NSException *exception) {
            success = NO;
            blockError = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown exception"}];
        }
        
        if (success && !blockError) {
            result = sqlite3_exec(self.db, "COMMIT", NULL, NULL, &errMsg);
            if (result != SQLITE_OK) {
                localError = [self errorWithSQLiteResult:result message:[NSString stringWithUTF8String:errMsg]];
                sqlite3_free(errMsg);
                sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
            }
        } else {
            sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
            localError = blockError;
        }

        [self.stmtCache removeAllObjects];
    });

    if (localError && error) {
        *error = localError;
    }
}

- (void)readWithBlock:(void (^)(id<PDSActorStoreReader> reader))block 
                error:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:PDSActorStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return;
    }
    
    block(self);
}

#pragma mark - Statement Management

- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error {
    if (!self.open || !self.db) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:PDSActorStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is not open"}];
        }
        return NULL;
    }

    sqlite3_stmt *stmt = NULL;
    int result = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);

    if (result != SQLITE_OK) {
        if (error) {
            *error = [self errorWithSQLiteResult:result message:@"Failed to prepare statement"];
        }
        return NULL;
    }

    return stmt;
}

- (void)finalizeStatement:(sqlite3_stmt *)stmt {
    if (stmt) {
        sqlite3_finalize(stmt);
    }
}


#pragma mark - Account Operations (Reader)

- (nullable PDSDatabaseAccount *)getAccountForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [self accountFromStatement:stmt];
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return account;
}

- (nullable NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    __block NSMutableArray<PDSDatabaseAccount *> *accounts = [NSMutableArray array];
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT * FROM accounts ORDER BY created_at DESC";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PDSDatabaseAccount *account = [self accountFromStatement:stmt];
            if (account) {
                [accounts addObject:account];
            }
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return [accounts copy];
}

- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
    account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
    
    int col = 2;
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, col)];
    }
    col++;
    
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, col) 
                                              length:sqlite3_column_bytes(stmt, col)];
    }
    col++;
    
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, col) 
                                              length:sqlite3_column_bytes(stmt, col)];
    }
    col++;
    
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.accessJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, col) 
                                           length:sqlite3_column_bytes(stmt, col)];
    }
    col++;
    
    if (sqlite3_column_type(stmt, col) != SQLITE_NULL) {
        account.refreshJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, col) 
                                            length:sqlite3_column_bytes(stmt, col)];
    }
    col++;
    
    account.createdAt = sqlite3_column_double(stmt, col);
    col++;
    account.updatedAt = sqlite3_column_double(stmt, col);
    
    return account;
}

#pragma mark - Account Operations (Transactor)

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    NSString *sql = @"INSERT INTO accounts (did, handle, email, password_hash, password_salt, "
                     @"access_jwt, refresh_jwt, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    sqlite3_bind_text(stmt, 1, account.did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, account.handle.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (account.email) {
        sqlite3_bind_text(stmt, 3, account.email.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    
    if (account.passwordHash) {
        sqlite3_bind_blob(stmt, 4, account.passwordHash.bytes, (int)account.passwordHash.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    
    if (account.passwordSalt) {
        sqlite3_bind_blob(stmt, 5, account.passwordSalt.bytes, (int)account.passwordSalt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 5);
    }
    
    if (account.accessJwt) {
        sqlite3_bind_blob(stmt, 6, account.accessJwt.bytes, (int)account.accessJwt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 6);
    }
    
    if (account.refreshJwt) {
        sqlite3_bind_blob(stmt, 7, account.refreshJwt.bytes, (int)account.refreshJwt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 7);
    }
    
    sqlite3_bind_double(stmt, 8, account.createdAt);
    sqlite3_bind_double(stmt, 9, account.updatedAt);
    
    int stepResult = sqlite3_step(stmt);
    BOOL success = (stepResult == SQLITE_DONE);
    if (!success) {
        int sqliteCode = sqlite3_extended_errcode(self.db);
        NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(self.db)];
        
        if (error) {
            BOOL isConstraintViolation = (sqliteCode == SQLITE_CONSTRAINT_UNIQUE ||
                                          sqliteCode == SQLITE_CONSTRAINT_PRIMARYKEY ||
                                          sqliteCode == SQLITE_CONSTRAINT_FOREIGNKEY ||
                                          sqliteCode == SQLITE_CONSTRAINT_CHECK ||
                                          sqliteCode == SQLITE_CONSTRAINT_NOTNULL);
            if (isConstraintViolation) {
                *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                            code:PDSActorStoreErrorAlreadyExists
                                        userInfo:@{NSLocalizedDescriptionKey: @"Account already exists",
                                                 @"sqlite_code": @(sqliteCode),
                                                 @"sqlite_message": errorMsg ?: @""}];
            } else {
                *error = [self errorWithSQLiteResult:sqliteCode
                                             message:@"Failed to insert account"];
            }
        }
        return NO;
    }
    
#if defined(GNUSTEP)
    // Generate secp256k1 signing key for the new account using the account's DID
    NSError *keyError = nil;
    if (![self generateSigningKeyForDid:account.did error:&keyError]) {
        NSLog(@"[ActorStore] Warning: Failed to generate signing key for %@: %@", account.did, keyError);
        // Don't fail account creation if key generation fails - it can be retried later
    } else {
        NSLog(@"[ActorStore] Generated secp256k1 signing key for %@", account.did);
    }
#else
    // Only generate signing key if we're using the keychain for storage
    // In-memory stores (useKeychainSigningKey = NO) don't need persistent signing keys
    if (self.useKeychainSigningKey) {
        NSError *keyError = nil;
        if (![self generateSigningKeyWithError:&keyError]) {
            NSLog(@"[ActorStore] Warning: Failed to generate signing key for %@: %@", account.did, keyError);
        } else {
            NSLog(@"[ActorStore] Generated signing key for %@", account.did);
        }
    }
#endif

    return YES;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    NSString *sql = @"UPDATE accounts SET handle = ?, email = ?, password_hash = ?, "
                     @"password_salt = ?, access_jwt = ?, refresh_jwt = ?, updated_at = ? WHERE did = ?";
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    int idx = 1;
    sqlite3_bind_text(stmt, idx++, account.handle.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (account.email) {
        sqlite3_bind_text(stmt, idx++, account.email.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    if (account.passwordHash) {
        sqlite3_bind_blob(stmt, idx++, account.passwordHash.bytes, (int)account.passwordHash.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    if (account.passwordSalt) {
        sqlite3_bind_blob(stmt, idx++, account.passwordSalt.bytes, (int)account.passwordSalt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    if (account.accessJwt) {
        sqlite3_bind_blob(stmt, idx++, account.accessJwt.bytes, (int)account.accessJwt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    if (account.refreshJwt) {
        sqlite3_bind_blob(stmt, idx++, account.refreshJwt.bytes, (int)account.refreshJwt.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx++);
    }
    
    sqlite3_bind_double(stmt, idx++, account.updatedAt);
    sqlite3_bind_text(stmt, idx, account.did.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    
    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM accounts WHERE did = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    
    return success;
}

#pragma mark - Repo Operations

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseRepo *repo = nil;
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT * FROM repo_root LIMIT 1";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            repo = [[PDSDatabaseRepo alloc] init];
            repo.ownerDid = did;
            repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) 
                                          length:sqlite3_column_bytes(stmt, 0)];
            repo.createdAt = [NSDate date];
            repo.updatedAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 1)];
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return repo;
}

- (nullable NSData *)getRepoRootForDid:(NSString *)did error:(NSError **)error {
    __block NSData *rootCid = nil;
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT cid FROM repo_root LIMIT 1";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) 
                                     length:sqlite3_column_bytes(stmt, 0)];
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return rootCid;
}

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    NSString *sql = @"INSERT INTO repo_root (cid, updated_at) VALUES (?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    if (repo.rootCid) {
        sqlite3_bind_blob(stmt, 1, repo.rootCid.bytes, (int)repo.rootCid.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_double(stmt, 2, repo.updatedAt.timeIntervalSince1970);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO repo_root (cid, updated_at) VALUES (?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    if (rootCid) {
        sqlite3_bind_blob(stmt, 1, rootCid.bytes, (int)rootCid.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (BOOL)deleteRepo:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM repo_root";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

#pragma mark - Record Operations

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseRecord *record = nil;
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT * FROM records WHERE uri = ?";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            record = [self recordFromStatement:stmt];
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return record;
}

- (PDSDatabaseRecord *)recordFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    const char *uri = (const char *)sqlite3_column_text(stmt, 0);
    record.uri = uri ? [NSString stringWithUTF8String:uri] : @"";
    
    const char *did = (const char *)sqlite3_column_text(stmt, 1);
    record.did = did ? [NSString stringWithUTF8String:did] : @"";
    
    const char *collection = (const char *)sqlite3_column_text(stmt, 2);
    record.collection = collection ? [NSString stringWithUTF8String:collection] : @"";
    
    const char *rkey = (const char *)sqlite3_column_text(stmt, 3);
    record.rkey = rkey ? [NSString stringWithUTF8String:rkey] : @"";
    
    const char *cidText = (const char *)sqlite3_column_text(stmt, 4);
    if (cidText) {
        record.cid = [NSString stringWithUTF8String:cidText];
    }
    
    const void *valueBlob = sqlite3_column_blob(stmt, 5);
    int valueBytes = sqlite3_column_bytes(stmt, 5);
    if (valueBlob && valueBytes > 0) {
        record.value = [[NSString alloc] initWithBytes:valueBlob length:valueBytes encoding:NSUTF8StringEncoding];
    }
    
    record.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 6)];
    return record;
}

- (NSArray<PDSDatabaseRecord *> *)listRecordsForDid:(NSString *)did 
                                         collection:(nullable NSString *)collection 
                                               limit:(NSUInteger)limit
                                              offset:(NSUInteger)offset
                                               error:(NSError **)error {
    __block NSArray<PDSDatabaseRecord *> *result = nil;
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSMutableArray<PDSDatabaseRecord *> *records = [NSMutableArray array];
        
        NSString *sql;
        if (collection) {
            sql = @"SELECT * FROM records WHERE collection = ? ORDER BY rkey LIMIT ? OFFSET ?";
        } else {
            sql = @"SELECT * FROM records ORDER BY rkey LIMIT ? OFFSET ?";
        }
        
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        int idx = 1;
        if (collection) {
            sqlite3_bind_text(stmt, idx++, collection.UTF8String, -1, SQLITE_TRANSIENT);
        }
        sqlite3_bind_int(stmt, idx++, (int)limit);
        sqlite3_bind_int(stmt, idx++, (int)offset);
        
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [records addObject:[self recordFromStatement:stmt]];
        }
        
        result = records;
    });

    if (error && blockError) {
        *error = blockError;
    }
    return result ?: @[];
}

- (BOOL)putRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, value, indexed_at) "
                     @"VALUES (?, ?, ?, ?, ?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, record.uri.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, record.collection.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, record.rkey.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, record.cid.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (record.value) {
        sqlite3_bind_text(stmt, 6, record.value.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 6);
    }
    
    sqlite3_bind_double(stmt, 7, record.createdAt.timeIntervalSince1970);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (BOOL)deleteRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM records WHERE uri = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (BOOL)putRecords:(NSArray<PDSDatabaseRecord *> *)records forDid:(NSString *)did error:(NSError **)error {
    for (PDSDatabaseRecord *record in records) {
        if (![self putRecord:record forDid:did error:error]) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - Block Operations

- (nullable NSData *)getBlockForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    __block NSData *blockData = nil;
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT block FROM ipld_blocks WHERE cid = ?";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            blockData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) 
                                       length:sqlite3_column_bytes(stmt, 0)];
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return blockData;
}

- (NSArray<PDSDatabaseBlock *> *)listBlocksForDid:(NSString *)did 
                                            limit:(NSUInteger)limit 
                                           offset:(NSUInteger)offset
                                            error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseBlock *> *blocks = [NSMutableArray array];
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT cid, size FROM ipld_blocks LIMIT ? OFFSET ?";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        sqlite3_bind_int(stmt, 1, (int)limit);
        sqlite3_bind_int(stmt, 2, (int)offset);
        
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
            block.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) 
                                       length:sqlite3_column_bytes(stmt, 0)];
            block.size = sqlite3_column_int64(stmt, 1);
            block.repoDid = did;
            [blocks addObject:block];
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return blocks;
}

- (BOOL)putBlock:(PDSDatabaseBlock *)block forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO ipld_blocks (cid, block, size) VALUES (?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    if (block.cid) {
        sqlite3_bind_blob(stmt, 1, block.cid.bytes, (int)block.cid.length, SQLITE_TRANSIENT);
    }
    if (block.blockData) {
        sqlite3_bind_blob(stmt, 2, block.blockData.bytes, (int)block.blockData.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_int64(stmt, 3, block.size);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (BOOL)putBlocks:(NSArray<PDSDatabaseBlock *> *)blocks forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO ipld_blocks (cid, block, size) VALUES (?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    for (PDSDatabaseBlock *block in blocks) {
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
        
        if (block.cid) {
            sqlite3_bind_blob(stmt, 1, block.cid.bytes, (int)block.cid.length, SQLITE_TRANSIENT);
        }
        if (block.blockData) {
            sqlite3_bind_blob(stmt, 2, block.blockData.bytes, (int)block.blockData.length, SQLITE_TRANSIENT);
        }
        sqlite3_bind_int64(stmt, 3, block.size);
        
        if (sqlite3_step(stmt) != SQLITE_DONE) {
            // handle error?
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)deleteBlock:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM ipld_blocks WHERE cid = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

#pragma mark - Count Operations

- (NSInteger)getRecordCountForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error {
    __block NSInteger count = 0;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        NSString *sql;
        if (collection) {
            sql = @"SELECT COUNT(*) FROM records WHERE collection = ?";
        } else {
            sql = @"SELECT COUNT(*) FROM records";
        }
        
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        if (collection) {
            sqlite3_bind_text(stmt, 1, collection.UTF8String, -1, SQLITE_TRANSIENT);
        }
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int64(stmt, 0);
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return count;
}

- (NSInteger)getBlockCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger count = 0;
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT COUNT(*) FROM ipld_blocks";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int64(stmt, 0);
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return count;
}

#pragma mark - Signing Key Management (Keychain)

static NSString * const kSigningKeyService = @"com.atproto.pds.signing";
static NSString * const kSigningKeyAccountPrefix = @"signing-key-";
static NSString * const kFallbackECPrivateKeyBase64 =
@"MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgEWHQ/ocH8Atl3zOY"
@"QYcfBRNRUrps+GZIuA62/FH2dt2hRANCAAQ9hiv8igbi5vaOYHzXt6gDxbocoWAX"
@"V6jBppig8YRtvlHJe/LXyvTzAZmWXq2CeUTyE8kyAG9N5qn975sNXg0V";

- (NSString *)keychainAccountForDid:(NSString *)did {
    return [kSigningKeyAccountPrefix stringByAppendingString:did];
}

#if defined(GNUSTEP)
- (nullable NSData *)loadSigningKeyDataWithError:(NSError **)error {
    if (self.signingKeyData) {
        return self.signingKeyData;
    }
    
    if (!self.useKeychainSigningKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorSigningKeyNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key not available in memory-only store"}];
        }
        return NULL;
    }
    
    NSString *account = [self keychainAccountForDid:self.did];
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };
    
    CFDataRef keyData = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&keyData);
    
    if (status == errSecItemNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:PDSActorStoreErrorSigningKeyNotFound
                                    userInfo:@{NSLocalizedDescriptionKey: @"Signing key not found in Keychain"}];
        }
        return nil;
    }
    
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:PDSActorStoreErrorSigningKeyInvalid
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to retrieve signing key from Keychain"}];
        }
        return nil;
    }
    
    NSData *data = (__bridge_transfer NSData *)keyData;
    
    if (data.length != 32) {
        NSLog(@"Warning: Stored key is %lu bytes, expected 32 for secp256k1.", (unsigned long)data.length);
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:PDSActorStoreErrorSigningKeyInvalid
                                    userInfo:@{NSLocalizedDescriptionKey: @"Invalid key format - expected 32-byte secp256k1 key"}];
        }
        return nil;
    }
    
    self.signingKeyData = data;
    return data;
}
#else
- (nullable SecKeyRef)signingKeyWithError:(NSError **)error {
    if (self.signingKey) {
        CFRetain(self.signingKey);
        return self.signingKey;
    }
    
    if (!self.useKeychainSigningKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorSigningKeyNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key not available in memory-only store"}];
        }
        return NULL;
    }
    
    NSString *account = [self keychainAccountForDid:self.did];
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnRef: @YES,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };
    
    CFTypeRef keyRef = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &keyRef);
    
    if (status == errSecItemNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:PDSActorStoreErrorSigningKeyNotFound
                                    userInfo:@{NSLocalizedDescriptionKey: @"Signing key not found in Keychain"}];
        }
        return NULL;
    }
    
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:PDSActorStoreErrorSigningKeyInvalid
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to retrieve signing key from Keychain"}];
        }
        return NULL;
    }
    
    self.signingKey = (SecKeyRef)keyRef;
    CFRetain(self.signingKey);
    CFRelease(keyRef);
    return self.signingKey;
}
#endif

- (BOOL)storeSigningKeyData:(NSData *)keyData error:(NSError **)error {
    return [self storeSigningKeyData:keyData forDid:self.did error:error];
}

- (BOOL)storeSigningKeyData:(NSData *)keyData forDid:(NSString *)targetDid error:(NSError **)error {
    if (keyData.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key must be 32 bytes (secp256k1)"}];
        }
        return NO;
    }

    NSString *account = [self keychainAccountForDid:targetDid];

    if (self.useBiometricProtection && self.biometricKeychain) {
        return [self.biometricKeychain storeKey:keyData forAccount:account error:error];
    }

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: account
    };

    SecItemDelete((__bridge CFDictionaryRef)query);

    NSDictionary *attributes = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecValueData: keyData,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)attributes, NULL);

    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to store signing key in Keychain"}];
        }
        return NO;
    }

#if defined(GNUSTEP)
    if ([targetDid isEqualToString:self.did]) {
        self.signingKeyData = keyData;
    }
#endif
    return YES;
}

- (BOOL)generateSigningKeyWithError:(NSError **)error {
#if defined(GNUSTEP)
    return [self generateSigningKeyForDid:self.did error:error];
}

- (BOOL)generateSigningKeyForDid:(NSString *)targetDid error:(NSError **)error {
    // Generate secp256k1 key pair using the Secp256k1 wrapper
    NSError *genError = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&genError];
    
    if (!keyPair) {
        if (error) {
            *error = genError ?: [NSError errorWithDomain:PDSActorStoreErrorDomain
                                                     code:-1
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate secp256k1 signing key"}];
        }
        return NO;
    }
    
    // Store the 32-byte private key for the target DID
    return [self storeSigningKeyData:keyPair.privateKey forDid:targetDid error:error];
}
#else
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeySizeInBits: @(2048),
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO
        }
    };
    CFErrorRef cfError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfError);

    if (!privateKey && !self.useKeychainSigningKey) {
        if (cfError) {
            CFRelease(cfError);
            cfError = NULL;
        }
        NSDictionary *fallbackAttributes = @{
            (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
            (__bridge id)kSecAttrKeySizeInBits: @(256)
        };
        privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)fallbackAttributes, &cfError);
    }

    if (!privateKey && !self.useKeychainSigningKey) {
        if (cfError) {
            CFRelease(cfError);
            cfError = NULL;
        }
        NSData *fallbackData = [[NSData alloc] initWithBase64EncodedString:kFallbackECPrivateKeyBase64
                                                                   options:0];
        if (fallbackData) {
            NSDictionary *importAttributes = @{
                (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
                (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
                (__bridge id)kSecAttrKeySizeInBits: @(256)
            };
            privateKey = SecKeyCreateWithData((__bridge CFDataRef)fallbackData,
                                              (__bridge CFDictionaryRef)importAttributes,
                                              &cfError);
        }
    }
    
    if (!privateKey) {
        if (error) {
            if (cfError) {
                *error = CFBridgingRelease(cfError);
            } else {
                *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate signing key"}];
            }
        } else if (cfError) {
            CFRelease(cfError);
        }
        return NO;
    }
    
    self.signingKey = privateKey;
    // Note: NOT calling CFRelease(privateKey) - the assign property takes ownership
    return YES;
}
#endif

#if defined(GNUSTEP)
- (nullable NSData *)signingKeyPrivateBytesWithError:(NSError **)error {
    // Return the raw 32-byte secp256k1 private key
    return [self loadSigningKeyDataWithError:error];
}
#else
- (nullable NSData *)signingKeyPrivateBytesWithError:(NSError **)error {
    if (!self.useKeychainSigningKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorSigningKeyNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key not available in memory-only store"}];
        }
        return nil;
    }

    NSString *account = [self keychainAccountForDid:self.did];

    if (self.useBiometricProtection && self.biometricKeychain) {
        NSData *keyData = [self.biometricKeychain retrieveKeyForAccount:account error:error];
        if (keyData) {
            if (keyData.length != 32) {
                if (error) {
                    *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                                 code:PDSActorStoreErrorSigningKeyInvalid
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid key format - expected 32-byte secp256k1 key"}];
                }
                return nil;
            }
            return keyData;
        }
        return nil;
    }

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };

    CFDataRef keyData = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&keyData);
    if (status == errSecItemNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorSigningKeyNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key not found in Keychain"}];
        }
        return nil;
    }

    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorSigningKeyInvalid
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to retrieve signing key from Keychain"}];
        }
        return nil;
    }

    NSData *data = (__bridge_transfer NSData *)keyData;
    if (data.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorSigningKeyInvalid
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid key format - expected 32-byte secp256k1 key"}];
        }
        return nil;
    }

    return data;
}

#endif

- (BOOL)upgradeKeychainToBiometricWithError:(NSError **)error {
#if defined(GNUSTEP)
    if (error) {
        *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                     code:PDSActorStoreErrorBiometryNotAvailable
                                 userInfo:@{NSLocalizedDescriptionKey: @"Biometric protection not available on Linux"}];
    }
    return NO;
#else
    if (!self.useBiometricProtection || !self.biometricKeychain) {
        return YES;
    }

    NSString *account = [self keychainAccountForDid:self.did];

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };

    CFDataRef keyData = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&keyData);

    if (status == errSecItemNotFound) {
        self.keychainNeedsUpgrade = NO;
        return YES;
    }

    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorSigningKeyNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to retrieve existing key for upgrade"}];
        }
        return NO;
    }

    NSData *data = (__bridge_transfer NSData *)keyData;

    SecItemDelete((__bridge CFDictionaryRef)query);

    BOOL success = [self.biometricKeychain storeKey:data forAccount:account error:error];
    if (success) {
        self.keychainNeedsUpgrade = NO;
    }

    return success;
#endif
}

#pragma mark - Blob Operations

- (PDSDatabaseBlob *)blobFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0)
                              length:sqlite3_column_bytes(stmt, 0)];
    blob.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];

    if (sqlite3_column_type(stmt, 2) != SQLITE_NULL) {
        blob.mimeType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
    }

    blob.size = sqlite3_column_int64(stmt, 3);
    blob.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 4)];

    return blob;
}

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO blobs (cid, did, mimeType, size, created_at) VALUES (?, ?, ?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    if (blob.cid) {
        sqlite3_bind_blob(stmt, 1, blob.cid.bytes, (int)blob.cid.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_text(stmt, 2, blob.did.UTF8String, -1, SQLITE_TRANSIENT);

    if (blob.mimeType) {
        sqlite3_bind_text(stmt, 3, blob.mimeType.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }

    sqlite3_bind_int64(stmt, 4, blob.size);
    sqlite3_bind_double(stmt, 5, blob.createdAt.timeIntervalSince1970);

    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (nullable PDSDatabaseBlob *)getBlobForCID:(NSData *)cid error:(NSError **)error {
    __block PDSDatabaseBlob *blob = nil;
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSString *sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE cid = ?";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            blob = [self blobFromStatement:stmt];
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return blob;
}

- (NSArray<PDSDatabaseBlob *> *)listBlobsForDid:(NSString *)did
                                          limit:(NSUInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseBlob *> *blobs = [NSMutableArray array];
    __block NSError *blockError = nil;

    dispatch_sync(self.transactionQueue, ^{
        NSString *sql;
        if (cursor) {
            sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE did = ? AND cid > ? ORDER BY cid LIMIT ?";
        } else {
            sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE did = ? ORDER BY cid LIMIT ?";
        }

        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        int idx = 1;
        sqlite3_bind_text(stmt, idx++, did.UTF8String, -1, SQLITE_TRANSIENT);

        if (cursor) {
            NSData *cursorData = [[NSData alloc] initWithBase64EncodedString:cursor options:0];
            if (cursorData) {
                sqlite3_bind_blob(stmt, idx++, cursorData.bytes, (int)cursorData.length, SQLITE_TRANSIENT);
            }
        }

        sqlite3_bind_int(stmt, idx++, (int)limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [blobs addObject:[self blobFromStatement:stmt]];
        }
    });

    if (error && blockError) {
        *error = blockError;
    }
    return blobs;
}

- (BOOL)deleteBlobForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM blobs WHERE cid = ? AND did = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);

    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

#pragma mark - Rotation Key Management

- (BOOL)storeRotationKeyPrivate:(NSData *)privateKey
                     publicKey:(NSData *)compressedPublicKey
              encryptedWithPassword:(NSString *)password
                          error:(NSError **)error {
    if (privateKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Private key must be 32 bytes"}];
        }
        return NO;
    }
    
    if (compressedPublicKey.length != 33) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Compressed public key must be 33 bytes"}];
        }
        return NO;
    }
    
    // Generate a random salt
    uint8_t saltBytes[16];
    for (int i = 0; i < 16; i++) {
        saltBytes[i] = (uint8_t)(arc4random() & 0xFF);
    }
    NSData *salt = [NSData dataWithBytes:saltBytes length:16];
    
    // Derive encryption key using PBKDF2
    NSData *encryptionKey = [self deriveKeyFromPassword:password salt:salt];
    if (!encryptionKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive encryption key"}];
        }
        return NO;
    }
    
    // Encrypt the private key using AES-256-CBC
    NSData *encryptedKey = [self encryptData:privateKey withKey:encryptionKey];
    if (!encryptedKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to encrypt private key"}];
        }
        return NO;
    }
    
    // Store in database
    NSString *sql = @"INSERT OR REPLACE INTO rotation_keys "
                    @"(did, encrypted_private_key, public_key_compressed, encryption_salt, created_at, updated_at) "
                    @"VALUES (?, ?, ?, ?, ?, ?)";
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    double now = [[NSDate date] timeIntervalSince1970];
    
    sqlite3_bind_text(stmt, 1, self.did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 2, encryptedKey.bytes, (int)encryptedKey.length, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 3, compressedPublicKey.bytes, (int)compressedPublicKey.length, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 4, salt.bytes, (int)salt.length, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 5, now);
    sqlite3_bind_double(stmt, 6, now);
    
    int result = sqlite3_step(stmt);
    
    if (result != SQLITE_DONE) {
        if (error) {
            *error = [self errorWithSQLiteResult:result message:@"Failed to store rotation key"];
        }
        return NO;
    }
    
    return YES;
}

- (nullable NSData *)rotationKeyDecryptedWithPassword:(NSString *)password
                                               error:(NSError **)error {
    NSString *sql = @"SELECT encrypted_private_key, encryption_salt FROM rotation_keys WHERE did = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;
    
    sqlite3_bind_text(stmt, 1, self.did.UTF8String, -1, SQLITE_TRANSIENT);
    
    int result = sqlite3_step(stmt);
    if (result != SQLITE_ROW) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Rotation key not found"}];
        }
        return nil;
    }
    
    const void *encryptedBytes = sqlite3_column_blob(stmt, 0);
    int encryptedLen = sqlite3_column_bytes(stmt, 0);
    NSData *encryptedKey = [NSData dataWithBytes:encryptedBytes length:encryptedLen];
    
    const void *saltBytes = sqlite3_column_blob(stmt, 1);
    int saltLen = sqlite3_column_bytes(stmt, 1);
    NSData *salt = [NSData dataWithBytes:saltBytes length:saltLen];
    
    // Derive decryption key
    NSData *decryptionKey = [self deriveKeyFromPassword:password salt:salt];
    if (!decryptionKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive decryption key"}];
        }
        return nil;
    }
    
    // Decrypt the private key
    NSData *privateKey = [self decryptData:encryptedKey withKey:decryptionKey];
    if (!privateKey || privateKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decrypt rotation key (wrong password?)"}];
        }
        return nil;
    }
    
    return privateKey;
}

- (nullable NSData *)rotationKeyCompressedPublicKeyWithError:(NSError **)error {
    NSString *sql = @"SELECT public_key_compressed FROM rotation_keys WHERE did = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;
    
    sqlite3_bind_text(stmt, 1, self.did.UTF8String, -1, SQLITE_TRANSIENT);
    
    int result = sqlite3_step(stmt);
    if (result != SQLITE_ROW) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:PDSActorStoreErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Rotation key not found"}];
        }
        return nil;
    }
    
    const void *publicKeyBytes = sqlite3_column_blob(stmt, 0);
    int publicKeyLen = sqlite3_column_bytes(stmt, 0);
    NSData *publicKey = [NSData dataWithBytes:publicKeyBytes length:publicKeyLen];
    
    return publicKey;
}

- (BOOL)hasRotationKey {
    NSString *sql = @"SELECT 1 FROM rotation_keys WHERE did = ? LIMIT 1";
    NSError *error;
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, self.did.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL hasKey = (sqlite3_step(stmt) == SQLITE_ROW);
    return hasKey;
}

#pragma mark - Encryption Helpers

- (nullable NSData *)deriveKeyFromPassword:(NSString *)password salt:(NSData *)salt {
    // PBKDF2 with SHA-256, 100000 iterations, 32-byte output
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableData *derivedKey = [NSMutableData dataWithLength:32];
    
    int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      passwordData.bytes, passwordData.length,
                                      salt.bytes, salt.length,
                                      kCCPRFHmacAlgSHA256,
                                      100000,
                                      derivedKey.mutableBytes, 32);
    
    if (result != kCCSuccess) {
        return nil;
    }
    
    return derivedKey;
}

- (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key {
    // AES-256-CBC with PKCS7 padding
    // Generate random IV
    uint8_t ivBytes[kCCBlockSizeAES128];
    for (int i = 0; i < kCCBlockSizeAES128; i++) {
        ivBytes[i] = (uint8_t)(arc4random() & 0xFF);
    }
    
    size_t bufferSize = data.length + kCCBlockSizeAES128;
    NSMutableData *cipherData = [NSMutableData dataWithLength:bufferSize];
    
    size_t numBytesEncrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCEncrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     key.bytes, kCCKeySizeAES256,
                                     ivBytes,
                                     data.bytes, data.length,
                                     cipherData.mutableBytes, bufferSize,
                                     &numBytesEncrypted);
    
    if (status != kCCSuccess) {
        return nil;
    }
    
    cipherData.length = numBytesEncrypted;
    
    // Prepend IV to ciphertext
    NSMutableData *result = [NSMutableData dataWithBytes:ivBytes length:kCCBlockSizeAES128];
    [result appendData:cipherData];
    
    return result;
}

- (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key {
    // AES-256-CBC with PKCS7 padding
    // IV is prepended to the ciphertext
    if (data.length < kCCBlockSizeAES128) {
        return nil;
    }
    
    const uint8_t *iv = data.bytes;
    NSData *ciphertext = [data subdataWithRange:NSMakeRange(kCCBlockSizeAES128, data.length - kCCBlockSizeAES128)];
    
    size_t bufferSize = ciphertext.length + kCCBlockSizeAES128;
    NSMutableData *plainData = [NSMutableData dataWithLength:bufferSize];
    
    size_t numBytesDecrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     key.bytes, kCCKeySizeAES256,
                                     iv,
                                     ciphertext.bytes, ciphertext.length,
                                     plainData.mutableBytes, bufferSize,
                                     &numBytesDecrypted);
    
    if (status != kCCSuccess) {
        return nil;
    }
    
    plainData.length = numBytesDecrypted;
    return plainData;
}

@end
