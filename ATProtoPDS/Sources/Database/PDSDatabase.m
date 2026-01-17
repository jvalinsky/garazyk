#import "Database/PDSDatabase.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Compat/PDSTypes.h"
#import "Database/Schema.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Debug/PDSLogger.h"
#if !defined(__linux__) && !defined(__GNUstep__)
#import <Security/Security.h>
#endif

NSString * const PDSDatabaseErrorDomain = @"com.atproto.pds.database";

static NSDateFormatter * iso8601Formatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    });
    return formatter;
}

@interface PDSDatabase ()

@property (nonatomic, readwrite) NSURL *databaseURL;
@property (nonatomic, readwrite) BOOL isOpen;
@property (nonatomic, assign) sqlite3 *db;
#if defined(__linux__) || defined(__GNUstep__)
@property (nonatomic, strong) NSMutableDictionary *statementCache;
@property (nonatomic, assign) dispatch_queue_t cacheQueue;
#else
@property (nonatomic, strong) NSMutableDictionary *statementCache;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t cacheQueue;
#endif

@end

@implementation PDSDatabase

+ (instancetype)sharedDatabase {
    static PDSDatabase *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PDSDatabase alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _statementCache = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (instancetype)databaseAtURL:(NSURL *)url {
    PDSDatabase *database = [[PDSDatabase alloc] init];
    database.databaseURL = url;
    database.isOpen = NO;
    database.db = NULL;
#if defined(__linux__) || defined(__GNUstep__)
    database.statementCache = [NSMutableDictionary dictionary];
    database.cacheQueue = dispatch_queue_create("com.atproto.pds.database.cache", DISPATCH_QUEUE_SERIAL);
#else
    database.statementCache = [NSMutableDictionary dictionary];
#endif
    return database;
}

- (BOOL)openWithError:(NSError **)error {
    if (self.isOpen) {
        return YES;
    }

    // Ensure parent directory exists
    NSURL *parentDir = [self.databaseURL URLByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:parentDir.path]) {
        NSError *dirError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:parentDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&dirError]) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                             code:PDSDatabaseErrorNotOpen
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create database directory: %@", dirError.localizedDescription]}];
            }
            return NO;
        }
    }

    int rc = sqlite3_open(self.databaseURL.path.fileSystemRepresentation, &_db);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey: @(sqlite3_errmsg(_db))}];
        }
        return NO;
    }

    [self setPerformanceOptimizations:error];
    [self setWalMode:error];
    [self createSchema:error];

    self.isOpen = (rc == SQLITE_OK);
    return self.isOpen;
}



- (void)close {
    if (!self.isOpen) return;
    PDS_LOG_DB_DEBUG(@"Closing database connection");

#if defined(__linux__) || defined(__GNUstep__)
    dispatch_sync(self.cacheQueue, ^{
        for (NSValue *val in [self.statementCache allValues]) {
            sqlite3_finalize([val pointerValue]);
        }
        [self.statementCache removeAllObjects];
        self.statementCache = nil;
    });
#else
    if (_db) {
        // Finalize all cached statements
        @synchronized(self.statementCache) {
            for (NSValue *stmtValue in [self.statementCache allValues]) {
                sqlite3_stmt *stmt = [stmtValue pointerValue];
                sqlite3_finalize(stmt);
            }
            [self.statementCache removeAllObjects];
        }
        
        sqlite3_close(_db);
        _db = NULL;
    }
#endif

    // Finalize any other stray statements
    sqlite3_stmt *strayStmt;
    while ((strayStmt = sqlite3_next_stmt(self.db, NULL)) != NULL) {
        sqlite3_finalize(strayStmt);
    }

    sqlite3_close(_db);
    _db = NULL;
    self.isOpen = NO;
    PDS_LOG_DB_DEBUG(@"Database connection closed");
}

- (void)dealloc {
    [self close];
}

#if defined(__linux__) || defined(__GNUstep__)
- (nullable sqlite3_stmt *)cachedStatementForKey:(NSString *)key {
    __block sqlite3_stmt *stmt = NULL;
    dispatch_sync(self.cacheQueue, ^{
        NSValue *val = self.statementCache[key];
        if (val) {
            stmt = [val pointerValue];
        }
    });
    return stmt;
}

- (void)cacheStatement:(sqlite3_stmt *)stmt forKey:(NSString *)key {
    dispatch_sync(self.cacheQueue, ^{
        NSValue *existingVal = self.statementCache[key];
        if (existingVal) {
            sqlite3_finalize([existingVal pointerValue]);
        }
        
        if (self.statementCache.count >= 100) {
            NSString *keyToRemove = [self.statementCache allKeys].firstObject;
            if (keyToRemove) {
                 NSValue *valToRemove = self.statementCache[keyToRemove];
                 sqlite3_finalize([valToRemove pointerValue]);
                 [self.statementCache removeObjectForKey:keyToRemove];
            }
        }
        self.statementCache[key] = [NSValue valueWithPointer:stmt];
    });
}
#else
- (sqlite3_stmt *)preparedStatementForQuery:(NSString *)query {
    @synchronized(self.statementCache) {
        NSValue *stmtValue = self.statementCache[query];
        if (stmtValue) {
            sqlite3_stmt *stmt = [stmtValue pointerValue];
            sqlite3_reset(stmt);
            return stmt;
        }
        
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(_db, [query UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            // Primitive cache eviction if too large
            if (self.statementCache.count >= 100) {
                // Just remove one arbitrary key
                NSString *keyToRemove = [self.statementCache allKeys].firstObject;
                if (keyToRemove) {
                    NSValue *sVal = self.statementCache[keyToRemove];
                    sqlite3_finalize([sVal pointerValue]);
                    [self.statementCache removeObjectForKey:keyToRemove];
                }
            }
            
            self.statementCache[query] = [NSValue valueWithPointer:stmt];
            return stmt;
        }
    }
    return NULL;
}
#endif

- (BOOL)prepareStatement:(sqlite3_stmt **)stmt sql:(NSString *)sql error:(NSError **)error {
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        return NO;
    }
    return YES;
}

- (BOOL)setWalMode:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "PRAGMA journal_mode=WAL", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorQueryFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @(errMsg)}];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }
    return YES;
}

- (BOOL)setPerformanceOptimizations:(NSError **)error {
    char *errMsg = NULL;
    int rc;

    rc = sqlite3_exec(_db, "PRAGMA synchronous=NORMAL", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, "PRAGMA cache_size=65536", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, "PRAGMA temp_store=MEMORY", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, "PRAGMA mmap_size=268435456", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, "PRAGMA page_size=65536", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    return YES;
}

- (BOOL)createSchema:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, [kPDSAccountTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSRepoTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSRecordTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSBlockTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSBlobTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexBlocksRepoDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexBlobsDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexAccountsHandleSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSInviteCodeTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSAdminTakedownTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexInviteCodesAccountDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexTakedownsSubjectIdSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSPasskeysTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSOAuthClientsTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexPasskeysAccountDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexPasskeysCredentialIdSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    // Migrations for accounts table
    const char *migrations[] = {
        "ALTER TABLE accounts ADD COLUMN password_salt BLOB",
        "ALTER TABLE accounts ADD COLUMN tfa_enabled INTEGER DEFAULT 0",
        "ALTER TABLE accounts ADD COLUMN tfa_secret BLOB",
        "ALTER TABLE accounts ADD COLUMN recovery_codes BLOB",
        "ALTER TABLE accounts ADD COLUMN invite_enabled INTEGER DEFAULT 0"
    };

    for (int i = 0; i < 5; i++) {
        rc = sqlite3_exec(_db, migrations[i], NULL, NULL, &errMsg);
        if (rc != SQLITE_OK && errMsg && strstr(errMsg, "duplicate column name") == NULL) {
            NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
            sqlite3_free(errMsg);
            if (error) *error = e;
            return NO;
        }
        if (errMsg) {
            sqlite3_free(errMsg);
            errMsg = NULL;
        }
    }
    
    if (errMsg) sqlite3_free(errMsg);

    return YES;
}

- (BOOL)executeRawSQL:(NSString *)sql error:(NSError **)error {
    if (!self.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey:@"Database is not open"}];
        }
        return NO;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &errMsg);

    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    return YES;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql error:(NSError **)error {
    if (!self.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey:@"Database is not open"}];
        }
        return @[];
    }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        return @[];
    }

    NSMutableArray *results = [NSMutableArray array];
    int columnCount = sqlite3_column_count(stmt);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < columnCount; i++) {
            NSString *columnName = @(sqlite3_column_name(stmt, i));
            id value = [self valueFromStatement:stmt columnIndex:i];
            if (value) {
                row[columnName] = value;
            }
        }
        [results addObject:row];
    }

    return results;
}

- (id)valueFromStatement:(sqlite3_stmt *)stmt columnIndex:(int)colIndex {
    int type = sqlite3_column_type(stmt, colIndex);
    switch (type) {
        case SQLITE_INTEGER:
            return @(sqlite3_column_int64(stmt, colIndex));
        case SQLITE_FLOAT:
            return @(sqlite3_column_double(stmt, colIndex));
        case SQLITE_BLOB: {
            const void *bytes = sqlite3_column_blob(stmt, colIndex);
            int size = sqlite3_column_bytes(stmt, colIndex);
            return [NSData dataWithBytes:bytes length:size];
        }
        case SQLITE_TEXT: {
            const unsigned char *text = sqlite3_column_text(stmt, colIndex);
            return @((const char *)text);
        }
        case SQLITE_NULL:
        default:
            return nil;
    }
}

- (NSError *)errorWithMessage:(const char *)message code:(NSInteger)code {
    NSString *msg = message ? @(message) : @"Unknown error";
    return [NSError errorWithDomain:PDSDatabaseErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}

#pragma mark - Parameterized Queries

- (NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                params:(NSArray *)params
                                                 error:(NSError **)error {
    if (!self.isOpen) {
        if (error) {
            *error = [self errorWithMessage:"Database is not open" code:PDSDatabaseErrorNotOpen];
        }
        return @[];
    }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        return @[];
    }

    for (NSUInteger i = 0; i < params.count; i++) {
        id param = params[i];
        int paramIndex = (int)(i + 1);

        if (param == [NSNull null]) {
            sqlite3_bind_null(stmt, paramIndex);
        } else if ([param isKindOfClass:[NSString class]]) {
            sqlite3_bind_text(stmt, paramIndex, [param UTF8String], -1, SQLITE_STATIC);
        } else if ([param isKindOfClass:[NSNumber class]]) {
            const char *objCType = [param objCType];
            if (strcmp(objCType, @encode(double)) == 0 || 
                strcmp(objCType, @encode(float)) == 0) {
                sqlite3_bind_double(stmt, paramIndex, [param doubleValue]);
            } else {
                sqlite3_bind_int64(stmt, paramIndex, [param longLongValue]);
            }
        } else if ([param isKindOfClass:[NSData class]]) {
            sqlite3_bind_blob(stmt, paramIndex, [param bytes], (int)[param length], SQLITE_STATIC);
        }
    }

    NSMutableArray *results = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < sqlite3_column_count(stmt); i++) {
            NSString *columnName = @(sqlite3_column_name(stmt, i));
            id value = [self valueFromStatement:stmt columnIndex:i];
            if (value) {
                row[columnName] = value;
            }
        }
        [results addObject:row];
    }

    return results;
}

- (BOOL)executeParameterizedUpdate:(NSString *)sql
                            params:(NSArray *)params
                             error:(NSError **)error {
    if (!self.isOpen) {
        if (error) {
            *error = [self errorWithMessage:"Database is not open" code:PDSDatabaseErrorNotOpen];
        }
        return NO;
    }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        return NO;
    }

    for (NSUInteger i = 0; i < params.count; i++) {
        id param = params[i];
        int paramIndex = (int)(i + 1);

        if (param == [NSNull null]) {
            sqlite3_bind_null(stmt, paramIndex);
        } else if ([param isKindOfClass:[NSString class]]) {
            sqlite3_bind_text(stmt, paramIndex, [param UTF8String], -1, SQLITE_STATIC);
        } else if ([param isKindOfClass:[NSNumber class]]) {
            const char *objCType = [param objCType];
            if (strcmp(objCType, @encode(double)) == 0 || 
                strcmp(objCType, @encode(float)) == 0) {
                sqlite3_bind_double(stmt, paramIndex, [param doubleValue]);
            } else {
                sqlite3_bind_int64(stmt, paramIndex, [param longLongValue]);
            }
        } else if ([param isKindOfClass:[NSData class]]) {
            sqlite3_bind_blob(stmt, paramIndex, [param bytes], (int)[param length], SQLITE_STATIC);
        }
    }

    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);

    if (!success && error) {
        *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
    }

    return success;
}

#pragma mark - Accounts

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    // Validate handle
    if (![ATProtoHandleValidator validateHandle:account.handle error:error]) {
        return NO;
    }
    account.handle = [ATProtoHandleValidator normalizeHandle:account.handle];

    NSString *sql = @"INSERT INTO accounts (did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at, updated_at, tfa_enabled, tfa_secret, recovery_codes, invite_enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, account.did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, account.handle.UTF8String, -1, SQLITE_STATIC);
    if (account.email) {
        sqlite3_bind_text(stmt, 3, account.email.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    [self bindData:account.passwordHash toStatement:stmt index:4];
    [self bindData:account.passwordSalt toStatement:stmt index:5];
    [self bindData:account.accessJwt toStatement:stmt index:6];
    [self bindData:account.refreshJwt toStatement:stmt index:7];
    sqlite3_bind_text(stmt, 8, [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSince1970:account.createdAt]].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 9, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);
    // 2FA columns (defaults)
    sqlite3_bind_int(stmt, 10, account.tfaEnabled ? 1 : 0);
    [self bindData:account.tfaSecret toStatement:stmt index:11];
    [self bindData:account.recoveryCodes toStatement:stmt index:12];
    sqlite3_bind_int(stmt, 13, account.inviteEnabled ? 1 : 0);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    // Validate handle
    if (![ATProtoHandleValidator validateHandle:account.handle error:error]) {
        return NO;
    }
    account.handle = [ATProtoHandleValidator normalizeHandle:account.handle];

    NSString *sql = @"UPDATE accounts SET handle = ?, email = ?, password_hash = ?, password_salt = ?, access_jwt = ?, refresh_jwt = ?, updated_at = ?, tfa_enabled = ?, tfa_secret = ?, recovery_codes = ?, invite_enabled = ? WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, account.handle.UTF8String, -1, SQLITE_STATIC);
    if (account.email) {
        sqlite3_bind_text(stmt, 2, account.email.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 2);
    }
    [self bindData:account.passwordHash toStatement:stmt index:3];
    [self bindData:account.passwordSalt toStatement:stmt index:4];
    [self bindData:account.accessJwt toStatement:stmt index:5];
    [self bindData:account.refreshJwt toStatement:stmt index:6];
    sqlite3_bind_text(stmt, 7, [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSince1970:account.updatedAt]].UTF8String, -1, SQLITE_STATIC);
    
    // 2FA
    sqlite3_bind_int(stmt, 8, account.tfaEnabled ? 1 : 0);
    [self bindData:account.tfaSecret toStatement:stmt index:9];
    [self bindData:account.recoveryCodes toStatement:stmt index:10];
    sqlite3_bind_int(stmt, 11, account.inviteEnabled ? 1 : 0);

    // WHERE did = ?
    sqlite3_bind_text(stmt, 12, account.did.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    return account;
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE handle = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    handle = [ATProtoHandleValidator normalizeHandle:handle];
    sqlite3_bind_text(stmt, 1, handle.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    return account;
}

- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE email = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    sqlite3_bind_text(stmt, 1, email.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    return account;
}

- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE refresh_jwt = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    // Convert NSString refreshToken to NSData for BLOB comparison
    NSData *refreshTokenData = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    sqlite3_bind_blob(stmt, 1, refreshTokenData.bytes, (int)refreshTokenData.length, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    return account;
}



- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts ORDER BY created_at DESC";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return @[];
    }

    NSMutableArray *accounts = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseAccount *account = [self accountFromStatement:stmt];
        if (account) {
            [accounts addObject:account];
        }
    }

    return accounts;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM accounts WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    return YES;
}

- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @((const char *)sqlite3_column_text(stmt, 0));
    account.handle = @((const char *)sqlite3_column_text(stmt, 1));
    
    const char *emailText = (const char *)sqlite3_column_text(stmt, 2);
    if (emailText) {
        account.email = @(emailText);
    }
    
    int blobBytes = sqlite3_column_bytes(stmt, 3);
    if (blobBytes > 0) {
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 4);
    if (blobBytes > 0) {
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 5);
    if (blobBytes > 0) {
        account.accessJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 5) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 6);
    if (blobBytes > 0) {
        account.refreshJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 6) length:blobBytes];
    }
    
    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 7);
    if (createdAtText) {
        account.createdAt = [[iso8601Formatter() dateFromString:@(createdAtText)] timeIntervalSince1970];
    }
    
    const char *updatedAtText = (const char *)sqlite3_column_text(stmt, 8);
    if (updatedAtText) {
        account.updatedAt = [[iso8601Formatter() dateFromString:@(updatedAtText)] timeIntervalSince1970];
    }
    
    // 2FA
    account.tfaEnabled = (sqlite3_column_int(stmt, 9) != 0);
    
    blobBytes = sqlite3_column_bytes(stmt, 10);
    if (blobBytes > 0) {
        account.tfaSecret = [NSData dataWithBytes:sqlite3_column_blob(stmt, 10) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 11);
    if (blobBytes > 0) {
        account.recoveryCodes = [NSData dataWithBytes:sqlite3_column_blob(stmt, 11) length:blobBytes];
    }
    
    account.inviteEnabled = (sqlite3_column_int(stmt, 12) != 0);
    
    return account;
}

- (PDSDatabaseRecord *)recordFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = @((const char *)sqlite3_column_text(stmt, 0));
    record.did = @((const char *)sqlite3_column_text(stmt, 1));
    record.collection = @((const char *)sqlite3_column_text(stmt, 2));
    record.rkey = @((const char *)sqlite3_column_text(stmt, 3));
    record.cid = @((const char *)sqlite3_column_text(stmt, 4));

    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 5);
    if (createdAtText) {
        record.createdAt = [iso8601Formatter() dateFromString:@(createdAtText)];
    }

    return record;
}

#pragma mark - Repos

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    NSString *sql = @"INSERT INTO repos (owner_did, root_cid, collection_data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, repo.ownerDid.UTF8String, -1, SQLITE_STATIC);
    [self bindData:repo.rootCid toStatement:stmt index:2];
    [self bindData:repo.collectionData toStatement:stmt index:3];
    sqlite3_bind_text(stmt, 4, [self iso8601StringFromDate:repo.createdAt].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, [self iso8601StringFromDate:repo.updatedAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error {
    NSString *sql = @"UPDATE repos SET root_cid = ?, updated_at = ? WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    [self bindData:rootCid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, ownerDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        return NO;
    }

    return YES;
}

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT * FROM repos WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseRepo *repo = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        repo = [self repoFromStatement:stmt];
    }

    return repo;
}

- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error {
    NSString *sql = @"SELECT * FROM repos ORDER BY updated_at DESC";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return @[];
    }

    NSMutableArray *repos = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRepo *repo = [self repoFromStatement:stmt];
        if (repo) {
            [repos addObject:repo];
        }
    }

    return repos;
}

- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error {
    NSString *sql = @"DELETE FROM repos WHERE owner_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, ownerDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    return YES;
}

- (PDSDatabaseRepo *)repoFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = @((const char *)sqlite3_column_text(stmt, 0));
    
    int blobBytes = sqlite3_column_bytes(stmt, 1);
    if (blobBytes > 0) {
        repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 1) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 2);
    if (blobBytes > 0) {
        repo.collectionData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
    }
    
    repo.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 3))];
    repo.updatedAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 4))];
    
    return repo;
}

#pragma mark - Blocks

- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    [self bindData:block.cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_STATIC);
    [self bindData:block.blockData toStatement:stmt index:3];
    if (block.contentType) {
        sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_int64(stmt, 5, block.size);
    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:block.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error {
    if (blocks.count == 0) {
        return YES;
    }

    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    for (PDSDatabaseBlock *block in blocks) {
        [self bindData:block.cid toStatement:stmt index:1];
        sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_STATIC);
        [self bindData:block.blockData toStatement:stmt index:3];
        if (block.contentType) {
            sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_STATIC);
        } else {
            sqlite3_bind_null(stmt, 4);
        }
        sqlite3_bind_int64(stmt, 5, block.size);
        sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:block.createdAt].UTF8String, -1, SQLITE_STATIC);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            if (error) {
                NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
                *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
            }
            return NO;
        }

        sqlite3_reset(stmt);
    }

    return YES;
}

- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blocks WHERE cid = ? AND repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    [self bindData:cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseBlock *block = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        block = [self blockFromStatement:stmt];
    }

    return block;
}

- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blocks WHERE repo_did = ? ORDER BY created_at ASC LIMIT ? OFFSET ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return @[];
    }

    sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, limit);
    sqlite3_bind_int64(stmt, 3, offset);

    NSMutableArray *blocks = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseBlock *block = [self blockFromStatement:stmt];
        if (block) {
            [blocks addObject:block];
        }
    }

    return blocks;
}

- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error {
    NSString *sql = @"SELECT COUNT(*) FROM blocks WHERE repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return 0;
    }

    sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_STATIC);

    NSInteger count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }

    return count;
}

- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    NSString *sql = @"DELETE FROM blocks WHERE cid = ? AND repo_did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    [self bindData:cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    return YES;
}

- (PDSDatabaseBlock *)blockFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    
    int blobBytes = sqlite3_column_bytes(stmt, 0);
    if (blobBytes > 0) {
        block.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:blobBytes];
    }
    
    block.repoDid = @((const char *)sqlite3_column_text(stmt, 1));
    
    blobBytes = sqlite3_column_bytes(stmt, 2);
    if (blobBytes > 0) {
        block.blockData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
    }
    
    const char *contentTypeText = (const char *)sqlite3_column_text(stmt, 3);
    if (contentTypeText) {
        block.contentType = @(contentTypeText);
    }
    
    block.size = sqlite3_column_int64(stmt, 4);
    block.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 5))];
    
    return block;
}

#pragma mark - Blobs

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO blobs (cid, did, mime_type, size, created_at) VALUES (?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    [self bindData:blob.cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, blob.did.UTF8String, -1, SQLITE_STATIC);
    if (blob.mimeType) {
        sqlite3_bind_text(stmt, 3, blob.mimeType.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    sqlite3_bind_int64(stmt, 4, blob.size);
    sqlite3_bind_text(stmt, 5, [self iso8601StringFromDate:blob.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (nullable PDSDatabaseBlob *)getBlobWithCid:(NSData *)cid error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blobs WHERE cid = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    [self bindData:cid toStatement:stmt index:1];

    PDSDatabaseBlob *blob = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        blob = [self blobFromStatement:stmt];
    }

    return blob;
}

- (NSArray<PDSDatabaseBlob *> *)getBlobsForDid:(NSString *)did limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blobs WHERE did = ? ORDER BY created_at DESC LIMIT ? OFFSET ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return @[];
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, limit);
    sqlite3_bind_int64(stmt, 3, offset);

    NSMutableArray *blobs = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseBlob *blob = [self blobFromStatement:stmt];
        if (blob) {
            [blobs addObject:blob];
        }
    }

    return blobs;
}

- (NSInteger)getBlobCountForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT COUNT(*) FROM blobs WHERE did = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return 0;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    NSInteger count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }

    return count;
}

- (BOOL)deleteBlob:(NSData *)cid error:(NSError **)error {
    NSString *sql = @"DELETE FROM blobs WHERE cid = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    [self bindData:cid toStatement:stmt index:1];

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    return YES;
}

- (PDSDatabaseBlob *)blobFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];

    int blobBytes = sqlite3_column_bytes(stmt, 0);
    if (blobBytes > 0) {
        blob.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:blobBytes];
    }

    blob.did = @((const char *)sqlite3_column_text(stmt, 1));

    const char *mimeTypeText = (const char *)sqlite3_column_text(stmt, 2);
    if (mimeTypeText) {
        blob.mimeType = @(mimeTypeText);
    }

    blob.size = sqlite3_column_int64(stmt, 3);
    blob.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 4))];

    return blob;
}

#pragma mark - Transactions

- (BOOL)beginTransactionWithError:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "BEGIN TRANSACTION", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }
    return YES;
}

- (BOOL)commitTransactionWithError:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "COMMIT", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }
    return YES;
}

- (BOOL)rollbackTransactionWithError:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "ROLLBACK", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }
    return YES;
}

#pragma mark - Helpers

- (void)bindData:(nullable NSData *)data toStatement:(sqlite3_stmt *)stmt index:(int)index {
    if (data && data.length > 0) {
        sqlite3_bind_blob(stmt, index, data.bytes, (int)data.length, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, index);
    }
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    return [iso8601Formatter() stringFromDate:date];
}

- (NSDate *)dateFromISO8601String:(NSString *)string {
    return [iso8601Formatter() dateFromString:string];
}

#pragma mark - OAuth Clients

- (NSDictionary *)getClientWithID:(NSString *)clientID error:(NSError **)error {
    NSString *sql = @"SELECT * FROM oauth_clients WHERE client_id = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    sqlite3_bind_text(stmt, 1, clientID.UTF8String, -1, SQLITE_STATIC);

    NSDictionary *client = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"client_id"] = @((const char *)sqlite3_column_text(stmt, 0));

        const char *secret = (const char *)sqlite3_column_text(stmt, 1);
        if (secret) dict[@"client_secret"] = @(secret);

        // Parse redirect_uris as space-separated list
        const char *redirectUrisStr = (const char *)sqlite3_column_text(stmt, 2);
        if (redirectUrisStr) {
            NSString *urisString = @(redirectUrisStr);
            NSArray *uris = [urisString componentsSeparatedByString:@" "];
            dict[@"redirect_uris"] = uris;
        } else {
            dict[@"redirect_uris"] = @[];
        }

        const char *grants = (const char *)sqlite3_column_text(stmt, 3);
        if (grants) dict[@"grant_types"] = @(grants);

        const char *scope = (const char *)sqlite3_column_text(stmt, 4);
        if (scope) dict[@"scope"] = @(scope);

        client = dict;
    }

    return client;
}

- (BOOL)createClient:(NSDictionary *)client error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO oauth_clients (client_id, client_secret, redirect_uris, grant_types, scope, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    NSString *clientID = client[@"client_id"];
    sqlite3_bind_text(stmt, 1, clientID.UTF8String, -1, SQLITE_STATIC);

    NSString *secret = client[@"client_secret"];
    if (secret) sqlite3_bind_text(stmt, 2, secret.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 2);

    // Convert redirect_uris array to space-separated string
    NSArray *redirectURIs = client[@"redirect_uris"];
    NSString *redirectURIsString = @"";
    if ([redirectURIs isKindOfClass:[NSArray class]] && redirectURIs.count > 0) {
        redirectURIsString = [redirectURIs componentsJoinedByString:@" "];
    }
    sqlite3_bind_text(stmt, 3, redirectURIsString.UTF8String, -1, SQLITE_STATIC);

    NSString *grants = client[@"grant_types"];
    if (grants) sqlite3_bind_text(stmt, 4, grants.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 4);

    NSString *scope = client[@"scope"];
    if (scope) sqlite3_bind_text(stmt, 5, scope.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 5);

    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }
    return YES;
}

- (BOOL)seedTestClient:(NSError **)error {
    #ifndef DEBUG
    if (error) {
        *error = [NSError errorWithDomain:@"PDSDatabase"
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Test client seeding disabled in release builds"}];
    }
    return NO;
    #else
    NSDictionary *testClient = @{
        @"client_id": @"test-client",
        @"redirect_uris": @[@"http://localhost:3000/callback", @"http://localhost:8080/callback", @"https://localhost:2583/oauth-demo/callback", @"http://localhost:2583/oauth-demo/callback", @"https://127.0.0.1:2583/oauth-demo/callback", @"http://127.0.0.1:2583/oauth-demo/callback"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    return [self createClient:testClient error:error];
    #endif
}

@end

#pragma mark - Records

@implementation PDSDatabase (Records)

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri error:(NSError **)error {
    NSString *sql = @"SELECT * FROM records WHERE uri = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseRecord *record = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        record = [self recordFromStatement:stmt];
    }

    return record;
}

- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, record.uri.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, record.did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, record.collection.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, record.rkey.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, record.cid.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:record.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        PDS_LOG_DB_ERROR(@"Failed to save record: %s (SQLite code: %d, URI: %@)",
                         sqlite3_errmsg(_db), rc, record.uri);
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error {
    NSMutableString *sql = [NSMutableString stringWithString:@"SELECT * FROM records WHERE did = ?"];
    NSMutableArray *params = [NSMutableArray arrayWithObject:did];

    if (collection.length > 0) {
        [sql appendString:@" AND collection = ?"];
        [params addObject:collection];
    }

    [sql appendString:@" ORDER BY created_at DESC"];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return @[];
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);
    if (collection.length > 0) {
        sqlite3_bind_text(stmt, 2, collection.UTF8String, -1, SQLITE_STATIC);
    }

    NSMutableArray *records = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRecord *record = [self recordFromStatement:stmt];
        if (record) {
            [records addObject:record];
        }
    }

    return records;
}

@end

#pragma mark - PDSDatabaseAccount

@implementation PDSDatabaseAccount
@end

#pragma mark - PDSDatabaseRepo

@implementation PDSDatabaseRepo
@end

#pragma mark - PDSDatabaseBlock

@implementation PDSDatabaseBlock
@end

#pragma mark - PDSDatabaseBlob

@implementation PDSDatabaseBlob
@end

#pragma mark - PDSDatabaseRecord

@implementation PDSDatabaseRecord
@end
