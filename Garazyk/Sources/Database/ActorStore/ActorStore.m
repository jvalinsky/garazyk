#import "ActorStore.h"
#import "Core/ATProtoError.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>
#if defined(GNUSTEP)
#import "Auth/PDSOpenSSLKeyManager.h"
#else
#import "Auth/PDSAppleActorKeyManager.h"
#endif
#if !defined(GNUSTEP)
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#endif
#import "Database/PDSDatabase.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Auth/Secp256k1.h"
#import "Debug/PDSLogger.h"
#import "PDSActorStoreInternal.h"
#import "PDSActorStore+Account.h"
#import "PDSActorStore+Blob.h"
#import "Auth/CryptoUtils.h"
#import "App/PDSConfiguration.h"

extern void PDSActorStoreLinkAccountCategory(void);
extern void PDSActorStoreLinkBlobCategory(void);

NSString * const PDSActorStoreErrorDomain = @"com.atproto.pds.actorstore";

static inline void PDSActorStoreEnsureCategoryObjectsLinked(void) {
    PDSActorStoreLinkAccountCategory();
    PDSActorStoreLinkBlobCategory();
}



#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"

#if !defined(GNUSTEP)
@interface PDSActorStore () <PDSAppleActorKeyManagerDelegate>
#else
@interface PDSActorStore ()
#endif

- (BOOL)addColumnIfNeeded:(NSString *)tableName column:(NSString *)columnName type:(NSString *)type;

@end

@implementation PDSActorStore

#if defined(GNUSTEP)
static NSString *PDSActorStoreBaseDirectoryFromDBPath(NSString *dbPath) {
    if (dbPath.length == 0) return @"";
    // dbPath is {base}/{method}/{prefix}/{did}
    // base = dirname(dirname(dirname(dbPath)))
    NSString *prefixDir = [dbPath stringByDeletingLastPathComponent];
    NSString *methodDir = [prefixDir stringByDeletingLastPathComponent];
    NSString *baseDir = [methodDir stringByDeletingLastPathComponent];
    return baseDir ?: @"";
}
#endif

+ (instancetype)storeWithDid:(NSString *)did 
                    dbPath:(NSString *)dbPath
                      error:(NSError **)error {
    PDSActorStore *store = [[PDSActorStore alloc] initWithDid:did dbPath:dbPath];
    if (![store openWithError:error]) {
        return nil;
    }
    return store;
}

const void * const kPDSActorStoreQueueKey = &kPDSActorStoreQueueKey;

- (instancetype)initWithDid:(NSString *)did dbPath:(NSString *)dbPath {
    PDSActorStoreEnsureCategoryObjectsLinked();
    self = [super init];
    if (self) {
        _did = [did copy];
        _dbPath = [dbPath copy];
#if defined(GNUSTEP)
        // Keys are stored under {base}/keys (shared across actor stores), not under the per-prefix shard directory.
        NSString *baseDir = PDSActorStoreBaseDirectoryFromDBPath(dbPath);
        NSString *keystorePath = [[baseDir stringByAppendingPathComponent:@"keys"] copy];
        _keyManager = [[PDSOpenSSLKeyManager alloc] initWithDid:did keystorePath:keystorePath];
#else
        _keyManager = [[PDSAppleActorKeyManager alloc] initWithDid:did];
        if ([_keyManager isKindOfClass:[PDSAppleActorKeyManager class]]) {
            ((PDSAppleActorKeyManager *)_keyManager).delegate = self;
        }
#endif
        _db = NULL;
        _open = NO;
        _transactionQueue = dispatch_queue_create("com.atproto.pds.actorstore.transaction", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_transactionQueue, kPDSActorStoreQueueKey, (void *)kPDSActorStoreQueueKey, NULL);
        _stmtCache = [NSMapTable strongToStrongObjectsMapTable];
        _blobCache = [NSMutableDictionary dictionary];
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
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:@"Failed to create database directory"
                                    underlyingError:createError];
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
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:[NSString stringWithUTF8String:errMsg]
                                          userInfo:@{@"sqlite_code": @(result)}];
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
        NSString *schemaError = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Failed to apply schema";
        BOOL recoverableRevMigrationError = [schemaError rangeOfString:@"no such column: rev"].location != NSNotFound ||
                                           [schemaError rangeOfString:@"no such column: subject_did"].location != NSNotFound ||
                                           [schemaError rangeOfString:@"no such column: keychain_tag"].location != NSNotFound;
        if (!recoverableRevMigrationError) {
            if (error) {
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:schemaError
                                          userInfo:@{@"sqlite_code": @(result)}];
            }
            if (errMsg) {
                sqlite3_free(errMsg);
            }
            return NO;
        }

        PDS_LOG_DB_WARN(@"Actor store schema needs revision migration for %@: %@",
                        self.did,
                        schemaError);
    }
    if (errMsg) {
        sqlite3_free(errMsg);
    }

    // Phase 4 Migrations: Add missing columns to existing tables
    // Actor and service tables share some common columns
    [self addColumnIfNeeded:@"accounts" column:@"password_salt" type:@"BLOB"];
    [self addColumnIfNeeded:@"accounts" column:@"tfa_enabled" type:@"INTEGER DEFAULT 0"];
    [self addColumnIfNeeded:@"accounts" column:@"tfa_secret" type:@"BLOB"];
    [self addColumnIfNeeded:@"accounts" column:@"recovery_codes" type:@"BLOB"];
    [self addColumnIfNeeded:@"accounts" column:@"invite_enabled" type:@"INTEGER DEFAULT 0"];

    [self addColumnIfNeeded:@"records" column:@"value" type:@"BLOB"];
    [self addColumnIfNeeded:@"records" column:@"subject_did" type:@"TEXT"];
    [self addColumnIfNeeded:@"records" column:@"rev" type:@"TEXT"];

    [self addColumnIfNeeded:@"ipld_blocks" column:@"rev" type:@"TEXT"];
    
    // For service DB
    [self addColumnIfNeeded:@"jwt_signing_keys" column:@"keychain_tag" type:@"TEXT"];

    // Ensure indices for migrated columns
    sqlite3_exec(_db, "CREATE INDEX IF NOT EXISTS idx_records_subject_did ON records(subject_did)", NULL, NULL, NULL);
    sqlite3_exec(_db, "CREATE INDEX IF NOT EXISTS idx_records_subject_did_collection ON records(subject_did, collection)", NULL, NULL, NULL);

    // Backward-compatible schema evolution for repo revision tracking.
    NSString *tableInfoSQL = @"PRAGMA table_info(repo_root)";
    sqlite3_stmt *tableInfoStmt = NULL;
    int tableInfoResult = sqlite3_prepare_v2(self.db, tableInfoSQL.UTF8String, -1, &tableInfoStmt, NULL);
    if (tableInfoResult != SQLITE_OK) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:@"Failed to inspect repo_root schema"
                                      userInfo:@{@"sqlite_code": @(tableInfoResult)}];
        }
        return NO;
    }

    BOOL hasRevColumn = NO;
    while (sqlite3_step(tableInfoStmt) == SQLITE_ROW) {
        const char *columnName = (const char *)sqlite3_column_text(tableInfoStmt, 1);
        if (columnName && strcmp(columnName, "rev") == 0) {
            hasRevColumn = YES;
            break;
        }
    }
    sqlite3_finalize(tableInfoStmt);

    if (!hasRevColumn) {
        char *alterErrMsg = NULL;
        int alterResult = sqlite3_exec(self.db,
                                       "ALTER TABLE repo_root ADD COLUMN rev TEXT",
                                       NULL,
                                       NULL,
                                       &alterErrMsg);
        if (alterResult != SQLITE_OK) {
            if (error) {
                NSString *msg = alterErrMsg ? [NSString stringWithUTF8String:alterErrMsg] : @"Failed to add rev column";
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:msg
                                          userInfo:@{@"sqlite_code": @(alterResult)}];
            }
            if (alterErrMsg) {
                sqlite3_free(alterErrMsg);
            }
            return NO;
        }
    }

    // Backward-compatible schema evolution for per-record revision tracking.
    tableInfoSQL = @"PRAGMA table_info(records)";
    tableInfoStmt = NULL;
    tableInfoResult = sqlite3_prepare_v2(self.db, tableInfoSQL.UTF8String, -1, &tableInfoStmt, NULL);
    if (tableInfoResult != SQLITE_OK) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:@"Failed to inspect records schema"
                                      userInfo:@{@"sqlite_code": @(tableInfoResult)}];
        }
        return NO;
    }

    BOOL hasRecordRevColumn = NO;
    while (sqlite3_step(tableInfoStmt) == SQLITE_ROW) {
        const char *columnName = (const char *)sqlite3_column_text(tableInfoStmt, 1);
        if (columnName && strcmp(columnName, "rev") == 0) {
            hasRecordRevColumn = YES;
            break;
        }
    }
    sqlite3_finalize(tableInfoStmt);

    if (!hasRecordRevColumn) {
        char *alterErrMsg = NULL;
        int alterResult = sqlite3_exec(self.db,
                                       "ALTER TABLE records ADD COLUMN rev TEXT",
                                       NULL,
                                       NULL,
                                       &alterErrMsg);
        if (alterResult != SQLITE_OK) {
            if (error) {
                NSString *msg = alterErrMsg ? [NSString stringWithUTF8String:alterErrMsg] : @"Failed to add records.rev column";
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:msg
                                          userInfo:@{@"sqlite_code": @(alterResult)}];
            }
            if (alterErrMsg) {
                sqlite3_free(alterErrMsg);
            }
            return NO;
        }
    }

    // Backward-compatible schema evolution for tombstone revision tracking.
    tableInfoSQL = @"PRAGMA table_info(record_tombstones)";
    tableInfoStmt = NULL;
    tableInfoResult = sqlite3_prepare_v2(self.db, tableInfoSQL.UTF8String, -1, &tableInfoStmt, NULL);
    if (tableInfoResult != SQLITE_OK) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:@"Failed to inspect record_tombstones schema"
                                      userInfo:@{@"sqlite_code": @(tableInfoResult)}];
        }
        return NO;
    }

    BOOL hasTombstoneRevColumn = NO;
    while (sqlite3_step(tableInfoStmt) == SQLITE_ROW) {
        const char *columnName = (const char *)sqlite3_column_text(tableInfoStmt, 1);
        if (columnName && strcmp(columnName, "rev") == 0) {
            hasTombstoneRevColumn = YES;
            break;
        }
    }
    sqlite3_finalize(tableInfoStmt);

    if (!hasTombstoneRevColumn) {
        char *alterErrMsg = NULL;
        int alterResult = sqlite3_exec(self.db,
                                       "ALTER TABLE record_tombstones ADD COLUMN rev TEXT",
                                       NULL,
                                       NULL,
                                       &alterErrMsg);
        if (alterResult != SQLITE_OK) {
            if (error) {
                NSString *msg = alterErrMsg ? [NSString stringWithUTF8String:alterErrMsg] : @"Failed to add record_tombstones.rev column";
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:msg
                                          userInfo:@{@"sqlite_code": @(alterResult)}];
            }
            if (alterErrMsg) {
                sqlite3_free(alterErrMsg);
            }
            return NO;
        }

        char *backfillErrMsg = NULL;
        int backfillResult = sqlite3_exec(self.db,
                                          "UPDATE record_tombstones "
                                          "SET rev = COALESCE(rev, created_at) "
                                          "WHERE rev IS NULL OR rev = ''",
                                          NULL,
                                          NULL,
                                          &backfillErrMsg);
        if (backfillResult != SQLITE_OK) {
            if (error) {
                NSString *msg = backfillErrMsg ? [NSString stringWithUTF8String:backfillErrMsg] : @"Failed to backfill record_tombstones.rev";
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:msg
                                          userInfo:@{@"sqlite_code": @(backfillResult)}];
            }
            if (backfillErrMsg) {
                sqlite3_free(backfillErrMsg);
            }
            return NO;
        }
    }

    char *indexErrMsg = NULL;
    int indexResult = sqlite3_exec(self.db,
                                   "CREATE INDEX IF NOT EXISTS idx_records_rev ON records(rev)",
                                   NULL,
                                   NULL,
                                   &indexErrMsg);
    if (indexResult != SQLITE_OK) {
        if (error) {
            NSString *msg = indexErrMsg ? [NSString stringWithUTF8String:indexErrMsg] : @"Failed to create records.rev index";
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:msg
                                      userInfo:@{@"sqlite_code": @(indexResult)}];
        }
        if (indexErrMsg) {
            sqlite3_free(indexErrMsg);
        }
        return NO;
    }

    indexErrMsg = NULL;
    indexResult = sqlite3_exec(self.db,
                               "CREATE INDEX IF NOT EXISTS idx_record_tombstones_rev ON record_tombstones(rev)",
                               NULL,
                               NULL,
                               &indexErrMsg);
    if (indexResult != SQLITE_OK) {
        if (error) {
            NSString *msg = indexErrMsg ? [NSString stringWithUTF8String:indexErrMsg] : @"Failed to create record_tombstones.rev index";
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:msg
                                      userInfo:@{@"sqlite_code": @(indexResult)}];
        }
        if (indexErrMsg) {
            sqlite3_free(indexErrMsg);
        }
        return NO;
    }

    indexErrMsg = NULL;
    indexResult = sqlite3_exec(self.db,
                               "CREATE INDEX IF NOT EXISTS idx_record_tombstones_did_rev ON record_tombstones(did, rev)",
                               NULL,
                               NULL,
                               &indexErrMsg);
    if (indexResult != SQLITE_OK) {
        if (error) {
            NSString *msg = indexErrMsg ? [NSString stringWithUTF8String:indexErrMsg] : @"Failed to create record_tombstones.did,rev index";
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:msg
                                      userInfo:@{@"sqlite_code": @(indexResult)}];
        }
        if (indexErrMsg) {
            sqlite3_free(indexErrMsg);
        }
        return NO;
    }

    // Backward-compatible schema evolution for block revision tracking.
    tableInfoSQL = @"PRAGMA table_info(ipld_blocks)";
    tableInfoStmt = NULL;
    tableInfoResult = sqlite3_prepare_v2(self.db, tableInfoSQL.UTF8String, -1, &tableInfoStmt, NULL);
    if (tableInfoResult != SQLITE_OK) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:@"Failed to inspect ipld_blocks schema"
                                      userInfo:@{@"sqlite_code": @(tableInfoResult)}];
        }
        return NO;
    }

    BOOL hasBlockRevColumn = NO;
    while (sqlite3_step(tableInfoStmt) == SQLITE_ROW) {
        const char *columnName = (const char *)sqlite3_column_text(tableInfoStmt, 1);
        if (columnName && strcmp(columnName, "rev") == 0) {
            hasBlockRevColumn = YES;
            break;
        }
    }
    sqlite3_finalize(tableInfoStmt);

    if (!hasBlockRevColumn) {
        char *alterErrMsg = NULL;
        int alterResult = sqlite3_exec(self.db,
                                       "ALTER TABLE ipld_blocks ADD COLUMN rev TEXT",
                                       NULL,
                                       NULL,
                                       &alterErrMsg);
        if (alterResult != SQLITE_OK) {
            if (error) {
                NSString *msg = alterErrMsg ? [NSString stringWithUTF8String:alterErrMsg] : @"Failed to add ipld_blocks.rev column";
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:msg
                                          userInfo:@{@"sqlite_code": @(alterResult)}];
            }
            if (alterErrMsg) {
                sqlite3_free(alterErrMsg);
            }
            return NO;
        }
    }

    indexErrMsg = NULL;
    indexResult = sqlite3_exec(self.db,
                               "CREATE INDEX IF NOT EXISTS idx_ipld_blocks_rev ON ipld_blocks(rev)",
                               NULL,
                               NULL,
                               &indexErrMsg);
    if (indexResult != SQLITE_OK) {
        if (error) {
            NSString *msg = indexErrMsg ? [NSString stringWithUTF8String:indexErrMsg] : @"Failed to create ipld_blocks.rev index";
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:msg
                                      userInfo:@{@"sqlite_code": @(indexResult)}];
        }
        if (indexErrMsg) {
            sqlite3_free(indexErrMsg);
        }
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
    
    sqlite3_close(self.db);
    self.db = NULL;
    self.open = NO;
}

#pragma mark - Error Handling

- (NSError *)errorWithSQLiteResult:(int)result message:(NSString *)message {
    return [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                             message:message ?: @"Unknown error"
                            userInfo:@{@"sqlite_code": @(result),
                                     @"sqlite_message": [NSString stringWithUTF8String:sqlite3_errmsg(self.db)] ?: @""}];
}

#pragma mark - Transaction Support

- (void)safeExecuteSync:(void(^)(void))block {
    if (dispatch_get_specific(kPDSActorStoreQueueKey)) {
        block();
    } else {
        dispatch_sync(self.transactionQueue, block);
    }
}

- (void)transactWithBlock:(void (^)(id<PDSActorStoreTransactor> transactor, NSError **error))block
                    error:(NSError **)error {
    void (^workBlock)(void) = ^{
        if (!self.open) {
            if (error) {
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                             message:@"Database is closed"];
            }
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
            block(self, &blockError);
            if (blockError) {
                success = NO;
            }
        } @catch (NSException *exception) {
            success = NO;
            blockError = [ATProtoError errorWithCode:ATProtoErrorCodeUnknown
                                           message:exception.reason ?: @"Unknown exception"];
        }
        
        if (success) {
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
            if (error) {
                *error = blockError;
            }
        }

        [self.stmtCache removeAllObjects];
    };

    [self safeExecuteSync:workBlock];
}

- (void)readWithBlock:(void (^)(id<PDSActorStoreReader> reader, NSError **error))block 
                error:(NSError **)error {
    void (^workBlock)(void) = ^{
        if (!self.open) {
            if (error) {
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:@"Database is closed"];
            }
            return;
        }
        
        NSError *blockError = nil;
        block(self, &blockError);
        if (blockError && error) {
            *error = blockError;
        }
    };

    [self safeExecuteSync:workBlock];
}

#pragma mark - Statement Management

- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error {
    if (!self.open || !self.db) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                       message:@"Database is not open"];
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


#pragma mark - Account Operations (Moved to PDSActorStore+Account)


#pragma mark - Repo Operations

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseRepo *repo = nil;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT cid, updated_at, rev FROM repo_root ORDER BY updated_at DESC LIMIT 1";
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
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return repo;
}

- (nullable NSData *)getRepoRootForDid:(NSString *)did error:(NSError **)error {
    __block NSData *rootCid = nil;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT cid FROM repo_root ORDER BY updated_at DESC LIMIT 1";
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
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return rootCid;
}

- (nullable NSString *)getRepoRevisionForDid:(NSString *)did error:(NSError **)error {
    __block NSString *revision = nil;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT rev FROM repo_root ORDER BY updated_at DESC LIMIT 1";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *revText = (const char *)sqlite3_column_text(stmt, 0);
            if (revText) {
                revision = [NSString stringWithUTF8String:revText];
            }
        }
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return revision;
}

- (nullable NSString *)latestMutationRevisionWithError:(NSError **)error {
    __block NSString *revision = nil;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT rev FROM ("
                         @"  SELECT rev AS rev FROM records WHERE rev IS NOT NULL "
                         @"  UNION ALL "
                         @"  SELECT rev AS rev FROM record_tombstones"
                         @") ORDER BY rev DESC LIMIT 1";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *revText = (const char *)sqlite3_column_text(stmt, 0);
            if (revText) {
                revision = [NSString stringWithUTF8String:revText];
            }
        }
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return revision;
}

- (BOOL)repoRevisionExists:(NSString *)rev error:(NSError **)error {
    if (rev.length == 0) {
        return NO;
    }

    __block BOOL exists = NO;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT 1 FROM repo_root WHERE rev = ? LIMIT 1";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        sqlite3_bind_text(stmt, 1, rev.UTF8String, -1, SQLITE_TRANSIENT);
        exists = (sqlite3_step(stmt) == SQLITE_ROW);
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return exists;
}

- (BOOL)mutationRevisionExists:(NSString *)rev error:(NSError **)error {
    if (rev.length == 0) {
        return NO;
    }

    __block BOOL exists = NO;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *recordsSQL = @"SELECT 1 FROM records WHERE rev = ? LIMIT 1";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *recordsStmt = [self prepareStatement:recordsSQL error:&prepError];
        if (!recordsStmt) {
            blockError = prepError;
            return;
        }

        sqlite3_bind_text(recordsStmt, 1, rev.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(recordsStmt) == SQLITE_ROW) {
            exists = YES;
            return;
        }

        NSString *tombstonesSQL = @"SELECT 1 FROM record_tombstones WHERE rev = ? LIMIT 1";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *tombstonesStmt = [self prepareStatement:tombstonesSQL error:&prepError];
        if (!tombstonesStmt) {
            blockError = prepError;
            return;
        }

        sqlite3_bind_text(tombstonesStmt, 1, rev.UTF8String, -1, SQLITE_TRANSIENT);
        exists = (sqlite3_step(tombstonesStmt) == SQLITE_ROW);
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return exists;
}

- (BOOL)blockRevisionExists:(NSString *)rev error:(NSError **)error {
    if (rev.length == 0) {
        return NO;
    }

    __block BOOL exists = NO;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT 1 FROM ipld_blocks WHERE rev = ? LIMIT 1";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        sqlite3_bind_text(stmt, 1, rev.UTF8String, -1, SQLITE_TRANSIENT);
        exists = (sqlite3_step(stmt) == SQLITE_ROW);
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return exists;
}

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    NSString *sql = @"INSERT INTO repo_root (cid, rev, updated_at) VALUES (?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    if (repo.rootCid) {
        sqlite3_bind_blob(stmt, 1, repo.rootCid.bytes, (int)repo.rootCid.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_text(stmt, 2, "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 3, repo.updatedAt.timeIntervalSince1970);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid error:(NSError **)error {
    return [self updateRepoRoot:did rootCid:rootCid rev:nil error:error];
}

- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid rev:(nullable NSString *)rev error:(NSError **)error {
    NSString *resolvedRev = rev;
    if (!resolvedRev) {
        NSString *existingRevSQL = @"SELECT rev FROM repo_root ORDER BY updated_at DESC LIMIT 1";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *existingStmt = [self prepareStatement:existingRevSQL error:error];
        if (!existingStmt) {
            return NO;
        }

        if (sqlite3_step(existingStmt) == SQLITE_ROW) {
            const char *existingRevText = (const char *)sqlite3_column_text(existingStmt, 0);
            if (existingRevText) {
                resolvedRev = [NSString stringWithUTF8String:existingRevText];
            }
        }
    }

    if (!resolvedRev) {
        resolvedRev = @"";
    }

    // Keep historical repo roots keyed by CID; this preserves revision history needed for
    // future `since` semantics while still updating the timestamp/rev for repeated heads.
    NSString *insertSQL = @"INSERT OR REPLACE INTO repo_root (cid, rev, updated_at) VALUES (?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *insertStmt = [self prepareStatement:insertSQL error:error];
    if (!insertStmt) return NO;

    if (rootCid) {
        sqlite3_bind_blob(insertStmt, 1, rootCid.bytes, (int)rootCid.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(insertStmt, 1);
    }
    sqlite3_bind_text(insertStmt, 2, resolvedRev.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(insertStmt, 3, [[NSDate date] timeIntervalSince1970]);

    int stepResult = sqlite3_step(insertStmt);
    if (stepResult != SQLITE_DONE) {
        if (error) {
            *error = [self errorWithSQLiteResult:stepResult message:@"Failed to store repo root"];
        }
        return NO;
    }
    return YES;
}

- (BOOL)clearRepoRootWithError:(NSError **)error {
    NSString *sql = @"DELETE FROM repo_root";
    char *errMsg = NULL;
    int result = sqlite3_exec(self.db, sql.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown error";
            *error = [NSError errorWithDomain:@"PDSActorStore" code:result
                                     userInfo:@{NSLocalizedDescriptionKey: msg}];
            sqlite3_free(errMsg);
        }
        return NO;
    }
    NSLog(@"[clearRepoRoot] Cleared repo_root table");
    return YES;
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

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT uri, did, collection, rkey, cid, value, created_at, rev, subject_did "
                         @"FROM records WHERE uri = ?";
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
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return record;
}

- (NSArray<NSDictionary<NSString *, id> *> *)listRecordTombstonesSinceRev:(nullable NSString *)rev
                                                                     limit:(NSUInteger)limit
                                                                     error:(NSError **)error {
    __block NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        BOOL hasRevFilter = (rev.length > 0);
        NSString *sql = hasRevFilter
            ? @"SELECT uri, did, collection, rkey, rev, created_at FROM record_tombstones "
              @"WHERE rev > ? ORDER BY rev LIMIT ?"
            : @"SELECT uri, did, collection, rkey, rev, created_at FROM record_tombstones "
              @"ORDER BY rev LIMIT ?";

        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        int idx = 1;
        if (hasRevFilter) {
            sqlite3_bind_text(stmt, idx++, rev.UTF8String, -1, SQLITE_TRANSIENT);
        }
        sqlite3_bind_int(stmt, idx++, (int)limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *uriText = (const char *)sqlite3_column_text(stmt, 0);
            const char *didText = (const char *)sqlite3_column_text(stmt, 1);
            const char *collectionText = (const char *)sqlite3_column_text(stmt, 2);
            const char *rkeyText = (const char *)sqlite3_column_text(stmt, 3);
            const char *revText = (const char *)sqlite3_column_text(stmt, 4);
            double indexedAt = sqlite3_column_double(stmt, 5);

            NSMutableDictionary<NSString *, id> *row = [NSMutableDictionary dictionary];
            row[@"uri"] = uriText ? [NSString stringWithUTF8String:uriText] : @"";
            row[@"did"] = didText ? [NSString stringWithUTF8String:didText] : @"";
            row[@"collection"] = collectionText ? [NSString stringWithUTF8String:collectionText] : @"";
            row[@"rkey"] = rkeyText ? [NSString stringWithUTF8String:rkeyText] : @"";
            row[@"rev"] = revText ? [NSString stringWithUTF8String:revText] : @"";
            row[@"indexedAt"] = @(indexedAt);
            [rows addObject:row];
        }
    };

    [self safeExecuteSync:workBlock];

    if (error && blockError) {
        *error = blockError;
    }
    return [rows copy];
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
    
    const char *revText = (const char *)sqlite3_column_text(stmt, 7);
    if (revText) {
        record.rev = [NSString stringWithUTF8String:revText];
    }

    const char *subjectDid = (const char *)sqlite3_column_text(stmt, 8);
    if (subjectDid) {
        record.subjectDid = [NSString stringWithUTF8String:subjectDid];
    }
    
    return record;
}

- (NSArray<PDSDatabaseRecord *> *)listRecordsForDid:(NSString *)did 
                                         collection:(nullable NSString *)collection 
                                               limit:(NSUInteger)limit
                                              offset:(NSUInteger)offset
                                               error:(NSError **)error {
    __block NSArray<PDSDatabaseRecord *> *result = nil;
    __block NSError *blockError = nil;

    [self safeExecuteSync:^{
        NSMutableArray<PDSDatabaseRecord *> *records = [NSMutableArray array];
        
        NSString *sql;
        if (collection) {
            sql = @"SELECT uri, did, collection, rkey, cid, value, created_at, rev, subject_did "
                  @"FROM records WHERE collection = ? ORDER BY rkey LIMIT ? OFFSET ?";
        } else {
            sql = @"SELECT uri, did, collection, rkey, cid, value, created_at, rev, subject_did "
                  @"FROM records ORDER BY rkey LIMIT ? OFFSET ?";
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
    }];

    if (error && blockError) {
        *error = blockError;
    }
    return result ?: @[];
}

- (BOOL)putRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, value, created_at, rev, subject_did) "
                     @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
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

    if (record.rev) {
        sqlite3_bind_text(stmt, 8, record.rev.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 8);
    }
    
    if (record.subjectDid) {
        sqlite3_bind_text(stmt, 9, record.subjectDid.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 9);
    }
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (BOOL)createRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT INTO records (uri, did, collection, rkey, cid, value, created_at, rev, subject_did) "
                     @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
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

    if (record.rev) {
        sqlite3_bind_text(stmt, 8, record.rev.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 8);
    }

    if (record.subjectDid) {
        sqlite3_bind_text(stmt, 9, record.subjectDid.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 9);
    }

    int stepResult = sqlite3_step(stmt);
    if (stepResult != SQLITE_DONE) {
        if (error) {
            *error = [self errorWithSQLiteResult:stepResult message:@"Failed to create record"];
        }
        return NO;
    }
    return YES;
}

- (BOOL)updateRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"UPDATE records SET did = ?, collection = ?, rkey = ?, cid = ?, value = ?, created_at = ?, rev = ?, subject_did = ? "
                     @"WHERE uri = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, record.collection.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, record.rkey.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, record.cid.UTF8String, -1, SQLITE_TRANSIENT);

    if (record.value) {
        sqlite3_bind_text(stmt, 5, record.value.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 5);
    }

    sqlite3_bind_double(stmt, 6, record.createdAt.timeIntervalSince1970);

    if (record.rev) {
        sqlite3_bind_text(stmt, 7, record.rev.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 7);
    }

    if (record.subjectDid) {
        sqlite3_bind_text(stmt, 8, record.subjectDid.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 8);
    }

    sqlite3_bind_text(stmt, 9, record.uri.UTF8String, -1, SQLITE_TRANSIENT);

    int stepResult = sqlite3_step(stmt);
    if (stepResult != SQLITE_DONE) {
        if (error) {
            *error = [self errorWithSQLiteResult:stepResult message:@"Failed to update record"];
        }
        return NO;
    }

    if (sqlite3_changes(self.db) == 0) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError message:@"Record not found"];
        }
        return NO;
    }

    return YES;
}

- (BOOL)deleteRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM records WHERE uri = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (BOOL)addRecordTombstoneURI:(NSString *)uri
                          did:(NSString *)did
                    collection:(NSString *)collection
                         rkey:(NSString *)rkey
                           rev:(NSString *)rev
                         error:(NSError **)error {
    NSString *sql = @"INSERT INTO record_tombstones (uri, did, collection, rkey, rev, created_at) "
                     @"VALUES (?, ?, ?, ?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, collection.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, rkey.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, rev.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 6, [[NSDate date] timeIntervalSince1970]);

    int stepResult = sqlite3_step(stmt);
    if (stepResult != SQLITE_DONE) {
        if (error) {
            *error = [self errorWithSQLiteResult:stepResult message:@"Failed to add record tombstone"];
        }
        return NO;
    }
    return YES;
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

- (NSArray<NSData *> *)listBlockCIDsSinceRev:(nullable NSString *)rev
                                        limit:(NSUInteger)limit
                                        error:(NSError **)error {
    __block NSMutableArray<NSData *> *cids = [NSMutableArray array];
    __block NSError *blockError = nil;

    [self safeExecuteSync:^{
        BOOL hasRevFilter = (rev.length > 0);
        NSString *sql = hasRevFilter
            ? @"SELECT cid FROM ipld_blocks WHERE rev > ? ORDER BY rev, cid LIMIT ?"
            : @"SELECT cid FROM ipld_blocks ORDER BY cid LIMIT ?";

        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        int bindIndex = 1;
        if (hasRevFilter) {
            sqlite3_bind_text(stmt, bindIndex++, rev.UTF8String, -1, SQLITE_TRANSIENT);
        }
        sqlite3_bind_int(stmt, bindIndex, (int)limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const void *cidBytes = sqlite3_column_blob(stmt, 0);
            int cidLength = sqlite3_column_bytes(stmt, 0);
            if (!cidBytes || cidLength <= 0) {
                continue;
            }
            NSData *cid = [NSData dataWithBytes:cidBytes length:(NSUInteger)cidLength];
            [cids addObject:cid];
        }
    }];

    if (error && blockError) {
        *error = blockError;
    }
    return [cids copy];
}

- (NSArray<NSData *> *)listBlockCIDsForRevision:(NSString *)rev
                                           limit:(NSUInteger)limit
                                           error:(NSError **)error {
    if (rev.length == 0) {
        return @[];
    }

    __block NSMutableArray<NSData *> *cids = [NSMutableArray array];
    __block NSError *blockError = nil;

    [self safeExecuteSync:^{
        NSString *sql = @"SELECT cid FROM ipld_blocks WHERE rev = ? ORDER BY cid LIMIT ?";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        sqlite3_bind_text(stmt, 1, rev.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, (int)limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const void *cidBytes = sqlite3_column_blob(stmt, 0);
            int cidLength = sqlite3_column_bytes(stmt, 0);
            if (!cidBytes || cidLength <= 0) {
                continue;
            }
            NSData *cid = [NSData dataWithBytes:cidBytes length:(NSUInteger)cidLength];
            [cids addObject:cid];
        }
    }];

    if (error && blockError) {
        *error = blockError;
    }
    return [cids copy];
}

- (nullable NSData *)getBlockForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    __block NSData *blockData = nil;
    __block NSError *blockError = nil;

    [self safeExecuteSync:^{
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
    }];

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
    
    [self safeExecuteSync:^{
        NSString *sql = @"SELECT cid, size, rev FROM ipld_blocks LIMIT ? OFFSET ?";
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
            const char *revText = (const char *)sqlite3_column_text(stmt, 2);
            if (revText) {
                block.rev = [NSString stringWithUTF8String:revText];
            }
            block.repoDid = did;
            [blocks addObject:block];
        }
    }];

    if (error && blockError) {
        *error = blockError;
    }
    return blocks;
}

- (BOOL)putBlock:(PDSDatabaseBlock *)block forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO ipld_blocks (cid, block, size, rev) VALUES (?, ?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    if (block.cid) {
        sqlite3_bind_blob(stmt, 1, block.cid.bytes, (int)block.cid.length, SQLITE_TRANSIENT);
    }
    if (block.blockData) {
        sqlite3_bind_blob(stmt, 2, block.blockData.bytes, (int)block.blockData.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_int64(stmt, 3, block.size);
    if (block.rev.length > 0) {
        sqlite3_bind_text(stmt, 4, block.rev.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    
    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    if (!success) {
        PDS_LOG_DB_ERROR(@"putBlock failed for cid %@: %s", [block.cid description], sqlite3_errmsg(self.db));
    }
    return success;
}

- (BOOL)putBlocks:(NSArray<PDSDatabaseBlock *> *)blocks forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO ipld_blocks (cid, block, size, rev) VALUES (?, ?, ?, ?)";
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
        if (block.rev.length > 0) {
            sqlite3_bind_text(stmt, 4, block.rev.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 4);
        }
        
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
    
    [self safeExecuteSync:^{
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
    }];

    if (error && blockError) {
        *error = blockError;
    }
    return count;
}

- (NSInteger)getBlockCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger count = 0;
    __block NSError *blockError = nil;

    [self safeExecuteSync:^{
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
    }];

    if (error && blockError) {
        *error = blockError;
    }
    return count;
}

#pragma mark - Signing Key Management

- (BOOL)generateSigningKeyWithError:(NSError **)error {
    return [self generateSigningKeyForDid:self.did error:error];
}

- (BOOL)generateSigningKeyForDid:(NSString *)targetDid error:(NSError **)error {
    if (![targetDid isEqualToString:self.did]) {
#if defined(GNUSTEP)
        NSString *baseDir = PDSActorStoreBaseDirectoryFromDBPath(self.dbPath);
        NSString *keystorePath = [[baseDir stringByAppendingPathComponent:@"keys"] copy];
        id<PDSActorKeyManager> manager = [[PDSOpenSSLKeyManager alloc] initWithDid:targetDid keystorePath:keystorePath];
#else
        id<PDSActorKeyManager> manager = [[PDSAppleActorKeyManager alloc] initWithDid:targetDid];
#endif
        return [manager generateSigningKeyWithError:error];
    }

    return [self.keyManager generateSigningKeyWithError:error];
}

- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error {
    return [self.keyManager importSigningKey:privateKey error:error];
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    return [self.keyManager signData:data error:error];
}

- (nullable NSData *)publicSigningKeyWithError:(NSError **)error {
    return [self.keyManager publicSigningKeyWithError:error];
}

- (nullable NSString *)didKeyStringWithError:(NSError **)error {
    return [self.keyManager didKeyStringWithError:error];
}

- (BOOL)storeSigningKey:(NSData *)privateKey
              publicKey:(NSData *)publicKey
                  error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT OR REPLACE INTO signing_keys (did, private_key, public_key_compressed, created_at, updated_at) "
                         "VALUES (?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }

        sqlite3_bind_text(stmt, 1, store.did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 2, privateKey.bytes, (int)privateKey.length, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 3, publicKey.bytes, (int)publicKey.length, SQLITE_TRANSIENT);
        double now = [[NSDate date] timeIntervalSince1970];
        sqlite3_bind_double(stmt, 4, now);
        sqlite3_bind_double(stmt, 5, now);

        success = (sqlite3_step(stmt) == SQLITE_DONE);
        [store finalizeStatement:stmt];
    } error:&localError];

    if (!success && error) *error = localError;
    return success;
}

- (nullable NSData *)loadSigningKeyWithError:(NSError **)error {
    __block NSData *keyData = nil;
    __block NSError *localError = nil;

    [self readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT private_key FROM signing_keys WHERE did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, store.did.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const void *blob = sqlite3_column_blob(stmt, 0);
            int bytes = sqlite3_column_bytes(stmt, 0);
            keyData = [NSData dataWithBytes:blob length:bytes];
        }
        [store finalizeStatement:stmt];
    } error:&localError];

    if (!keyData && error) *error = localError;
    return keyData;
}



#if !defined(GNUSTEP)
#pragma mark - PDSAppleActorKeyManagerDelegate

- (BOOL)appleActorKeyManager:(PDSAppleActorKeyManager *)manager
             storeSigningKey:(NSData *)privateKey
                   publicKey:(NSData *)publicKey
                       error:(NSError **)error {
    return [self storeSigningKey:privateKey publicKey:publicKey error:error];
}

- (nullable NSData *)appleActorKeyManagerLoadSigningKey:(PDSAppleActorKeyManager *)manager
                                                 error:(NSError **)error {
    return [self loadSigningKeyWithError:error];
}
#endif

#pragma mark - Blob Operations (Moved to PDSActorStore+Blob)


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
    
    // Generate a cryptographically secure random salt
    uint8_t saltBytes[16];
    if (SecRandomCopyBytes(kSecRandomDefault, 16, saltBytes) != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                          code:-1
                                      userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate secure random salt"}];
        }
        return NO;
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

- (BOOL)storeRotationKeyPrivate:(NSData *)privateKey
                      publicKey:(NSData *)compressedPublicKey
                            error:(NSError **)error {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSString *masterSecret = config.masterSecret;
    if (masterSecret.length == 0) {
        PDS_LOG_AUTH_ERROR(@"Master secret is empty in ActorStore!");
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"PDS_MASTER_SECRET not configured"}];
        }
        return NO;
    }

    return [self storeRotationKeyPrivate:privateKey
                               publicKey:compressedPublicKey
                    encryptedWithPassword:masterSecret
                                    error:error];
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

- (nullable NSData *)rotationKeyDecryptedWithError:(NSError **)error {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSString *masterSecret = config.masterSecret;
    if (masterSecret.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"PDS_MASTER_SECRET not configured"}];
        }
        return nil;
    }

    return [self rotationKeyDecryptedWithPassword:masterSecret error:error];
}

- (nullable NSData *)exportSigningKeyWithError:(NSError **)error {
    if (!self.keyManager) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeInternalServerError message:@"Key manager not available"];
        }
        return nil;
    }
    return [self.keyManager exportPrivateKeyWithError:error];
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
    return [CryptoUtils deriveKeyFromPassword:password salt:salt];
}

- (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key {
    return [CryptoUtils encryptData:data withKey:key];
}

- (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key {
    return [CryptoUtils decryptData:data withKey:key];
}

- (BOOL)addColumnIfNeeded:(NSString *)tableName column:(NSString *)columnName type:(NSString *)type {
    // First, check if the table exists
    NSString *tableCheckSql = [NSString stringWithFormat:@"SELECT name FROM sqlite_master WHERE type='table' AND name='%@'", tableName];
    sqlite3_stmt *tableStmt;
    BOOL tableExists = NO;
    if (sqlite3_prepare_v2(_db, tableCheckSql.UTF8String, -1, &tableStmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(tableStmt) == SQLITE_ROW) {
            tableExists = YES;
        }
        sqlite3_finalize(tableStmt);
    }
    
    if (!tableExists) {
        // Table doesn't exist, so column doesn't need to be added (it's likely a service table in an actor store or vice versa)
        return YES;
    }

    NSString *checkSql = [NSString stringWithFormat:@"PRAGMA table_info(%@)", tableName];
    sqlite3_stmt *stmt;
    BOOL exists = NO;
    if (sqlite3_prepare_v2(_db, checkSql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *name = (const char *)sqlite3_column_text(stmt, 1);
            if (name && strcmp(name, columnName.UTF8String) == 0) {
                exists = YES;
                break;
            }
        }
        sqlite3_finalize(stmt);
    }
    
    if (!exists) {
        NSString *alterSql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@", tableName, columnName, type];
        char *errMsg = NULL;
        if (sqlite3_exec(_db, alterSql.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
            PDS_LOG_DB_ERROR(@"Failed to add column %@ to table %@: %s", columnName, tableName, errMsg);
            sqlite3_free(errMsg);
            return NO;
        }
        PDS_LOG_DB_INFO(@"Added column %@ to table %@", columnName, tableName);
    }
    return YES;
}

@end

#pragma clang diagnostic pop
