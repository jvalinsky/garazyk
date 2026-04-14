/*!
 @file AppViewDatabase.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppViewServer/AppViewDatabase.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"

#import <sqlite3.h>

NSString * const AppViewDatabaseErrorDomain = @"AppViewDatabaseErrorDomain";

// ---------------------------------------------------------------------------
// Schema SQL
// ---------------------------------------------------------------------------

static NSString * const kSchemaV1 = @""
"CREATE TABLE IF NOT EXISTS appview_schema_version ("
"  version INTEGER NOT NULL"
");"

"CREATE TABLE IF NOT EXISTS appview_checkpoints ("
"  relay_url  TEXT NOT NULL PRIMARY KEY,"
"  seq        INTEGER NOT NULL,"
"  saved_at   TEXT NOT NULL"
");"

"CREATE TABLE IF NOT EXISTS appview_repo_sync_state ("
"  did              TEXT NOT NULL PRIMARY KEY,"
"  status           INTEGER NOT NULL DEFAULT 0,"  // AppViewRepoSyncStatusPending
"  last_rev         TEXT,"
"  last_backfill_at TEXT,"
"  error_count      INTEGER NOT NULL DEFAULT 0,"
"  last_error       TEXT"
");"

"CREATE TABLE IF NOT EXISTS appview_pending_deltas ("
"  id           INTEGER PRIMARY KEY AUTOINCREMENT,"
"  did          TEXT NOT NULL,"
"  seq          INTEGER NOT NULL,"
"  commit_cid   TEXT NOT NULL,"
"  rev          TEXT NOT NULL,"
"  raw_envelope BLOB NOT NULL,"
"  enqueued_at  TEXT NOT NULL,"
"  UNIQUE(did, seq)"
");"
"CREATE INDEX IF NOT EXISTS idx_pending_deltas_did ON appview_pending_deltas(did);"
"CREATE INDEX IF NOT EXISTS idx_pending_deltas_seq ON appview_pending_deltas(seq);"

"CREATE TABLE IF NOT EXISTS appview_event_log ("
"  id          INTEGER PRIMARY KEY AUTOINCREMENT,"
"  seq         INTEGER NOT NULL,"
"  did         TEXT,"
"  rev         TEXT,"
"  cid         TEXT,"
"  raw_envelope BLOB NOT NULL,"
"  created_at  TEXT NOT NULL"
");"
"CREATE UNIQUE INDEX IF NOT EXISTS idx_event_log_dedup ON appview_event_log(did, rev, cid);"
"CREATE INDEX IF NOT EXISTS idx_event_log_seq ON appview_event_log(seq);"
"CREATE INDEX IF NOT EXISTS idx_event_log_created ON appview_event_log(created_at);"

"CREATE TABLE IF NOT EXISTS appview_relevance ("
"  did        TEXT NOT NULL PRIMARY KEY,"
"  reason     INTEGER NOT NULL,"
"  expires_at TEXT,"
"  added_at   TEXT NOT NULL"
");"
"CREATE INDEX IF NOT EXISTS idx_relevance_expires ON appview_relevance(expires_at);"

"CREATE TABLE IF NOT EXISTS appview_dead_letter ("
"  id               INTEGER PRIMARY KEY AUTOINCREMENT,"
"  collection       TEXT NOT NULL,"
"  seq              INTEGER NOT NULL,"
"  did              TEXT NOT NULL,"
"  rev              TEXT,"
"  cid              TEXT,"
"  raw_record       BLOB NOT NULL,"
"  validation_error TEXT NOT NULL,"
"  created_at       TEXT NOT NULL"
");"
"CREATE INDEX IF NOT EXISTS idx_dead_letter_did ON appview_dead_letter(did);"
"CREATE INDEX IF NOT EXISTS idx_dead_letter_created ON appview_dead_letter(created_at);"
;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static NSString *iso8601Now(void) {
    NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
    fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                        NSISO8601DateFormatWithFractionalSeconds;
    return [fmt stringFromDate:[NSDate date]];
}

static NSDate * _Nullable iso8601Parse(NSString * _Nullable str) {
    if (!str) return nil;
    NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
    fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                        NSISO8601DateFormatWithFractionalSeconds;
    NSDate *d = [fmt dateFromString:str];
    if (!d) {
        fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        d = [fmt dateFromString:str];
    }
    return d;
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation AppViewDatabase {
    sqlite3 *_db;
    dispatch_queue_t _queue;
    NSMutableSet<NSString *> *_relevanceCache; // in-memory set for fast isDIDRelevant
}

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (!self) return nil;

    _queue = dispatch_queue_create("dev.garazyk.appview.db", DISPATCH_QUEUE_SERIAL);
    _relevanceCache = [NSMutableSet set];

    int rc = sqlite3_open_v2(path.UTF8String, &_db,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                             NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain
                                         code:rc
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
        }
        sqlite3_close(_db);
        _db = NULL;
        return nil;
    }

    // WAL for concurrent reads
    sqlite3_exec(_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
    sqlite3_exec(_db, "PRAGMA synchronous=NORMAL;", NULL, NULL, NULL);
    sqlite3_exec(_db, "PRAGMA foreign_keys=ON;", NULL, NULL, NULL);
    sqlite3_exec(_db, "PRAGMA busy_timeout=5000;", NULL, NULL, NULL);

    return self;
}

- (nullable instancetype)initInMemoryWithError:(NSError **)error {
    return [self initWithPath:@":memory:" error:error];
}

- (void)dealloc {
    [self close];
}

- (void)close {
    dispatch_sync(_queue, ^{
        if (self->_db) {
            sqlite3_close(self->_db);
            self->_db = NULL;
        }
    });
}

// ---------------------------------------------------------------------------
// Migrations
// ---------------------------------------------------------------------------

- (BOOL)runMigrations:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        char *errmsg = NULL;
        int rc = sqlite3_exec(self->_db, kSchemaV1.UTF8String, NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        errmsg ? [NSString stringWithUTF8String:errmsg]
                                                               : @"Migration failed"}];
            if (errmsg) sqlite3_free(errmsg);
            ok = NO;
            return;
        }

        // Populate in-memory relevance cache
        const char *sql = "SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > datetime('now')";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *did = (const char *)sqlite3_column_text(stmt, 0);
                if (did) {
                    [self->_relevanceCache addObject:[NSString stringWithUTF8String:did]];
                }
            }
            sqlite3_finalize(stmt);
        }
    });

    if (!ok && error) *error = innerError;
    return ok;
}

// ---------------------------------------------------------------------------
// Checkpoint
// ---------------------------------------------------------------------------

- (BOOL)saveCheckpoint:(AppViewCheckpoint *)checkpoint error:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        const char *sql =
            "INSERT OR REPLACE INTO appview_checkpoints(relay_url, seq, saved_at) VALUES(?,?,?)";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, checkpoint.relayURL.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, checkpoint.seq);
            sqlite3_bind_text(stmt, 3, now.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
        if (rc != SQLITE_DONE && rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to save checkpoint"}];
            ok = NO;
        }
    });

    if (!ok && error) *error = innerError;
    return ok;
}

- (nullable AppViewCheckpoint *)loadCheckpointForRelayURL:(NSString *)relayURL
                                                    error:(NSError **)error {
    __block AppViewCheckpoint *result = nil;

    dispatch_sync(_queue, ^{
        const char *sql = "SELECT seq, saved_at FROM appview_checkpoints WHERE relay_url = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, relayURL.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                int64_t seq = sqlite3_column_int64(stmt, 0);
                result = [[AppViewCheckpoint alloc] initWithRelayURL:relayURL seq:seq];
                const char *savedAt = (const char *)sqlite3_column_text(stmt, 1);
                if (savedAt) result.savedAt = iso8601Parse([NSString stringWithUTF8String:savedAt]);
            }
            sqlite3_finalize(stmt);
        }
    });

    return result;
}

// ---------------------------------------------------------------------------
// Repo Sync State
// ---------------------------------------------------------------------------

- (BOOL)upsertRepoSyncState:(AppViewRepoSyncState *)state error:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        const char *sql =
            "INSERT INTO appview_repo_sync_state(did, status, last_rev, last_backfill_at, error_count, last_error)"
            " VALUES(?,?,?,?,?,?)"
            " ON CONFLICT(did) DO UPDATE SET"
            "   status = excluded.status,"
            "   last_rev = excluded.last_rev,"
            "   last_backfill_at = excluded.last_backfill_at,"
            "   error_count = excluded.error_count,"
            "   last_error = excluded.last_error";
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, state.did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt,  2, (int)state.status);
            if (state.lastRev)
                sqlite3_bind_text(stmt, 3, state.lastRev.UTF8String, -1, SQLITE_TRANSIENT);
            else
                sqlite3_bind_null(stmt, 3);
            if (state.lastBackfillAt) {
                NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
                fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
                sqlite3_bind_text(stmt, 4, [fmt stringFromDate:state.lastBackfillAt].UTF8String, -1, SQLITE_TRANSIENT);
            } else {
                sqlite3_bind_null(stmt, 4);
            }
            sqlite3_bind_int64(stmt, 5, state.errorCount);
            if (state.lastError)
                sqlite3_bind_text(stmt, 6, state.lastError.UTF8String, -1, SQLITE_TRANSIENT);
            else
                sqlite3_bind_null(stmt, 6);
            rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
        if (rc != SQLITE_DONE && rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to upsert repo sync state"}];
            ok = NO;
        }
    });

    if (!ok && error) *error = innerError;
    return ok;
}

- (nullable AppViewRepoSyncState *)loadRepoSyncStateForDID:(NSString *)did
                                                     error:(NSError **)error {
    __block AppViewRepoSyncState *result = nil;

    dispatch_sync(_queue, ^{
        const char *sql =
            "SELECT status, last_rev, last_backfill_at, error_count, last_error"
            " FROM appview_repo_sync_state WHERE did = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                result = [[AppViewRepoSyncState alloc] initWithDID:did];
                result.status     = (AppViewRepoSyncStatus)sqlite3_column_int(stmt, 0);
                const char *rev   = (const char *)sqlite3_column_text(stmt, 1);
                if (rev) result.lastRev = [NSString stringWithUTF8String:rev];
                const char *bfAt  = (const char *)sqlite3_column_text(stmt, 2);
                if (bfAt) result.lastBackfillAt = iso8601Parse([NSString stringWithUTF8String:bfAt]);
                result.errorCount = sqlite3_column_int64(stmt, 3);
                const char *err   = (const char *)sqlite3_column_text(stmt, 4);
                if (err) result.lastError = [NSString stringWithUTF8String:err];
            }
            sqlite3_finalize(stmt);
        }
    });

    return result;
}

- (nullable NSArray<AppViewRepoSyncState *> *)loadRepoSyncStatesWithStatus:(AppViewRepoSyncStatus)status
                                                                     limit:(NSInteger)limit
                                                                     error:(NSError **)error {
    __block NSMutableArray<AppViewRepoSyncState *> *results = [NSMutableArray array];

    dispatch_sync(_queue, ^{
        const char *sql =
            "SELECT did, last_rev, last_backfill_at, error_count, last_error"
            " FROM appview_repo_sync_state"
            " WHERE status = ?"
            " ORDER BY error_count ASC, last_backfill_at ASC NULLS FIRST"
            " LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(stmt,  1, (int)status);
            sqlite3_bind_int64(stmt, 2, limit);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *did = (const char *)sqlite3_column_text(stmt, 0);
                AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc]
                    initWithDID:[NSString stringWithUTF8String:did]];
                s.status = status;
                const char *rev = (const char *)sqlite3_column_text(stmt, 1);
                if (rev) s.lastRev = [NSString stringWithUTF8String:rev];
                const char *bfAt = (const char *)sqlite3_column_text(stmt, 2);
                if (bfAt) s.lastBackfillAt = iso8601Parse([NSString stringWithUTF8String:bfAt]);
                s.errorCount = sqlite3_column_int64(stmt, 3);
                const char *err = (const char *)sqlite3_column_text(stmt, 4);
                if (err) s.lastError = [NSString stringWithUTF8String:err];
                [results addObject:s];
            }
            sqlite3_finalize(stmt);
        }
    });

    return [results copy];
}

- (NSInteger)countRepoSyncStatesWithStatus:(AppViewRepoSyncStatus)status error:(NSError **)error {
    __block NSInteger count = 0;

    dispatch_sync(_queue, ^{
        const char *sql = "SELECT COUNT(*) FROM appview_repo_sync_state WHERE status = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, (int)status);
            if (sqlite3_step(stmt) == SQLITE_ROW)
                count = sqlite3_column_int64(stmt, 0);
            sqlite3_finalize(stmt);
        }
    });

    return count;
}

- (nullable NSArray<NSString *> *)markReposAsProcessing:(NSArray<NSString *> *)dids
                                                  error:(NSError **)error {
    if (dids.count == 0) return @[];

    __block NSMutableArray<NSString *> *transitioned = [NSMutableArray array];
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        // Use a transaction to atomically CAS pending → processing
        sqlite3_exec(self->_db, "BEGIN IMMEDIATE", NULL, NULL, NULL);

        for (NSString *did in dids) {
            const char *sql =
                "UPDATE appview_repo_sync_state SET status = ? WHERE did = ? AND status = ?";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int(stmt,  1, (int)AppViewRepoSyncStatusProcessing);
                sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt,  3, (int)AppViewRepoSyncStatusPending);
                sqlite3_step(stmt);
                int changes = sqlite3_changes(self->_db);
                sqlite3_finalize(stmt);
                if (changes > 0) [transitioned addObject:did];
            }
        }

        sqlite3_exec(self->_db, "COMMIT", NULL, NULL, NULL);
    });

    if (innerError && error) *error = innerError;
    return [transitioned copy];
}

- (BOOL)markRepoSynced:(NSString *)did lastRev:(NSString *)lastRev error:(NSError **)error {
    __block BOOL ok = YES;
    dispatch_sync(_queue, ^{
        const char *sql =
            "UPDATE appview_repo_sync_state"
            " SET status = ?, last_rev = ?, last_backfill_at = ?, error_count = 0, last_error = NULL"
            " WHERE did = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_int(stmt,  1, (int)AppViewRepoSyncStatusSynced);
            sqlite3_bind_text(stmt, 2, lastRev.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 3, now.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, did.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) ok = NO;
        }
    });
    return ok;
}

- (BOOL)markRepoDirty:(NSString *)did error:(NSError **)error {
    __block BOOL ok = YES;
    dispatch_sync(_queue, ^{
        const char *sql =
            "UPDATE appview_repo_sync_state SET status = ? WHERE did = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(stmt,  1, (int)AppViewRepoSyncStatusDirty);
            sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) ok = NO;
        }
    });
    return ok;
}

- (BOOL)recordBackfillError:(NSString *)did message:(NSString *)message error:(NSError **)error {
    __block BOOL ok = YES;
    dispatch_sync(_queue, ^{
        const char *sql =
            "UPDATE appview_repo_sync_state"
            " SET error_count = error_count + 1, last_error = ?"
            " WHERE did = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, message.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) ok = NO;
        }
    });
    return ok;
}

// ---------------------------------------------------------------------------
// Pending Deltas
// ---------------------------------------------------------------------------

- (BOOL)enqueuePendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error {
    __block BOOL ok = YES;
    dispatch_sync(_queue, ^{
        const char *sql =
            "INSERT OR IGNORE INTO appview_pending_deltas"
            "(did, seq, commit_cid, rev, raw_envelope, enqueued_at)"
            " VALUES(?,?,?,?,?,?)";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, delta.did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, delta.seq);
            sqlite3_bind_text(stmt, 3, delta.commitCID.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, delta.rev.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_blob(stmt, 5, delta.rawEnvelope.bytes, (int)delta.rawEnvelope.length, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 6, now.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) ok = NO;
        }
    });
    return ok;
}

- (nullable NSArray<AppViewPendingDelta *> *)dequeuePendingDeltasForDID:(NSString *)did
                                                                  error:(NSError **)error {
    __block NSMutableArray<AppViewPendingDelta *> *results = [NSMutableArray array];

    dispatch_sync(_queue, ^{
        sqlite3_exec(self->_db, "BEGIN IMMEDIATE", NULL, NULL, NULL);

        const char *selectSQL =
            "SELECT seq, commit_cid, rev, raw_envelope FROM appview_pending_deltas"
            " WHERE did = ? ORDER BY seq ASC";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, selectSQL, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                int64_t seq        = sqlite3_column_int64(stmt, 0);
                const char *cidStr = (const char *)sqlite3_column_text(stmt, 1);
                const char *revStr = (const char *)sqlite3_column_text(stmt, 2);
                const void *blob   = sqlite3_column_blob(stmt, 3);
                int blobLen        = sqlite3_column_bytes(stmt, 3);
                NSData *envelope   = [NSData dataWithBytes:blob length:blobLen];
                AppViewPendingDelta *d = [[AppViewPendingDelta alloc]
                    initWithDID:did
                            seq:seq
                      commitCID:[NSString stringWithUTF8String:cidStr ?: ""]
                            rev:[NSString stringWithUTF8String:revStr ?: ""]
                    rawEnvelope:envelope];
                [results addObject:d];
            }
            sqlite3_finalize(stmt);
        }

        // Delete them
        const char *deleteSQL = "DELETE FROM appview_pending_deltas WHERE did = ?";
        sqlite3_stmt *delStmt = NULL;
        if (sqlite3_prepare_v2(self->_db, deleteSQL, -1, &delStmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(delStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_step(delStmt);
            sqlite3_finalize(delStmt);
        }

        sqlite3_exec(self->_db, "COMMIT", NULL, NULL, NULL);
    });

    return [results copy];
}

- (NSInteger)countPendingDeltasForDID:(NSString *)did error:(NSError **)error {
    __block NSInteger count = 0;
    dispatch_sync(_queue, ^{
        const char *sql = "SELECT COUNT(*) FROM appview_pending_deltas WHERE did = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) count = sqlite3_column_int64(stmt, 0);
            sqlite3_finalize(stmt);
        }
    });
    return count;
}

// ---------------------------------------------------------------------------
// Event Log
// ---------------------------------------------------------------------------

- (BOOL)logEvent:(int64_t)seq
              did:(nullable NSString *)did
              rev:(nullable NSString *)rev
              cid:(nullable NSString *)cid
      rawEnvelope:(NSData *)rawEnvelope
            error:(NSError **)error {
    __block BOOL ok = YES;
    dispatch_sync(_queue, ^{
        const char *sql =
            "INSERT OR IGNORE INTO appview_event_log(seq, did, rev, cid, raw_envelope, created_at)"
            " VALUES(?,?,?,?,?,?)";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_int64(stmt, 1, seq);
            if (did)  sqlite3_bind_text(stmt, 2, did.UTF8String,  -1, SQLITE_TRANSIENT);
            else      sqlite3_bind_null(stmt, 2);
            if (rev)  sqlite3_bind_text(stmt, 3, rev.UTF8String,  -1, SQLITE_TRANSIENT);
            else      sqlite3_bind_null(stmt, 3);
            if (cid)  sqlite3_bind_text(stmt, 4, cid.UTF8String,  -1, SQLITE_TRANSIENT);
            else      sqlite3_bind_null(stmt, 4);
            sqlite3_bind_blob(stmt, 5, rawEnvelope.bytes, (int)rawEnvelope.length, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 6, now.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) ok = NO;
        }
    });
    return ok;
}

- (BOOL)hasEventWithDID:(nullable NSString *)did
                    rev:(nullable NSString *)rev
                    cid:(nullable NSString *)cid {
    __block BOOL found = NO;
    dispatch_sync(_queue, ^{
        const char *sql =
            "SELECT 1 FROM appview_event_log WHERE did IS ? AND rev IS ? AND cid IS ? LIMIT 1";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            if (did) sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 1);
            if (rev) sqlite3_bind_text(stmt, 2, rev.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 2);
            if (cid) sqlite3_bind_text(stmt, 3, cid.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 3);
            found = (sqlite3_step(stmt) == SQLITE_ROW);
            sqlite3_finalize(stmt);
        }
    });
    return found;
}

- (NSInteger)pruneEventLogOlderThan:(NSDate *)cutoff error:(NSError **)error {
    __block NSInteger deleted = 0;
    dispatch_sync(_queue, ^{
        NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
        fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        NSString *cutoffStr = [fmt stringFromDate:cutoff];

        const char *sql = "DELETE FROM appview_event_log WHERE created_at < ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, cutoffStr.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_step(stmt);
            deleted = sqlite3_changes(self->_db);
            sqlite3_finalize(stmt);
        }
    });
    return deleted;
}

// ---------------------------------------------------------------------------
// Relevance Set
// ---------------------------------------------------------------------------

- (BOOL)upsertRelevanceMembership:(AppViewRelevanceMembership *)membership
                            error:(NSError **)error {
    __block BOOL ok = YES;
    dispatch_sync(_queue, ^{
        const char *sql =
            "INSERT INTO appview_relevance(did, reason, expires_at, added_at)"
            " VALUES(?,?,?,?)"
            " ON CONFLICT(did) DO UPDATE SET"
            "   reason = excluded.reason,"
            "   expires_at = excluded.expires_at,"
            "   added_at = excluded.added_at";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
            fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;

            sqlite3_bind_text(stmt, 1, membership.did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt,  2, (int)membership.reason);
            if (membership.expiresAt)
                sqlite3_bind_text(stmt, 3, [fmt stringFromDate:membership.expiresAt].UTF8String, -1, SQLITE_TRANSIENT);
            else
                sqlite3_bind_null(stmt, 3);
            sqlite3_bind_text(stmt, 4, iso8601Now().UTF8String, -1, SQLITE_TRANSIENT);

            int rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) { ok = NO; return; }
        }
        // Update cache
        if (membership.isValid)
            [self->_relevanceCache addObject:membership.did];
        else
            [self->_relevanceCache removeObject:membership.did];
    });
    return ok;
}

- (nullable AppViewRelevanceMembership *)loadRelevanceMembershipForDID:(NSString *)did
                                                                 error:(NSError **)error {
    __block AppViewRelevanceMembership *result = nil;
    dispatch_sync(_queue, ^{
        const char *sql = "SELECT reason, expires_at, added_at FROM appview_relevance WHERE did = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                AppViewRelevanceReason reason = (AppViewRelevanceReason)sqlite3_column_int(stmt, 0);
                const char *expiresStr = (const char *)sqlite3_column_text(stmt, 1);
                NSDate *expires = expiresStr ? iso8601Parse([NSString stringWithUTF8String:expiresStr]) : nil;
                result = [[AppViewRelevanceMembership alloc] initWithDID:did reason:reason expiresAt:expires];
                const char *addedStr = (const char *)sqlite3_column_text(stmt, 2);
                if (addedStr) result.addedAt = iso8601Parse([NSString stringWithUTF8String:addedStr]);
            }
            sqlite3_finalize(stmt);
        }
    });
    return result;
}

- (BOOL)isDIDRelevant:(NSString *)did {
    __block BOOL relevant = NO;
    dispatch_sync(_queue, ^{
        relevant = [self->_relevanceCache containsObject:did];
    });
    return relevant;
}

- (NSInteger)pruneExpiredRelevanceMemberships:(NSError **)error {
    __block NSInteger deleted = 0;
    dispatch_sync(_queue, ^{
        const char *sql =
            "DELETE FROM appview_relevance WHERE expires_at IS NOT NULL AND expires_at <= datetime('now')";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_step(stmt);
            deleted = sqlite3_changes(self->_db);
            sqlite3_finalize(stmt);
        }
        // Rebuild cache
        [self->_relevanceCache removeAllObjects];
        const char *sel =
            "SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > datetime('now')";
        sqlite3_stmt *sel_stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sel, -1, &sel_stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(sel_stmt) == SQLITE_ROW) {
                const char *did = (const char *)sqlite3_column_text(sel_stmt, 0);
                if (did) [self->_relevanceCache addObject:[NSString stringWithUTF8String:did]];
            }
            sqlite3_finalize(sel_stmt);
        }
    });
    return deleted;
}

- (nullable NSArray<NSString *> *)loadAllRelevantDIDs:(NSError **)error {
    __block NSMutableArray<NSString *> *results = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        const char *sql =
            "SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > datetime('now')";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *did = (const char *)sqlite3_column_text(stmt, 0);
                if (did) [results addObject:[NSString stringWithUTF8String:did]];
            }
            sqlite3_finalize(stmt);
        }
    });
    return [results copy];
}

// ---------------------------------------------------------------------------
// Dead-Letter
// ---------------------------------------------------------------------------

- (BOOL)recordDeadLetterEvent:(NSString *)collection
                          seq:(int64_t)seq
                          did:(NSString *)did
                          rev:(nullable NSString *)rev
                          cid:(nullable NSString *)cid
                    rawRecord:(NSData *)rawRecord
              validationError:(NSString *)validationError
                        error:(NSError **)error {
    __block BOOL ok = YES;
    dispatch_sync(_queue, ^{
        const char *sql =
            "INSERT INTO appview_dead_letter(collection, seq, did, rev, cid, raw_record, validation_error, created_at)"
            " VALUES(?,?,?,?,?,?,?,?)";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, collection.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, seq);
            sqlite3_bind_text(stmt, 3, did.UTF8String, -1, SQLITE_TRANSIENT);
            if (rev) sqlite3_bind_text(stmt, 4, rev.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 4);
            if (cid) sqlite3_bind_text(stmt, 5, cid.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 5);
            sqlite3_bind_blob(stmt, 6, rawRecord.bytes, (int)rawRecord.length, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 7, validationError.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 8, now.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            if (rc != SQLITE_DONE) ok = NO;
        }
    });
    return ok;
}

@end
