#import "ActorStore.h"
#import <sqlite3.h>
#import <Security/Security.h>
#import "Database/PDSDatabase.h"
#import "Database/Schema/PDSSchemaManager.h"

NSString * const PDSActorStoreErrorDomain = @"com.atproto.pds.actorstore";

@interface PDSActorStore ()

@property (nonatomic, copy, readwrite) NSString *did;
@property (nonatomic, copy, readwrite) NSString *dbPath;
@property (nonatomic, assign, readwrite) sqlite3 *db;
@property (nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, strong) NSMapTable<NSString *, NSValue *> *stmtCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *blobCache;
#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_queue_t transactionQueue;
#else
@property (nonatomic, strong) dispatch_queue_t transactionQueue;
#endif
@property (nonatomic, assign) SecKeyRef signingKey;

@end

@implementation PDSActorStore

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
        _stmtCache = [NSMapTable strongToStrongObjectsMapTable];
        _blobCache = [NSMutableDictionary dictionary];
        _transactionQueue = dispatch_queue_create("com.atproto.pds.actorstore.transaction", DISPATCH_QUEUE_SERIAL);
        _signingKey = NULL;
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
    
    // Finalize all cached statements to prevent memory leaks
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
    [self.blobCache removeAllObjects];
    
    if (self.signingKey) {
        CFRelease(self.signingKey);
        self.signingKey = NULL;
    }
    
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
            if (error) {
                *error = [self errorWithSQLiteResult:result message:[NSString stringWithUTF8String:errMsg]];
            }
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
                if (error) {
                    *error = [self errorWithSQLiteResult:result message:[NSString stringWithUTF8String:errMsg]];
                }
                sqlite3_free(errMsg);
                
                sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
            }
        } else {
            sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
            if (error && blockError) {
                *error = blockError;
            }
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
    // Defensive check: ensure database is open before use
    if (!self.open || !self.db) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:PDSActorStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is not open"}];
        }
        return NULL;
    }

    // Check cache first
    NSValue *stmtValue = [self.stmtCache objectForKey:sql];
    sqlite3_stmt *stmt = NULL;
    if (stmtValue) {
        [stmtValue getValue:&stmt];
        if (stmt) {
            // Reset the cached statement for reuse
            sqlite3_reset(stmt);
            sqlite3_clear_bindings(stmt);
            return stmt;
        }
    }

    // Prepare new statement
    int result = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);

    if (result != SQLITE_OK) {
        if (error) {
            *error = [self errorWithSQLiteResult:result message:@"Failed to prepare statement"];
        }
        return NULL;
    }

    // Cache the prepared statement
    [self.stmtCache setObject:[NSValue valueWithPointer:stmt] forKey:sql];

    return stmt;
}

- (void)finalizeStatement:(sqlite3_stmt *)stmt {
    if (stmt) {
        // Reset the statement but keep it in cache for reuse
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
        // Statement remains in cache for future reuse
    }
}

#pragma mark - Account Operations (Reader)

- (nullable PDSDatabaseAccount *)getAccountForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseAccount *account = nil;

    NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }
    
    [self finalizeStatement:stmt];
    return account;
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

    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
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
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];

    if (!success) {
        int sqliteCode = sqlite3_extended_errcode(self.db);
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
                                                 @"sqlite_message": [NSString stringWithUTF8String:sqlite3_errmsg(self.db)] ?: @""}];
            } else {
                *error = [self errorWithSQLiteResult:sqliteCode
                                             message:@"Failed to insert account"];
            }
        }
        return NO;
    }

    return YES;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    NSString *sql = @"UPDATE accounts SET handle = ?, email = ?, password_hash = ?, "
                     @"password_salt = ?, access_jwt = ?, refresh_jwt = ?, updated_at = ? WHERE did = ?";
    
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
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
    [self finalizeStatement:stmt];
    
    return success;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM accounts WHERE did = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];
    
    return success;
}

#pragma mark - Repo Operations

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseRepo *repo = nil;
    
    NSString *sql = @"SELECT * FROM repo_root LIMIT 1";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        repo = [[PDSDatabaseRepo alloc] init];
        repo.ownerDid = did;
        repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) 
                                      length:sqlite3_column_bytes(stmt, 0)];
        repo.createdAt = [NSDate date];
        repo.updatedAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 1)];
    }
    
    [self finalizeStatement:stmt];
    return repo;
}

- (nullable NSData *)getRepoRootForDid:(NSString *)did error:(NSError **)error {
    __block NSData *rootCid = nil;
    
    NSString *sql = @"SELECT cid FROM repo_root LIMIT 1";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) 
                                 length:sqlite3_column_bytes(stmt, 0)];
    }
    
    [self finalizeStatement:stmt];
    return rootCid;
}

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    NSString *sql = @"INSERT INTO repo_root (cid, updated_at) VALUES (?, ?)";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    if (repo.rootCid) {
        sqlite3_bind_blob(stmt, 1, repo.rootCid.bytes, (int)repo.rootCid.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_double(stmt, 2, repo.updatedAt.timeIntervalSince1970);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];
    return success;
}

- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO repo_root (cid, updated_at) VALUES (?, ?)";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    if (rootCid) {
        sqlite3_bind_blob(stmt, 1, rootCid.bytes, (int)rootCid.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];
    return success;
}

- (BOOL)deleteRepo:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM repo_root";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];
    return success;
}

#pragma mark - Record Operations

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseRecord *record = nil;
    
    NSString *sql = @"SELECT * FROM records WHERE uri = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;
    
    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        record = [self recordFromStatement:stmt];
    }
    
    [self finalizeStatement:stmt];
    return record;
}

- (PDSDatabaseRecord *)recordFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
    record.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
    record.collection = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
    record.rkey = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 3)];
    
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
    __block NSMutableArray<PDSDatabaseRecord *> *records = [NSMutableArray array];
    
    NSString *sql;
    if (collection) {
        sql = @"SELECT * FROM records WHERE collection = ? ORDER BY rkey LIMIT ? OFFSET ?";
    } else {
        sql = @"SELECT * FROM records ORDER BY rkey LIMIT ? OFFSET ?";
    }
    
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return @[];
    
    int idx = 1;
    if (collection) {
        sqlite3_bind_text(stmt, idx++, collection.UTF8String, -1, SQLITE_TRANSIENT);
    }
    sqlite3_bind_int(stmt, idx++, (int)limit);
    sqlite3_bind_int(stmt, idx++, (int)offset);
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        [records addObject:[self recordFromStatement:stmt]];
    }
    
    [self finalizeStatement:stmt];
    return records;
}

- (BOOL)putRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, value, indexed_at) "
                     @"VALUES (?, ?, ?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
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
    [self finalizeStatement:stmt];
    return success;
}

- (BOOL)deleteRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM records WHERE uri = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];
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
    
    NSString *sql = @"SELECT block FROM ipld_blocks WHERE cid = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;
    
    sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        blockData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) 
                                   length:sqlite3_column_bytes(stmt, 0)];
    }
    
    [self finalizeStatement:stmt];
    return blockData;
}

- (NSArray<PDSDatabaseBlock *> *)listBlocksForDid:(NSString *)did 
                                            limit:(NSUInteger)limit 
                                           offset:(NSUInteger)offset
                                            error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseBlock *> *blocks = [NSMutableArray array];
    
    NSString *sql = @"SELECT cid, size FROM ipld_blocks LIMIT ? OFFSET ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return @[];
    
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
    
    [self finalizeStatement:stmt];
    return blocks;
}

- (BOOL)putBlock:(PDSDatabaseBlock *)block forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO ipld_blocks (cid, block, size) VALUES (?, ?, ?)";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    if (block.cid) {
        sqlite3_bind_blob(stmt, 1, block.cid.bytes, (int)block.cid.length, SQLITE_TRANSIENT);
    }
    if (block.blockData) {
        sqlite3_bind_blob(stmt, 2, block.blockData.bytes, (int)block.blockData.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_int64(stmt, 3, block.size);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];
    return success;
}

- (BOOL)putBlocks:(NSArray<PDSDatabaseBlock *> *)blocks forDid:(NSString *)did error:(NSError **)error {
    for (PDSDatabaseBlock *block in blocks) {
        if (![self putBlock:block forDid:did error:error]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)deleteBlock:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM ipld_blocks WHERE cid = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];
    return success;
}

#pragma mark - Count Operations

- (NSInteger)getRecordCountForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error {
    __block NSInteger count = 0;
    
    NSString *sql;
    if (collection) {
        sql = @"SELECT COUNT(*) FROM records WHERE collection = ?";
    } else {
        sql = @"SELECT COUNT(*) FROM records";
    }
    
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return 0;
    
    if (collection) {
        sqlite3_bind_text(stmt, 1, collection.UTF8String, -1, SQLITE_TRANSIENT);
    }
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }
    
    [self finalizeStatement:stmt];
    return count;
}

- (NSInteger)getBlockCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger count = 0;
    
    NSString *sql = @"SELECT COUNT(*) FROM ipld_blocks";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return 0;
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }
    
    [self finalizeStatement:stmt];
    return count;
}

#pragma mark - Signing Key Management (Keychain)

static NSString * const kSigningKeyService = @"com.atproto.pds.signing";
static NSString * const kSigningKeyAccountPrefix = @"signing-key-";

- (NSString *)keychainAccountForDid:(NSString *)did {
    return [kSigningKeyAccountPrefix stringByAppendingString:did];
}

- (nullable SecKeyRef)signingKeyWithError:(NSError **)error {
    if (self.signingKey) {
        return self.signingKey;
    }
    
    NSString *account = [self keychainAccountForDid:self.did];
    
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnRef: @YES,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };
    
    SecKeyRef keyRef = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&keyRef);
    
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
    
    self.signingKey = keyRef;
    return keyRef;
}

- (BOOL)storeSigningKey:(SecKeyRef)key error:(NSError **)error {
    NSString *account = [self keychainAccountForDid:self.did];
    
    NSData *keyData = [self exportPublicKeyData:key];
    if (!keyData) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to export key data"}];
        }
        return NO;
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
        (__bridge id)kSecValueRef: (__bridge id)key,
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
    
    if (self.signingKey) {
        CFRelease(self.signingKey);
    }
    self.signingKey = key;
    CFRetain(self.signingKey);
    
    return YES;
}

- (BOOL)generateSigningKeyWithError:(NSError **)error {
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeySizeInBits: @(2048),
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO
        }
    };
    
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, NULL);
    
    if (!privateKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate signing key"}];
        }
        return NO;
    }
    
    BOOL success = [self storeSigningKey:privateKey error:error];
    CFRelease(privateKey);
    
    return success;
}

- (NSData *)exportPublicKeyData:(SecKeyRef)key {
    SecKeyRef publicKey = SecKeyCopyPublicKey(key);
    if (!publicKey) return nil;
    
    NSData *data = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(publicKey, NULL);
    CFRelease(publicKey);
    return data;
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
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
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
    [self finalizeStatement:stmt];
    return success;
}

- (nullable PDSDatabaseBlob *)getBlobForCID:(NSData *)cid error:(NSError **)error {
    __block PDSDatabaseBlob *blob = nil;

    NSString *sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE cid = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;

    sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        blob = [self blobFromStatement:stmt];
    }

    [self finalizeStatement:stmt];
    return blob;
}

- (NSArray<PDSDatabaseBlob *> *)listBlobsForDid:(NSString *)did
                                          limit:(NSUInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseBlob *> *blobs = [NSMutableArray array];

    NSString *sql;
    if (cursor) {
        sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE did = ? AND cid > ? ORDER BY cid LIMIT ?";
    } else {
        sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE did = ? ORDER BY cid LIMIT ?";
    }

    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return @[];

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

    [self finalizeStatement:stmt];
    return blobs;
}

- (BOOL)deleteBlobForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM blobs WHERE cid = ? AND did = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);

    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    [self finalizeStatement:stmt];
    return success;
}

#pragma mark - Error Handling

@end
