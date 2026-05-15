// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewDatabase.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/AppViewDatabase.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Core/NSDateFormatter+ATProto.h"

#import <sqlite3.h>
#include <string.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"

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
"    uri TEXT UNIQUE,"
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
"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
"    did TEXT NOT NULL,"
"    uri TEXT NOT NULL UNIQUE,"
"    subject_uri TEXT NOT NULL,"
"    subject_cid TEXT,"
"    created_at TEXT NOT NULL,"
"    UNIQUE(did, subject_uri)"
");"

"CREATE TABLE IF NOT EXISTS starter_packs ("
"    uri TEXT PRIMARY KEY,"
"    did TEXT NOT NULL,"
"    rkey TEXT NOT NULL,"
"    cid TEXT NOT NULL,"
"    name TEXT NOT NULL,"
"    description TEXT,"
"    list_uri TEXT,"
"    created_at TEXT,"
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

"CREATE TABLE IF NOT EXISTS actor_preferences ("
"  did         TEXT PRIMARY KEY,"
"  preferences BLOB NOT NULL,"
"  created_at  REAL NOT NULL,"
"  updated_at  REAL NOT NULL,"
"  FOREIGN KEY (did) REFERENCES accounts(did)"
");"

"CREATE TABLE IF NOT EXISTS actor_mutes ("
"  id          INTEGER PRIMARY KEY AUTOINCREMENT,"
"  did         TEXT NOT NULL,"
"  muted_did   TEXT NOT NULL,"
"  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
"  UNIQUE(did, muted_did)"
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

"CREATE TABLE IF NOT EXISTS age_assurance_states ("
"    id TEXT PRIMARY KEY,"
"    did TEXT NOT NULL,"
"    status TEXT NOT NULL,"
"    email TEXT,"
"    country_code TEXT,"
"    region_code TEXT,"
"    language TEXT,"
"    token TEXT,"
"    created_at INTEGER,"
"    updated_at INTEGER"
");"

"CREATE TABLE IF NOT EXISTS search_actors("
"  rowid INTEGER PRIMARY KEY,"
"  did TEXT NOT NULL,"
"  display_name TEXT,"
"  handle TEXT,"
"  description TEXT"
");"

"CREATE TABLE IF NOT EXISTS search_posts("
"  rowid INTEGER PRIMARY KEY,"
"  uri TEXT NOT NULL,"
"  did TEXT NOT NULL,"
"  text TEXT"
");"

"CREATE TABLE IF NOT EXISTS search_starter_packs("
"  rowid INTEGER PRIMARY KEY,"
"  uri TEXT NOT NULL,"
"  did TEXT NOT NULL,"
"  name TEXT"
");"

"CREATE VIRTUAL TABLE IF NOT EXISTS fts_actors USING fts5(did, display_name, handle, description, content=search_actors, content_rowid=rowid);"
"CREATE VIRTUAL TABLE IF NOT EXISTS fts_posts USING fts5(uri, did, text, content=search_posts, content_rowid=rowid);"
"CREATE VIRTUAL TABLE IF NOT EXISTS fts_starter_packs USING fts5(uri, did, name, content=search_starter_packs, content_rowid=rowid);"

"CREATE INDEX IF NOT EXISTS idx_search_actors_did ON search_actors(did);"
"CREATE INDEX IF NOT EXISTS idx_search_posts_uri ON search_posts(uri);"
"CREATE INDEX IF NOT EXISTS idx_search_starter_packs_uri ON search_starter_packs(uri);"
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

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation AppViewDatabase {
    sqlite3 *_db;
    dispatch_queue_t _queue;
    NSMutableSet<NSString *> *_relevanceCache; // in-memory set for fast isDIDRelevant
    NSMutableDictionary<NSString *, NSNumber *> *_durableCursorByRelayURL;
}

- (void)safeExecuteSync:(void(^)(void))block {
    if (dispatch_get_specific(kAppViewDatabaseQueueKey)) {
        block();
    } else {
        dispatch_sync(_queue, block);
    }
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

    if (!ATProtoDBConfigurePragmas(_db, ATProtoDBConfigDefault)) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain
                                         code:rc
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Failed to configure SQLite pragmas"}];
        }
        sqlite3_close_v2(_db);
        _db = NULL;
        return nil;
    }

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

    [self safeExecuteSync:^{
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

        rc = sqlite3_exec(self->_db,
                          "ALTER TABLE bsky_feed_threadgates ADD COLUMN uri TEXT;",
                          NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            BOOL duplicateColumn = errmsg && strstr(errmsg, "duplicate column name") != NULL;
            if (errmsg) {
                sqlite3_free(errmsg);
                errmsg = NULL;
            }
            if (!duplicateColumn) {
                innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain
                                                 code:rc
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to add bsky_feed_threadgates.uri"}];
                ok = NO;
                return;
            }
        }

        rc = sqlite3_exec(self->_db,
                          "CREATE UNIQUE INDEX IF NOT EXISTS idx_bsky_feed_threadgates_uri ON bsky_feed_threadgates(uri);",
                          NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        errmsg ? [NSString stringWithUTF8String:errmsg]
                                                               : @"Failed to create threadgate uri index"}];
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
        NSString *sql = @"SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > ?";
        NSArray *rows = [self executeParameterizedQuery:sql params:@[iso8601Now()] error:nil];
        for (NSDictionary *row in rows) {
            NSString *did = row[@"did"];
            if (did) [self->_relevanceCache addObject:did];
        }
    }];

    if (!ok && error) *error = innerError;
    return ok;
}

// ---------------------------------------------------------------------------
// Checkpoint
// ---------------------------------------------------------------------------

- (BOOL)saveCheckpoint:(AppViewCheckpoint *)checkpoint error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO appview_checkpoints(relay_url, seq, saved_at) VALUES(?,?,?)";
    NSArray *params = @[checkpoint.relayURL, @(checkpoint.seq), iso8601Now()];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (nullable AppViewCheckpoint *)loadCheckpointForRelayURL:(NSString *)relayURL
                                                    error:(NSError **)error {
    NSString *sql = @"SELECT seq, saved_at FROM appview_checkpoints WHERE relay_url = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[relayURL] error:error];
    if (rows.count == 0) return nil;

    NSDictionary *row = rows.firstObject;
    AppViewCheckpoint *result = [[AppViewCheckpoint alloc] initWithRelayURL:relayURL seq:[row[@"seq"] longLongValue]];
    NSString *savedAt = row[@"saved_at"];
    if (savedAt) result.savedAt = iso8601Parse(savedAt);
    return result;
}

// ---------------------------------------------------------------------------
// Repo Sync State
// ---------------------------------------------------------------------------

- (BOOL)upsertRepoSyncState:(AppViewRepoSyncState *)state error:(NSError **)error {
    NSString *sql =
        @"INSERT INTO appview_repo_sync_state(did, status, last_rev, last_backfill_at, error_count, last_error)"
        " VALUES(?,?,?,?,?,?)"
        " ON CONFLICT(did) DO UPDATE SET"
        "   status = excluded.status,"
        "   last_rev = excluded.last_rev,"
        "   last_backfill_at = excluded.last_backfill_at,"
        "   error_count = excluded.error_count,"
        "   last_error = excluded.last_error";
    
    id bfAt = [NSNull null];
    if (state.lastBackfillAt) {
        bfAt = [NSDateFormatter atproto_stringFromDate:state.lastBackfillAt];
    }

    NSArray *params = @[
        state.did,
        @(state.status),
        state.lastRev ?: [NSNull null],
        bfAt,
        @(state.errorCount),
        state.lastError ?: [NSNull null]
    ];

    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (nullable AppViewRepoSyncState *)loadRepoSyncStateForDID:(NSString *)did
                                                     error:(NSError **)error {
    NSString *sql = @"SELECT status, last_rev, last_backfill_at, error_count, last_error FROM appview_repo_sync_state WHERE did = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[did] error:error];
    if (rows.count == 0) return nil;

    NSDictionary *row = rows.firstObject;
    AppViewRepoSyncState *result = [[AppViewRepoSyncState alloc] initWithDID:did];
    result.status = (AppViewRepoSyncStatus)[row[@"status"] intValue];
    result.lastRev = row[@"last_rev"] != [NSNull null] ? row[@"last_rev"] : nil;
    NSString *bfAt = row[@"last_backfill_at"] != [NSNull null] ? row[@"last_backfill_at"] : nil;
    if (bfAt) result.lastBackfillAt = iso8601Parse(bfAt);
    result.errorCount = [row[@"error_count"] longLongValue];
    result.lastError = row[@"last_error"] != [NSNull null] ? row[@"last_error"] : nil;
    return result;
}

- (nullable AppViewRepoSyncState *)getRepoSyncState:(NSString *)did
                                              error:(NSError **)error {
    return [self loadRepoSyncStateForDID:did error:error];
}

- (nullable NSArray<AppViewRepoSyncState *> *)loadRepoSyncStatesWithStatus:(AppViewRepoSyncStatus)status
                                                                     limit:(NSInteger)limit
                                                                     error:(NSError **)error {
    NSString *sql =
        @"SELECT did, last_rev, last_backfill_at, error_count, last_error"
        " FROM appview_repo_sync_state"
        " WHERE status = ?"
        " ORDER BY error_count ASC, last_backfill_at ASC NULLS FIRST"
        " LIMIT ?";
    
    NSArray *rows = [self executeParameterizedQuery:sql params:@[@(status), @(limit)] error:error];
    if (!rows) return nil;

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:row[@"did"]];
        s.status = status;
        s.lastRev = row[@"last_rev"] != [NSNull null] ? row[@"last_rev"] : nil;
        NSString *bfAt = row[@"last_backfill_at"] != [NSNull null] ? row[@"last_backfill_at"] : nil;
        if (bfAt) s.lastBackfillAt = iso8601Parse(bfAt);
        s.errorCount = [row[@"error_count"] longLongValue];
        s.lastError = row[@"last_error"] != [NSNull null] ? row[@"last_error"] : nil;
        [results addObject:s];
    }
    return [results copy];
}

- (BOOL)setRepoSyncState:(AppViewRepoSyncState *)state
                   error:(NSError **)error {
    return [self upsertRepoSyncState:state error:error];
}

- (NSInteger)countRepoSyncStatesWithStatus:(AppViewRepoSyncStatus)status error:(NSError **)error {
    NSString *sql = @"SELECT COUNT(*) AS count FROM appview_repo_sync_state WHERE status = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[@(status)] error:error];
    if (rows.count == 0) return 0;
    return [rows.firstObject[@"count"] integerValue];
}

- (nullable NSArray<NSString *> *)markReposAsProcessing:(NSArray<NSString *> *)dids
                                                  error:(NSError **)error {
    if (dids.count == 0) return @[];

    __block NSMutableArray<NSString *> *transitioned = [NSMutableArray array];

    BOOL ok = [self performTransaction:^BOOL(AppViewDatabase *db, NSError **innerError) {
        for (NSString *did in dids) {
            NSString *sql = @"UPDATE appview_repo_sync_state SET status = ? WHERE did = ? AND status = ?";
            NSArray *params = @[@(AppViewRepoSyncStatusProcessing), did, @(AppViewRepoSyncStatusPending)];
            
            // We need to know if any rows were changed. 
            // Since executeParameterizedUpdate doesn't return change count, we might need to handle this differently.
            // However, the original code used sqlite3_changes(self->_db).
            // Let's assume we can check changes within the queue.
            
            [db executeParameterizedUpdate:sql params:params error:nil];
            if (sqlite3_changes(db->_db) > 0) {
                [transitioned addObject:did];
            }
        }
        return YES;
    } error:error];

    return ok ? [transitioned copy] : nil;
}

- (BOOL)markRepoSynced:(NSString *)did lastRev:(NSString *)lastRev error:(NSError **)error {
    NSString *sql =
        @"UPDATE appview_repo_sync_state"
        " SET status = ?, last_rev = ?, last_backfill_at = ?, error_count = 0, last_error = NULL"
        " WHERE did = ?";
    NSArray *params = @[@(AppViewRepoSyncStatusSynced), lastRev, iso8601Now(), did];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)markRepoDirty:(NSString *)did error:(NSError **)error {
    NSString *sql = @"UPDATE appview_repo_sync_state SET status = ? WHERE did = ?";
    NSArray *params = @[@(AppViewRepoSyncStatusDirty), did];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)recordBackfillError:(NSString *)did message:(NSString *)message error:(NSError **)error {
    NSString *sql =
        @"UPDATE appview_repo_sync_state"
        " SET error_count = error_count + 1, last_error = ?"
        " WHERE did = ?";
    NSArray *params = @[message, did];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

// ---------------------------------------------------------------------------
// Pending Deltas
// ---------------------------------------------------------------------------

- (BOOL)enqueuePendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error {
    NSString *sql =
        @"INSERT OR IGNORE INTO appview_pending_deltas"
        "(did, seq, commit_cid, rev, raw_envelope, enqueued_at)"
        " VALUES(?,?,?,?,?,?)";
    NSArray *params = @[
        delta.did,
        @(delta.seq),
        delta.commitCID,
        delta.rev,
        delta.rawEnvelope ?: [NSData data],
        iso8601Now()
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (nullable NSArray<AppViewPendingDelta *> *)dequeuePendingDeltasForDID:(NSString *)did
                                                                  error:(NSError **)error {
    __block NSMutableArray<AppViewPendingDelta *> *results = [NSMutableArray array];

    BOOL ok = [self performTransaction:^BOOL(AppViewDatabase *db, NSError **innerError) {
        NSString *selectSQL =
            @"SELECT seq, commit_cid, rev, raw_envelope FROM appview_pending_deltas"
            " WHERE did = ? ORDER BY seq ASC";
        NSArray *rows = [db executeParameterizedQuery:selectSQL params:@[did] error:innerError];
        if (!rows) return NO;

        for (NSDictionary *row in rows) {
            int64_t seq = [row[@"seq"] longLongValue];
            NSString *cid = row[@"commit_cid"];
            NSString *rev = row[@"rev"];
            NSData *envelope = row[@"raw_envelope"];
            AppViewPendingDelta *d = [[AppViewPendingDelta alloc]
                initWithDID:did
                        seq:seq
                  commitCID:cid
                        rev:rev
                rawEnvelope:envelope];
            [results addObject:d];
        }

        NSString *deleteSQL = @"DELETE FROM appview_pending_deltas WHERE did = ?";
        return [db executeParameterizedUpdate:deleteSQL params:@[did] error:innerError];
    } error:error];

    return ok ? [results copy] : nil;
}

- (NSInteger)countPendingDeltasForDID:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT COUNT(*) AS count FROM appview_pending_deltas WHERE did = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[did] error:error];
    if (rows.count == 0) return 0;
    return [rows.firstObject[@"count"] integerValue];
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
    NSString *sql =
        @"INSERT OR IGNORE INTO appview_event_log(seq, did, rev, cid, raw_envelope, created_at)"
        " VALUES(?,?,?,?,?,?)";
    NSArray *params = @[
        @(seq),
        did ?: [NSNull null],
        rev ?: [NSNull null],
        cid ?: [NSNull null],
        rawEnvelope ?: [NSData data],
        iso8601Now()
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)hasEventWithDID:(nullable NSString *)did
                    rev:(nullable NSString *)rev
                    cid:(nullable NSString *)cid {
    NSString *sql = @"SELECT 1 FROM appview_event_log WHERE did IS ? AND rev IS ? AND cid IS ? LIMIT 1";
    NSArray *params = @[did ?: [NSNull null], rev ?: [NSNull null], cid ?: [NSNull null]];
    NSArray *rows = [self executeParameterizedQuery:sql params:params error:nil];
    return rows.count > 0;
}

- (NSInteger)pruneEventLogOlderThan:(NSDate *)cutoff error:(NSError **)error {
    NSString *cutoffStr = [NSDateFormatter atproto_stringFromDate:cutoff];
    NSString *sql = @"DELETE FROM appview_event_log WHERE created_at < ?";
    
    __block NSInteger deleted = 0;
    [self safeExecuteSync:^{
        [self executeParameterizedUpdate:sql params:@[cutoffStr] error:error];
        deleted = sqlite3_changes(self->_db);
    }];
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
    NSString *sql =
        @"INSERT OR IGNORE INTO appview_cursor_events(event_type, seq, did, rev, cid, raw_envelope, created_at)"
        " VALUES(?,?,?,?,?,?,?)";
    NSArray *params = @[
        eventType,
        @(seq),
        did ?: [NSNull null],
        rev ?: [NSNull null],
        cid ?: [NSNull null],
        rawEnvelope ?: [NSData data],
        iso8601Now()
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (nullable NSArray<NSDictionary *> *)loadStoredEventsAfterCursor:(int64_t)cursor
                                                           limit:(NSInteger)limit
                                                           error:(NSError **)error {
    NSString *sql =
        @"SELECT cursor, event_type, seq, did, rev, cid, raw_envelope, created_at"
        " FROM appview_cursor_events WHERE cursor > ? ORDER BY cursor ASC LIMIT ?";
    
    NSArray *rows = [self executeParameterizedQuery:sql params:@[@(cursor), @(limit)] error:error];
    if (!rows) return nil;

    NSMutableArray *events = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *event = [row mutableCopy];
        // The executeParameterizedQuery already handles types well, but let's ensure compatibility with expected output
        if (event[@"event_type"] == [NSNull null]) event[@"event_type"] = @"";
        if (event[@"raw_envelope"] == [NSNull null]) event[@"raw_envelope"] = [NSData data];
        [events addObject:[event copy]];
    }
    return [events copy];
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
    NSString *sql =
        @"INSERT INTO appview_relevance(did, reason, expires_at, added_at)"
        " VALUES(?,?,?,?)"
        " ON CONFLICT(did) DO UPDATE SET"
        "   reason = excluded.reason,"
        "   expires_at = excluded.expires_at,"
        "   added_at = excluded.added_at";
    
    id expiresAt = [NSNull null];
    if (membership.expiresAt) {
        expiresAt = [NSDateFormatter atproto_stringFromDate:membership.expiresAt];
    }

    NSArray *params = @[
        membership.did,
        @(membership.reason),
        expiresAt,
        iso8601Now()
    ];

    __block BOOL ok = [self executeParameterizedUpdate:sql params:params error:error];
    if (ok) {
        [self safeExecuteSync:^{
            if (membership.isValid)
                [self->_relevanceCache addObject:membership.did];
            else
                [self->_relevanceCache removeObject:membership.did];
        }];
    }
    return ok;
}

- (nullable AppViewRelevanceMembership *)loadRelevanceMembershipForDID:(NSString *)did
                                                                 error:(NSError **)error {
    NSString *sql = @"SELECT reason, expires_at, added_at FROM appview_relevance WHERE did = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[did] error:error];
    if (rows.count == 0) return nil;

    NSDictionary *row = rows.firstObject;
    AppViewRelevanceReason reason = (AppViewRelevanceReason)[row[@"reason"] intValue];
    NSString *expiresStr = row[@"expires_at"] != [NSNull null] ? row[@"expires_at"] : nil;
    NSDate *expires = expiresStr ? iso8601Parse(expiresStr) : nil;
    AppViewRelevanceMembership *result = [[AppViewRelevanceMembership alloc] initWithDID:did reason:reason expiresAt:expires];
    NSString *addedStr = row[@"added_at"] != [NSNull null] ? row[@"added_at"] : nil;
    if (addedStr) result.addedAt = iso8601Parse(addedStr);
    return result;
}

- (BOOL)isDIDRelevant:(NSString *)did {
    __block BOOL relevant = NO;
    [self safeExecuteSync:^{
        relevant = [self->_relevanceCache containsObject:did];
    }];
    return relevant;
}

- (NSInteger)pruneExpiredRelevanceMemberships:(NSError **)error {
    NSString *now = iso8601Now();
    NSString *sql = @"DELETE FROM appview_relevance WHERE expires_at IS NOT NULL AND expires_at <= ?";
    
    __block NSInteger deleted = 0;
    [self safeExecuteSync:^{
        [self executeParameterizedUpdate:sql params:@[now] error:error];
        deleted = sqlite3_changes(self->_db);

        // Rebuild cache
        [self->_relevanceCache removeAllObjects];
        NSString *sel = @"SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > ?";
        NSArray *rows = [self executeParameterizedQuery:sel params:@[now] error:nil];
        for (NSDictionary *row in rows) {
            NSString *did = row[@"did"];
            if (did) [self->_relevanceCache addObject:did];
        }
    }];
    return deleted;
}

- (nullable NSArray<NSString *> *)loadAllRelevantDIDs:(NSError **)error {
    NSString *sql = @"SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[iso8601Now()] error:error];
    if (!rows) return nil;

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *did = row[@"did"];
        if (did) [results addObject:did];
    }
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
    NSString *sql =
        @"INSERT INTO appview_dead_letter(collection, seq, did, rev, cid, raw_record, validation_error, created_at)"
        " VALUES(?,?,?,?,?,?,?,?)";
    NSArray *params = @[
        collection,
        @(seq),
        did,
        rev ?: [NSNull null],
        cid ?: [NSNull null],
        rawRecord ?: [NSData data],
        validationError,
        iso8601Now()
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

// ---------------------------------------------------------------------------
// PDSQueryDatabase Implementation
// ---------------------------------------------------------------------------

- (nullable NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                        params:(NSArray *)params
                                                         error:(NSError **)error {
    __block NSMutableArray *results = [NSMutableArray array];
    __block NSError *innerError = nil;

    [self safeExecuteSync:^{
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

        ATProtoDBBindParams(stmt, params);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            int count = sqlite3_column_count(stmt);
            for (int i = 0; i < count; i++) {
                NSString *name = @(sqlite3_column_name(stmt, i));
                id val = ATProtoDBColumnValue(stmt, i);
                if (val && val != [NSNull null]) row[name] = val;
            }
            [results addObject:row];
        }
    }];

    if (innerError && error) *error = innerError;
    return innerError ? nil : results;
}

- (BOOL)executeParameterizedUpdate:(NSString *)sql
                           params:(NSArray *)params
                            error:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    [self safeExecuteSync:^{
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

        ATProtoDBBindParams(stmt, params);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(self->_db)]}];
            ok = NO;
        }
    }];

    if (!ok && error) *error = innerError;
    return ok;
}

- (BOOL)executeUnsafeRawSQL:(NSString *)sql error:(NSError **)error {
    __block BOOL ok = YES;
    __block NSError *innerError = nil;

    [self safeExecuteSync:^{
        char *errmsg = NULL;
        int rc = sqlite3_exec(self->_db, sql.UTF8String, NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                            userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"SQL failed"}];
            if (errmsg) sqlite3_free(errmsg);
            ok = NO;
        }
    }];

    if (!ok && error) *error = innerError;
    return ok;
}

- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid
                                      repoDid:(NSString *)repoDid
                                        error:(NSError **)error {
    NSString *sql = @"SELECT cid, repo_did, block_data, content_type, size, created_at FROM blocks WHERE cid = ? AND repo_did = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[cid, repoDid] error:error];
    if (rows.count == 0) return nil;

    NSDictionary *row = rows.firstObject;
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = row[@"cid"];
    block.repoDid = row[@"repo_did"];
    if (row[@"block_data"] != [NSNull null]) block.blockData = row[@"block_data"];
    if (row[@"content_type"] != [NSNull null]) block.contentType = row[@"content_type"];
    block.size = [row[@"size"] intValue];
    NSString *createdAt = row[@"created_at"] != [NSNull null] ? row[@"created_at"] : nil;
    if (createdAt) block.createdAt = iso8601Parse(createdAt);
    return block;
}

#pragma mark - Private Helpers



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
    return [self performTransaction:^BOOL(AppViewDatabase *db, NSError **innerError) {
        // Prepare temp table
        [db executeUnsafeRawSQL:@"CREATE TEMP TABLE IF NOT EXISTS appview_snapshot_uris(uri TEXT PRIMARY KEY); DELETE FROM appview_snapshot_uris;" error:innerError];
        
        // Insert blocks
        NSString *insertBlockSQL = @"INSERT OR REPLACE INTO blocks(cid, repo_did, block_data, content_type, size, created_at) VALUES(?,?,?,?,?,?)";
        for (NSDictionary *block in blocks) {
            NSData *cidData = block[@"cid_data"];
            NSData *blockData = block[@"block_data"];
            if (![cidData isKindOfClass:[NSData class]] || ![blockData isKindOfClass:[NSData class]]) continue;
            NSString *contentType = block[@"content_type"] ?: @"application/cbor";
            
            NSArray *params = @[cidData, did, blockData, contentType, @(blockData.length), iso8601Now()];
            if (![db executeParameterizedUpdate:insertBlockSQL params:params error:innerError]) return NO;
        }

        // Insert records
        NSString *insertRecordSQL = @"INSERT OR REPLACE INTO records(uri, did, collection, rkey, cid, handle, value, subject_did, indexed_at) VALUES(?,?,?,?,?,?,?,?,?)";
        NSString *insertURIToTempSQL = @"INSERT OR IGNORE INTO appview_snapshot_uris(uri) VALUES(?)";
        
        for (NSDictionary *record in records) {
            NSString *uri = record[@"uri"];
            NSString *collection = record[@"collection"];
            NSString *rkey = record[@"rkey"];
            NSString *cid = record[@"cid"];
            NSString *handle = record[@"handle"];
            NSString *value = record[@"value"];
            NSString *subjectDID = record[@"subject_did"];
            if (uri.length == 0 || collection.length == 0 || rkey.length == 0 || cid.length == 0) continue;

            NSArray *recordParams = @[
                uri, did, collection, rkey, cid,
                handle ?: [NSNull null],
                value ?: [NSNull null],
                subjectDID ?: [NSNull null],
                iso8601Now()
            ];
            if (![db executeParameterizedUpdate:insertRecordSQL params:recordParams error:innerError]) return NO;
            if (![db executeParameterizedUpdate:insertURIToTempSQL params:@[uri] error:innerError]) return NO;
        }

        // Delete stale records
        NSString *deleteSQL = @"DELETE FROM records WHERE did = ? AND uri NOT IN (SELECT uri FROM appview_snapshot_uris)";
        if (![db executeParameterizedUpdate:deleteSQL params:@[did] error:innerError]) return NO;

        // Log snapshot event
        NSString *eventSQL = @"INSERT OR IGNORE INTO appview_cursor_events(event_type, seq, did, rev, cid, raw_envelope, created_at) VALUES('historical_snapshot', 0, ?, ?, ?, ?, ?)";
        NSData *rawEnvelope = [lastRev dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        NSArray *eventParams = @[did, lastRev, lastRev, rawEnvelope, iso8601Now()];
        if (![db executeParameterizedUpdate:eventSQL params:eventParams error:innerError]) return NO;

        // Update sync state
        AppViewRepoSyncState *state = [[AppViewRepoSyncState alloc] initWithDID:did];
        state.status = AppViewRepoSyncStatusSynced;
        state.lastRev = lastRev;
        state.lastBackfillAt = [NSDate date];
        state.errorCount = 0;
        state.lastError = nil;
        return [db upsertRepoSyncState:state error:innerError];
    } error:error];
}

#pragma mark - Stats

- (NSInteger)getTotalRecordsCountForCollection:(NSString *)collection error:(NSError **)error {
    NSString *sql = @"SELECT COUNT(*) AS count FROM records WHERE collection = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[collection] error:error];
    if (rows.count == 0) return 0;
    return [rows.firstObject[@"count"] integerValue];
}

- (NSInteger)getTotalBlocksCountWithError:(NSError **)error {
    NSString *sql = @"SELECT COUNT(*) AS count FROM blocks";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[] error:error];
    if (rows.count == 0) return 0;
    return [rows.firstObject[@"count"] integerValue];
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
    limit = MAX(1, MIN(limit, 1000));

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
        id valueObj = row[@"value"];
        NSData *data = nil;
        if ([valueObj isKindOfClass:[NSData class]]) {
            data = valueObj;
        } else if ([valueObj isKindOfClass:[NSString class]]) {
            data = [(NSString *)valueObj dataUsingEncoding:NSUTF8StringEncoding];
        }

        NSDictionary *record = nil;
        if (data && data.length > 0) {
            record = [NSJSONSerialization JSONObjectWithData:data
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

    // Add total count for the query (useful for admin pagination)
    NSString *countSql = @"SELECT COUNT(*) AS total FROM records WHERE collection = ?";
    NSMutableArray *countParams = [NSMutableArray arrayWithObject:collection];
    if (did.length > 0) {
        countSql = [countSql stringByAppendingString:@" AND did = ?"];
        [countParams addObject:did];
    }
    NSArray *countRows = [self executeParameterizedQuery:countSql params:countParams error:nil];
    if (countRows.count > 0) {
        id total = countRows[0][@"total"];
        if (total) result[@"total"] = total;
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
    NSString *sql = @"SELECT did FROM handles WHERE handle = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[handle] error:error];
    if (rows.count == 0) return nil;
    return rows.firstObject[@"did"];
}

- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT handle FROM handles WHERE did = ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[did] error:error];
    if (rows.count == 0) return nil;
    return rows.firstObject[@"handle"];
}

- (NSString *)parameterPlaceholdersForCount:(NSUInteger)count {
    return ATProtoDBPlaceholders(count);
}

#pragma mark - Transactions

- (BOOL)performTransaction:(BOOL (^)(AppViewDatabase *db, NSError **error))block error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *innerError = nil;
    [self safeExecuteSync:^{
        char *errmsg = NULL;
        int rc = sqlite3_exec(self->_db, "BEGIN IMMEDIATE", NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"Failed to begin transaction"}];
            if (errmsg) sqlite3_free(errmsg);
            ok = NO;
            return;
        }

        NSError *blockError = nil;
        ok = block(self, &blockError);
        if (!ok) {
            if (blockError) innerError = blockError;
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            return;
        }

        rc = sqlite3_exec(self->_db, "COMMIT", NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            innerError = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"Failed to commit transaction"}];
            if (errmsg) sqlite3_free(errmsg);
            sqlite3_exec(self->_db, "ROLLBACK", NULL, NULL, NULL);
            ok = NO;
        }
    }];
    if (!ok && error) *error = innerError;
    return ok;
}

- (BOOL)inTransaction:(BOOL (^)(NSError **blockError))block error:(NSError **)error {
    return [self performTransaction:^BOOL(AppViewDatabase * _Nonnull db, NSError * _Nullable * _Nullable innerError) {
        return block(innerError);
    } error:error];
}

@end
