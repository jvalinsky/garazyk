// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Database/Migrations/PDSMigrationManager.h"
#import "Database/Schema.h"
#import "Chat/Server/Config/ChatSchemaManager.h"
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

@end
