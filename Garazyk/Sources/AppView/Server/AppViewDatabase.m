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
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Database/Pool/ATProtoConnectionPool.h"
#import "Database/Connection/ATProtoConnectionManagerPooled.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Database/Migrations/PDSMigrationManager.h"

NSString * const AppViewDatabaseErrorDomain = @"AppViewDatabaseErrorDomain";



// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
    ATProtoConnectionPool *_pool;
    ATProtoConnectionManagerPooled *_connectionManager;
    ATProtoDatabaseQueryRunner *_queryRunner;
    NSMutableSet<NSString *> *_relevanceCache;
    NSMutableDictionary<NSString *, NSNumber *> *_durableCursorByRelayURL;
}

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (!self) return nil;

    _relevanceCache = [NSMutableSet set];
    _durableCursorByRelayURL = [NSMutableDictionary dictionary];

    _pool = [[ATProtoConnectionPool alloc] initWithPath:path minConnections:1 maxConnections:8];
    if (!_pool) {
        if (error) *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create connection pool"}];
        return nil;
    }
    _connectionManager = [[ATProtoConnectionManagerPooled alloc] initWithPool:_pool];
    _queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:_connectionManager
                                                                    errorDomain:AppViewDatabaseErrorDomain];

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



    return self;
}

- (nullable instancetype)initInMemoryWithError:(NSError **)error {
    return [self initWithPath:@":memory:" error:error];
}

- (void)dealloc {
    [self close];
}

- (void)close {
    [_pool closeAllConnections];

}



- (void)appView_reloadRelevanceCache {
    [self->_relevanceCache removeAllObjects];
    NSString *sql = @"SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > ?";
    NSArray *rows = [self executeParameterizedQuery:sql params:@[iso8601Now()] error:nil];
    for (NSDictionary *row in rows) {
        NSString *did = row[@"did"];
        if (did) [self->_relevanceCache addObject:did];
    }
}

- (BOOL)runMigrations:(NSError **)error {
    PDSMigrationManager *migrationManager = [PDSMigrationManager appViewDatabaseMigrationManager];
    sqlite3 *conn = [_pool acquireConnection];
    if (!conn) {
        if (error) *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:-1
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                @"Failed to acquire connection for migrations"}];
        return NO;
    }
    BOOL ok = [migrationManager migrateDatabase:conn error:error];
    [_pool releaseConnection:conn];
    if (!ok) return NO;

    @synchronized(self) {
        [self appView_reloadRelevanceCache];
    }
    return YES;
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

    BOOL ok = [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        for (NSString *did in dids) {
            NSString *selectSQL = @"SELECT did FROM appview_repo_sync_state WHERE did = ? AND status IN (?, ?)";
            NSArray *rows = [tx executeQuery:selectSQL params:@[
                did,
                @(AppViewRepoSyncStatusPending),
                @(AppViewRepoSyncStatusDirty)
            ] error:innerError];
            if (!rows) return NO;
            if (rows.count == 0) continue;

            NSString *sql =
                @"UPDATE appview_repo_sync_state"
                " SET status = ?"
                " WHERE did = ? AND status IN (?, ?)";
            NSArray *params = @[
                @(AppViewRepoSyncStatusProcessing),
                did,
                @(AppViewRepoSyncStatusPending),
                @(AppViewRepoSyncStatusDirty)
            ];

            if (![tx executeUpdate:sql params:params error:innerError]) return NO;
            [transitioned addObject:did];
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
        " SET status = ?, error_count = error_count + 1, last_error = ?"
        " WHERE did = ?";
    NSArray *params = @[@(AppViewRepoSyncStatusDirty), message, did];
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

    BOOL ok = [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        NSString *selectSQL =
            @"SELECT seq, commit_cid, rev, raw_envelope FROM appview_pending_deltas"
            " WHERE did = ? ORDER BY seq ASC";
        NSArray *rows = [tx executeQuery:selectSQL params:@[did] error:innerError];
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
        return [tx executeUpdate:deleteSQL params:@[did] error:innerError];
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
    NSInteger deleted = [_queryRunner executeUpdate:sql params:@[cutoffStr] error:error];
    return deleted >= 0 ? deleted : 0;
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
    @synchronized(self) {
        return [self->_durableCursorByRelayURL[relayURL] longLongValue];
    }
}

- (void)markDurableCursor:(int64_t)seq forRelayURL:(NSString *)relayURL {
    @synchronized(self) {
        int64_t current = [self->_durableCursorByRelayURL[relayURL] longLongValue];
        if (seq > current) {
            self->_durableCursorByRelayURL[relayURL] = @(seq);
        }
    }
}

// ---------------------------------------------------------------------------
// Durable Index Queue
// ---------------------------------------------------------------------------

- (BOOL)enqueueIndexEventForRelayURL:(NSString *)relayURL
                                  seq:(int64_t)seq
                            eventType:(NSString *)eventType
                                  did:(nullable NSString *)did
                                  rev:(nullable NSString *)rev
                                  cid:(nullable NSString *)cid
                          rawEnvelope:(NSData *)rawEnvelope
                                error:(NSError **)error {
    if (relayURL.length == 0 || eventType.length == 0 || !rawEnvelope) {
        if (error) *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:SQLITE_MISUSE
                                             userInfo:@{NSLocalizedDescriptionKey: @"Relay URL, event type, and envelope are required"}];
        return NO;
    }
    NSString *sql = @"INSERT OR IGNORE INTO appview_pending_index_events("
                    "relay_url, seq, event_type, did, rev, cid, raw_envelope, received_at) VALUES(?,?,?,?,?,?,?,?)";
    return [self executeParameterizedUpdate:sql params:@[
        relayURL, @(seq), eventType, did ?: [NSNull null], rev ?: [NSNull null],
        cid ?: [NSNull null], rawEnvelope, iso8601Now()
    ] error:error];
}

- (BOOL)appendAndEnqueueIndexEventForRelayURL:(NSString *)relayURL
                                           seq:(int64_t)seq
                                     eventType:(NSString *)eventType
                                           did:(nullable NSString *)did
                                           rev:(nullable NSString *)rev
                                           cid:(nullable NSString *)cid
                                   rawEnvelope:(NSData *)rawEnvelope
                                         error:(NSError **)error {
    NSError *innerError = nil;
    BOOL ok = [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **transactionError) {
        NSString *storedSQL =
            @"INSERT OR IGNORE INTO appview_cursor_events(event_type, seq, did, rev, cid, raw_envelope, created_at)"
            " VALUES(?,?,?,?,?,?,?)";
        NSArray *storedParams = @[
            eventType, @(seq), did ?: [NSNull null], rev ?: [NSNull null],
            cid ?: [NSNull null], rawEnvelope ?: [NSData data], iso8601Now()
        ];
        if (![tx executeUpdate:storedSQL params:storedParams error:transactionError]) return NO;

        NSString *pendingSQL = @"INSERT OR IGNORE INTO appview_pending_index_events("
                               "relay_url, seq, event_type, did, rev, cid, raw_envelope, received_at) VALUES(?,?,?,?,?,?,?,?)";
        return [tx executeUpdate:pendingSQL params:@[
            relayURL, @(seq), eventType, did ?: [NSNull null], rev ?: [NSNull null],
            cid ?: [NSNull null], rawEnvelope, iso8601Now()
        ] error:transactionError];
    } error:&innerError];
    if (!ok && error) *error = innerError;
    return ok;
}

- (nullable NSArray<NSDictionary *> *)claimIndexEventsForWorker:(NSString *)workerID
                                                            limit:(NSInteger)limit
                                                    leaseDuration:(NSTimeInterval)leaseDuration
                                                            error:(NSError **)error {
    if (workerID.length == 0 || limit <= 0 || leaseDuration <= 0) {
        if (error) *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:SQLITE_MISUSE
                                             userInfo:@{NSLocalizedDescriptionKey: @"Worker ID, positive limit, and lease duration are required"}];
        return nil;
    }
    NSString *now = iso8601Now();
    NSString *leaseUntil = [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSinceNow:leaseDuration]];
    __block NSArray<NSDictionary *> *claimed = nil;
    NSError *innerError = nil;
    BOOL ok = [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **transactionError) {
        NSArray<NSDictionary *> *candidates = [tx executeQuery:
            @"SELECT relay_url, seq, event_type, did, rev, cid, raw_envelope, attempts "
             "FROM appview_pending_index_events AS candidate "
             "WHERE candidate.indexed_at IS NULL AND candidate.terminal_error IS NULL "
             "AND (candidate.lease_expires_at IS NULL OR candidate.lease_expires_at <= ?) "
             "AND NOT EXISTS ("
             "  SELECT 1 FROM appview_pending_index_events AS earlier "
             "  WHERE earlier.relay_url = candidate.relay_url "
             "    AND earlier.seq < candidate.seq "
             "    AND earlier.indexed_at IS NULL"
             ") "
             "ORDER BY candidate.relay_url ASC, candidate.seq ASC LIMIT ?"
            params:@[now, @(limit)] error:transactionError];
        if (!candidates) return NO;
        NSMutableArray<NSDictionary *> *accepted = [NSMutableArray arrayWithCapacity:candidates.count];
        for (NSDictionary *candidate in candidates) {
            BOOL updated = [tx executeUpdate:
                @"UPDATE appview_pending_index_events SET lease_owner = ?, lease_expires_at = ?, attempts = attempts + 1 "
                 "WHERE relay_url = ? AND seq = ? AND indexed_at IS NULL AND terminal_error IS NULL "
                 "AND (lease_expires_at IS NULL OR lease_expires_at <= ?)"
                params:@[workerID, leaseUntil, candidate[@"relay_url"], candidate[@"seq"], now]
                error:transactionError];
            if (!updated) return NO;
            [accepted addObject:candidate];
        }
        claimed = [accepted copy];
        return YES;
    } error:&innerError];
    if (!ok) {
        if (error) *error = innerError;
        return nil;
    }
    return claimed;
}

- (BOOL)markIndexEventIndexedForRelayURL:(NSString *)relayURL
                                      seq:(int64_t)seq
                                workerID:(NSString *)workerID
                                   error:(NSError **)error {
    return [self executeParameterizedUpdate:
        @"UPDATE appview_pending_index_events SET indexed_at = ?, lease_owner = NULL, lease_expires_at = NULL "
         "WHERE relay_url = ? AND seq = ? AND lease_owner = ? AND indexed_at IS NULL AND terminal_error IS NULL"
        params:@[iso8601Now(), relayURL, @(seq), workerID] error:error];
}

- (BOOL)markIndexEventTerminalForRelayURL:(NSString *)relayURL
                                       seq:(int64_t)seq
                                 workerID:(NSString *)workerID
                                    error:(NSString *)message
                                   dbError:(NSError **)dbError {
    return [self executeParameterizedUpdate:
        @"UPDATE appview_pending_index_events SET terminal_error = ?, lease_owner = NULL, lease_expires_at = NULL "
         "WHERE relay_url = ? AND seq = ? AND lease_owner = ? AND indexed_at IS NULL"
        params:@[message ?: @"Unknown indexing error", relayURL, @(seq), workerID] error:dbError];
}

- (nullable NSDictionary<NSString *, NSNumber *> *)pendingIndexQueueMetricsForRelayURL:(NSString *)relayURL
                                                                                   error:(NSError **)error {
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:
        @"SELECT "
         "COALESCE(SUM(CASE WHEN indexed_at IS NULL AND terminal_error IS NULL THEN 1 ELSE 0 END), 0) AS event_count, "
         "COALESCE(SUM(CASE WHEN indexed_at IS NULL AND terminal_error IS NULL THEN LENGTH(raw_envelope) ELSE 0 END), 0) AS envelope_bytes, "
         "COALESCE(SUM(CASE WHEN terminal_error IS NOT NULL THEN 1 ELSE 0 END), 0) AS terminal_count "
         "FROM appview_pending_index_events "
         "WHERE relay_url = ?"
        params:@[relayURL] error:error];
    if (!rows) return nil;
    NSDictionary *row = rows.firstObject ?: @{};
    return @{
        @"event_count": row[@"event_count"] ?: @0,
        @"envelope_bytes": row[@"envelope_bytes"] ?: @0,
        @"terminal_count": row[@"terminal_count"] ?: @0,
    };
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
        @synchronized(self) {
            if (membership.isValid)
                [self->_relevanceCache addObject:membership.did];
            else
                [self->_relevanceCache removeObject:membership.did];
        }
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
    @synchronized(self) {
        return [self->_relevanceCache containsObject:did];
    }
}

- (NSInteger)pruneExpiredRelevanceMemberships:(NSError **)error {
    NSString *now = iso8601Now();
    NSString *sql = @"DELETE FROM appview_relevance WHERE expires_at IS NOT NULL AND expires_at <= ?";
    
    NSInteger deleted = [_queryRunner executeUpdate:sql params:@[now] error:error];

    @synchronized(self) {
        [self->_relevanceCache removeAllObjects];
        NSString *sel = @"SELECT did FROM appview_relevance WHERE expires_at IS NULL OR expires_at > ?";
        NSArray *rows = [self executeParameterizedQuery:sel params:@[now] error:nil];
        for (NSDictionary *row in rows) {
            NSString *did = row[@"did"];
            if (did) [self->_relevanceCache addObject:did];
        }
    }
    return deleted >= 0 ? deleted : 0;
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
    NSArray<NSDictionary *> *rows = [_queryRunner executeQuery:sql params:params error:error];
    NSMutableArray<NSDictionary *> *filtered = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *cleaned = [NSMutableDictionary dictionaryWithCapacity:row.count];
        [row enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if (![value isKindOfClass:[NSNull class]]) cleaned[key] = value;
        }];
        [filtered addObject:[cleaned copy]];
    }
    return [filtered copy];
}

- (BOOL)executeParameterizedUpdate:(NSString *)sql
                            params:(NSArray *)params
                             error:(NSError **)error {
    return [_queryRunner executeUpdate:sql params:params error:error] >= 0;
}

- (BOOL)executeUnsafeRawSQL:(NSString *)sql error:(NSError **)error {
    sqlite3 *conn = [_pool acquireConnection];
    if (!conn) {
        if (error) *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:SQLITE_MISUSE
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to acquire connection"}];
        return NO;
    }
    char *errmsg = NULL;
    int rc = sqlite3_exec(conn, sql.UTF8String, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:rc
                                     userInfo:@{NSLocalizedDescriptionKey: errmsg ? @(errmsg) : @"SQL failed"}];
        }
        if (errmsg) sqlite3_free(errmsg);
        [_pool releaseConnection:conn];
        return NO;
    }
    [_pool releaseConnection:conn];
    return YES;
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
    return [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        // Prepare temp table
        if (![tx executeUpdate:@"CREATE TEMP TABLE IF NOT EXISTS appview_snapshot_uris(uri TEXT PRIMARY KEY)"
                        params:@[] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM appview_snapshot_uris"
                        params:@[] error:innerError]) return NO;

        // Insert blocks
        NSString *insertBlockSQL = @"INSERT OR REPLACE INTO blocks(cid, repo_did, block_data, content_type, size, created_at) VALUES(?,?,?,?,?,?)";
        for (NSDictionary *block in blocks) {
            NSData *cidData = block[@"cid_data"];
            NSData *blockData = block[@"block_data"];
            if (![cidData isKindOfClass:[NSData class]] || ![blockData isKindOfClass:[NSData class]]) continue;
            NSString *contentType = block[@"content_type"] ?: @"application/cbor";

            NSArray *params = @[cidData, did, blockData, contentType, @(blockData.length), iso8601Now()];
            if (![tx executeUpdate:insertBlockSQL params:params error:innerError]) return NO;
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
            if (![tx executeUpdate:insertRecordSQL params:recordParams error:innerError]) return NO;
            if (![tx executeUpdate:insertURIToTempSQL params:@[uri] error:innerError]) return NO;
        }

        // Delete stale records
        NSString *deleteSQL = @"DELETE FROM records WHERE did = ? AND uri NOT IN (SELECT uri FROM appview_snapshot_uris)";
        if (![tx executeUpdate:deleteSQL params:@[did] error:innerError]) return NO;

        // Log snapshot event
        NSString *eventSQL = @"INSERT OR IGNORE INTO appview_cursor_events(event_type, seq, did, rev, cid, raw_envelope, created_at) VALUES('historical_snapshot', 0, ?, ?, ?, ?, ?)";
        NSData *rawEnvelope = [lastRev dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        NSArray *eventParams = @[did, lastRev, lastRev, rawEnvelope, iso8601Now()];
        if (![tx executeUpdate:eventSQL params:eventParams error:innerError]) return NO;

        // Update sync state
        NSString *upsertSQL =
            @"INSERT INTO appview_repo_sync_state(did, status, last_rev, last_backfill_at, error_count, last_error)"
            " VALUES(?,?,?,?,?,?)"
            " ON CONFLICT(did) DO UPDATE SET"
            "   status = excluded.status,"
            "   last_rev = excluded.last_rev,"
            "   last_backfill_at = excluded.last_backfill_at,"
            "   error_count = excluded.error_count,"
            "   last_error = excluded.last_error";
        NSArray *upsertParams = @[
            did,
            @(AppViewRepoSyncStatusSynced),
            lastRev,
            [NSDateFormatter atproto_stringFromDate:[NSDate date]],
            @0,
            [NSNull null]
        ];
        if (![tx executeUpdate:upsertSQL params:upsertParams error:innerError]) return NO;

        GZ_LOG_INFO(@"[AppView] Snapshot saved for %@", did);
        return YES;
    } error:error];
}

#pragma mark - Takedown Enforcement

- (BOOL)deleteRecordsForDID:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) *error = [NSError errorWithDomain:AppViewDatabaseErrorDomain code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"DID must not be nil or empty"}];
        return NO;
    }

    return [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        // Core record and block tables
        if (![tx executeUpdate:@"DELETE FROM records WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM blocks WHERE repo_did = ?"
                        params:@[did] error:innerError]) return NO;

        // Search indexes — actors use DID directly, posts and starter packs use URI
        if (![tx executeUpdate:@"DELETE FROM search_actors WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM search_posts WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM search_starter_packs WHERE did = ?"
                        params:@[did] error:innerError]) return NO;

        // Pending deltas and dead-letter rows
        if (![tx executeUpdate:@"DELETE FROM appview_pending_deltas WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM appview_dead_letter WHERE did = ?"
                        params:@[did] error:innerError]) return NO;

        // Domain-specific materialized tables
        NSString *uriPrefix = [NSString stringWithFormat:@"at://%@", did];
        if (![tx executeUpdate:@"DELETE FROM bsky_feed_generators WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM bsky_graph_lists WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM bsky_graph_listitems WHERE list_uri LIKE ? || '%' ESCAPE '\\'"
                        params:@[uriPrefix] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM bookmarks WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM starter_packs WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM groups WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM group_members WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM bsky_labeler_services WHERE did = ? OR labeler_did = ?"
                        params:@[did, did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM accounts WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM actor_preferences WHERE did = ?"
                        params:@[did] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM actor_mutes WHERE did = ?"
                        params:@[did] error:innerError]) return NO;

        // Threadgates and postgates reference records by URI
        if (![tx executeUpdate:@"DELETE FROM bsky_feed_threadgates WHERE uri LIKE ? || '%' ESCAPE '\\'"
                        params:@[uriPrefix] error:innerError]) return NO;
        if (![tx executeUpdate:@"DELETE FROM bsky_feed_postgates WHERE post_uri LIKE ? || '%' ESCAPE '\\'"
                        params:@[uriPrefix] error:innerError]) return NO;

        // Tombstone the repo sync state so backfill re-fetches on reinstatement
        NSString *upsertSQL =
            @"INSERT INTO appview_repo_sync_state(did, status, last_rev, last_backfill_at, error_count, last_error)"
            " VALUES(?,?,?,?,?,?)"
            " ON CONFLICT(did) DO UPDATE SET"
            "   status = excluded.status,"
            "   last_rev = excluded.last_rev,"
            "   last_backfill_at = excluded.last_backfill_at,"
            "   error_count = excluded.error_count,"
            "   last_error = excluded.last_error";
        NSArray *upsertParams = @[
            did,
            @(AppViewRepoSyncStatusDirty),
            [NSNull null],
            [NSNull null],
            @0,
            @"takendown"
        ];
        if (![tx executeUpdate:upsertSQL params:upsertParams error:innerError]) return NO;

        GZ_LOG_INFO(@"[AppView] Takedown enforcement: purged all data for %@", did);
        return YES;
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

- (BOOL)performWriteTransaction:(BOOL (^)(id<ATProtoDatabaseTransactor> tx, NSError **error))block
                          error:(NSError **)error {
    return [_queryRunner performWriteTransaction:block error:error];
}

@end
