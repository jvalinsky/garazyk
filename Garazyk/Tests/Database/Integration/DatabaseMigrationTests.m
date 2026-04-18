#import <XCTest/XCTest.h>
#import "Database/Integration/PDSDatabaseIntegrationTestUtilities.h"
#import "Database/Migrations/PDSMigrationManager.h"
#import <sqlite3.h>

@interface DatabaseMigrationTests : XCTestCase

@property (nonatomic, strong) PDSMigrationTestFixture *fixture;

@end

@implementation DatabaseMigrationTests

- (void)setUp {
    [super setUp];

    self.fixture = [[PDSMigrationTestFixture alloc] initWithTestName:@"DatabaseMigrationTests"];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture setupDatabaseWithError:&error], @"Failed to setup migration test fixture: %@", error);
}

- (void)tearDown {
    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture teardownDatabaseWithError:&error], @"Failed to teardown migration test fixture: %@", error);
    self.fixture = nil;
    [super tearDown];
}

#pragma mark - Migration Execution Tests

/// Tests successful end-to-end migration execution with valid monolithic database
/// This test verifies that the migration manager can successfully process a well-formed
/// monolithic database containing accounts, repos, records, and blocks, transforming it
/// into the new single-tenant directory structure. It ensures the migration completes
/// without errors and creates the expected output directory.
- (void)testSuccessfulMigrationExecution {
    // Create a test database with standard schema and sample data
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_success"];

    // Execute migration and verify it completes successfully
    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture testMigrationWithSourcePath:sourcePath destinationDirectory:destinationDir error:&error],
                 @"Migration should succeed with valid monolithic database: %@", error);

    // Verify the migration created the expected output directory structure
    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm fileExistsAtPath:destinationDir], @"Destination directory should exist after migration");

    // Cleanup temporary files
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

/// Tests migration behavior when the source database is corrupted
/// This test verifies that the migration manager properly handles corrupted
/// or invalid SQLite databases, failing gracefully and providing appropriate
/// error information without crashing or causing data corruption.
- (void)testMigrationWithCorruptedDatabase {
    // Create a file that appears to be a database but contains invalid data
    NSString *tempDir = NSTemporaryDirectory();
    NSString *corruptedPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"corrupted_%@.db", [[NSUUID UUID] UUIDString]]];

    // Write some garbage data to simulate a corrupted database
    NSString *garbageData = @"This is not a valid SQLite database file. Just some random text.";
    XCTAssertTrue([garbageData writeToFile:corruptedPath atomically:YES encoding:NSUTF8StringEncoding error:nil]);

    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_corrupted"];

    // Execute migration and verify it fails appropriately
    __autoreleasing NSError *error = nil;
    XCTAssertFalse([self.fixture testMigrationWithSourcePath:corruptedPath destinationDirectory:destinationDir error:&error],
                  @"Migration should fail with corrupted database");

    // Verify proper error reporting
    XCTAssertNotNil(error, @"Error should be provided for corrupted database");

    // Cleanup
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:corruptedPath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

/// Tests migration behavior when the database file is truncated or incomplete
/// This test verifies handling of partially written database files that may
/// occur due to interrupted writes or disk space issues.
- (void)testMigrationWithTruncatedDatabase {
    // Create a valid database then truncate it to simulate partial corruption
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_truncated"];

    // Truncate the database file to half its size
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attributes = [fm attributesOfItemAtPath:sourcePath error:nil];
    unsigned long long originalSize = [attributes[NSFileSize] unsignedLongLongValue];

    NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:sourcePath];
    [fileHandle truncateFileAtOffset:originalSize / 2];
    [fileHandle closeFile];

    // Execute migration and verify it fails gracefully
    __autoreleasing NSError *error = nil;
    XCTAssertFalse([self.fixture testMigrationWithSourcePath:sourcePath destinationDirectory:destinationDir error:&error],
                  @"Migration should fail with truncated database");

    // Verify proper error reporting
    XCTAssertNotNil(error, @"Error should be provided for truncated database");

    // Cleanup
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

#pragma mark - Helper Methods

/// Creates the standard monolithic database schema tables
/// @param db The SQLite database to create tables in
- (void)createMonolithicDatabaseSchema:(sqlite3 *)db {
    // Create tables matching the expected monolithic schema
    const char *createTablesSQL[] = {
        "CREATE TABLE accounts (did TEXT PRIMARY KEY, handle TEXT, email TEXT, password_hash BLOB, password_salt BLOB, access_jwt BLOB, refresh_jwt BLOB, created_at REAL, updated_at REAL)",
        "CREATE TABLE repos (owner_did TEXT, root_cid BLOB, collection_data BLOB, created_at REAL, updated_at REAL)",
        "CREATE TABLE records (uri TEXT, did TEXT, collection TEXT, rkey TEXT, cid TEXT, created_at REAL)",
        "CREATE TABLE blocks (cid BLOB, repo_did TEXT, block_data BLOB, content_type TEXT, size INTEGER, created_at REAL)",
        NULL
    };

    for (int i = 0; createTablesSQL[i] != NULL; i++) {
        XCTAssertEqual(sqlite3_exec(db, createTablesSQL[i], NULL, NULL, NULL), SQLITE_OK,
                      @"Should be able to create table %d", i);
    }
}

/// Creates a temporary monolithic database with test data
/// @return Path to the created database file
- (NSString *)createTestMonolithicDatabase {
    // Create a temporary monolithic database with test data
    NSString *tempDir = NSTemporaryDirectory();
    NSString *dbPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"monolithic_test_%@.db", [[NSUUID UUID] UUIDString]]];

    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([dbPath UTF8String], &db), SQLITE_OK, @"Should be able to create test database");

    // Create standard schema and insert test data
    [self createMonolithicDatabaseSchema:db];
    [self insertTestDataIntoDatabase:db];

    sqlite3_close(db);
    return dbPath;
}

- (NSString *)createEmptyMonolithicDatabase {
    // Create a temporary empty monolithic database
    NSString *tempDir = NSTemporaryDirectory();
    NSString *dbPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"monolithic_empty_%@.db", [[NSUUID UUID] UUIDString]]];

    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([dbPath UTF8String], &db), SQLITE_OK, @"Should be able to create empty test database");

    // Create standard schema but don't insert any data
    [self createMonolithicDatabaseSchema:db];

    sqlite3_close(db);
    return dbPath;
}

- (NSString *)createTestMonolithicDatabaseWithMultipleRecords {
    // Create a database with multiple accounts, repos, records, and blocks
    NSString *tempDir = NSTemporaryDirectory();
    NSString *dbPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"monolithic_multi_%@.db", [[NSUUID UUID] UUIDString]]];

    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([dbPath UTF8String], &db), SQLITE_OK, @"Should be able to create multi-record test database");

    // Create standard schema and insert multiple test records
    [self createMonolithicDatabaseSchema:db];
    [self insertMultipleTestDataIntoDatabase:db];

    sqlite3_close(db);
    return dbPath;
}

- (void)insertTestDataIntoDatabase:(sqlite3 *)db {
    // Insert sample account
    const char *insertAccountSQL = "INSERT INTO accounts (did, handle, email, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt;
    XCTAssertEqual(sqlite3_prepare_v2(db, insertAccountSQL, -1, &stmt, NULL), SQLITE_OK);

    sqlite3_bind_text(stmt, 1, "did:plc:test123", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, "test.example.com", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, "test@example.com", -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 4, [[NSDate date] timeIntervalSince1970]);
    sqlite3_bind_double(stmt, 5, [[NSDate date] timeIntervalSince1970]);

    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    // Insert sample repo
    const char *insertRepoSQL = "INSERT INTO repos (owner_did, created_at, updated_at) VALUES (?, ?, ?)";
    XCTAssertEqual(sqlite3_prepare_v2(db, insertRepoSQL, -1, &stmt, NULL), SQLITE_OK);

    sqlite3_bind_text(stmt, 1, "did:plc:test123", -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);
    sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);

    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    // Insert sample record
    const char *insertRecordSQL = "INSERT INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    XCTAssertEqual(sqlite3_prepare_v2(db, insertRecordSQL, -1, &stmt, NULL), SQLITE_OK);

    sqlite3_bind_text(stmt, 1, "at://did:plc:test123/app.bsky.feed.post/test123", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, "did:plc:test123", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, "app.bsky.feed.post", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, "test123", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, "bafyreih5v3k4z5n5q5q5q5q5q5q5q5q5q5q5q5q5q5q5q5q5q5q5q5q5q", -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 6, [[NSDate date] timeIntervalSince1970]);

    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    // Insert sample block
    const char *insertBlockSQL = "INSERT INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    XCTAssertEqual(sqlite3_prepare_v2(db, insertBlockSQL, -1, &stmt, NULL), SQLITE_OK);

    NSData *testData = [@"test block data" dataUsingEncoding:NSUTF8StringEncoding];
    sqlite3_bind_blob(stmt, 1, testData.bytes, (int)testData.length, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, "did:plc:test123", -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 3, testData.bytes, (int)testData.length, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, "text/plain", -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 5, testData.length);
    sqlite3_bind_double(stmt, 6, [[NSDate date] timeIntervalSince1970]);

    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);
}

- (void)insertMultipleTestDataIntoDatabase:(sqlite3 *)db {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    // Insert multiple accounts
    NSArray *accounts = @[
        @{@"did": @"did:plc:user1", @"handle": @"user1.example.com", @"email": @"user1@example.com"},
        @{@"did": @"did:plc:user2", @"handle": @"user2.example.com", @"email": @"user2@example.com"},
        @{@"did": @"did:plc:user3", @"handle": @"user3.example.com", @"email": @"user3@example.com"}
    ];

    for (NSDictionary *account in accounts) {
        const char *insertAccountSQL = "INSERT INTO accounts (did, handle, email, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt;
        XCTAssertEqual(sqlite3_prepare_v2(db, insertAccountSQL, -1, &stmt, NULL), SQLITE_OK);

        sqlite3_bind_text(stmt, 1, [account[@"did"] UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [account[@"handle"] UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [account[@"email"] UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, now);
        sqlite3_bind_double(stmt, 5, now);

        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
        sqlite3_finalize(stmt);

        // Insert repo for each account
        const char *insertRepoSQL = "INSERT INTO repos (owner_did, created_at, updated_at) VALUES (?, ?, ?)";
        XCTAssertEqual(sqlite3_prepare_v2(db, insertRepoSQL, -1, &stmt, NULL), SQLITE_OK);

        sqlite3_bind_text(stmt, 1, [account[@"did"] UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, now);
        sqlite3_bind_double(stmt, 3, now);

        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
        sqlite3_finalize(stmt);

        // Insert multiple records for each account
        for (int i = 0; i < 3; i++) {
            NSString *rkey = [NSString stringWithFormat:@"post%d", i];
            NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", account[@"did"], rkey];
            NSString *cid = [NSString stringWithFormat:@"bafyreitestcid%d%@", i, account[@"did"]];

            const char *insertRecordSQL = "INSERT INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, ?)";
            XCTAssertEqual(sqlite3_prepare_v2(db, insertRecordSQL, -1, &stmt, NULL), SQLITE_OK);

            sqlite3_bind_text(stmt, 1, [uri UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, [account[@"did"] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 3, "app.bsky.feed.post", -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, [rkey UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 5, [cid UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_double(stmt, 6, now);

            XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
            sqlite3_finalize(stmt);
        }

        // Insert blocks for each account
        for (int i = 0; i < 2; i++) {
            NSString *content = [NSString stringWithFormat:@"Block data for %@ #%d", account[@"did"], i];
            NSData *blockData = [content dataUsingEncoding:NSUTF8StringEncoding];
            NSData *cidData = [[NSString stringWithFormat:@"cid_%@_%d", account[@"did"], i] dataUsingEncoding:NSUTF8StringEncoding];

            const char *insertBlockSQL = "INSERT INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";
            XCTAssertEqual(sqlite3_prepare_v2(db, insertBlockSQL, -1, &stmt, NULL), SQLITE_OK);

            sqlite3_bind_blob(stmt, 1, cidData.bytes, (int)cidData.length, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, [account[@"did"] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_blob(stmt, 3, blockData.bytes, (int)blockData.length, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, "text/plain", -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 5, blockData.length);
            sqlite3_bind_double(stmt, 6, now);

            XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
            sqlite3_finalize(stmt);
        }
    }
}

- (void)verifyDataPreservationFromSource:(NSString *)sourcePath toDestination:(NSString *)destinationDir {
    // Count records in source database
    sqlite3 *sourceDb;
    XCTAssertEqual(sqlite3_open([sourcePath UTF8String], &sourceDb), SQLITE_OK);

    int sourceAccountCount = [self countRowsInTable:@"accounts" database:sourceDb];
    int sourceRepoCount = [self countRowsInTable:@"repos" database:sourceDb];
    int sourceRecordCount = [self countRowsInTable:@"records" database:sourceDb];
    int sourceBlockCount = [self countRowsInTable:@"blocks" database:sourceDb];

    sqlite3_close(sourceDb);

    // Count records in migrated databases
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *tenantDirs = [fm contentsOfDirectoryAtPath:destinationDir error:nil];

    int totalMigratedAccounts = 0;
    int totalMigratedRepos = 0;
    int totalMigratedRecords = 0;
    int totalMigratedBlocks = 0;

    for (NSString *tenantDirName in tenantDirs) {
        NSString *tenantDir = [destinationDir stringByAppendingPathComponent:tenantDirName];

        // Check accounts
        NSString *accountDbPath = [tenantDir stringByAppendingPathComponent:@"accounts.db"];
        if ([fm fileExistsAtPath:accountDbPath]) {
            sqlite3 *db;
            XCTAssertEqual(sqlite3_open([accountDbPath UTF8String], &db), SQLITE_OK);
            totalMigratedAccounts += [self countRowsInTable:@"accounts" database:db];
            sqlite3_close(db);
        }

        // Check repos and records
        NSString *repoDbPath = [tenantDir stringByAppendingPathComponent:@"repos.db"];
        if ([fm fileExistsAtPath:repoDbPath]) {
            sqlite3 *db;
            XCTAssertEqual(sqlite3_open([repoDbPath UTF8String], &db), SQLITE_OK);
            totalMigratedRepos += [self countRowsInTable:@"repos" database:db];
            sqlite3_close(db);
        }

        NSString *recordDbPath = [tenantDir stringByAppendingPathComponent:@"records.db"];
        if ([fm fileExistsAtPath:recordDbPath]) {
            sqlite3 *db;
            XCTAssertEqual(sqlite3_open([recordDbPath UTF8String], &db), SQLITE_OK);
            totalMigratedRecords += [self countRowsInTable:@"records" database:db];
            sqlite3_close(db);
        }

        // Check blocks
        NSString *blockDbPath = [tenantDir stringByAppendingPathComponent:@"blocks.db"];
        if ([fm fileExistsAtPath:blockDbPath]) {
            sqlite3 *db;
            XCTAssertEqual(sqlite3_open([blockDbPath UTF8String], &db), SQLITE_OK);
            totalMigratedBlocks += [self countRowsInTable:@"blocks" database:db];
            sqlite3_close(db);
        }
    }

    // Verify counts match
    XCTAssertEqual(totalMigratedAccounts, sourceAccountCount, @"All accounts should be migrated");
    XCTAssertEqual(totalMigratedRepos, sourceRepoCount, @"All repos should be migrated");
    XCTAssertEqual(totalMigratedRecords, sourceRecordCount, @"All records should be migrated");
    XCTAssertEqual(totalMigratedBlocks, sourceBlockCount, @"All blocks should be migrated");
}

- (int)countRowsInTable:(NSString *)tableName database:(sqlite3 *)db {
    NSString *query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@", tableName];
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, [query UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        return 0;
    }

    int count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int(stmt, 0);
    }

    sqlite3_finalize(stmt);
    return count;
}

@end