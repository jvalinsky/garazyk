#import <XCTest/XCTest.h>
#import "Database/Integration/PDSDatabaseIntegrationTestUtilities.h"
#import "Database/Migration/PDSMigrationManager.h"
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

- (void)testSuccessfulMigrationExecution {
    // Test that migration completes successfully with valid data
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_success"];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture testMigrationWithSourcePath:sourcePath destinationDirectory:destinationDir error:&error],
                 @"Migration should succeed with valid monolithic database: %@", error);

    // Verify destination directory was created and contains expected structure
    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm fileExistsAtPath:destinationDir], @"Destination directory should exist after migration");

    // Cleanup
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

- (void)testMigrationWithEmptyDatabase {
    // Test migration with a database that has no data
    NSString *sourcePath = [self createEmptyMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_empty"];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture testMigrationWithSourcePath:sourcePath destinationDirectory:destinationDir error:&error],
                 @"Migration should succeed with empty database: %@", error);

    // Cleanup
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

- (void)testMigrationWithInvalidSourcePath {
    // Test that migration fails gracefully with invalid source path
    NSString *invalidPath = @"/nonexistent/database.db";
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_invalid"];

    __autoreleasing NSError *error = nil;
    XCTAssertFalse([self.fixture testMigrationWithSourcePath:invalidPath destinationDirectory:destinationDir error:&error],
                  @"Migration should fail with invalid source path");

    XCTAssertNotNil(error, @"Error should be provided for invalid source path");
    XCTAssertEqual(error.code, PDSMigrationErrorSourceNotFound, @"Error code should be SourceNotFound");

    // Cleanup
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:destinationDir error:nil];
}

- (void)testMigrationAsyncExecution {
    // Test asynchronous migration execution
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_async"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Async migration completion"];

    [self.fixture.migrationManager migrateFromMonolithicDatabaseAsync:sourcePath
                                                toSingleTenantDirectory:destinationDir
                                                            completion:^(NSError *error) {
        XCTAssertNil(error, @"Async migration should complete without error: %@", error);

        // Verify destination exists
        NSFileManager *fm = [NSFileManager defaultManager];
        XCTAssertTrue([fm fileExistsAtPath:destinationDir], @"Destination directory should exist after async migration");

        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:30.0 handler:nil];

    // Cleanup
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

#pragma mark - Rollback Verification Tests

- (void)testMigrationRollbackAfterCancellation {
    // Test that migration can be cancelled and properly rolled back
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_cancel"];

    // Set up cancellation block that cancels after a short delay
    __block BOOL shouldCancel = NO;
    self.fixture.migrationManager.cancelBlock = ^BOOL {
        return shouldCancel;
    };

    // Start migration in background
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        // Wait a bit then cancel
        [NSThread sleepForTimeInterval:0.1];
        shouldCancel = YES;
    });

    __autoreleasing NSError *error = nil;
    BOOL migrationResult = [self.fixture.migrationManager migrateFromMonolithicDatabase:sourcePath
                                                             toSingleTenantDirectory:destinationDir
                                                                              error:&error];

    // Migration should fail due to cancellation
    XCTAssertFalse(migrationResult, @"Migration should fail when cancelled");
    XCTAssertNotNil(error, @"Error should be provided when migration is cancelled");
    XCTAssertEqual(error.code, PDSMigrationErrorCancelled, @"Error code should be Cancelled");

    // Verify destination directory doesn't exist or is empty (rollback)
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL destinationExists = [fm fileExistsAtPath:destinationDir];
    if (destinationExists) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:destinationDir error:nil];
        XCTAssertEqual(contents.count, 0, @"Destination directory should be empty after cancelled migration rollback");
    }

    // Cleanup
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
    self.fixture.migrationManager.cancelBlock = nil;
}

- (void)testMigrationRollbackOnDestinationExists {
    // Test rollback when destination directory already exists
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_dest_exists"];

    NSFileManager *fm = [NSFileManager defaultManager];

    // Create destination directory with some content
    XCTAssertTrue([fm createDirectoryAtPath:destinationDir withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *dummyFile = [destinationDir stringByAppendingPathComponent:@"dummy.txt"];
    XCTAssertTrue([@"dummy content" writeToFile:dummyFile atomically:YES encoding:NSUTF8StringEncoding error:nil]);

    __autoreleasing NSError *error = nil;
    // This should fail because destination exists and is not empty
    XCTAssertFalse([self.fixture.migrationManager migrateFromMonolithicDatabase:sourcePath
                                                      toSingleTenantDirectory:destinationDir
                                                                       error:&error]);

    XCTAssertNotNil(error, @"Error should be provided when destination exists");

    // Verify dummy file still exists (no partial migration occurred)
    XCTAssertTrue([fm fileExistsAtPath:dummyFile], @"Original files should remain untouched on migration failure");

    // Cleanup
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

- (void)testMigrationRollbackVerification {
    // Test the rollback verification functionality
    NSString *sourcePath = [self createTestMonolithicDatabase];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture testMigrationRollbackWithSourcePath:sourcePath error:&error],
                 @"Rollback verification should succeed: %@", error);

    // Verify source database still exists and is intact
    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm fileExistsAtPath:sourcePath], @"Source database should still exist after rollback test");

    // Verify we can still open and query the database
    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([sourcePath UTF8String], &db), SQLITE_OK, @"Should be able to reopen database after rollback test");

    // Check that our test data is still there
    sqlite3_stmt *stmt;
    const char *countSQL = "SELECT COUNT(*) FROM accounts";
    XCTAssertEqual(sqlite3_prepare_v2(db, countSQL, -1, &stmt, NULL), SQLITE_OK);

    XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW);
    int accountCount = sqlite3_column_int(stmt, 0);
    XCTAssertEqual(accountCount, 1, @"Account data should be preserved after rollback test");

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    // Cleanup
    [fm removeItemAtPath:sourcePath error:nil];
}

#pragma mark - Data Preservation Tests

- (void)testDataPreservationDuringMigration {
    // Test that all data types are correctly migrated and preserved
    NSString *sourcePath = [self createTestMonolithicDatabaseWithMultipleRecords];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_data_preservation"];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture testMigrationWithSourcePath:sourcePath destinationDirectory:destinationDir error:&error],
                 @"Migration should succeed and preserve all data: %@", error);

    // Verify data preservation by checking counts and content
    [self verifyDataPreservationFromSource:sourcePath toDestination:destinationDir];

    // Cleanup
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

- (void)testAccountDataPreservation {
    // Test that account data is correctly migrated
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_accounts"];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture testMigrationWithSourcePath:sourcePath destinationDirectory:destinationDir error:&error],
                 @"Migration should succeed for account data: %@", error);

    // Find the migrated tenant database
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *tenantDirs = [fm contentsOfDirectoryAtPath:destinationDir error:nil];
    XCTAssertTrue(tenantDirs.count > 0, @"Should have at least one tenant directory");

    NSString *tenantDir = [destinationDir stringByAppendingPathComponent:tenantDirs.firstObject];
    NSString *accountDbPath = [tenantDir stringByAppendingPathComponent:@"accounts.db"];

    // Verify account data exists in migrated database
    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([accountDbPath UTF8String], &db), SQLITE_OK, @"Should be able to open migrated account database");

    sqlite3_stmt *stmt;
    const char *querySQL = "SELECT did, handle, email FROM accounts WHERE did = ?";
    XCTAssertEqual(sqlite3_prepare_v2(db, querySQL, -1, &stmt, NULL), SQLITE_OK);

    sqlite3_bind_text(stmt, 1, "did:plc:test123", -1, SQLITE_TRANSIENT);

    XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW, @"Should find migrated account");
    XCTAssertEqual(strcmp((const char *)sqlite3_column_text(stmt, 0), "did:plc:test123"), 0, @"DID should match");
    XCTAssertEqual(strcmp((const char *)sqlite3_column_text(stmt, 1), "test.example.com"), 0, @"Handle should match");
    XCTAssertEqual(strcmp((const char *)sqlite3_column_text(stmt, 2), "test@example.com"), 0, @"Email should match");

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    // Cleanup
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

- (void)testRecordDataPreservation {
    // Test that record data is correctly migrated
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_records"];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture testMigrationWithSourcePath:sourcePath destinationDirectory:destinationDir error:&error],
                 @"Migration should succeed for record data: %@", error);

    // Find the migrated tenant database
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *tenantDirs = [fm contentsOfDirectoryAtPath:destinationDir error:nil];
    XCTAssertTrue(tenantDirs.count > 0, @"Should have at least one tenant directory");

    NSString *tenantDir = [destinationDir stringByAppendingPathComponent:tenantDirs.firstObject];
    NSString *recordDbPath = [tenantDir stringByAppendingPathComponent:@"records.db"];

    // Verify record data exists in migrated database
    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([recordDbPath UTF8String], &db), SQLITE_OK, @"Should be able to open migrated record database");

    sqlite3_stmt *stmt;
    const char *querySQL = "SELECT uri, collection, rkey FROM records WHERE did = ?";
    XCTAssertEqual(sqlite3_prepare_v2(db, querySQL, -1, &stmt, NULL), SQLITE_OK);

    sqlite3_bind_text(stmt, 1, "did:plc:test123", -1, SQLITE_TRANSIENT);

    XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW, @"Should find migrated record");
    XCTAssertTrue(strstr((const char *)sqlite3_column_text(stmt, 0), "did:plc:test123") != NULL, @"URI should contain DID");
    XCTAssertEqual(strcmp((const char *)sqlite3_column_text(stmt, 1), "app.bsky.feed.post"), 0, @"Collection should match");
    XCTAssertEqual(strcmp((const char *)sqlite3_column_text(stmt, 2), "test123"), 0, @"Rkey should match");

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    // Cleanup
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

- (void)testBlockDataPreservation {
    // Test that block data is correctly migrated
    NSString *sourcePath = [self createTestMonolithicDatabase];
    NSString *destinationDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_test_blocks"];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture testMigrationWithSourcePath:sourcePath destinationDirectory:destinationDir error:&error],
                 @"Migration should succeed for block data: %@", error);

    // Find the migrated tenant database
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *tenantDirs = [fm contentsOfDirectoryAtPath:destinationDir error:nil];
    XCTAssertTrue(tenantDirs.count > 0, @"Should have at least one tenant directory");

    NSString *tenantDir = [destinationDir stringByAppendingPathComponent:tenantDirs.firstObject];
    NSString *blockDbPath = [tenantDir stringByAppendingPathComponent:@"blocks.db"];

    // Verify block data exists in migrated database
    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([blockDbPath UTF8String], &db), SQLITE_OK, @"Should be able to open migrated block database");

    sqlite3_stmt *stmt;
    const char *querySQL = "SELECT repo_did, content_type, size FROM blocks WHERE repo_did = ?";
    XCTAssertEqual(sqlite3_prepare_v2(db, querySQL, -1, &stmt, NULL), SQLITE_OK);

    sqlite3_bind_text(stmt, 1, "did:plc:test123", -1, SQLITE_TRANSIENT);

    XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW, @"Should find migrated block");
    XCTAssertEqual(strcmp((const char *)sqlite3_column_text(stmt, 0), "did:plc:test123"), 0, @"Repo DID should match");
    XCTAssertEqual(strcmp((const char *)sqlite3_column_text(stmt, 1), "text/plain"), 0, @"Content type should match");
    XCTAssertEqual(sqlite3_column_int64(stmt, 2), 15, @"Size should match test data");

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    // Cleanup
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:destinationDir error:nil];
}

#pragma mark - Helper Methods

- (NSString *)createTestMonolithicDatabase {
    // Create a temporary monolithic database with test data
    NSString *tempDir = NSTemporaryDirectory();
    NSString *dbPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"monolithic_test_%@.db", [[NSUUID UUID] UUIDString]]];

    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([dbPath UTF8String], &db), SQLITE_OK, @"Should be able to create test database");

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

    // Insert test data
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

    // Create tables but don't insert any data
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

    sqlite3_close(db);
    return dbPath;
}

- (NSString *)createTestMonolithicDatabaseWithMultipleRecords {
    // Create a database with multiple accounts, repos, records, and blocks
    NSString *tempDir = NSTemporaryDirectory();
    NSString *dbPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"monolithic_multi_%@.db", [[NSUUID UUID] UUIDString]]];

    sqlite3 *db;
    XCTAssertEqual(sqlite3_open([dbPath UTF8String], &db), SQLITE_OK, @"Should be able to create multi-record test database");

    // Create tables
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

    // Insert multiple test records
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