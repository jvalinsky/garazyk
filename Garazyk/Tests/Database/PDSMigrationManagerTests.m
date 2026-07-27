// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Database/Migrations/PDSMigrationManager.h"
#import "Database/Schema.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Chat/Server/Config/ChatSchemaManager.h"
#import "Core/CID.h"
#import <sqlite3.h>

static void PDSMigrationTestExecute(sqlite3 *db, const char *sql) {
    char *message = NULL;
    int result = sqlite3_exec(db, sql, NULL, NULL, &message);
    NSString *description = message ? [NSString stringWithUTF8String:message] : @"unknown SQLite error";
    if (message) sqlite3_free(message);
    XCTAssertEqual(result, SQLITE_OK, @"SQL failed: %s (%@)", sql, description);
}

static BOOL PDSMigrationTestTableUsesWithoutRowid(sqlite3 *db, const char *tableName) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", -1, &statement, NULL) != SQLITE_OK) return NO;
    sqlite3_bind_text(statement, 1, tableName, -1, SQLITE_STATIC);
    BOOL usesWithoutRowid = NO;
    if (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *sql = sqlite3_column_text(statement, 0);
        usesWithoutRowid = sql && [[NSString stringWithUTF8String:(const char *)sql]
            rangeOfString:@"WITHOUT ROWID" options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    sqlite3_finalize(statement);
    return usesWithoutRowid;
}

static NSString *PDSMigrationTestTableSQL(sqlite3 *db, const char *tableName) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", -1, &statement, NULL) != SQLITE_OK) return nil;
    sqlite3_bind_text(statement, 1, tableName, -1, SQLITE_STATIC);
    NSString *sql = nil;
    if (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *value = sqlite3_column_text(statement, 0);
        if (value) sql = [NSString stringWithUTF8String:(const char *)value];
    }
    sqlite3_finalize(statement);
    return sql;
}

static NSInteger PDSMigrationTestRowCount(sqlite3 *db, const char *tableName) {
    NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %s", tableName];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) return -1;
    NSInteger count = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : -1;
    sqlite3_finalize(statement);
    return count;
}

static BOOL PDSMigrationTestIndexExists(sqlite3 *db, const char *indexName) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?", -1, &statement, NULL) != SQLITE_OK) return NO;
    sqlite3_bind_text(statement, 1, indexName, -1, SQLITE_STATIC);
    BOOL exists = sqlite3_step(statement) == SQLITE_ROW;
    sqlite3_finalize(statement);
    return exists;
}

static BOOL PDSMigrationTestTableExists(sqlite3 *db, const char *tableName) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", -1, &statement, NULL) != SQLITE_OK) return NO;
    sqlite3_bind_text(statement, 1, tableName, -1, SQLITE_STATIC);
    BOOL exists = sqlite3_step(statement) == SQLITE_ROW;
    sqlite3_finalize(statement);
    return exists;
}

static BOOL PDSMigrationTestTriggerExists(sqlite3 *db, const char *triggerName) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = ?", -1, &statement, NULL) != SQLITE_OK) return NO;
    sqlite3_bind_text(statement, 1, triggerName, -1, SQLITE_STATIC);
    BOOL exists = sqlite3_step(statement) == SQLITE_ROW;
    sqlite3_finalize(statement);
    return exists;
}

static NSString *PDSMigrationTestObjectSQL(sqlite3 *db, const char *type, const char *name) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type = ? AND name = ?", -1, &statement, NULL) != SQLITE_OK) return nil;
    sqlite3_bind_text(statement, 1, type, -1, SQLITE_STATIC);
    sqlite3_bind_text(statement, 2, name, -1, SQLITE_STATIC);
    NSString *sql = nil;
    if (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(statement, 0);
        if (text) sql = [NSString stringWithUTF8String:(const char *)text];
    }
    sqlite3_finalize(statement);
    return sql;
}

static BOOL PDSMigrationTestQueryPlanUsesIndex(sqlite3 *db, const char *sql, const char *indexName) {
    NSString *explain = [NSString stringWithFormat:@"EXPLAIN QUERY PLAN %s", sql];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, explain.UTF8String, -1, &statement, NULL) != SQLITE_OK) return NO;
    BOOL usesIndex = NO;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *detail = sqlite3_column_text(statement, 3);
        if (detail && [[NSString stringWithUTF8String:(const char *)detail]
            rangeOfString:[NSString stringWithUTF8String:indexName]].location != NSNotFound) {
            usesIndex = YES;
            break;
        }
    }
    sqlite3_finalize(statement);
    return usesIndex;
}

@interface PDSMigrationManagerTests : XCTestCase
@end

@implementation PDSMigrationManagerTests

- (NSString *)createSourceDatabaseWithAccounts:(BOOL)includeAccount {
    NSString *dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"migration-source-%@.db", [[NSUUID UUID] UUIDString]]];
    sqlite3 *db = NULL;
    XCTAssertEqual(SQLITE_OK, sqlite3_open(dbPath.UTF8String, &db));

    const char *schema[] = {
        "CREATE TABLE accounts (did TEXT, handle TEXT, email TEXT, password_hash BLOB, password_salt BLOB, access_jwt BLOB, refresh_jwt BLOB, created_at REAL, updated_at REAL);",
        "CREATE TABLE repos (owner_did TEXT, root_cid BLOB, collection_data BLOB, created_at REAL, updated_at REAL);",
        "CREATE TABLE records (uri TEXT, did TEXT, collection TEXT, rkey TEXT, cid TEXT, created_at REAL);",
        "CREATE TABLE blocks (cid BLOB, repo_did TEXT, block_data BLOB, content_type TEXT, size INTEGER, created_at REAL);"
    };
    for (NSUInteger i = 0; i < sizeof(schema) / sizeof(schema[0]); i++) {
        char *err = NULL;
        XCTAssertEqual(SQLITE_OK, sqlite3_exec(db, schema[i], NULL, NULL, &err));
        if (err) {
            sqlite3_free(err);
        }
    }

    if (includeAccount) {
        const char *insertAccount =
            "INSERT INTO accounts (did, handle, email, created_at, updated_at) VALUES ('did:plc:test1', 'test.example', 'a@example.com', 1, 1);";
        char *err = NULL;
        XCTAssertEqual(SQLITE_OK, sqlite3_exec(db, insertAccount, NULL, NULL, &err));
        if (err) {
            sqlite3_free(err);
        }
    }

    sqlite3_close(db);
    return dbPath;
}

- (void)testSharedManagerReturnsSameInstance {
    PDSMigrationManager *a = [PDSMigrationManager sharedManager];
    PDSMigrationManager *b = [PDSMigrationManager sharedManager];
    XCTAssertEqual(a, b);
}

- (void)testEstimatedMigrateTimeUsesFileSizeInMiB {
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"migration-size-%@.db", [[NSUUID UUID] UUIDString]]];
    NSMutableData *data = [NSMutableData dataWithLength:(2 * 1024 * 1024) + 123];
    XCTAssertTrue([data writeToFile:tmpPath atomically:YES]);

    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSUInteger estimate = [manager estimatedMigrateTimeWithSourcePath:tmpPath];
    XCTAssertEqual(estimate, (NSUInteger)2);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

- (void)testMigrateFromMissingSourceReturnsSourceNotFound {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSString *missingPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"missing-%@.db", [[NSUUID UUID] UUIDString]]];
    NSError *error = nil;
    BOOL ok = [manager migrateFromMonolithicDatabase:missingPath
                             toSingleTenantDirectory:NSTemporaryDirectory()
                                               error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqualObjects(error.domain, PDSMigrationErrorDomain);
    XCTAssertEqual(error.code, PDSMigrationErrorSourceNotFound);
}

- (void)testMigrateAsyncInvokesCompletionWithErrorForMissingSource {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSString *missingPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"missing-async-%@.db", [[NSUUID UUID] UUIDString]]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    __block NSError *completionError = nil;

    [manager migrateFromMonolithicDatabaseAsync:missingPath
                        toSingleTenantDirectory:NSTemporaryDirectory()
                                     completion:^(NSError * _Nullable error) {
        completionError = error;
        [expectation fulfill];
    }];

    [self waitForExpectations:@[expectation] timeout:2.0];
    XCTAssertNotNil(completionError);
    XCTAssertEqualObjects(completionError.domain, PDSMigrationErrorDomain);
    XCTAssertEqual(completionError.code, PDSMigrationErrorSourceNotFound);
}

- (void)testMigrateEmptyDatabaseSucceedsAndReportsCompletionProgress {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSString *sourcePath = [self createSourceDatabaseWithAccounts:NO];
    NSString *destination = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"migration-dest-%@", [[NSUUID UUID] UUIDString]]];
    __block double lastProgress = 0.0;
    __block NSString *lastStatus = nil;
    XCTestExpectation *progressExpectation = [self expectationWithDescription:@"progress complete"];
    manager.progressBlock = ^(double progress, NSString *status) {
        lastProgress = progress;
        lastStatus = status;
        if (progress >= 1.0) {
            [progressExpectation fulfill];
        }
    };

    NSError *error = nil;
    BOOL ok = [manager migrateFromMonolithicDatabase:sourcePath toSingleTenantDirectory:destination error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    [self waitForExpectations:@[progressExpectation] timeout:2.0];
    XCTAssertEqual(lastProgress, 1.0);
    XCTAssertEqualObjects(lastStatus, @"Migration complete");

    [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
}

- (void)testMigrateCancellationReturnsCancelledError {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSString *sourcePath = [self createSourceDatabaseWithAccounts:YES];
    NSString *destination = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"migration-cancel-%@", [[NSUUID UUID] UUIDString]]];
    manager.cancelBlock = ^BOOL{
        return YES;
    };

    NSError *error = nil;
    BOOL ok = [manager migrateFromMonolithicDatabase:sourcePath toSingleTenantDirectory:destination error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSMigrationErrorDomain);
    XCTAssertEqual(error.code, PDSMigrationErrorCancelled);

    [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
}

- (void)testFreshChatSchemasUseWithoutRowid {
    NSArray<NSString *> *schemas = @[
        kPDSConversationMembersTableCreateSQL,
        kPDSMessageReactionsTableCreateSQL,
        kPDSGroupMembersTableCreateSQL,
        kPDSGroupMessageReactionsTableCreateSQL,
        kPDSCollectionMembershipTableCreateSQL,
    ];
    for (NSString *schema in schemas) {
        XCTAssertNotEqual([schema rangeOfString:@"WITHOUT ROWID" options:NSCaseInsensitiveSearch].location,
                          NSNotFound, @"Fresh schema must use WITHOUT ROWID: %@", schema);
    }
    ChatSchemaManager *chatSchema = [ChatSchemaManager sharedManager];
    XCTAssertNotEqual([[chatSchema conversationMembersTableSchema] rangeOfString:@"WITHOUT ROWID"].location, NSNotFound);
    XCTAssertNotEqual([[chatSchema messageReactionsTableSchema] rangeOfString:@"WITHOUT ROWID"].location, NSNotFound);
}

- (void)testRecordsRevisionIndexMigrationIsCoveringAndReversible {
    sqlite3 *db = NULL;
    XCTAssertEqual(SQLITE_OK, sqlite3_open(":memory:", &db));
    PDSMigrationTestExecute(db, "CREATE TABLE _migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at REAL NOT NULL)");
    for (NSInteger version = 1; version <= 4; version++) {
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO _migrations VALUES (%ld, 'seed', 0)", (long)version];
        PDSMigrationTestExecute(db, sql.UTF8String);
    }
    PDSMigrationTestExecute(db, "CREATE TABLE records (uri TEXT PRIMARY KEY, did TEXT NOT NULL, rev TEXT, value BLOB)");
    PDSMigrationTestExecute(db, "INSERT INTO records VALUES ('at://did:plc:alice/app.bsky.feed.post/one', 'did:plc:alice', '3jzfcijpj2z2a', NULL)");
    // V6 dependency tables: minimal empty shapes so the blob lifecycle migration
    // can run after V5 without failing on missing tables.
    PDSMigrationTestExecute(db, "CREATE TABLE ipld_blocks (cid BLOB PRIMARY KEY, block BLOB NOT NULL, size INTEGER NOT NULL, rev TEXT)");
    PDSMigrationTestExecute(db, "CREATE TABLE blobs (cid BLOB PRIMARY KEY, did TEXT NOT NULL, mimeType TEXT, size INTEGER NOT NULL, created_at DATETIME NOT NULL)");
    PDSMigrationTestExecute(db, "CREATE TABLE rotation_keys (did TEXT PRIMARY KEY)");
    PDSMigrationTestExecute(db, "CREATE TABLE signing_keys (did TEXT PRIMARY KEY)");

    PDSMigrationManager *manager = [PDSMigrationManager actorStoreMigrationManager];
    NSError *error = nil;
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_records_rev"));
    XCTAssertTrue(PDSMigrationTestQueryPlanUsesIndex(db,
        "SELECT rev FROM records WHERE rev IS NOT NULL ORDER BY rev DESC LIMIT 1", "idx_records_rev"));
    XCTAssertNotEqual([[[PDSSchemaManager sharedManager] actorStoreSchemaSQL] rangeOfString:@"idx_records_rev"].location, NSNotFound);
    XCTAssertTrue([manager rollbackToVersion:db version:4 error:&error], @"%@", error);
    XCTAssertFalse(PDSMigrationTestIndexExists(db, "idx_records_rev"));
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_records_rev"));
    sqlite3_close(db);
}

- (void)testLegacyChatMigrationRoundTripPreservesRowsAndIndexes {
    sqlite3 *db = NULL;
    XCTAssertEqual(SQLITE_OK, sqlite3_open(":memory:", &db));
    PDSMigrationTestExecute(db, "PRAGMA foreign_keys = ON");
    PDSMigrationTestExecute(db, "CREATE TABLE _migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at REAL NOT NULL)");
    PDSMigrationTestExecute(db, "INSERT INTO _migrations VALUES (10, 'legacy_schema_bridge', 0), (11, 'legacy_column_additions', 0)");
    PDSMigrationTestExecute(db, "CREATE TABLE conversations (id TEXT PRIMARY KEY)");
    PDSMigrationTestExecute(db, "CREATE TABLE messages (id TEXT PRIMARY KEY)");
    PDSMigrationTestExecute(db, "CREATE TABLE groups (uri TEXT PRIMARY KEY)");
    PDSMigrationTestExecute(db, "CREATE TABLE group_messages (id TEXT PRIMARY KEY)");
    PDSMigrationTestExecute(db, "INSERT INTO conversations VALUES ('convo-1')");
    PDSMigrationTestExecute(db, "INSERT INTO messages VALUES ('message-1')");
    PDSMigrationTestExecute(db, "INSERT INTO groups VALUES ('at://group/1')");
    PDSMigrationTestExecute(db, "INSERT INTO group_messages VALUES ('group-message-1')");
    PDSMigrationTestExecute(db, "CREATE TABLE conversation_members (convo_id TEXT NOT NULL, member_did TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', muted INTEGER DEFAULT 0, last_read_id TEXT, joined_at TEXT NOT NULL, PRIMARY KEY (convo_id, member_did), FOREIGN KEY (convo_id) REFERENCES conversations(id) ON DELETE CASCADE)");
    PDSMigrationTestExecute(db, "CREATE TABLE message_reactions (message_id TEXT NOT NULL, actor_did TEXT NOT NULL, emoji TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY (message_id, actor_did, emoji), FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE)");
    PDSMigrationTestExecute(db, "CREATE TABLE group_members (group_uri TEXT NOT NULL, member_did TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'member', status TEXT NOT NULL DEFAULT 'accepted', invited_by TEXT, joined_at TEXT NOT NULL, PRIMARY KEY (group_uri, member_did))");
    PDSMigrationTestExecute(db, "CREATE TABLE group_message_reactions (message_id TEXT NOT NULL, actor_did TEXT NOT NULL, emoji TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY (message_id, actor_did, emoji), FOREIGN KEY (message_id) REFERENCES group_messages(id))");
    PDSMigrationTestExecute(db, "INSERT INTO conversation_members VALUES ('convo-1', 'did:plc:alice', 'accepted', 1, 'message-1', '2026-01-01T00:00:00Z')");
    PDSMigrationTestExecute(db, "INSERT INTO message_reactions VALUES ('message-1', 'did:plc:bob', '👍', '2026-01-01T00:00:00Z')");
    PDSMigrationTestExecute(db, "INSERT INTO group_members VALUES ('at://group/1', 'did:plc:alice', 'admin', 'accepted', NULL, '2026-01-01T00:00:00Z')");
    PDSMigrationTestExecute(db, "INSERT INTO group_message_reactions VALUES ('group-message-1', 'did:plc:bob', '🔥', '2026-01-01T00:00:00Z')");

    PDSMigrationManager *manager = [PDSMigrationManager pdsDatabaseMigrationManager];
    NSError *error = nil;
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);
    const char *tables[] = { "conversation_members", "message_reactions", "group_members", "group_message_reactions" };
    for (NSUInteger i = 0; i < sizeof(tables) / sizeof(tables[0]); i++) {
        XCTAssertTrue(PDSMigrationTestTableUsesWithoutRowid(db, tables[i]));
        XCTAssertEqual(PDSMigrationTestRowCount(db, tables[i]), (NSInteger)1);
    }
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_conversation_members_convo"));
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_conversation_members_actor"));
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_group_members_group"));
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_group_members_member"));
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "conversation_members") rangeOfString:@"DEFAULT 'pending'"].location, NSNotFound);
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "conversation_members") rangeOfString:@"ON DELETE CASCADE"].location, NSNotFound);
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "message_reactions") rangeOfString:@"ON DELETE CASCADE"].location, NSNotFound);
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "group_members") rangeOfString:@"DEFAULT 'member'"].location, NSNotFound);
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "group_members") rangeOfString:@"DEFAULT 'accepted'"].location, NSNotFound);
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "group_message_reactions") rangeOfString:@"FOREIGN KEY (message_id)"].location, NSNotFound);
    XCTAssertTrue([manager rollbackToVersion:db version:11 error:&error], @"%@", error);
    for (NSUInteger i = 0; i < sizeof(tables) / sizeof(tables[0]); i++) {
        XCTAssertFalse(PDSMigrationTestTableUsesWithoutRowid(db, tables[i]));
        XCTAssertEqual(PDSMigrationTestRowCount(db, tables[i]), (NSInteger)1);
    }
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);
    for (NSUInteger i = 0; i < sizeof(tables) / sizeof(tables[0]); i++) {
        XCTAssertTrue(PDSMigrationTestTableUsesWithoutRowid(db, tables[i]));
        XCTAssertEqual(PDSMigrationTestRowCount(db, tables[i]), (NSInteger)1);
    }
    sqlite3_close(db);
}

- (void)testCollectionMembershipMigrationRoundTripPreservesRowsAndIndex {
    sqlite3 *db = NULL;
    XCTAssertEqual(SQLITE_OK, sqlite3_open(":memory:", &db));
    PDSMigrationTestExecute(db, "CREATE TABLE _migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at REAL NOT NULL)");
    for (NSInteger version = 1; version <= 14; version++) {
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO _migrations VALUES (%ld, 'seed', 0)", (long)version];
        PDSMigrationTestExecute(db, sql.UTF8String);
    }
    PDSMigrationTestExecute(db, "CREATE TABLE collection_membership (did TEXT NOT NULL, collection TEXT NOT NULL, indexed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), PRIMARY KEY (did, collection))");
    PDSMigrationTestExecute(db, "INSERT INTO collection_membership VALUES ('did:plc:alice', 'app.bsky.feed.post', '2026-01-01T00:00:00Z')");

    PDSMigrationManager *manager = [PDSMigrationManager serviceDatabaseMigrationManager];
    NSError *error = nil;
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);
    XCTAssertTrue(PDSMigrationTestTableUsesWithoutRowid(db, "collection_membership"));
    XCTAssertEqual(PDSMigrationTestRowCount(db, "collection_membership"), (NSInteger)1);
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_collection_membership_collection"));
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "collection_membership") rangeOfString:@"DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))"].location, NSNotFound);
    XCTAssertTrue([manager rollbackToVersion:db version:14 error:&error], @"%@", error);
    XCTAssertFalse(PDSMigrationTestTableUsesWithoutRowid(db, "collection_membership"));
    XCTAssertEqual(PDSMigrationTestRowCount(db, "collection_membership"), (NSInteger)1);
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);
    XCTAssertTrue(PDSMigrationTestTableUsesWithoutRowid(db, "collection_membership"));
    XCTAssertEqual(PDSMigrationTestRowCount(db, "collection_membership"), (NSInteger)1);
    sqlite3_close(db);
}

static NSString *PDSMigrationTestHexLiteral(NSData *data) {
    NSMutableString *hex = [NSMutableString stringWithString:@"X'"];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    [hex appendString:@"'"];
    return hex;
}

- (nullable NSString *)pds_columnTextFromTable:(sqlite3 *)db sql:(NSString *)sql {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) return nil;
    NSString *value = nil;
    if (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(statement, 0);
        if (text) value = [NSString stringWithUTF8String:(const char *)text];
    }
    sqlite3_finalize(statement);
    return value;
}

// Phase 15 slice 1: apply/rollback/re-apply coverage for V6BlobLifecycleSchema.
// Verifies rows, indexes, the blob_refs foreign key, and the blobs.state
// default all survive a round trip, and that the migration's backfill pass
// correctly classifies a blob a record already references as 'referenced'
// (rather than leaving it 'temporary' and wrongly eligible for the
// slice-5 sweep).
- (void)testBlobLifecycleMigrationRoundTripPreservesRowsIndexesAndBackfillsState {
    sqlite3 *db = NULL;
    XCTAssertEqual(SQLITE_OK, sqlite3_open(":memory:", &db));
    PDSMigrationTestExecute(db, "CREATE TABLE _migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at REAL NOT NULL)");
    for (NSInteger version = 1; version <= 5; version++) {
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO _migrations VALUES (%ld, 'seed', 0)", (long)version];
        PDSMigrationTestExecute(db, sql.UTF8String);
    }

    // Pre-v6 shapes: no lifecycle state on blobs or blob_refs join table.
    PDSMigrationTestExecute(db, "CREATE TABLE ipld_blocks (cid BLOB PRIMARY KEY, block BLOB NOT NULL, size INTEGER NOT NULL, rev TEXT)");
    PDSMigrationTestExecute(db, "CREATE TABLE blobs (cid BLOB PRIMARY KEY, did TEXT NOT NULL, mimeType TEXT, size INTEGER NOT NULL, created_at DATETIME NOT NULL)");
    PDSMigrationTestExecute(db, "CREATE TABLE records (uri TEXT PRIMARY KEY, did TEXT NOT NULL, value BLOB)");

    NSString *did = @"did:plc:alice";
    CID *commitCID = [CID sha256:[@"initial-commit-block" dataUsingEncoding:NSUTF8StringEncoding]];
    PDSMigrationTestExecute(db, [NSString stringWithFormat:
        @"INSERT INTO ipld_blocks (cid, block, size, rev) VALUES (%@, X'01', 1, 'rev1')",
        PDSMigrationTestHexLiteral(commitCID.bytes)].UTF8String);

    CID *referencedBlobCID = [CID sha256:[@"referenced-blob-bytes" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *temporaryBlobCID = [CID sha256:[@"temporary-blob-bytes" dataUsingEncoding:NSUTF8StringEncoding]];
    PDSMigrationTestExecute(db, [NSString stringWithFormat:
        @"INSERT INTO blobs (cid, did, mimeType, size, created_at) VALUES (%@, '%@', 'image/png', 100, '2026-01-01T00:00:00Z')",
        PDSMigrationTestHexLiteral(referencedBlobCID.bytes), did].UTF8String);
    PDSMigrationTestExecute(db, [NSString stringWithFormat:
        @"INSERT INTO blobs (cid, did, mimeType, size, created_at) VALUES (%@, '%@', 'image/png', 50, '2026-01-01T00:00:00Z')",
        PDSMigrationTestHexLiteral(temporaryBlobCID.bytes), did].UTF8String);

    NSString *recordURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/one", did];
    NSDictionary *recordValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"hello",
        @"embed": @{@"$type": @"blob", @"ref": @{@"$link": referencedBlobCID.stringValue}, @"mimeType": @"image/png", @"size": @100}
    };
    NSData *recordJSON = [NSJSONSerialization dataWithJSONObject:recordValue options:0 error:nil];
    PDSMigrationTestExecute(db, [NSString stringWithFormat:
        @"INSERT INTO records (uri, did, value) VALUES ('%@', '%@', %@)",
        recordURI, did, PDSMigrationTestHexLiteral(recordJSON)].UTF8String);

    PDSMigrationManager *manager = [PDSMigrationManager actorStoreMigrationManager];
    NSError *error = nil;
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);

    // Rows preserved.
    XCTAssertEqual(PDSMigrationTestRowCount(db, "ipld_blocks"), (NSInteger)1);
    XCTAssertEqual(PDSMigrationTestRowCount(db, "blobs"), (NSInteger)2);

    // Indexes present.
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_blobs_state"));
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_blob_refs_blob_cid"));
    XCTAssertTrue(PDSMigrationTestIndexExists(db, "idx_blob_refs_record_uri"));

    // Foreign key and default preserved.
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "blob_refs") rangeOfString:@"REFERENCES blobs(cid)"].location, NSNotFound);
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "blobs") rangeOfString:@"DEFAULT 'temporary'"].location, NSNotFound);

    // The already-referenced blob is promoted; the untouched one stays temporary.
    NSString *referencedState = [self pds_columnTextFromTable:db sql:
        [NSString stringWithFormat:@"SELECT state FROM blobs WHERE cid = %@", PDSMigrationTestHexLiteral(referencedBlobCID.bytes)]];
    NSString *temporaryState = [self pds_columnTextFromTable:db sql:
        [NSString stringWithFormat:@"SELECT state FROM blobs WHERE cid = %@", PDSMigrationTestHexLiteral(temporaryBlobCID.bytes)]];
    XCTAssertEqualObjects(referencedState, @"referenced");
    XCTAssertEqualObjects(temporaryState, @"temporary");

    // blob_refs links exactly the referenced record/blob pair.
    XCTAssertEqual(PDSMigrationTestRowCount(db, "blob_refs"), (NSInteger)1);
    NSString *linkedURI = [self pds_columnTextFromTable:db sql:@"SELECT record_uri FROM blob_refs LIMIT 1"];
    XCTAssertEqualObjects(linkedURI, recordURI);

    // Roll back: lifecycle state and blob_refs are removed while rows remain.
    XCTAssertTrue([manager rollbackToVersion:db version:5 error:&error], @"%@", error);
    XCTAssertEqual([PDSMigrationTestTableSQL(db, "blobs") rangeOfString:@"state"].location, (NSUInteger)NSNotFound);
    XCTAssertNil(PDSMigrationTestTableSQL(db, "blob_refs"));
    XCTAssertEqual(PDSMigrationTestRowCount(db, "ipld_blocks"), (NSInteger)1);
    XCTAssertEqual(PDSMigrationTestRowCount(db, "blobs"), (NSInteger)2);

    // Re-apply: everything comes back, backfill re-runs correctly.
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);
    XCTAssertEqual(PDSMigrationTestRowCount(db, "ipld_blocks"), (NSInteger)1);
    XCTAssertEqual(PDSMigrationTestRowCount(db, "blobs"), (NSInteger)2);
    XCTAssertEqual(PDSMigrationTestRowCount(db, "blob_refs"), (NSInteger)1);
    referencedState = [self pds_columnTextFromTable:db sql:
        [NSString stringWithFormat:@"SELECT state FROM blobs WHERE cid = %@", PDSMigrationTestHexLiteral(referencedBlobCID.bytes)]];
    XCTAssertEqualObjects(referencedState, @"referenced");

    sqlite3_close(db);
}

// Phase 15 slice 2: apply/rollback/re-apply coverage for V7AccountUsageTriggers.
// Verifies that account_usage is created, all six triggers fire, and the
// backfill aggregates existing blobs/ipld_blocks/records into account_usage
// so consumers (XrpcVendorPack, XrpcAdminPack+AccountInfo) see non-zero
// values immediately after migration.
- (void)testAccountUsageTriggersMigrationRoundTripBackfillsAndInstallsTriggers {
    sqlite3 *db = NULL;
    XCTAssertEqual(SQLITE_OK, sqlite3_open(":memory:", &db));
    PDSMigrationTestExecute(db, "CREATE TABLE _migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at REAL NOT NULL)");
    for (NSInteger version = 1; version <= 6; version++) {
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO _migrations VALUES (%ld, 'seed', 0)", (long)version];
        PDSMigrationTestExecute(db, sql.UTF8String);
    }

    // V6 post-state: blobs has lifecycle state and blob_refs exists.
    NSString *did = @"did:plc:alice";
    PDSMigrationTestExecute(db, "CREATE TABLE ipld_blocks (cid BLOB PRIMARY KEY, block BLOB NOT NULL, size INTEGER NOT NULL, rev TEXT)");
    PDSMigrationTestExecute(db, "INSERT INTO ipld_blocks VALUES (X'aabb', X'01', 512, 'rev1')");
    PDSMigrationTestExecute(db, "INSERT INTO ipld_blocks VALUES (X'bbcc', X'02', 256, 'rev1')");

    PDSMigrationTestExecute(db, "CREATE TABLE blobs (cid BLOB PRIMARY KEY, did TEXT NOT NULL, mimeType TEXT, size INTEGER NOT NULL, created_at DATETIME NOT NULL, state TEXT NOT NULL DEFAULT 'temporary')");
    PDSMigrationTestExecute(db, [NSString stringWithFormat:@"INSERT INTO blobs VALUES (X'ddee', '%@', 'image/png', 2048, '2026-01-01T00:00:00Z', 'referenced')", did].UTF8String);
    PDSMigrationTestExecute(db, [NSString stringWithFormat:@"INSERT INTO blobs VALUES (X'eeff', '%@', 'image/jpeg', 1024, '2026-01-02T00:00:00Z', 'temporary')", did].UTF8String);

    PDSMigrationTestExecute(db, "CREATE TABLE records (uri TEXT PRIMARY KEY, did TEXT NOT NULL, value BLOB)");
    PDSMigrationTestExecute(db, [NSString stringWithFormat:@"INSERT INTO records VALUES ('at://%@/app.bsky.feed.post/1', '%@', NULL)", did, did].UTF8String);
    PDSMigrationTestExecute(db, [NSString stringWithFormat:@"INSERT INTO records VALUES ('at://%@/app.bsky.feed.post/2', '%@', NULL)", did, did].UTF8String);
    PDSMigrationTestExecute(db, [NSString stringWithFormat:@"INSERT INTO records VALUES ('at://%@/app.bsky.feed.post/3', '%@', NULL)", did, did].UTF8String);

    PDSMigrationTestExecute(db, "CREATE TABLE blob_refs (record_uri TEXT NOT NULL, blob_cid BLOB NOT NULL, did TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY (record_uri, blob_cid)) WITHOUT ROWID");
    PDSMigrationTestExecute(db, kPDSAccountUsageTableCreateSQL.UTF8String);
    PDSMigrationTestExecute(db, [NSString stringWithFormat:@"INSERT INTO account_usage (did, blob_bytes, blob_count, repo_bytes, record_count) VALUES ('%@', 1, 1, 1, 1)", did].UTF8String);

    PDSMigrationManager *manager = [PDSMigrationManager actorStoreMigrationManager];
    NSError *error = nil;
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);

    // account_usage table created and backfilled.
    XCTAssertTrue(PDSMigrationTestTableExists(db, "account_usage"));
    NSString *usageBlobBytes = [self pds_columnTextFromTable:db sql:@"SELECT blob_bytes FROM account_usage WHERE did = 'did:plc:alice'"];
    XCTAssertEqualObjects(usageBlobBytes, @"3072"); // 2048 + 1024
    NSString *usageBlobCount = [self pds_columnTextFromTable:db sql:@"SELECT blob_count FROM account_usage WHERE did = 'did:plc:alice'"];
    XCTAssertEqualObjects(usageBlobCount, @"2");
    NSString *usageRepoBytes = [self pds_columnTextFromTable:db sql:@"SELECT repo_bytes FROM account_usage WHERE did = 'did:plc:alice'"];
    XCTAssertEqualObjects(usageRepoBytes, @"768"); // 512 + 256
    NSString *usageRecordCount = [self pds_columnTextFromTable:db sql:@"SELECT record_count FROM account_usage WHERE did = 'did:plc:alice'"];
    XCTAssertEqualObjects(usageRecordCount, @"3");

    // All six canonical trigger definitions are installed verbatim.
    XCTAssertTrue(PDSMigrationTestTriggerExists(db, "trg_account_usage_blob_insert"));
    XCTAssertTrue(PDSMigrationTestTriggerExists(db, "trg_account_usage_blob_delete"));
    XCTAssertTrue(PDSMigrationTestTriggerExists(db, "trg_account_usage_block_insert"));
    XCTAssertTrue(PDSMigrationTestTriggerExists(db, "trg_account_usage_block_delete"));
    XCTAssertTrue(PDSMigrationTestTriggerExists(db, "trg_account_usage_record_insert"));
    XCTAssertTrue(PDSMigrationTestTriggerExists(db, "trg_account_usage_record_delete"));
    NSDictionary<NSString *, NSString *> *canonicalTriggerSQL = @{
        @"trg_account_usage_blob_insert": kPDSAccountUsageTriggerBlobInsertSQL,
        @"trg_account_usage_blob_delete": kPDSAccountUsageTriggerBlobDeleteSQL,
        @"trg_account_usage_block_insert": kPDSAccountUsageTriggerBlockInsertSQL,
        @"trg_account_usage_block_delete": kPDSAccountUsageTriggerBlockDeleteSQL,
        @"trg_account_usage_record_insert": kPDSAccountUsageTriggerRecordInsertSQL,
        @"trg_account_usage_record_delete": kPDSAccountUsageTriggerRecordDeleteSQL,
    };
    [canonicalTriggerSQL enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *sql, BOOL *stop) {
        // SQLite normalizes CREATE TRIGGER by omitting IF NOT EXISTS in
        // sqlite_master. Compare the remaining definition exactly, which
        // still proves V7 executed the canonical constant rather than a
        // migration-local copy.
        NSString *normalizedSQL = [sql stringByReplacingOccurrencesOfString:@"CREATE TRIGGER IF NOT EXISTS "
                                                                  withString:@"CREATE TRIGGER "];
        XCTAssertEqualObjects(PDSMigrationTestObjectSQL(db, "trigger", name.UTF8String), normalizedSQL, @"%@ differs from its canonical schema definition", name);
    }];

    // Trigger fire: insert a new blob and verify counter incremented.
    PDSMigrationTestExecute(db, [NSString stringWithFormat:@"INSERT INTO blobs VALUES (X'1122', '%@', 'image/png', 100, '2026-01-03T00:00:00Z', 'temporary')", did].UTF8String);
    NSString *afterInsertBlobCount = [self pds_columnTextFromTable:db sql:@"SELECT blob_count FROM account_usage WHERE did = 'did:plc:alice'"];
    XCTAssertEqualObjects(afterInsertBlobCount, @"3");
    NSString *afterInsertBlobBytes = [self pds_columnTextFromTable:db sql:@"SELECT blob_bytes FROM account_usage WHERE did = 'did:plc:alice'"];
    XCTAssertEqualObjects(afterInsertBlobBytes, @"3172"); // 3072 + 100

    // Roll back removes the V7-installed triggers but preserves the pre-existing
    // account_usage table, its defaults, and the backfilled rows.
    XCTAssertTrue([manager rollbackToVersion:db version:6 error:&error], @"%@", error);
    XCTAssertTrue(PDSMigrationTestTableExists(db, "account_usage"));
    XCTAssertFalse(PDSMigrationTestTriggerExists(db, "trg_account_usage_blob_insert"));
    XCTAssertFalse(PDSMigrationTestTriggerExists(db, "trg_account_usage_block_insert"));
    XCTAssertNotEqual([PDSMigrationTestTableSQL(db, "account_usage") rangeOfString:@"DEFAULT 0"].location, NSNotFound);
    XCTAssertEqualObjects([self pds_columnTextFromTable:db sql:@"SELECT blob_bytes FROM account_usage WHERE did = 'did:plc:alice'"], @"3172");

    // Re-apply: everything restored, backfill re-runs.
    XCTAssertTrue([manager migrateDatabase:db error:&error], @"%@", error);
    XCTAssertTrue(PDSMigrationTestTableExists(db, "account_usage"));
    // Now has 3 blobs (the trigger-created one persisted via INSERT into blobs).
    NSString *reapplyBlobCount = [self pds_columnTextFromTable:db sql:@"SELECT blob_count FROM account_usage WHERE did = 'did:plc:alice'"];
    XCTAssertEqualObjects(reapplyBlobCount, @"3");
    NSString *reapplyBlobBytes = [self pds_columnTextFromTable:db sql:@"SELECT blob_bytes FROM account_usage WHERE did = 'did:plc:alice'"];
    XCTAssertEqualObjects(reapplyBlobBytes, @"3172");

    sqlite3_close(db);
}

@end
