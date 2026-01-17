#import "PLCPersistentStore.h"
#import "PLCMockStore.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>
#import "PLC/PLCMetrics.h"

NSString * const PLCPersistentStoreErrorDomain = @"com.atproto.pds.plc.persistentstore";

static NSString * const kCreateOperationsTableSQL = 
    @"CREATE TABLE IF NOT EXISTS plc_operations ("
    @"  id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"  did TEXT NOT NULL,"
    @"  prev TEXT,"
    @"  sig TEXT NOT NULL,"
    @"  data BLOB NOT NULL,"
    @"  created_at DATETIME DEFAULT CURRENT_TIMESTAMP"
    @");";

static NSString * const kCreateDidIndexSQL = 
    @"CREATE INDEX IF NOT EXISTS idx_plc_operations_did ON plc_operations(did);";

static NSString * const kCreatePrevIndexSQL = 
    @"CREATE INDEX IF NOT EXISTS idx_plc_operations_prev ON plc_operations(prev);";

static NSString * const kInsertOperationSQL = 
    @"INSERT INTO plc_operations (did, prev, sig, data) VALUES (?, ?, ?, ?);";

static NSString * const kSelectHistorySQL = 
    @"SELECT id, did, prev, sig, data FROM plc_operations WHERE did = ? ORDER BY id ASC;";

static NSString * const kSelectHistorySinceSQL = 
    @"SELECT id, did, prev, sig, data FROM plc_operations WHERE did = ? AND id > ? ORDER BY id ASC;";

static NSString * const kCountOperationsSQL = 
    @"SELECT COUNT(*) FROM plc_operations WHERE did = ?;";

static NSString * const kDeleteOperationsSQL = 
    @"DELETE FROM plc_operations WHERE did = ?;";

@interface PLCPersistentStore ()

@property (nonatomic, copy, readwrite) NSString *dbPath;
@property (nonatomic, assign, readwrite) sqlite3 *db;
@property (nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *stmtCache;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t transactionQueue;

@end

@implementation PLCPersistentStore

+ (nullable instancetype)storeWithPath:(NSString *)dbPath error:(NSError **)error {
    PLCPersistentStore *store = [[PLCPersistentStore alloc] initWithPath:dbPath];
    if (![store openWithError:error]) {
        return nil;
    }
    return store;
}

- (instancetype)initWithPath:(NSString *)dbPath {
    self = [super init];
    if (self) {
        _dbPath = [dbPath copy];
        _db = NULL;
        _open = NO;
        _stmtCache = [NSMutableDictionary dictionary];
        _transactionQueue = dispatch_queue_create("com.atproto.pds.plc.persistentstore.transaction", DISPATCH_QUEUE_SERIAL);
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
                *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
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
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open database: %s", sqlite3_errmsg(_db)]}];
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
                *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Unknown error"]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)createSchema:(NSError **)error {
    char *errMsg = NULL;
    int result = sqlite3_exec(self.db, kCreateOperationsTableSQL.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to create operations table"]}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }
    
    result = sqlite3_exec(self.db, kCreateDidIndexSQL.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to create DID index"]}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }
    
    result = sqlite3_exec(self.db, kCreatePrevIndexSQL.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to create prev index"]}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }
    
    return YES;
}

- (void)close {
    if (!self.open) {
        return;
    }
    
    for (NSValue *boxedStmt in self.stmtCache.allValues) {
        sqlite3_stmt *stmt = NULL;
        [boxedStmt getValue:&stmt];
        if (stmt) {
            sqlite3_finalize(stmt);
        }
    }
    [self.stmtCache removeAllObjects];
    
    if (self.db) {
        sqlite3_close(self.db);
        self.db = NULL;
    }
    
    self.open = NO;
}

#pragma mark - Prepared Statements

- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error {
    NSValue *cachedValue = self.stmtCache[sql];
    sqlite3_stmt *cachedStmt = NULL;
    [cachedValue getValue:&cachedStmt];
    
    if (cachedStmt) {
        return cachedStmt;
    }
    
    const char *pzTail = NULL;
    int result = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &cachedStmt, &pzTail);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(self.db)]}];
        }
        return NULL;
    }
    
    self.stmtCache[sql] = [NSValue valueWithPointer:cachedStmt];
    return cachedStmt;
}

- (void)finalizeStatement:(sqlite3_stmt *)stmt {
    if (stmt) {
        sqlite3_finalize(stmt);
        NSString *keyToRemove = nil;
        for (NSString *key in self.stmtCache) {
            sqlite3_stmt *cachedStmt = NULL;
            [self.stmtCache[key] getValue:&cachedStmt];
            if (cachedStmt == stmt) {
                keyToRemove = key;
                break;
            }
        }
        if (keyToRemove) {
            [self.stmtCache removeObjectForKey:keyToRemove];
        }
    }
}

#pragma mark - PLCStore Protocol

- (nullable NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did error:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:PLCPersistentStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return nil;
    }
    
    __block NSMutableArray<PLCOperation *> *operations = [NSMutableArray array];
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        sqlite3_stmt *stmt = [self prepareStatement:kSelectHistorySQL error:&blockError];
        if (!stmt) {
            return;
        }
        
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PLCOperation *op = [self operationFromStatement:stmt];
            if (op) {
                [operations addObject:op];
            }
        }
        
        sqlite3_reset(stmt);
    });
    
    if (blockError && error) {
        *error = blockError;
    }
    
    // Instrument metrics
    if (operations.count > 0) {
        [[PLCMetrics sharedMetrics] recordCacheHit];
    } else {
        [[PLCMetrics sharedMetrics] recordCacheMiss];
    }
    
    return operations;
}

- (BOOL)appendOperation:(PLCOperation *)op error:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:PLCPersistentStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return NO;
    }
    
    if (!op.did || !op.sig || !op.data) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:PLCPersistentStoreErrorInvalidOperation
                                    userInfo:@{NSLocalizedDescriptionKey: @"Operation is missing required fields"}];
        }
        return NO;
    }
    
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        sqlite3_stmt *stmt = [self prepareStatement:kInsertOperationSQL error:&blockError];
        if (!stmt) {
            return;
        }
        
        sqlite3_bind_text(stmt, 1, op.did.UTF8String, -1, SQLITE_TRANSIENT);
        
        if (op.prev) {
            sqlite3_bind_text(stmt, 2, op.prev.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 2);
        }
        
        sqlite3_bind_text(stmt, 3, op.sig.UTF8String, -1, SQLITE_TRANSIENT);
        
        NSError *dataError = nil;
        NSData *cborData = [NSJSONSerialization dataWithJSONObject:op.data options:0 error:&dataError];
        if (!cborData) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:PLCPersistentStoreErrorInvalidOperation
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize operation data",
                                                 NSUnderlyingErrorKey: dataError}];
            return;
        }
        
        sqlite3_bind_blob(stmt, 4, cborData.bytes, (int)cborData.length, SQLITE_TRANSIENT);
        
        int result = sqlite3_step(stmt);
        if (result != SQLITE_DONE) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to insert operation: %s", sqlite3_errmsg(self.db)]}];
            sqlite3_reset(stmt);
            return;
        }
        
        sqlite3_reset(stmt);
        success = YES;
    });
    
    if (blockError && error) {
        *error = blockError;
    }
    
    return success;
}

#pragma mark - Helper Methods

- (PLCOperation *)operationFromStatement:(sqlite3_stmt *)stmt {
    const unsigned char *didText = sqlite3_column_text(stmt, 1);
    const unsigned char *prevText = sqlite3_column_text(stmt, 2);
    const unsigned char *sigText = sqlite3_column_text(stmt, 3);
    const void *dataBlob = sqlite3_column_blob(stmt, 4);
    int dataLen = sqlite3_column_bytes(stmt, 4);
    
    if (!didText || !sigText || !dataBlob) {
        return nil;
    }
    
    NSData *data = [NSData dataWithBytes:dataBlob length:dataLen];
    NSError *parseError = nil;
    NSDictionary *dataDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    
    if (!dataDict || ![dataDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = [NSString stringWithUTF8String:(const char *)didText];
    op.sig = [NSString stringWithUTF8String:(const char *)sigText];
    op.data = dataDict;
    
    if (prevText) {
        op.prev = [NSString stringWithUTF8String:(const char *)prevText];
    }
    
    return op;
}

- (NSInteger)operationCountForDid:(NSString *)did error:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:PLCPersistentStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return -1;
    }
    
    __block NSInteger count = -1;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        sqlite3_stmt *stmt = [self prepareStatement:kCountOperationsSQL error:&blockError];
        if (!stmt) {
            return;
        }
        
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int64(stmt, 0);
        }
        
        sqlite3_reset(stmt);
    });
    
    if (blockError && error) {
        *error = blockError;
    }
    
    return count;
}

- (BOOL)deleteOperationsForDid:(NSString *)did error:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:PLCPersistentStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return NO;
    }
    
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        sqlite3_stmt *stmt = [self prepareStatement:kDeleteOperationsSQL error:&blockError];
        if (!stmt) {
            return;
        }
        
        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        
        int result = sqlite3_step(stmt);
        if (result != SQLITE_DONE) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to delete operations: %s", sqlite3_errmsg(self.db)]}];
            sqlite3_reset(stmt);
            return;
        }
        
        sqlite3_reset(stmt);
        success = YES;
    });
    
    if (blockError && error) {
        *error = blockError;
    }
    
    return success;
}

@end
