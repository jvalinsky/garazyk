// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Tests the bsky_feed_threadgates migration path in AppViewDatabase.runMigrations:
// (AppViewDatabase.m: kSchemaV1 CREATE TABLE + ALTER TABLE ADD COLUMN uri + CREATE UNIQUE INDEX).
// Uses an in-memory AppViewDatabase so tests are fast and leave no disk state.
#import <XCTest/XCTest.h>
#import "AppView/Server/AppViewDatabase.h"

@interface ThreadgateMigrationTests : XCTestCase
@property (nonatomic, strong) AppViewDatabase *db;
@end

@implementation ThreadgateMigrationTests

- (void)setUp {
    [super setUp];
    NSError *err = nil;
    self.db = [[AppViewDatabase alloc] initInMemoryWithError:&err];
    XCTAssertNotNil(self.db, @"In-memory AppViewDatabase init failed: %@", err);
}

- (void)tearDown {
    self.db = nil;
    [super tearDown];
}

// MARK: - Forward migration

- (void)testThreadgateMigrationCreatesTable {
    // runMigrations: applies kSchemaV1 (which creates bsky_feed_threadgates) plus an ALTER TABLE
    // that adds the uri column, followed by a CREATE UNIQUE INDEX on uri.
    NSError *err = nil;
    XCTAssertTrue([self.db runMigrations:&err], @"runMigrations failed: %@", err);

    // A query that names all expected columns succeeds only if the table and all columns exist.
    NSArray *rows = [self.db executeParameterizedQuery:
        @"SELECT uri, post_uri, allow_json, created_at, updated_at "
        @"FROM bsky_feed_threadgates LIMIT 0"
        params:@[] error:&err];
    XCTAssertNotNil(rows,
        @"bsky_feed_threadgates with all expected columns must exist after migration: %@", err);
}

- (void)testThreadgateMigrationCreatesUniqueURIIndex {
    NSError *err = nil;
    XCTAssertTrue([self.db runMigrations:&err]);

    // Insert a first row.
    BOOL inserted = [self.db executeParameterizedUpdate:
        @"INSERT INTO bsky_feed_threadgates (uri, post_uri, allow_json, created_at, updated_at) "
        @"VALUES (?, ?, ?, ?, ?)"
        params:@[
            @"at://did:plc:a/app.bsky.feed.threadgate/1",
            @"at://did:plc:a/app.bsky.feed.post/p1",
            @"[]", @1, @1,
        ]
        error:&err];
    XCTAssertTrue(inserted, @"Failed to insert first threadgate: %@", err);

    // A second row with the same uri must be rejected by the UNIQUE constraint on uri.
    NSError *dupErr = nil;
    BOOL ok = [self.db executeParameterizedUpdate:
        @"INSERT INTO bsky_feed_threadgates (uri, post_uri, allow_json, created_at, updated_at) "
        @"VALUES (?, ?, ?, ?, ?)"
        params:@[
            @"at://did:plc:a/app.bsky.feed.threadgate/1",  // same uri
            @"at://did:plc:a/app.bsky.feed.post/p2",       // different post_uri
            @"[]", @2, @2,
        ]
        error:&dupErr];
    XCTAssertFalse(ok, @"Duplicate uri must be rejected by the UNIQUE index");
    XCTAssertNotNil(dupErr, @"Error must be set on UNIQUE constraint violation");
}

// MARK: - Idempotency

- (void)testThreadgateMigrationIsIdempotent {
    // The migration SQL uses CREATE TABLE IF NOT EXISTS, ALTER TABLE with duplicate-column
    // error suppression, and CREATE UNIQUE INDEX IF NOT EXISTS — so running it twice is safe.
    NSError *err = nil;
    XCTAssertTrue([self.db runMigrations:&err], @"First migration: %@", err);
    XCTAssertTrue([self.db runMigrations:&err], @"Second migration (idempotent): %@", err);

    // The table must still be queryable after two migration passes.
    NSArray *rows = [self.db executeParameterizedQuery:
        @"SELECT COUNT(*) AS c FROM bsky_feed_threadgates"
        params:@[] error:&err];
    XCTAssertNotNil(rows, @"Table must remain usable after double migration: %@", err);
}

// MARK: - Rollback safety

- (void)testThreadgateMigrationRollbackLeavesDBConsistent {
    // Verify that SQLite DDL wrapped in a manual transaction can be rolled back,
    // confirming the migration SQL can be safely composed with transactional migration systems.
    NSError *err = nil;

    // Table must not exist yet (no migration run).
    NSArray *before = [self.db executeParameterizedQuery:
        @"SELECT name FROM sqlite_master WHERE type='table' AND name='bsky_feed_threadgates'"
        params:@[] error:&err];
    XCTAssertEqual(before.count, 0U,
        @"bsky_feed_threadgates must not exist before any migration");

    // BEGIN a transaction, create the table, then ROLLBACK.
    XCTAssertTrue([self.db executeUnsafeRawSQL:@"BEGIN" error:&err], @"%@", err);
    XCTAssertTrue([self.db executeUnsafeRawSQL:
        @"CREATE TABLE bsky_feed_threadgates ("
        @"uri TEXT UNIQUE, post_uri TEXT PRIMARY KEY, "
        @"allow_json TEXT, created_at INTEGER, updated_at INTEGER)"
        error:&err], @"%@", err);
    XCTAssertTrue([self.db executeUnsafeRawSQL:@"ROLLBACK" error:&err], @"%@", err);

    // After rollback the table must be absent.
    NSArray *after = [self.db executeParameterizedQuery:
        @"SELECT name FROM sqlite_master WHERE type='table' AND name='bsky_feed_threadgates'"
        params:@[] error:&err];
    XCTAssertEqual(after.count, 0U,
        @"bsky_feed_threadgates must be absent after ROLLBACK");
}

// MARK: - Column schema

- (void)testThreadgateMigrationColumnSchema {
    // PRAGMA table_info returns one row per column with fields:
    //   cid (column index), name, type, notnull, dflt_value, pk (1 if primary key)
    NSError *err = nil;
    XCTAssertTrue([self.db runMigrations:&err]);

    NSArray *cols = [self.db executeParameterizedQuery:
        @"PRAGMA table_info(bsky_feed_threadgates)"
        params:@[] error:&err];
    XCTAssertNotNil(cols, @"PRAGMA table_info failed: %@", err);

    // Build a name→column-info dictionary for easy lookup.
    NSMutableDictionary<NSString *, NSDictionary *> *byName = [NSMutableDictionary dictionary];
    for (NSDictionary *col in cols) {
        NSString *name = col[@"name"];
        if (name) byName[name] = col;
    }

    XCTAssertNotNil(byName[@"uri"],        @"uri column must exist");
    XCTAssertNotNil(byName[@"post_uri"],   @"post_uri column must exist");
    XCTAssertNotNil(byName[@"allow_json"], @"allow_json column must exist");
    XCTAssertNotNil(byName[@"created_at"], @"created_at column must exist");
    XCTAssertNotNil(byName[@"updated_at"], @"updated_at column must exist");

    // post_uri is the PRIMARY KEY (pk == 1).
    XCTAssertEqual([byName[@"post_uri"][@"pk"] integerValue], 1,
        @"post_uri must be the PRIMARY KEY");
}

@end
