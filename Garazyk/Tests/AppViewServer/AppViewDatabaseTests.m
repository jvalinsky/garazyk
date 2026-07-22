// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewDatabaseTests.m

 @abstract Unit tests for AppViewDatabase — schema, checkpoint persistence,
 repo sync state machine, pending deltas, event log idempotency, and
 relevance set membership.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import <sqlite3.h>
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"

@interface AppViewDatabase (MigrationTesting)

/// Test-only statement failure injection. Zero disables injection.
- (void)appView_setMigrationFailureForTestingVersion:(NSInteger)version
                                            statement:(NSInteger)statement;

- (NSInteger)appView_migrationStatementCountForTestingVersion:(NSInteger)version;

@end

static NSString *AppViewMigrationFixturePath(void) {
    NSString *name = [NSString stringWithFormat:@"appview-migration-%@.sqlite",
                       [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

static BOOL CreateLegacyAppViewFixture(NSString *path, NSError **error) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(path.UTF8String, &db,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                             NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppViewMigrationFixture"
                                         code:rc
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create legacy fixture"}];
        }
        if (db) sqlite3_close_v2(db);
        return NO;
    }

    const char *sql =
        "CREATE TABLE appview_checkpoints ("
        "relay_url TEXT NOT NULL PRIMARY KEY, seq INTEGER NOT NULL, saved_at TEXT NOT NULL"
        ");"
        "INSERT INTO appview_checkpoints(relay_url, seq, saved_at) "
        "VALUES('wss://legacy.relay', 4242, '2026-01-01T00:00:00.000Z');"
        "CREATE TABLE bsky_feed_threadgates ("
        "post_uri TEXT PRIMARY KEY, allow_json TEXT, created_at INTEGER, updated_at INTEGER"
        ");"
        "INSERT INTO bsky_feed_threadgates(post_uri, allow_json, created_at, updated_at) "
        "VALUES('at://did:plc:legacy/app.bsky.feed.post/one', '[]', 1, 1);";
    char *message = NULL;
    rc = sqlite3_exec(db, sql, NULL, NULL, &message);
    if (rc != SQLITE_OK && error) {
        NSString *description = message ? [NSString stringWithUTF8String:message]
                                        : @"Failed to populate legacy fixture";
        *error = [NSError errorWithDomain:@"AppViewMigrationFixture"
                                     code:rc
                                 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
    if (message) sqlite3_free(message);
    sqlite3_close_v2(db);
    return rc == SQLITE_OK;
}

static BOOL ExecuteAppViewFixtureSQL(NSString *path, const char *sql, NSError **error) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READWRITE, NULL);
    if (rc == SQLITE_OK) {
        char *message = NULL;
        rc = sqlite3_exec(db, sql, NULL, NULL, &message);
        if (rc != SQLITE_OK && error) {
            NSString *description = message ? [NSString stringWithUTF8String:message]
                                            : @"Failed to update legacy fixture";
            *error = [NSError errorWithDomain:@"AppViewMigrationFixture"
                                         code:rc
                                     userInfo:@{NSLocalizedDescriptionKey: description}];
        }
        if (message) sqlite3_free(message);
    } else if (error) {
        *error = [NSError errorWithDomain:@"AppViewMigrationFixture"
                                     code:rc
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to reopen legacy fixture"}];
    }
    if (db) sqlite3_close_v2(db);
    return rc == SQLITE_OK;
}

@interface AppViewDatabaseTests : XCTestCase
@property (nonatomic, strong) AppViewDatabase *db;
@end

@implementation AppViewDatabaseTests

- (void)setUp {
    [super setUp];
    NSError *err = nil;
    self.db = [[AppViewDatabase alloc] initInMemoryWithError:&err];
    XCTAssertNotNil(self.db, @"Failed to open in-memory AppViewDatabase: %@", err);
    XCTAssertTrue([self.db runMigrations:&err], @"Migrations failed: %@", err);
}

- (void)tearDown {
    [self.db close];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Checkpoint
// ---------------------------------------------------------------------------

- (void)testCheckpointRoundTrip {
    AppViewCheckpoint *cp = [[AppViewCheckpoint alloc]
        initWithRelayURL:@"wss://bsky.network" seq:12345];

    NSError *err = nil;
    XCTAssertTrue([self.db saveCheckpoint:cp error:&err], @"Save failed: %@", err);

    AppViewCheckpoint *loaded = [self.db loadCheckpointForRelayURL:@"wss://bsky.network" error:&err];
    XCTAssertNotNil(loaded);
    XCTAssertEqual(loaded.seq, 12345LL);
    XCTAssertEqualObjects(loaded.relayURL, @"wss://bsky.network");
}

- (void)testCheckpointUpsert {
    NSError *err = nil;
    AppViewCheckpoint *cp1 = [[AppViewCheckpoint alloc] initWithRelayURL:@"wss://test.relay" seq:100];
    AppViewCheckpoint *cp2 = [[AppViewCheckpoint alloc] initWithRelayURL:@"wss://test.relay" seq:200];

    XCTAssertTrue([self.db saveCheckpoint:cp1 error:&err]);
    XCTAssertTrue([self.db saveCheckpoint:cp2 error:&err]);

    AppViewCheckpoint *loaded = [self.db loadCheckpointForRelayURL:@"wss://test.relay" error:&err];
    XCTAssertEqual(loaded.seq, 200LL, @"Upsert should update to latest seq");
}

- (void)testCheckpointMissingReturnsNil {
    NSError *err = nil;
    AppViewCheckpoint *loaded = [self.db loadCheckpointForRelayURL:@"wss://nonexistent" error:&err];
    XCTAssertNil(loaded);
    XCTAssertNil(err);
}

// ---------------------------------------------------------------------------
// Migrations
// ---------------------------------------------------------------------------

- (void)testLegacyFileMigrationPersistsVersionsAndSurvivesReopen {
    NSString *path = AppViewMigrationFixturePath();
    NSError *error = nil;
    XCTAssertTrue(CreateLegacyAppViewFixture(path, &error), @"%@", error);

    AppViewDatabase *database = [[AppViewDatabase alloc] initWithPath:path error:&error];
    XCTAssertNotNil(database, @"%@", error);
    XCTAssertTrue([database runMigrations:&error], @"%@", error);

    NSArray *versions = [database executeParameterizedQuery:
        @"SELECT version FROM appview_schema_version ORDER BY version"
                                                       params:@[] error:&error];
    XCTAssertNotNil(versions, @"%@", error);
    XCTAssertEqual(versions.count, 3U);
    XCTAssertEqual([versions[0][@"version"] integerValue], 1);
    XCTAssertEqual([versions[1][@"version"] integerValue], 2);
    XCTAssertEqual([versions[2][@"version"] integerValue], 3);

    NSArray *columns = [database executeParameterizedQuery:
        @"PRAGMA table_info(bsky_feed_threadgates)"
                                                      params:@[] error:&error];
    XCTAssertNotNil(columns, @"%@", error);
    BOOL foundURI = NO;
    for (NSDictionary *column in columns) {
        if ([column[@"name"] isEqual:@"uri"]) foundURI = YES;
    }
    XCTAssertTrue(foundURI, @"Legacy threadgate table must gain uri");

    NSArray *indexes = [database executeParameterizedQuery:
        @"SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name IN ('idx_bsky_feed_threadgates_uri', 'idx_pending_deltas_did')"
                                                      params:@[] error:&error];
    XCTAssertNotNil(indexes, @"%@", error);
    XCTAssertEqual(indexes.count, 2U, @"Required migration indexes must exist");
    [database close];

    database = [[AppViewDatabase alloc] initWithPath:path error:&error];
    XCTAssertNotNil(database, @"%@", error);
    XCTAssertTrue([database runMigrations:&error], @"%@", error);

    AppViewCheckpoint *checkpoint = [database loadCheckpointForRelayURL:@"wss://legacy.relay"
                                                                    error:&error];
    XCTAssertNotNil(checkpoint, @"%@", error);
    XCTAssertEqual(checkpoint.seq, 4242LL);
    NSArray *threadgates = [database executeParameterizedQuery:
        @"SELECT post_uri FROM bsky_feed_threadgates WHERE post_uri = ?"
                                                          params:@[@"at://did:plc:legacy/app.bsky.feed.post/one"]
                                                           error:&error];
    XCTAssertNotNil(threadgates, @"%@", error);
    XCTAssertEqual(threadgates.count, 1U, @"Legacy data must survive reopen");

    versions = [database executeParameterizedQuery:
        @"SELECT version FROM appview_schema_version ORDER BY version"
                                           params:@[] error:&error];
    XCTAssertEqual(versions.count, 3U, @"Reopen must not record migrations twice");
    indexes = [database executeParameterizedQuery:
        @"SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name IN ('idx_bsky_feed_threadgates_uri', 'idx_pending_deltas_did')"
                                          params:@[] error:&error];
    XCTAssertEqual(indexes.count, 2U, @"Migration indexes must survive reopen");
    [database close];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (void)testEveryMigrationStatementFailureRollsBackSchemaAndVersion {
    for (NSNumber *versionNumber in @[@1, @2, @3]) {
        NSInteger version = versionNumber.integerValue;
        NSInteger statementCount = [self.db appView_migrationStatementCountForTestingVersion:version];
        XCTAssertGreaterThan(statementCount, 0, @"Migration %ld must contain statements", (long)version);

        for (NSInteger statement = 1; statement <= statementCount; statement++) {
            @autoreleasepool {
                NSString *path = AppViewMigrationFixturePath();
                NSError *error = nil;
                XCTAssertTrue(CreateLegacyAppViewFixture(path, &error), @"%@", error);

                AppViewDatabase *database = [[AppViewDatabase alloc] initWithPath:path error:&error];
                XCTAssertNotNil(database, @"%@", error);
                [database appView_setMigrationFailureForTestingVersion:version statement:statement];
                XCTAssertFalse([database runMigrations:&error],
                               @"Migration %ld statement %ld must fail",
                               (long)version, (long)statement);
                XCTAssertNotNil(error, @"Migration %ld statement %ld must report an error",
                                (long)version, (long)statement);

                NSArray *versionsTable = [database executeParameterizedQuery:
                    @"SELECT name FROM sqlite_master WHERE type = 'table' "
                    "AND name = 'appview_schema_version'"
                                                                       params:@[] error:nil];
                XCTAssertEqual(versionsTable.count, 0U,
                               @"Migration %ld statement %ld must leave no applied version",
                               (long)version, (long)statement);

                NSArray *columns = [database executeParameterizedQuery:
                    @"PRAGMA table_info(bsky_feed_threadgates)"
                                                              params:@[] error:nil];
                for (NSDictionary *column in columns) {
                    XCTAssertFalse([column[@"name"] isEqual:@"uri"],
                                   @"Migration %ld statement %ld must roll back uri",
                                   (long)version, (long)statement);
                }
                NSArray *indexes = [database executeParameterizedQuery:
                    @"SELECT name FROM sqlite_master WHERE type = 'index' "
                    "AND name = 'idx_bsky_feed_threadgates_uri'"
                                                              params:@[] error:nil];
                XCTAssertEqual(indexes.count, 0U,
                               @"Migration %ld statement %ld must roll back its index",
                               (long)version, (long)statement);

                AppViewCheckpoint *checkpoint = [database loadCheckpointForRelayURL:@"wss://legacy.relay"
                                                                                error:nil];
                XCTAssertNotNil(checkpoint,
                                @"Migration %ld statement %ld must retain legacy data",
                                (long)version, (long)statement);
                XCTAssertEqual(checkpoint.seq, 4242LL);
                [database close];
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            }
        }
    }
}

- (void)testNewerSchemaVersionFailsWithoutChangingLegacyFile {
    NSString *path = AppViewMigrationFixturePath();
    NSError *error = nil;
    XCTAssertTrue(CreateLegacyAppViewFixture(path, &error), @"%@", error);
    XCTAssertTrue(ExecuteAppViewFixtureSQL(path,
                                            "CREATE TABLE appview_schema_version(version INTEGER NOT NULL);"
                                            "INSERT INTO appview_schema_version(version) VALUES(4);",
                                            &error), @"%@", error);

    AppViewDatabase *database = [[AppViewDatabase alloc] initWithPath:path error:&error];
    XCTAssertNotNil(database, @"%@", error);
    XCTAssertFalse([database runMigrations:&error]);
    XCTAssertNotNil(error, @"Newer schema version must be rejected");

    NSArray *versions = [database executeParameterizedQuery:
        @"SELECT version FROM appview_schema_version"
                                                       params:@[] error:nil];
    XCTAssertEqual(versions.count, 1U);
    XCTAssertEqual([versions.firstObject[@"version"] integerValue], 4);
    NSArray *columns = [database executeParameterizedQuery:
        @"PRAGMA table_info(bsky_feed_threadgates)"
                                                      params:@[] error:nil];
    for (NSDictionary *column in columns) {
        XCTAssertFalse([column[@"name"] isEqual:@"uri"],
                       @"Newer-version failure must not apply pending migrations");
    }
    AppViewCheckpoint *checkpoint = [database loadCheckpointForRelayURL:@"wss://legacy.relay"
                                                                    error:nil];
    XCTAssertNotNil(checkpoint);
    XCTAssertEqual(checkpoint.seq, 4242LL);
    [database close];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

// ---------------------------------------------------------------------------
// Repo Sync State Machine
// ---------------------------------------------------------------------------

- (void)testRepoSyncStateRoundTrip {
    AppViewRepoSyncState *state = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:test1"];
    state.status     = AppViewRepoSyncStatusPending;
    state.errorCount = 0;

    NSError *err = nil;
    XCTAssertTrue([self.db upsertRepoSyncState:state error:&err]);

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:test1" error:&err];
    XCTAssertNotNil(loaded);
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusPending);
    XCTAssertEqual(loaded.errorCount, 0);
}

- (void)testMarkReposAsProcessing {
    NSArray<NSString *> *dids = @[@"did:plc:a", @"did:plc:b", @"did:plc:c"];
    NSError *err = nil;

    for (NSString *did in dids) {
        AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:did];
        [self.db upsertRepoSyncState:s error:nil];
    }

    NSArray<NSString *> *transitioned = [self.db markReposAsProcessing:dids error:&err];
    XCTAssertNil(err);
    XCTAssertEqual(transitioned.count, 3u, @"All three should transition");

    // Second call — all are now processing, none should transition
    NSArray<NSString *> *second = [self.db markReposAsProcessing:dids error:&err];
    XCTAssertEqual(second.count, 0u, @"Already processing — no transitions");
}

- (void)testMarkDirtyReposAsProcessing {
    NSError *err = nil;
    AppViewRepoSyncState *state = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:dirty-processing"];
    state.status = AppViewRepoSyncStatusDirty;
    XCTAssertTrue([self.db upsertRepoSyncState:state error:&err]);

    NSArray<NSString *> *transitioned = [self.db markReposAsProcessing:@[state.did] error:&err];
    XCTAssertNil(err);
    XCTAssertEqual(transitioned.count, 1u);

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:state.did error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusProcessing);
}

- (void)testMarkRepoSynced {
    NSError *err = nil;
    AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:synced"];
    [self.db upsertRepoSyncState:s error:nil];

    XCTAssertTrue([self.db markRepoSynced:@"did:plc:synced" lastRev:@"abc123" error:&err]);

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:synced" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusSynced);
    XCTAssertEqualObjects(loaded.lastRev, @"abc123");
    XCTAssertEqual(loaded.errorCount, 0);
}

- (void)testMarkRepoDirty {
    NSError *err = nil;
    AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:dirty"];
    s.status = AppViewRepoSyncStatusSynced;
    [self.db upsertRepoSyncState:s error:nil];

    XCTAssertTrue([self.db markRepoDirty:@"did:plc:dirty" error:&err]);
    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:dirty" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusDirty);
}

- (void)testRecordBackfillError {
    NSError *err = nil;
    AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:errors"];
    s.status = AppViewRepoSyncStatusProcessing;
    [self.db upsertRepoSyncState:s error:nil];

    [self.db recordBackfillError:@"did:plc:errors" message:@"HTTP 503" error:nil];
    [self.db recordBackfillError:@"did:plc:errors" message:@"timeout" error:nil];

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:errors" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusDirty);
    XCTAssertEqual(loaded.errorCount, 2);
    XCTAssertEqualObjects(loaded.lastError, @"timeout");
}

- (void)testLoadByStatusWithOrdering {
    NSError *err = nil;
    // Insert repos with different error counts
    for (NSInteger i = 0; i < 5; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:repo%ld", (long)i];
        AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:did];
        s.status = AppViewRepoSyncStatusDirty;
        [self.db upsertRepoSyncState:s error:nil];
        for (NSInteger j = 0; j < i; j++) {
            [self.db recordBackfillError:did message:@"err" error:nil];
        }
    }

    NSArray *dirty = [self.db loadRepoSyncStatesWithStatus:AppViewRepoSyncStatusDirty
                                                     limit:10 error:&err];
    XCTAssertEqual(dirty.count, 5u);
    // Ordered by error_count ASC
    XCTAssertEqual(((AppViewRepoSyncState *)dirty[0]).errorCount, 0);
    XCTAssertEqual(((AppViewRepoSyncState *)dirty[4]).errorCount, 4);
}

// ---------------------------------------------------------------------------
// Pending Deltas
// ---------------------------------------------------------------------------

- (void)testPendingDeltaEnqueueDequeue {
    NSError *err = nil;
    AppViewPendingDelta *d1 = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:x" seq:10 commitCID:@"cid1" rev:@"rev1"
        rawEnvelope:[NSData data]];
    AppViewPendingDelta *d2 = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:x" seq:20 commitCID:@"cid2" rev:@"rev2"
        rawEnvelope:[NSData data]];

    XCTAssertTrue([self.db enqueuePendingDelta:d1 error:&err]);
    XCTAssertTrue([self.db enqueuePendingDelta:d2 error:&err]);

    NSArray<AppViewPendingDelta *> *dequeued = [self.db dequeuePendingDeltasForDID:@"did:plc:x" error:&err];
    XCTAssertEqual(dequeued.count, 2u);
    XCTAssertEqual(dequeued[0].seq, 10LL, @"Should be ordered by seq ASC");
    XCTAssertEqual(dequeued[1].seq, 20LL);

    // After dequeue, count should be 0
    NSInteger count = [self.db countPendingDeltasForDID:@"did:plc:x" error:&err];
    XCTAssertEqual(count, 0);
}

- (void)testPendingDeltaIdempotency {
    AppViewPendingDelta *d = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:y" seq:5 commitCID:@"cid" rev:@"rev"
        rawEnvelope:[NSData data]];

    [self.db enqueuePendingDelta:d error:nil];
    [self.db enqueuePendingDelta:d error:nil]; // duplicate — should be ignored

    NSInteger count = [self.db countPendingDeltasForDID:@"did:plc:y" error:nil];
    XCTAssertEqual(count, 1, @"Duplicate (did, seq) should be silently ignored");
}

// ---------------------------------------------------------------------------
// Event Log Idempotency
// ---------------------------------------------------------------------------

- (void)testEventLogDeduplication {
    NSError *err = nil;
    NSData *envelope = [@"test" dataUsingEncoding:NSUTF8StringEncoding];

    BOOL ok1 = [self.db logEvent:100 did:@"did:plc:z" rev:@"rev1" cid:@"cid1"
                    rawEnvelope:envelope error:&err];
    XCTAssertTrue(ok1);

    // Same (did, rev, cid) — idempotent insert
    BOOL ok2 = [self.db logEvent:101 did:@"did:plc:z" rev:@"rev1" cid:@"cid1"
                    rawEnvelope:envelope error:&err];
    XCTAssertTrue(ok2, @"INSERT OR IGNORE should not fail");

    XCTAssertTrue([self.db hasEventWithDID:@"did:plc:z" rev:@"rev1" cid:@"cid1"]);
    XCTAssertFalse([self.db hasEventWithDID:@"did:plc:z" rev:@"rev999" cid:@"cid999"]);
}

- (void)testStoredEventsReplayAfterCursor {
    NSError *err = nil;
    NSData *raw = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

    XCTAssertTrue([self.db appendStoredEventWithType:@"historical_snapshot"
                                                seq:0
                                                did:@"did:plc:replay"
                                                rev:@"rev1"
                                                cid:@"cid1"
                                        rawEnvelope:raw
                                              error:&err]);
    XCTAssertTrue([self.db appendStoredEventWithType:@"live_commit"
                                                seq:42
                                                did:@"did:plc:replay"
                                                rev:@"rev2"
                                                cid:@"cid2"
                                        rawEnvelope:raw
                                              error:&err]);

    NSArray<NSDictionary *> *events = [self.db loadStoredEventsAfterCursor:0 limit:10 error:&err];
    XCTAssertNil(err);
    XCTAssertEqual(events.count, 2u);
    XCTAssertEqualObjects(events[0][@"event_type"], @"historical_snapshot");
    XCTAssertEqualObjects(events[1][@"event_type"], @"live_commit");

    NSNumber *firstCursor = events[0][@"cursor"];
    NSArray<NSDictionary *> *tail = [self.db loadStoredEventsAfterCursor:firstCursor.longLongValue limit:10 error:&err];
    XCTAssertEqual(tail.count, 1u);
    XCTAssertEqualObjects(tail[0][@"rev"], @"rev2");
}

- (void)testRepoSnapshotStoresGenericRecordsBlocksAndMarksSynced {
    NSError *err = nil;
    AppViewRepoSyncState *state = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:snapshot"];
    state.status = AppViewRepoSyncStatusProcessing;
    XCTAssertTrue([self.db upsertRepoSyncState:state error:&err]);

    NSData *cidData = [@"cid-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *blockData = [@"block" dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *records = @[
        @{
            @"uri": @"at://did:plc:snapshot/app.bsky.feed.post/one",
            @"collection": @"app.bsky.feed.post",
            @"rkey": @"one",
            @"cid": @"bafyone",
            @"value": @"{\"$type\":\"app.bsky.feed.post\",\"text\":\"hello\"}"
        }
    ];
    NSArray *blocks = @[
        @{@"cid_data": cidData, @"block_data": blockData}
    ];

    XCTAssertTrue([self.db saveRepoSnapshotForDID:@"did:plc:snapshot"
                                          lastRev:@"rev-snapshot"
                                          records:records
                                           blocks:blocks
                                            error:&err], @"Snapshot failed: %@", err);

    XCTAssertEqual([self.db getTotalRecordsCountForCollection:@"app.bsky.feed.post" error:&err], 1);
    XCTAssertEqual([self.db getTotalBlocksCountWithError:&err], 1);

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:snapshot" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusSynced);
    XCTAssertEqualObjects(loaded.lastRev, @"rev-snapshot");

    NSArray<NSDictionary *> *events = [self.db loadStoredEventsAfterCursor:0 limit:10 error:&err];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0][@"event_type"], @"historical_snapshot");
}

- (void)testDurableCursorOnlyAdvancesForward {
    [self.db markDurableCursor:100 forRelayURL:@"wss://relay"];
    [self.db markDurableCursor:90 forRelayURL:@"wss://relay"];
    XCTAssertEqual([self.db durableCursorForRelayURL:@"wss://relay"], 100LL);
}

- (void)testDurableIndexQueueClaimsOnceAndAcknowledges {
    NSError *error = nil;
    NSData *envelope = [@"event" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([self.db enqueueIndexEventForRelayURL:@"wss://relay" seq:42 eventType:@"#commit"
                                                    did:@"did:plc:queue" rev:@"rev" cid:@"cid"
                                            rawEnvelope:envelope error:&error], @"%@", error);
    XCTAssertTrue([self.db enqueueIndexEventForRelayURL:@"wss://relay" seq:42 eventType:@"#commit"
                                                    did:@"did:plc:queue" rev:@"rev" cid:@"cid"
                                            rawEnvelope:envelope error:&error], @"%@", error);

    NSArray<NSDictionary *> *first = [self.db claimIndexEventsForWorker:@"worker-a" limit:10 leaseDuration:60 error:&error];
    XCTAssertNotNil(first, @"%@", error);
    XCTAssertEqual(first.count, 1u);
    XCTAssertEqualObjects(first.firstObject[@"relay_url"], @"wss://relay");
    NSArray<NSDictionary *> *second = [self.db claimIndexEventsForWorker:@"worker-b" limit:10 leaseDuration:60 error:&error];
    XCTAssertEqual(second.count, 0u, @"An active lease must prevent a duplicate claim");
    XCTAssertTrue([self.db markIndexEventIndexedForRelayURL:@"wss://relay" seq:42 workerID:@"worker-a" error:&error], @"%@", error);
    NSArray<NSDictionary *> *afterAck = [self.db claimIndexEventsForWorker:@"worker-b" limit:10 leaseDuration:60 error:&error];
    XCTAssertEqual(afterAck.count, 0u, @"Indexed events must not be replayed");
}

- (void)testDurableIndexQueuePreservesPerRelayOrder {
    NSError *error = nil;
    NSData *envelope = [@"event" dataUsingEncoding:NSUTF8StringEncoding];
    for (int64_t seq = 100; seq <= 101; seq++) {
        XCTAssertTrue([self.db enqueueIndexEventForRelayURL:@"wss://relay" seq:seq eventType:@"#commit"
                                                        did:@"did:plc:ordered" rev:@"rev" cid:@"cid"
                                                rawEnvelope:envelope error:&error], @"%@", error);
    }

    NSArray<NSDictionary *> *first = [self.db claimIndexEventsForWorker:@"worker-a" limit:10 leaseDuration:60 error:&error];
    XCTAssertEqual(first.count, 1u, @"Only the head event may be claimed for a relay");
    XCTAssertEqual([first.firstObject[@"seq"] longLongValue], 100LL);
    XCTAssertTrue([self.db markIndexEventIndexedForRelayURL:@"wss://relay" seq:100 workerID:@"worker-a" error:&error], @"%@", error);

    NSArray<NSDictionary *> *second = [self.db claimIndexEventsForWorker:@"worker-a" limit:10 leaseDuration:60 error:&error];
    XCTAssertEqual(second.count, 1u);
    XCTAssertEqual([second.firstObject[@"seq"] longLongValue], 101LL);
}

// ---------------------------------------------------------------------------
// Relevance Set
// ---------------------------------------------------------------------------

- (void)testRelevancePermanentMembership {
    AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
        initWithDID:@"did:plc:seed" reason:AppViewRelevanceReasonSeed expiresAt:nil];

    NSError *err = nil;
    XCTAssertTrue([self.db upsertRelevanceMembership:m error:&err]);
    XCTAssertTrue([self.db isDIDRelevant:@"did:plc:seed"]);
    XCTAssertFalse([self.db isDIDRelevant:@"did:plc:unknown"]);
}

- (void)testRelevanceExpiredMembership {
    NSDate *pastDate = [NSDate dateWithTimeIntervalSinceNow:-3600]; // 1 hour ago
    AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
        initWithDID:@"did:plc:expired"
             reason:AppViewRelevanceReasonRecentInteraction
          expiresAt:pastDate];

    NSError *err = nil;
    [self.db upsertRelevanceMembership:m error:&err];

    // The membership is inserted but should be treated as expired
    // (isDIDRelevant relies on the DB cache which checks validity)
    // After pruning, it should be gone
    [self.db pruneExpiredRelevanceMemberships:&err];
    XCTAssertFalse([self.db isDIDRelevant:@"did:plc:expired"], @"Expired membership should be removed by prune");
}

- (void)testRelevancePruneCount {
    NSDate *past  = [NSDate dateWithTimeIntervalSinceNow:-7200];
    NSDate *future = [NSDate dateWithTimeIntervalSinceNow:7200];

    NSError *err = nil;
    for (NSInteger i = 0; i < 5; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:expired%ld", (long)i];
        AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
            initWithDID:did reason:AppViewRelevanceReasonFollowOfSeed expiresAt:past];
        [self.db upsertRelevanceMembership:m error:&err];
    }
    // One permanent entry that should survive
    AppViewRelevanceMembership *permanent = [[AppViewRelevanceMembership alloc]
        initWithDID:@"did:plc:permanent" reason:AppViewRelevanceReasonSeed expiresAt:nil];
    [self.db upsertRelevanceMembership:permanent error:&err];

    // One future-expiring entry
    AppViewRelevanceMembership *future_m = [[AppViewRelevanceMembership alloc]
        initWithDID:@"did:plc:future" reason:AppViewRelevanceReasonFollowOfSeed expiresAt:future];
    [self.db upsertRelevanceMembership:future_m error:&err];

    NSInteger pruned = [self.db pruneExpiredRelevanceMemberships:&err];
    XCTAssertEqual(pruned, 5, @"Exactly 5 expired entries should be removed");
    XCTAssertTrue([self.db isDIDRelevant:@"did:plc:permanent"]);
    XCTAssertTrue([self.db isDIDRelevant:@"did:plc:future"]);
}

// ---------------------------------------------------------------------------
// Dead Letter
// ---------------------------------------------------------------------------

- (void)testDeadLetterInsertion {
    NSError *err = nil;
    NSData *rawRecord = [@"{\"$type\":\"app.bsky.feed.post\"}" dataUsingEncoding:NSUTF8StringEncoding];

    BOOL ok = [self.db recordDeadLetterEvent:@"app.bsky.feed.post"
                                         seq:999
                                         did:@"did:plc:bad"
                                         rev:@"rev1"
                                         cid:@"cid1"
                                   rawRecord:rawRecord
                             validationError:@"Missing text field"
                                       error:&err];
    XCTAssertTrue(ok, @"Dead letter insert should succeed: %@", err);
}

@end
