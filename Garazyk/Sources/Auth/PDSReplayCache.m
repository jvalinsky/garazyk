// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/PDSReplayCache.h"
#import "Debug/GZLogger.h"
#import <sqlite3.h>

@implementation PDSReplayCache {
    sqlite3 *_db;
    dispatch_source_t _cleanupTimer;
    dispatch_queue_t _databaseQueue;
}

+ (instancetype)sharedCache {
    static PDSReplayCache *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSReplayCache alloc] init];
    });
    return shared;
}

- (instancetype)init {
    return [self initWithDatabasePath:nil];
}

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (self) {
        const char *dbPath = path ? path.UTF8String : ":memory:";
        int rc = sqlite3_open(dbPath, &_db);
        if (rc != SQLITE_OK) {
            GZ_LOG_AUTH_ERROR(@"Failed to open replay cache database: %s", sqlite3_errmsg(_db));
            return nil;
        }
        _databaseQueue = dispatch_queue_create("com.garazyk.auth.replay-cache.database", DISPATCH_QUEUE_SERIAL);
        sqlite3_exec(_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);

        const char *createSQL =
            "CREATE TABLE IF NOT EXISTS jti_cache ("
            "  jti TEXT PRIMARY KEY,"
            "  expires_at REAL NOT NULL"
            ");"
            "CREATE INDEX IF NOT EXISTS idx_jti_cache_expires_at ON jti_cache(expires_at);";

        char *errMsg = NULL;
        if (sqlite3_exec(_db, createSQL, NULL, NULL, &errMsg) != SQLITE_OK) {
            GZ_LOG_AUTH_ERROR(@"Failed to create jti_cache table: %s", errMsg);
            sqlite3_free(errMsg);
            sqlite3_close(_db);
            return nil;
        }

        // Setup periodic cleanup via dispatch_source on database queue
        // (replaces NSTimer on main run loop to avoid thread hops)
        _cleanupTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _databaseQueue);
        if (_cleanupTimer) {
            dispatch_source_set_timer(_cleanupTimer,
                                      dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC),
                                      300 * NSEC_PER_SEC,
                                      0);
            __weak typeof(self) weakSelf = self;
            dispatch_source_set_event_handler(_cleanupTimer, ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf cleanup];
                }
            });
            dispatch_resume(_cleanupTimer);
        }
    }
    return self;
}

- (void)invalidate {
    if (_cleanupTimer) {
        dispatch_source_cancel(_cleanupTimer);
        _cleanupTimer = nil;
    }
    dispatch_sync(_databaseQueue, ^{
        if (_db) {
            sqlite3_close(_db);
            _db = NULL;
        }
    });
}

- (void)dealloc {
    [self invalidate];
}

- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration {
    if (!jti || !expiration) return NO;

    NSTimeInterval expiresAt = [expiration timeIntervalSince1970];
    __block BOOL result = NO;

    dispatch_sync(_databaseQueue, ^{
        if (!_db) {
            return;
        }

        // Use BEGIN IMMEDIATE to keep check-and-insert atomic. Access to the
        // single SQLite connection is serialized to avoid nested transactions.
        if (sqlite3_exec(_db, "BEGIN IMMEDIATE TRANSACTION;", NULL, NULL, NULL) != SQLITE_OK) {
            GZ_LOG_AUTH_ERROR(@"Replay cache: failed to begin transaction: %s", sqlite3_errmsg(_db));
            return;
        }

        // Check if a non-expired entry exists
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        BOOL replayDetected = NO;

        const char *selectSQL = "SELECT expires_at FROM jti_cache WHERE jti = ?";
        sqlite3_stmt *selectStmt = NULL;
        if (sqlite3_prepare_v2(_db, selectSQL, -1, &selectStmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(selectStmt, 1, jti.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(selectStmt) == SQLITE_ROW) {
                double existingExpiry = sqlite3_column_double(selectStmt, 0);
                if (existingExpiry >= now) {
                    replayDetected = YES;
                }
            }
        }
        sqlite3_finalize(selectStmt);

        if (replayDetected) {
            sqlite3_exec(_db, "COMMIT;", NULL, NULL, NULL);
            return;
        }

        // Insert or replace (new or expired entry)
        const char *insertSQL = "INSERT OR REPLACE INTO jti_cache (jti, expires_at) VALUES (?, ?)";
        sqlite3_stmt *insertStmt = NULL;
        BOOL insertSucceeded = NO;
        if (sqlite3_prepare_v2(_db, insertSQL, -1, &insertStmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(insertStmt, 1, jti.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_double(insertStmt, 2, expiresAt);
            if (sqlite3_step(insertStmt) == SQLITE_DONE) {
                insertSucceeded = YES;
            }
        }
        sqlite3_finalize(insertStmt);

        if (sqlite3_exec(_db, "COMMIT;", NULL, NULL, NULL) != SQLITE_OK) {
            GZ_LOG_AUTH_ERROR(@"Replay cache: failed to commit transaction: %s", sqlite3_errmsg(_db));
            return;
        }

        result = insertSucceeded;
    });

    return result;
}

- (void)cleanup {
    dispatch_sync(_databaseQueue, ^{
        if (!_db) {
            return;
        }
        const char *deleteSQL = "DELETE FROM jti_cache WHERE expires_at < ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, deleteSQL, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_double(stmt, 1, [[NSDate date] timeIntervalSince1970]);
            sqlite3_step(stmt);
        }
        sqlite3_finalize(stmt);
    });
}

@end
