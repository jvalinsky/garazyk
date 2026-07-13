// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLCPersistentStore.h"
#import "PLCPersistentStoreInternal.h"
#import "PLCMockStore.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "PLC/PLCMetrics.h"
#import "PLC/PLCConstants.h"
#import "Core/NSDateFormatter+ATProto.h"

NSString * const PLCPersistentStoreErrorDomain = @"com.atproto.pds.plc.persistentstore";

// Database configuration for the PLC persistent store: replicates the previously
// hand-rolled PRAGMA set exactly (WAL, synchronous=NORMAL, foreign_keys=ON,
// temp_store=MEMORY, busy_timeout=5s, 64 MB cache, wal_autocheckpoint=1000). This is the
// value that will be handed to ConnectionManagerSerial when the store adopts QueryRunner,
// so the DB configuration is preserved across that migration.
static const ATProtoDBConfig PLCPersistentStoreDBConfig = {
    .flags = ATProtoDBConfigFlagWAL | ATProtoDBConfigFlagSynchronousNormal
             | ATProtoDBConfigFlagForeignKeys | ATProtoDBConfigFlagTempStoreMemory,
    .busyTimeout = 5000,
    .cacheSize = -64000,
    .walAutocheckpoint = 1000,
};

static NSDateFormatter *PLCStoreDBDateFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return formatter;
}

static NSDate *PLCStoreDateFromText(NSString *createdString) {
    NSDate *date = [NSDateFormatter atproto_dateFromString:createdString];
    if (date) {
        return date;
    }
    return [PLCStoreDBDateFormatter() dateFromString:createdString];
}

static NSString * const kCreateOperationsTableSQL =
    @"CREATE TABLE IF NOT EXISTS plc_operations ("
    @"  id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"  did TEXT NOT NULL,"
    @"  prev TEXT,"
    @"  sig TEXT NOT NULL,"
    @"  data BLOB NOT NULL,"
    @"  cid TEXT,"
    @"  nullified INTEGER DEFAULT 0,"
    @"  seq INTEGER,"
    @"  created_at DATETIME DEFAULT CURRENT_TIMESTAMP"
    @");";

static NSString * const kCreateDidIndexSQL = 
    @"CREATE INDEX IF NOT EXISTS idx_plc_operations_did ON plc_operations(did);";

static NSString * const kCreatePrevIndexSQL = 
    @"CREATE INDEX IF NOT EXISTS idx_plc_operations_prev ON plc_operations(prev);";

static NSString * const kCreateSeqIndexSQL =
    @"CREATE UNIQUE INDEX IF NOT EXISTS idx_plc_operations_seq ON plc_operations(seq);";

static NSString * const kCreateDidCidIndexSQL =
    @"CREATE UNIQUE INDEX IF NOT EXISTS idx_plc_operations_did_cid ON plc_operations(did, cid);";

static NSString * const kInsertOperationSQL =
    @"INSERT INTO plc_operations (did, prev, sig, data, cid, nullified, seq, created_at) "
    @"VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, (SELECT COALESCE(MAX(seq), 0) + 1 FROM plc_operations)), ?);";

static NSString * const kSelectHistorySQL =
    @"SELECT id, did, prev, sig, data, cid, nullified, created_at, seq FROM plc_operations "
    @"WHERE did = ? AND nullified = 0 ORDER BY seq ASC, id ASC;";

static NSString * const kSelectHistoryIncludingNullifiedSQL =
    @"SELECT id, did, prev, sig, data, cid, nullified, created_at, seq FROM plc_operations "
    @"WHERE did = ? ORDER BY seq ASC, id ASC;";

static NSString * const kSelectHistorySinceSQL =
    @"SELECT id, did, prev, sig, data, cid, nullified, created_at, seq FROM plc_operations "
    @"WHERE did = ? AND id > ? AND nullified = 0 ORDER BY id ASC;";

static NSString * const kCountOperationsSQL = 
    @"SELECT COUNT(*) FROM plc_operations WHERE did = ?;";

static NSString * const kDeleteOperationsSQL =
    @"DELETE FROM plc_operations WHERE did = ?;";

static NSString * const kSelectLatestOperationSQL =
    @"SELECT id, did, prev, sig, data, cid, nullified, created_at, seq FROM plc_operations "
    @"WHERE did = ? AND nullified = 0 ORDER BY seq DESC, id DESC LIMIT 1;";

static NSString * const kSelectExportOperationsSQL =
    @"SELECT id, did, prev, sig, data, cid, nullified, created_at, seq FROM plc_operations "
    @"WHERE created_at > ? ORDER BY created_at ASC, id ASC LIMIT ?;";

static NSString * const kSelectExportOperationsBySeqSQL =
    @"SELECT id, did, prev, sig, data, cid, nullified, created_at, seq FROM plc_operations "
    @"WHERE seq > ? ORDER BY seq ASC LIMIT ?;";

static NSString * const kSelectAllDIDsSQL =
    @"SELECT DISTINCT did FROM plc_operations ORDER BY did ASC;";

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
        _open = NO;
        _connectionManager = [[ATProtoConnectionManagerSerial alloc] initWithLabel:@"com.atproto.pds.plc.persistentstore"];
        _queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:_connectionManager
                                                                         errorDomain:PLCPersistentStoreErrorDomain];
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
    if (dbDir.length > 0 && ![fm fileExistsAtPath:dbDir]) {
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

    // The connection manager owns the connection and applies PLCPersistentStoreDBConfig
    // (WAL, foreign_keys, 64 MB cache, ...) — exactly the pragmas the store set by hand.
    if (![self.connectionManager openWithPath:self.dbPath config:PLCPersistentStoreDBConfig error:error]) {
        return NO;
    }

    // Schema creation and legacy upgrades run atomically inside one transaction on the
    // managed connection: createSchemaOnConnection: threads the same handle through
    // ensureSchemaUpgradesOnConnection: (table -> ALTER -> index ordering), and any
    // failure rolls the whole thing back, so a half-migrated database is never left on
    // disk. (SQLite DDL and ALTER TABLE ADD COLUMN are transactional.)
    __block BOOL schemaOK = NO;
    __block NSError *schemaError = nil;
    [self.connectionManager transact:^(sqlite3 *db, BOOL *rollback) {
        schemaOK = [self createSchemaOnConnection:db error:&schemaError];
        *rollback = !schemaOK;
    } error:NULL];
    if (!schemaOK) {
        [self.connectionManager close];
        if (error) *error = schemaError;
        return NO;
    }

    self.open = YES;
    return YES;
}

- (BOOL)createSchemaOnConnection:(sqlite3 *)db error:(NSError **)error {
    char *errMsg = NULL;
    int result = sqlite3_exec(db, kCreateOperationsTableSQL.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to create operations table"]}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }

    if (![self ensureSchemaUpgradesOnConnection:db error:error]) {
        return NO;
    }

    result = sqlite3_exec(db, kCreateDidIndexSQL.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to create DID index"]}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }
    
    result = sqlite3_exec(db, kCreatePrevIndexSQL.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to create prev index"]}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }

    result = sqlite3_exec(db, kCreateSeqIndexSQL.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to create seq index"]}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }

    result = sqlite3_exec(db, kCreateDidCidIndexSQL.UTF8String, NULL, NULL, &errMsg);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to create DID/CID index"]}];
        }
        if (errMsg) sqlite3_free(errMsg);
        return NO;
    }
    
    return YES;
}

- (BOOL)ensureSchemaUpgradesOnConnection:(sqlite3 *)db error:(NSError **)error {
    NSMutableSet<NSString *> *columns = [NSMutableSet set];
    sqlite3_stmt *stmt = NULL;
    int prepareResult = sqlite3_prepare_v2(db, "PRAGMA table_info(plc_operations);", -1, &stmt, NULL);
    if (prepareResult != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:prepareResult
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to inspect plc_operations schema"}];
        }
        return NO;
    }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *nameText = sqlite3_column_text(stmt, 1);
        if (nameText) {
            [columns addObject:[NSString stringWithUTF8String:(const char *)nameText]];
        }
    }
    sqlite3_finalize(stmt);

    if (![columns containsObject:@"cid"]) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, "ALTER TABLE plc_operations ADD COLUMN cid TEXT;", NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to add cid column"]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }

    if (![columns containsObject:@"nullified"]) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, "ALTER TABLE plc_operations ADD COLUMN nullified INTEGER DEFAULT 0;", NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to add nullified column"]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }

    if (![columns containsObject:@"seq"]) {
        char *errMsg = NULL;
        int result = sqlite3_exec(db, "ALTER TABLE plc_operations ADD COLUMN seq INTEGER;", NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to add seq column"]}];
            }
            if (errMsg) sqlite3_free(errMsg);
            return NO;
        }
    }

    char *errMsg = NULL;
    int backfillResult = sqlite3_exec(db, "UPDATE plc_operations SET seq = id WHERE seq IS NULL;", NULL, NULL, &errMsg);
    if (backfillResult != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:backfillResult
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg ?: "Failed to backfill seq"]}];
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
    [self.connectionManager close];
    self.open = NO;
}

#pragma mark - PLCStore Protocol

- (nullable NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did
                                      includeNullified:(BOOL)includeNullified
                                                 error:(NSError **)error {
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
    
    [self.connectionManager execute:^(sqlite3 *db) {
        NSString *query = includeNullified ? kSelectHistoryIncludingNullifiedSQL : kSelectHistorySQL;
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, query.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(db)]}];
            return;
        }

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PLCOperation *op = [self operationFromStatement:stmt];
            if (op) {
                [operations addObject:op];
            }
        }

        sqlite3_finalize(stmt);
    } error:NULL];
    
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

- (BOOL)appendOperation:(PLCOperation *)op
           nullifyCIDs:(NSArray<NSString *> *)nullified
                 error:(NSError **)error {
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
    
    [self.connectionManager execute:^(sqlite3 *db) {
        char *txErr = NULL;
        if (sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", NULL, NULL, &txErr) != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:PLCPersistentStoreErrorInvalidOperation
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:txErr ?: "Failed to begin operation transaction"]}];
            if (txErr) sqlite3_free(txErr);
            return;
        }

        sqlite3_stmt *stmt = NULL;
        int prepareRC = sqlite3_prepare_v2(db, kInsertOperationSQL.UTF8String, -1, &stmt, NULL);
        if (prepareRC != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                             code:prepareRC
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(db)]}];
            sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
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
            sqlite3_finalize(stmt);
            sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
            return;
        }

        sqlite3_bind_blob(stmt, 4, cborData.bytes, (int)cborData.length, SQLITE_TRANSIENT);

        NSError *cidError = nil;
        NSString *cidString = op.cid;
        if (!cidString) {
            cidString = [PLCOperation calculateCIDForOperation:[op toDictionary] error:&cidError];
            op.cid = cidString;
        }
        if (!cidString) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:PLCPersistentStoreErrorInvalidOperation
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to calculate CID for operation",
                                                 NSUnderlyingErrorKey: cidError ?: [NSNull null]}];
            sqlite3_finalize(stmt);
            sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
            return;
        }

        sqlite3_bind_text(stmt, 5, cidString.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 6, 0);
        if (!op.createdAt) {
            op.createdAt = [NSDate date];
        }
        if (op.sequence) {
            sqlite3_bind_int64(stmt, 7, op.sequence.longLongValue);
        } else {
            sqlite3_bind_null(stmt, 7);
        }
        NSString *createdString = [NSDateFormatter atproto_stringFromDate:op.createdAt];
        sqlite3_bind_text(stmt, 8, createdString.UTF8String, -1, SQLITE_TRANSIENT);

        int result = sqlite3_step(stmt);
        if (result != SQLITE_DONE) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to insert operation: %s", sqlite3_errmsg(db)]}];
            sqlite3_finalize(stmt);
            sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
            return;
        }
        if (!op.sequence) {
            sqlite3_int64 rowid = sqlite3_last_insert_rowid(db);
            sqlite3_stmt *seqStmt = NULL;
            if (sqlite3_prepare_v2(db, "SELECT seq FROM plc_operations WHERE id = ?;", -1, &seqStmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int64(seqStmt, 1, rowid);
                if (sqlite3_step(seqStmt) == SQLITE_ROW) {
                    op.sequence = @(sqlite3_column_int64(seqStmt, 0));
                }
            }
            if (seqStmt) sqlite3_finalize(seqStmt);
        }

        sqlite3_finalize(stmt);
        success = YES;

        if (success && nullified.count > 0) {
            NSMutableString *sql = [NSMutableString stringWithString:@"UPDATE plc_operations SET nullified = 1 WHERE did = ? AND cid IN ("];
            for (NSUInteger i = 0; i < nullified.count; i++) {
                [sql appendString:(i == 0 ? @"?" : @",?")];
            }
            [sql appendString:@");"];
            sqlite3_stmt *updateStmt = NULL;
            int updateResult = sqlite3_prepare_v2(db, sql.UTF8String, -1, &updateStmt, NULL);
            if (updateResult != SQLITE_OK) {
                blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                                code:updateResult
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare nullify statement"}];
                if (updateStmt) sqlite3_finalize(updateStmt);
                sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
                success = NO;
                return;
            }
            sqlite3_bind_text(updateStmt, 1, op.did.UTF8String, -1, SQLITE_TRANSIENT);
            for (NSUInteger i = 0; i < nullified.count; i++) {
                sqlite3_bind_text(updateStmt, (int)i + 2, nullified[i].UTF8String, -1, SQLITE_TRANSIENT);
            }
            int updateStep = sqlite3_step(updateStmt);
            if (updateStep != SQLITE_DONE) {
                blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                                code:updateStep
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to nullify operations"}];
                success = NO;
            } else if (sqlite3_changes(db) != (int)nullified.count) {
                blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                                code:PLCPersistentStoreErrorInvalidOperation
                                            userInfo:@{NSLocalizedDescriptionKey: @"Nullification did not match all requested CIDs"}];
                success = NO;
            }
            sqlite3_finalize(updateStmt);
        }

        if (success) {
            if (sqlite3_exec(db, "COMMIT;", NULL, NULL, &txErr) != SQLITE_OK) {
                blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                                code:PLCPersistentStoreErrorInvalidOperation
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:txErr ?: "Failed to commit operation transaction"]}];
                if (txErr) sqlite3_free(txErr);
                sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
                success = NO;
            }
        } else {
            sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
        }
    } error:NULL];
    
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
    const unsigned char *cidText = sqlite3_column_text(stmt, 5);
    int nullifiedValue = sqlite3_column_int(stmt, 6);
    const unsigned char *createdText = sqlite3_column_text(stmt, 7);
    sqlite3_int64 seqValue = sqlite3_column_int64(stmt, 8);
    
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
    if (cidText) {
        op.cid = [NSString stringWithUTF8String:(const char *)cidText];
    }
    op.nullified = nullifiedValue != 0;
    if (createdText) {
        NSString *createdString = [NSString stringWithUTF8String:(const char *)createdText];
        if (createdString.length > 0) {
            op.createdAt = PLCStoreDateFromText(createdString);
        }
    }
    if (sqlite3_column_type(stmt, 8) != SQLITE_NULL) {
        op.sequence = @(seqValue);
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
    
    [self.connectionManager execute:^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, kCountOperationsSQL.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(db)]}];
            return;
        }

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int64(stmt, 0);
        }

        sqlite3_finalize(stmt);
    } error:NULL];
    
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
    
    [self.connectionManager execute:^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, kDeleteOperationsSQL.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(db)]}];
            return;
        }

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

        int result = sqlite3_step(stmt);
        if (result != SQLITE_DONE) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to delete operations: %s", sqlite3_errmsg(db)]}];
            sqlite3_finalize(stmt);
            return;
        }

        sqlite3_finalize(stmt);
        success = YES;
    } error:NULL];
    
    if (blockError && error) {
        *error = blockError;
    }
    
    return success;
}

- (nullable PLCOperation *)getLatestOperationForDID:(NSString *)did error:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:PLCPersistentStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return nil;
    }

    __block PLCOperation *operation = nil;
    __block NSError *blockError = nil;

    [self.connectionManager execute:^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, kSelectLatestOperationSQL.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(db)]}];
            return;
        }

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            operation = [self operationFromStatement:stmt];
        }

        sqlite3_finalize(stmt);
    } error:NULL];

    if (blockError && error) {
        *error = blockError;
    }

    return operation;
}

- (nullable NSArray<PLCOperation *> *)exportOperationsAfter:(nullable NSDate *)after
                                                      count:(NSUInteger)count
                                                      error:(NSError **)error {
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

    [self.connectionManager execute:^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, kSelectExportOperationsSQL.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(db)]}];
            return;
        }

        NSString *dateString = @"1970-01-01 00:00:00";
        if (after) {
            dateString = [NSDateFormatter atproto_stringFromDate:after];
        }

        sqlite3_bind_text(stmt, 1, dateString.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, (int)count);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PLCOperation *op = [self operationFromStatement:stmt];
            if (op) {
                [operations addObject:op];
            }
        }

        sqlite3_finalize(stmt);
    } error:NULL];

    if (blockError && error) {
        *error = blockError;
    }

    return operations;
}

- (nullable NSArray<PLCOperation *> *)exportOperationsAfterSequence:(NSNumber *)sequence
                                                              count:(NSUInteger)count
                                                              error:(NSError **)error {
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

    [self.connectionManager execute:^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, kSelectExportOperationsBySeqSQL.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(db)]}];
            return;
        }

        sqlite3_bind_int64(stmt, 1, sequence.longLongValue);
        sqlite3_bind_int(stmt, 2, (int)count);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PLCOperation *op = [self operationFromStatement:stmt];
            if (op) {
                [operations addObject:op];
            }
        }

        sqlite3_finalize(stmt);
    } error:NULL];

    if (blockError && error) {
        *error = blockError;
    }

    return operations;
}

- (nullable NSArray<NSString *> *)getAllDIDsWithError:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                        code:PLCPersistentStoreErrorDatabaseClosed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return nil;
    }

    __block NSMutableArray<NSString *> *dids = [NSMutableArray array];
    __block NSError *blockError = nil;

    [self.connectionManager execute:^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, kSelectAllDIDsSQL.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errmsg(db)]}];
            return;
        }

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *didText = sqlite3_column_text(stmt, 0);
            if (didText) {
                [dids addObject:[NSString stringWithUTF8String:(const char *)didText]];
            }
        }

        sqlite3_finalize(stmt);
    } error:NULL];

    if (blockError && error) {
        *error = blockError;
    }

    return dids;
}

@end
