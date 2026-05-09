/*!
 @file AppViewDatabase.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/AppViewDatabase.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"
#import "Core/NSDateFormatter+ATProto.h"

#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"

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

"CREATE TABLE IF NOT EXISTS appview_cursor_events ("
"  cursor      INTEGER PRIMARY KEY AUTOINCREMENT,"
"  event_type  TEXT NOT NULL,"
"  seq         INTEGER NOT NULL,"
"  did         TEXT,"
"  rev         TEXT,"
"  cid         TEXT,"
"  raw_envelope BLOB NOT NULL,"
"  created_at  TEXT NOT NULL"
");"
"CREATE UNIQUE INDEX IF NOT EXISTS idx_cursor_events_dedup ON appview_cursor_events(did, rev, cid, event_type);"
"CREATE INDEX IF NOT EXISTS idx_cursor_events_seq ON appview_cursor_events(seq);"

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

"CREATE TABLE IF NOT EXISTS dead_letter_hooks ("
"  id INTEGER PRIMARY KEY AUTOINCREMENT,"
"  hook_id TEXT NOT NULL,"
"  uri TEXT NOT NULL,"
"  did TEXT NOT NULL,"
"  collection TEXT NOT NULL,"
"  event_type TEXT NOT NULL,"
"  error_message TEXT,"
"  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))"
");"
"CREATE INDEX IF NOT EXISTS idx_dead_letter_hooks_hook_id ON dead_letter_hooks(hook_id);"
"CREATE INDEX IF NOT EXISTS idx_dead_letter_hooks_created ON dead_letter_hooks(created_at);"

// ATProto Record/Block Materialization
"CREATE TABLE IF NOT EXISTS records ("
"  uri TEXT PRIMARY KEY,"
"  did TEXT NOT NULL,"
"  collection TEXT NOT NULL,"
"  rkey TEXT NOT NULL,"
"  cid TEXT NOT NULL,"
"  handle TEXT,"
"  value TEXT,"
"  subject_did TEXT,"
"  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
"  indexed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))"
");"
"CREATE INDEX IF NOT EXISTS idx_records_did_collection ON records(did, collection);"
"CREATE INDEX IF NOT EXISTS idx_records_did_collection_rkey ON records(did, collection, rkey);"
"CREATE INDEX IF NOT EXISTS idx_records_subject_did ON records(subject_did);"
"CREATE INDEX IF NOT EXISTS idx_records_subject_did_collection ON records(subject_did, collection);"

"CREATE TABLE IF NOT EXISTS blocks ("
"  cid BLOB PRIMARY KEY,"
"  repo_did TEXT NOT NULL,"
"  block_data BLOB,"
"  content_type TEXT,"
"  size INTEGER,"
"  created_at TEXT NOT NULL"
");"
"CREATE INDEX IF NOT EXISTS idx_blocks_repo_did ON blocks(repo_did);"

"CREATE TABLE IF NOT EXISTS handles ("
"  handle TEXT PRIMARY KEY,"
"  did    TEXT NOT NULL"
");"
"CREATE INDEX IF NOT EXISTS idx_handles_did ON handles(did);"

// BSky AppView Tables migrated from PDS
"CREATE TABLE IF NOT EXISTS bsky_feed_threadgates ("
"    post_uri TEXT PRIMARY KEY,"
"    allow_json TEXT,"
"    created_at INTEGER,"
"    updated_at INTEGER"
");"

"CREATE TABLE IF NOT EXISTS bsky_feed_postgates ("
"    post_uri TEXT PRIMARY KEY,"
"    embedding_rules_json TEXT,"
"    created_at INTEGER,"
"    updated_at INTEGER"
");"

"CREATE TABLE IF NOT EXISTS bsky_feed_generators ("
"    uri TEXT PRIMARY KEY,"
"    did TEXT NOT NULL,"
"    display_name TEXT,"
"    description TEXT,"
"    avatar_cid TEXT,"
"    created_at INTEGER,"
"    updated_at INTEGER"
");"

"CREATE TABLE IF NOT EXISTS bsky_labeler_services ("
"    did TEXT PRIMARY KEY,"
"    labeler_did TEXT NOT NULL,"
"    created_at INTEGER,"
"    updated_at INTEGER"
");"

"CREATE TABLE IF NOT EXISTS bsky_graph_lists ("
"    uri TEXT PRIMARY KEY,"
"    did TEXT NOT NULL,"
"    name TEXT NOT NULL,"
"    purpose TEXT NOT NULL,"
"    description TEXT,"
"    avatar_cid TEXT,"
"    created_at INTEGER,"
"    updated_at INTEGER"
");"

"CREATE TABLE IF NOT EXISTS bsky_graph_listitems ("
"    uri TEXT PRIMARY KEY,"
"    list_uri TEXT NOT NULL,"
"    subject_did TEXT NOT NULL,"
"    created_at INTEGER,"
"    FOREIGN KEY (list_uri) REFERENCES bsky_graph_lists(uri) ON DELETE CASCADE"
");"

"CREATE TABLE IF NOT EXISTS bookmarks ("
"    uri TEXT NOT NULL,"
"    actor_did TEXT NOT NULL,"
"    created_at INTEGER,"
"    PRIMARY KEY (uri, actor_did)"
");"

"CREATE TABLE IF NOT EXISTS starter_packs ("
"    uri TEXT PRIMARY KEY,"
"    did TEXT NOT NULL,"
"    name TEXT NOT NULL,"
"    description TEXT,"
"    list_uri TEXT,"
"    created_at INTEGER,"
"    updated_at INTEGER"
");"

"CREATE TABLE IF NOT EXISTS groups ("
"    id TEXT PRIMARY KEY,"
"    did TEXT NOT NULL,"
"    name TEXT NOT NULL,"
"    description TEXT,"
"    created_at INTEGER,"
"    updated_at INTEGER"
");"

"CREATE TABLE IF NOT EXISTS group_members ("
"    group_id TEXT NOT NULL,"
"    member_did TEXT NOT NULL,"
"    role TEXT NOT NULL DEFAULT 'member',"
"    joined_at INTEGER,"
"    PRIMARY KEY (group_id, member_did),"
"    FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE"
");"

"CREATE TABLE IF NOT EXISTS accounts ("
"  did        TEXT PRIMARY KEY,"
"  handle     TEXT,"
"  email      TEXT,"
"  created_at TEXT"
");"

"CREATE TABLE IF NOT EXISTS labels ("
"  src        TEXT NOT NULL,"
"  uri        TEXT NOT NULL,"
"  cid        TEXT,"
"  val        TEXT NOT NULL,"
"  neg        INTEGER DEFAULT 0,"
"  created_at TEXT NOT NULL"
");"
"CREATE INDEX IF NOT EXISTS idx_labels_uri ON labels(uri);"

"CREATE TABLE IF NOT EXISTS drafts ("
"  id         TEXT PRIMARY KEY,"
"  did        TEXT NOT NULL,"
"  content    TEXT,"
"  created_at INTEGER,"
"  updated_at INTEGER"
");"
"CREATE INDEX IF NOT EXISTS idx_drafts_did ON drafts(did);"

"CREATE TABLE IF NOT EXISTS phone_verifications ("
"  id         TEXT PRIMARY KEY,"
"  phone      TEXT NOT NULL,"
"  code       TEXT NOT NULL,"
"  did        TEXT NOT NULL,"
"  created_at TEXT,"
"  expires_at TEXT"
");"

"CREATE TABLE IF NOT EXISTS contact_tokens ("
"  token      TEXT PRIMARY KEY,"
"  did        TEXT NOT NULL,"
"  phone      TEXT NOT NULL,"
"  created_at TEXT"
");"

"CREATE TABLE IF NOT EXISTS contact_hashes ("
"  did        TEXT NOT NULL,"
"  phone_hash TEXT NOT NULL,"
"  imported_at TEXT,"
"  UNIQUE(did, phone_hash)"
");"

"CREATE TABLE IF NOT EXISTS contact_sync_status ("
"  did           TEXT PRIMARY KEY,"
"  synced_at     TEXT,"
"  matches_count INTEGER"
");"

"CREATE TABLE IF NOT EXISTS contact_matches ("
"  did          TEXT NOT NULL,"
"  match_did    TEXT NOT NULL,"
"  dismissed_at TEXT,"
"  PRIMARY KEY (did, match_did)"
");"

"CREATE TABLE IF NOT EXISTS contact_notifications ("
"  from_did   TEXT NOT NULL,"
"  to_did     TEXT NOT NULL,"
"  created_at TEXT"
");"

"CREATE TABLE IF NOT EXISTS notification_preferences ("
"  did         TEXT PRIMARY KEY,"
"  preferences TEXT"
");"
;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static void * const kAppViewDatabaseQueueKey = (void *)&kAppViewDatabaseQueueKey;

static NSString *iso8601Now(void) {
    return [NSDateFormatter atproto_stringFromDate:[NSDate date]];
}

static NSDate * _Nullable iso8601Parse(NSString * _Nullable str) {
    if (!str) return nil;
    return [NSDateFormatter atproto_dateFromString:str];
}

static void bindDataOrZeroBlob(sqlite3_stmt *stmt, int idx, NSData *data) {
    if (data.length > 0) {
        sqlite3_bind_blob(stmt, idx, data.bytes, (int)data.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_zeroblob(stmt, idx, 0);
    }
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation AppViewDatabase {
    sqlite3 *_db;
    dispatch_queue_t _queue;
    NSMutableSet<NSString *> *_relevanceCache; // in-memory set for fast isDIDRelevant
    NSMutableDictionary<NSString *, NSNumber *> *_durableCursorByRelayURL;
}

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (!self) return nil;

    _queue = dispatch_queue_create("dev.garazyk.appview.db", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_queue, kAppViewDatabaseQueueKey, (void *)kAppViewDatabaseQueueKey, NULL);
    _relevanceCache = [NSMutableSet set];
    _durableCursorByRelayURL = [NSMutableDictionary dictionary];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dbDir = [path stringByDeletingLastPathComponent];
    if (![path isEqualToString:@":memory:"] && dbDir.length > 0 && ![fm fileExistsAtPath:dbDir]) {
        NSError *createError = nil;
        if (![fm createDirectoryAtPath:dbDir withIntermediateDirectories:YES attributes:nil error:&createError]) {
            if (error) {
                *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                       [NSString stringWithFormat:@"Failed to create database directory: %@",
                                                        createError.localizedDescription]}];
            }
            return nil;
        }
    }

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
        sqlite3_close_v2(_db);
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
            sqlite3_close_v2(self->_db);
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

        sqlite3_exec(self->_db,
                     "CREATE TABLE IF NOT EXISTS appview_cursor_events ("
                     "  cursor INTEGER PRIMARY KEY AUTOINCREMENT,"
                     "  event_type TEXT NOT NULL,"
                     "  seq INTEGER NOT NULL,"
                     "  did TEXT,"
                     "  rev TEXT,"
                     "  cid TEXT,"
                     "  raw_envelope BLOB NOT NULL,"
                     "  created_at TEXT NOT NULL"
                     ");"
                     "CREATE UNIQUE INDEX IF NOT EXISTS idx_cursor_events_dedup ON appview_cursor_events(did, rev, cid, event_type);"
                     "CREATE INDEX IF NOT EXISTS idx_cursor_events_seq ON appview_cursor_events(seq);",
                     NULL, NULL, NULL);

        // Populate in-memory relevance cache
        const char *sql = "SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, now.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *did = (const char *)sqlite3_column_text(stmt, 0);
                if (did) {
                    [self->_relevanceCache addObject:[NSString stringWithUTF8String:did]];
                }
            }
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, checkpoint.relayURL.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, checkpoint.seq);
            sqlite3_bind_text(stmt, 3, now.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(stmt);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, relayURL.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                int64_t seq = sqlite3_column_int64(stmt, 0);
                result = [[AppViewCheckpoint alloc] initWithRelayURL:relayURL seq:seq];
                const char *savedAt = (const char *)sqlite3_column_text(stmt, 1);
                if (savedAt) result.savedAt = iso8601Parse([NSString stringWithUTF8String:savedAt]);
            }
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, state.did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt,  2, (int)state.status);
            if (state.lastRev)
                sqlite3_bind_text(stmt, 3, state.lastRev.UTF8String, -1, SQLITE_TRANSIENT);
            else
                sqlite3_bind_null(stmt, 3);
            if (state.lastBackfillAt) {
                NSString *ts = [NSDateFormatter atproto_stringFromDate:state.lastBackfillAt];
                sqlite3_bind_text(stmt, 4, ts.UTF8String, -1, SQLITE_TRANSIENT);
            } else {
                sqlite3_bind_null(stmt, 4);
            }
            sqlite3_bind_int64(stmt, 5, state.errorCount);
            if (state.lastError)
                sqlite3_bind_text(stmt, 6, state.lastError.UTF8String, -1, SQLITE_TRANSIENT);
            else
                sqlite3_bind_null(stmt, 6);
            rc = sqlite3_step(stmt);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
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
        }
    });

    return result;
}

- (nullable AppViewRepoSyncState *)getRepoSyncState:(NSString *)did
                                              error:(NSError **)error {
    return [self loadRepoSyncStateForDID:did error:error];
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
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
        }
    });

    return [results copy];
}

- (BOOL)setRepoSyncState:(AppViewRepoSyncState *)state
                   error:(NSError **)error {
    return [self upsertRepoSyncState:state error:error];
}

- (NSInteger)countRepoSyncStatesWithStatus:(AppViewRepoSyncStatus)status error:(NSError **)error {
    __block NSInteger count = 0;

    dispatch_sync(_queue, ^{
        const char *sql = "SELECT COUNT(*) FROM appview_repo_sync_state WHERE status = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, (int)status);
            if (sqlite3_step(stmt) == SQLITE_ROW)
                count = sqlite3_column_int64(stmt, 0);
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
            PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int(stmt,  1, (int)AppViewRepoSyncStatusProcessing);
                sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt,  3, (int)AppViewRepoSyncStatusPending);
                sqlite3_step(stmt);
                int changes = sqlite3_changes(self->_db);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_int(stmt,  1, (int)AppViewRepoSyncStatusSynced);
            sqlite3_bind_text(stmt, 2, lastRev.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 3, now.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, did.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(stmt,  1, (int)AppViewRepoSyncStatusDirty);
            sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, message.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, delta.did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, delta.seq);
            sqlite3_bind_text(stmt, 3, delta.commitCID.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, delta.rev.UTF8String, -1, SQLITE_TRANSIENT);
            bindDataOrZeroBlob(stmt, 5, delta.rawEnvelope);
            sqlite3_bind_text(stmt, 6, now.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
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
        }

        // Delete them
        const char *deleteSQL = "DELETE FROM appview_pending_deltas WHERE did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *delStmt = NULL;
        if (sqlite3_prepare_v2(self->_db, deleteSQL, -1, &delStmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(delStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_step(delStmt);
        }

        sqlite3_exec(self->_db, "COMMIT", NULL, NULL, NULL);
    });

    return [results copy];
}

- (NSInteger)countPendingDeltasForDID:(NSString *)did error:(NSError **)error {
    __block NSInteger count = 0;
    dispatch_sync(_queue, ^{
        const char *sql = "SELECT COUNT(*) FROM appview_pending_deltas WHERE did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) count = sqlite3_column_int64(stmt, 0);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_int64(stmt, 1, seq);
            if (did)  sqlite3_bind_text(stmt, 2, did.UTF8String,  -1, SQLITE_TRANSIENT);
            else      sqlite3_bind_null(stmt, 2);
            if (rev)  sqlite3_bind_text(stmt, 3, rev.UTF8String,  -1, SQLITE_TRANSIENT);
            else      sqlite3_bind_null(stmt, 3);
            if (cid)  sqlite3_bind_text(stmt, 4, cid.UTF8String,  -1, SQLITE_TRANSIENT);
            else      sqlite3_bind_null(stmt, 4);
            bindDataOrZeroBlob(stmt, 5, rawEnvelope);
            sqlite3_bind_text(stmt, 6, now.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            if (did) sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 1);
            if (rev) sqlite3_bind_text(stmt, 2, rev.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 2);
            if (cid) sqlite3_bind_text(stmt, 3, cid.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 3);
            found = (sqlite3_step(stmt) == SQLITE_ROW);
        }
    });
    return found;
}

- (NSInteger)pruneEventLogOlderThan:(NSDate *)cutoff error:(NSError **)error {
    __block NSInteger deleted = 0;
    dispatch_sync(_queue, ^{
        NSString *cutoffStr = [NSDateFormatter atproto_stringFromDate:cutoff];

        const char *sql = "DELETE FROM appview_event_log WHERE created_at < ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, cutoffStr.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_step(stmt);
            deleted = sqlite3_changes(self->_db);
        }
    });
    return deleted;
}

// ---------------------------------------------------------------------------
// Internal Cursor Event Store
// ---------------------------------------------------------------------------

- (BOOL)appendStoredEventWithType:(NSString *)eventType
                              seq:(int64_t)seq
                              did:(nullable NSString *)did
                              rev:(nullable NSString *)rev
                              cid:(nullable NSString *)cid
                      rawEnvelope:(NSData *)rawEnvelope
                            error:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        const char *sql =
            "INSERT OR IGNORE INTO appview_cursor_events(event_type, seq, did, rev, cid, raw_envelope, created_at)"
            " VALUES(?,?,?,?,?,?,?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, eventType.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, seq);
            if (did) sqlite3_bind_text(stmt, 3, did.UTF8String, -1, SQLITE_TRANSIENT);
            else sqlite3_bind_null(stmt, 3);
            if (rev) sqlite3_bind_text(stmt, 4, rev.UTF8String, -1, SQLITE_TRANSIENT);
            else sqlite3_bind_null(stmt, 4);
            if (cid) sqlite3_bind_text(stmt, 5, cid.UTF8String, -1, SQLITE_TRANSIENT);
            else sqlite3_bind_null(stmt, 5);
            bindDataOrZeroBlob(stmt, 6, rawEnvelope);
            sqlite3_bind_text(stmt, 7, now.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(stmt);
        }
        if (rc != SQLITE_DONE && rc != SQLITE_OK) {
            ok = NO;
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to append stored AppView event"}];
        }
    });

    if (!ok && error) *error = innerError;
    return ok;
}

- (nullable NSArray<NSDictionary *> *)loadStoredEventsAfterCursor:(int64_t)cursor
                                                           limit:(NSInteger)limit
                                                           error:(NSError **)error {
    __block NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        const char *sql =
            "SELECT cursor, event_type, seq, did, rev, cid, raw_envelope, created_at"
            " FROM appview_cursor_events WHERE cursor > ? ORDER BY cursor ASC LIMIT ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare event replay query"}];
            return;
        }
        sqlite3_bind_int64(stmt, 1, cursor);
        sqlite3_bind_int64(stmt, 2, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableDictionary *event = [NSMutableDictionary dictionary];
            event[@"cursor"] = @(sqlite3_column_int64(stmt, 0));
            const char *type = (const char *)sqlite3_column_text(stmt, 1);
            event[@"event_type"] = type ? @(type) : @"";
            event[@"seq"] = @(sqlite3_column_int64(stmt, 2));
            const char *did = (const char *)sqlite3_column_text(stmt, 3);
            if (did) event[@"did"] = @(did);
            const char *rev = (const char *)sqlite3_column_text(stmt, 4);
            if (rev) event[@"rev"] = @(rev);
            const char *cid = (const char *)sqlite3_column_text(stmt, 5);
            if (cid) event[@"cid"] = @(cid);
            const void *blob = sqlite3_column_blob(stmt, 6);
            int blobLen = sqlite3_column_bytes(stmt, 6);
            event[@"raw_envelope"] = blob ? [NSData dataWithBytes:blob length:blobLen] : [NSData data];
            const char *createdAt = (const char *)sqlite3_column_text(stmt, 7);
            if (createdAt) event[@"created_at"] = @(createdAt);
            [events addObject:[event copy]];
        }
    });

    if (innerError && error) *error = innerError;
    return innerError ? nil : [events copy];
}

- (int64_t)durableCursorForRelayURL:(NSString *)relayURL {
    __block int64_t seq = 0;
    dispatch_sync(_queue, ^{
        seq = [self->_durableCursorByRelayURL[relayURL] longLongValue];
    });
    return seq;
}

- (void)markDurableCursor:(int64_t)seq forRelayURL:(NSString *)relayURL {
    dispatch_sync(_queue, ^{
        int64_t current = [self->_durableCursorByRelayURL[relayURL] longLongValue];
        if (seq > current) {
            self->_durableCursorByRelayURL[relayURL] = @(seq);
        }
    });
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, membership.did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt,  2, (int)membership.reason);
            if (membership.expiresAt) {
                NSString *ts = [NSDateFormatter atproto_stringFromDate:membership.expiresAt];
                sqlite3_bind_text(stmt, 3, ts.UTF8String, -1, SQLITE_TRANSIENT);
            } else {
                sqlite3_bind_null(stmt, 3);
            }
            sqlite3_bind_text(stmt, 4, iso8601Now().UTF8String, -1, SQLITE_TRANSIENT);

            int rc = sqlite3_step(stmt);
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
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
        NSString *now = iso8601Now();
        const char *sql =
            "DELETE FROM appview_relevance WHERE expires_at IS NOT NULL AND expires_at <= ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, now.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_step(stmt);
            deleted = sqlite3_changes(self->_db);
        }
        // Rebuild cache
        [self->_relevanceCache removeAllObjects];
        const char *sel =
            "SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *sel_stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sel, -1, &sel_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(sel_stmt, 1, now.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(sel_stmt) == SQLITE_ROW) {
                const char *did = (const char *)sqlite3_column_text(sel_stmt, 0);
                if (did) [self->_relevanceCache addObject:[NSString stringWithUTF8String:did]];
            }
        }
    });
    return deleted;
}

- (nullable NSArray<NSString *> *)loadAllRelevantDIDs:(NSError **)error {
    __block NSMutableArray<NSString *> *results = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        const char *sql =
            "SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, now.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *did = (const char *)sqlite3_column_text(stmt, 0);
                if (did) [results addObject:[NSString stringWithUTF8String:did]];
            }
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stmt, 1, collection.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, seq);
            sqlite3_bind_text(stmt, 3, did.UTF8String, -1, SQLITE_TRANSIENT);
            if (rev) sqlite3_bind_text(stmt, 4, rev.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 4);
            if (cid) sqlite3_bind_text(stmt, 5, cid.UTF8String, -1, SQLITE_TRANSIENT);
            else     sqlite3_bind_null(stmt, 5);
            bindDataOrZeroBlob(stmt, 6, rawRecord);
            sqlite3_bind_text(stmt, 7, validationError.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 8, now.UTF8String, -1, SQLITE_TRANSIENT);
            int rc = sqlite3_step(stmt);
            if (rc != SQLITE_DONE) ok = NO;
        }
    });
    return ok;
}

// ---------------------------------------------------------------------------
// PDSQueryDatabase Implementation
// ---------------------------------------------------------------------------

- (nullable NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                        params:(NSArray *)params
                                                         error:(NSError **)error {
    __block NSMutableArray *results = [NSMutableArray array];
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        if (!self->_db) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"Database not open"}];
            return;
        }

        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(self->_db)]}];
            return;
        }

        [self _bindParams:params toStatement:stmt];

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            int count = sqlite3_column_count(stmt);
            for (int i = 0; i < count; i++) {
                NSString *name = @(sqlite3_column_name(stmt, i));
                id val = [self _valueFromStatement:stmt columnIndex:i];
                if (val) row[name] = val;
            }
            [results addObject:row];
        }
    });

    if (innerError && error) *error = innerError;
    return innerError ? nil : results;
}

- (BOOL)executeParameterizedUpdate:(NSString *)sql
                           params:(NSArray *)params
                            error:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        if (!self->_db) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"Database not open"}];
            ok = NO;
            return;
        }

        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(self->_db)]}];
            ok = NO;
            return;
        }

        [self _bindParams:params toStatement:stmt];

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(self->_db)]}];
            ok = NO;
        }
    });

    if (!ok && error) *error = innerError;
    return ok;
}

- (BOOL)executeRawSQL:(NSString *)sql error:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        char *errmsg = NULL;
        int rc = sqlite3_exec(self->_db, sql.UTF8String, NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                            userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"SQL failed"}];
            if (errmsg) sqlite3_free(errmsg);
            ok = NO;
        }
    });

    if (!ok && error) *error = innerError;
    return ok;
}

- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid
                                      repoDid:(NSString *)repoDid
                                        error:(NSError **)error {
    __block PDSDatabaseBlock *block = nil;
    dispatch_sync(_queue, ^{
        const char *sql = "SELECT cid, repo_did, block_data, content_type, size, created_at FROM blocks WHERE cid = ? AND repo_did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_TRANSIENT);

            if (sqlite3_step(stmt) == SQLITE_ROW) {
                block = [[PDSDatabaseBlock alloc] init];
                const void *cidData = sqlite3_column_blob(stmt, 0);
                int cidLen = sqlite3_column_bytes(stmt, 0);
                block.cid = [NSData dataWithBytes:cidData length:cidLen];
                block.repoDid = @((const char *)sqlite3_column_text(stmt, 1));

                const void *blockData = sqlite3_column_blob(stmt, 2);
                int blockLen = sqlite3_column_bytes(stmt, 2);
                if (blockData) block.blockData = [NSData dataWithBytes:blockData length:blockLen];

                const char *ctype = (const char *)sqlite3_column_text(stmt, 3);
                if (ctype) block.contentType = @(ctype);

                block.size = sqlite3_column_int(stmt, 4);

                const char *createdAt = (const char *)sqlite3_column_text(stmt, 5);
                if (createdAt) block.createdAt = iso8601Parse(@(createdAt));
            }
        }
    });
    return block;
}

#pragma mark - Private Helpers

- (void)_bindParams:(NSArray *)params toStatement:(sqlite3_stmt *)stmt {
    for (NSUInteger i = 0; i < params.count; i++) {
        id param = params[i];
        int idx = (int)(i + 1);
        if (param == [NSNull null]) {
            sqlite3_bind_null(stmt, idx);
        } else if ([param isKindOfClass:[NSString class]]) {
            sqlite3_bind_text(stmt, idx, [param UTF8String], -1, SQLITE_TRANSIENT);
        } else if ([param isKindOfClass:[NSData class]]) {
            bindDataOrZeroBlob(stmt, idx, param);
        } else if ([param isKindOfClass:[NSNumber class]]) {
            sqlite3_bind_int64(stmt, idx, [param longLongValue]);
        }
    }
}

- (id)_valueFromStatement:(sqlite3_stmt *)stmt columnIndex:(int)idx {
    int type = sqlite3_column_type(stmt, idx);
    switch (type) {
        case SQLITE_INTEGER: return @(sqlite3_column_int64(stmt, idx));
        case SQLITE_FLOAT:   return @(sqlite3_column_double(stmt, idx));
        case SQLITE_TEXT:    return @((const char *)sqlite3_column_text(stmt, idx));
        case SQLITE_BLOB: {
            const void *data = sqlite3_column_blob(stmt, idx);
            int len = sqlite3_column_bytes(stmt, idx);
            return [NSData dataWithBytes:data length:len];
        }
        default: return [NSNull null];
    }
}

#pragma mark - Record Materialization

- (BOOL)saveRecordWithURI:(NSString *)uri
                     did:(NSString *)did
              collection:(NSString *)collection
                    rkey:(NSString *)rkey
                     cid:(NSString *)cid
                  handle:(nullable NSString *)handle
                   value:(nullable NSString *)value
              subjectDid:(nullable NSString *)subjectDid
                   error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, handle, value, subject_did) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
    NSArray *params = @[uri, did, collection, rkey, cid ?: [NSNull null], handle ?: [NSNull null], value ?: [NSNull null], subjectDid ?: [NSNull null]];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)saveBlockWithCid:(NSData *)cid
                repoDid:(NSString *)repoDid
              blockData:(NSData *)blockData
            contentType:(nullable NSString *)contentType
                  error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    NSArray *params = @[cid, repoDid, blockData, contentType ?: @"application/cbor", @(blockData.length), iso8601Now()];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)saveRepoSnapshotForDID:(NSString *)did
                       lastRev:(NSString *)lastRev
                       records:(NSArray<NSDictionary *> *)records
                        blocks:(NSArray<NSDictionary *> *)blocks
                         error:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    dispatch_sync(_queue, ^{
        char *errmsg = NULL;
        int rc = sqlite3_exec(self->_db, "BEGIN IMMEDIATE", NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"Failed to begin snapshot transaction"}];
            if (errmsg) sqlite3_free(errmsg);
            ok = NO;
            return;
        }

        rc = sqlite3_exec(self->_db,
                          "CREATE TEMP TABLE IF NOT EXISTS appview_snapshot_uris(uri TEXT PRIMARY KEY);"
                          "DELETE FROM appview_snapshot_uris;",
                          NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"Failed to prepare snapshot temp table"}];
            if (errmsg) sqlite3_free(errmsg);
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
            return;
        }

        const char *insertBlockSQL =
            "INSERT OR REPLACE INTO blocks(cid, repo_did, block_data, content_type, size, created_at)"
            " VALUES(?,?,?,?,?,?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *blockStmt = NULL;
        rc = sqlite3_prepare_v2(self->_db, insertBlockSQL, -1, &blockStmt, NULL);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare block snapshot insert"}];
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
            return;
        }
        for (NSDictionary *block in blocks) {
            NSData *cidData = block[@"cid_data"];
            NSData *blockData = block[@"block_data"];
            if (![cidData isKindOfClass:[NSData class]] || ![blockData isKindOfClass:[NSData class]]) continue;
            NSString *contentType = block[@"content_type"] ?: @"application/cbor";
            NSString *now = iso8601Now();
            sqlite3_bind_blob(blockStmt, 1, cidData.bytes, (int)cidData.length, SQLITE_TRANSIENT);
            sqlite3_bind_text(blockStmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_blob(blockStmt, 3, blockData.bytes, (int)blockData.length, SQLITE_TRANSIENT);
            sqlite3_bind_text(blockStmt, 4, contentType.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(blockStmt, 5, blockData.length);
            sqlite3_bind_text(blockStmt, 6, now.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(blockStmt);
            sqlite3_reset(blockStmt);
            sqlite3_clear_bindings(blockStmt);
            if (rc != SQLITE_DONE) break;
        }
        if (rc != SQLITE_DONE && blocks.count > 0) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to store snapshot blocks"}];
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
            return;
        }

        const char *insertRecordSQL =
            "INSERT OR REPLACE INTO records(uri, did, collection, rkey, cid, handle, value, subject_did, indexed_at)"
            " VALUES(?,?,?,?,?,?,?,?,?)";
        const char *insertURIToTempSQL = "INSERT OR IGNORE INTO appview_snapshot_uris(uri) VALUES(?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *recordStmt = NULL;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *tempStmt = NULL;
        rc = sqlite3_prepare_v2(self->_db, insertRecordSQL, -1, &recordStmt, NULL);
        if (rc == SQLITE_OK) rc = sqlite3_prepare_v2(self->_db, insertURIToTempSQL, -1, &tempStmt, NULL);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare record snapshot insert"}];
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
            return;
        }

        for (NSDictionary *record in records) {
            NSString *uri = record[@"uri"];
            NSString *collection = record[@"collection"];
            NSString *rkey = record[@"rkey"];
            NSString *cid = record[@"cid"];
            NSString *handle = record[@"handle"];
            NSString *value = record[@"value"];
            NSString *subjectDID = record[@"subject_did"];
            if (uri.length == 0 || collection.length == 0 || rkey.length == 0 || cid.length == 0) continue;

            NSString *now = iso8601Now();
            sqlite3_bind_text(recordStmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(recordStmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(recordStmt, 3, collection.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(recordStmt, 4, rkey.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(recordStmt, 5, cid.UTF8String, -1, SQLITE_TRANSIENT);
            if (handle) sqlite3_bind_text(recordStmt, 6, handle.UTF8String, -1, SQLITE_TRANSIENT);
            else sqlite3_bind_null(recordStmt, 6);
            if (value) sqlite3_bind_text(recordStmt, 7, value.UTF8String, -1, SQLITE_TRANSIENT);
            else sqlite3_bind_null(recordStmt, 7);
            if (subjectDID) sqlite3_bind_text(recordStmt, 8, subjectDID.UTF8String, -1, SQLITE_TRANSIENT);
            else sqlite3_bind_null(recordStmt, 8);
            sqlite3_bind_text(recordStmt, 9, now.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(recordStmt);
            sqlite3_reset(recordStmt);
            sqlite3_clear_bindings(recordStmt);
            if (rc != SQLITE_DONE) break;

            sqlite3_bind_text(tempStmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(tempStmt);
            sqlite3_reset(tempStmt);
            sqlite3_clear_bindings(tempStmt);
            if (rc != SQLITE_DONE) break;
        }
        if (rc != SQLITE_DONE && records.count > 0) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to store snapshot records"}];
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
            return;
        }

        const char *deleteSQL =
            "DELETE FROM records WHERE did = ? AND uri NOT IN (SELECT uri FROM appview_snapshot_uris)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *deleteStmt = NULL;
        rc = sqlite3_prepare_v2(self->_db, deleteSQL, -1, &deleteStmt, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_text(deleteStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(deleteStmt);
        }
        if (rc != SQLITE_DONE && rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"Failed to delete stale snapshot records"}];
            if (errmsg) sqlite3_free(errmsg);
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
            return;
        }

        const char *eventSQL =
            "INSERT OR IGNORE INTO appview_cursor_events(event_type, seq, did, rev, cid, raw_envelope, created_at)"
            " VALUES('historical_snapshot', 0, ?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *eventStmt = NULL;
        rc = sqlite3_prepare_v2(self->_db, eventSQL, -1, &eventStmt, NULL);
        if (rc == SQLITE_OK) {
            NSData *rawEnvelope = [lastRev dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
            NSString *now = iso8601Now();
            sqlite3_bind_text(eventStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(eventStmt, 2, lastRev.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(eventStmt, 3, lastRev.UTF8String, -1, SQLITE_TRANSIENT);
            bindDataOrZeroBlob(eventStmt, 4, rawEnvelope);
            sqlite3_bind_text(eventStmt, 5, now.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(eventStmt);
        }
        if (rc != SQLITE_DONE && rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to append snapshot cursor event"}];
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
            return;
        }

        const char *stateSQL =
            "INSERT INTO appview_repo_sync_state(did, status, last_rev, last_backfill_at, error_count, last_error)"
            " VALUES(?,?,?,?,0,NULL)"
            " ON CONFLICT(did) DO UPDATE SET"
            " status = excluded.status,"
            " last_rev = excluded.last_rev,"
            " last_backfill_at = excluded.last_backfill_at,"
            " error_count = 0,"
            " last_error = NULL";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stateStmt = NULL;
        rc = sqlite3_prepare_v2(self->_db, stateSQL, -1, &stateStmt, NULL);
        if (rc == SQLITE_OK) {
            NSString *now = iso8601Now();
            sqlite3_bind_text(stateStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stateStmt, 2, (int)AppViewRepoSyncStatusSynced);
            sqlite3_bind_text(stateStmt, 3, lastRev.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stateStmt, 4, now.UTF8String, -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(stateStmt);
        }
        if (rc != SQLITE_DONE && rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to mark snapshot synced"}];
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
            return;
        }

        rc = sqlite3_exec(self->_db, "COMMIT", NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"Failed to commit snapshot"}];
            if (errmsg) sqlite3_free(errmsg);
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
        }
    });

    if (!ok && error) *error = innerError;
    return ok;
}

#pragma mark - Stats

- (NSInteger)getTotalRecordsCountForCollection:(NSString *)collection error:(NSError **)error {
    __block NSInteger count = 0;
    dispatch_sync(_queue, ^{
        const char *sql = "SELECT COUNT(*) FROM records WHERE collection = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, collection.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                count = sqlite3_column_int64(stmt, 0);
            }
        }
    });
    return count;
}

- (NSInteger)getTotalBlocksCountWithError:(NSError **)error {
    __block NSInteger count = 0;
    dispatch_sync(_queue, ^{
        const char *sql = "SELECT COUNT(*) FROM blocks";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                count = sqlite3_column_int64(stmt, 0);
            }
        }
    });
    return count;
}

#pragma mark - Generic Record Queries

- (nullable NSDictionary *)getRecordWithURI:(NSString *)uri
                                       did:(NSString *)did
                                collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                    error:(NSError **)error {
    NSString *sql = @"SELECT uri, did, collection, rkey, cid, value, handle, subject_did, indexed_at FROM records WHERE uri = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[uri] error:error];
    if (!rows || rows.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }

    NSDictionary *row = rows.firstObject;
    NSString *value = row[@"value"];
    NSDictionary *record = nil;
    if (value && value.length > 0) {
        record = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding]
                                                options:0
                                                  error:nil];
        if (![record isKindOfClass:[NSDictionary class]]) {
            record = nil;
        }
    }

    return @{
        @"uri": row[@"uri"] ?: uri,
        @"cid": row[@"cid"] ?: @"",
        @"value": record ?: @{},
        @"did": row[@"did"] ?: did,
        @"collection": row[@"collection"] ?: collection,
        @"rkey": row[@"rkey"] ?: rkey
    };
}

- (nullable NSDictionary *)listRecordsForCollection:(NSString *)collection
                                                did:(nullable NSString *)did
                                              limit:(NSInteger)limit
                                             cursor:(nullable NSString *)cursor
                                              error:(NSError **)error {
    limit = MAX(1, MIN(limit, 100));

    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT uri, did, collection, rkey, cid, value, handle, indexed_at FROM records WHERE collection = ?"];
    NSMutableArray *params = [NSMutableArray arrayWithObject:collection];

    if (did.length > 0) {
        [sql appendString:@" AND did = ?"];
        [params addObject:did];
    }

    if (cursor.length > 0) {
        // Cursor is the last rkey from the previous page
        [sql appendString:@" AND rkey > ?"];
        [params addObject:cursor];
    }

    [sql appendString:@" ORDER BY rkey ASC LIMIT ?"];
    [params addObject:@(limit + 1)]; // Fetch one extra to detect next page

    NSArray *rows = [self executeParameterizedQuery:sql params:params error:error];
    if (!rows) return nil;

    BOOL hasMore = rows.count > (NSUInteger)limit;
    NSArray *resultRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, (NSUInteger)limit)] : rows;

    NSMutableArray *records = [NSMutableArray array];
    NSString *nextCursor = nil;

    for (NSUInteger i = 0; i < resultRows.count; i++) {
        NSDictionary *row = resultRows[i];
        NSString *value = row[@"value"];
        NSDictionary *record = nil;
        if (value && value.length > 0) {
            record = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:0
                                                      error:nil];
            if (![record isKindOfClass:[NSDictionary class]]) {
                record = nil;
            }
        }

        [records addObject:@{
            @"uri": row[@"uri"] ?: @"",
            @"cid": row[@"cid"] ?: @"",
            @"value": record ?: @{},
            @"did": row[@"did"] ?: @"",
            @"collection": row[@"collection"] ?: collection,
            @"rkey": row[@"rkey"] ?: @""
        }];

        // Use the last rkey as the next cursor
        if (i == resultRows.count - 1 && hasMore) {
            nextCursor = row[@"rkey"];
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:records forKey:@"records"];
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    }
    return [result copy];
}

- (nullable NSArray<NSString *> *)indexedCollectionsWithError:(NSError **)error {
    NSString *sql = @"SELECT DISTINCT collection FROM records ORDER BY collection";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[] error:error];
    if (!rows) return nil;

    NSMutableArray *collections = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *collection = row[@"collection"];
        if (collection.length > 0) {
            [collections addObject:collection];
        }
    }
    return [collections copy];
}

- (NSInteger)recordCountForCollection:(NSString *)collection error:(NSError **)error {
    __block NSInteger count = -1;
    NSString *sql = @"SELECT COUNT(*) AS cnt FROM records WHERE collection = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[collection] error:error];
    if (rows && rows.count > 0) {
        NSNumber *cnt = rows.firstObject[@"cnt"];
        if ([cnt isKindOfClass:[NSNumber class]]) {
            count = [cnt integerValue];
        }
    }
    return count;
}

#pragma mark - Handle Resolution

- (BOOL)saveHandle:(NSString *)handle did:(NSString *)did error:(NSError **)error {
    // Delete any existing entries for this DID first (handle might have changed)
    [self executeParameterizedUpdate:@"DELETE FROM handles WHERE did = ?" params:@[did] error:nil];
    
    NSString *sql = @"INSERT OR REPLACE INTO handles (handle, did) VALUES (?, ?)";
    NSArray *params = @[handle, did];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error {
    __block NSString *did = nil;
    dispatch_sync(_queue, ^{
        const char *sql = "SELECT did FROM handles WHERE handle = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, handle.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *val = (const char *)sqlite3_column_text(stmt, 0);
                if (val) did = [NSString stringWithUTF8String:val];
            }
        }
    });
    return did;
}

- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error {
    __block NSString *handle = nil;
    dispatch_sync(_queue, ^{
        const char *sql = "SELECT handle FROM handles WHERE did = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *val = (const char *)sqlite3_column_text(stmt, 0);
                if (val) handle = [NSString stringWithUTF8String:val];
            }
        }
    });
    return handle;
}

@end
