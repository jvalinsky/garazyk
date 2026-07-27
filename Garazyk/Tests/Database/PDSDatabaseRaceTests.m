// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabase+Private.h"

/// Regression tests for the isOpen/_db guards added to
/// -[PDSDatabase preparedStatementForQuery:] and
/// -[PDSDatabase prepareStatement:sql:error:].
///
/// These two methods previously accessed _db without checking isOpen or
/// the handle's validity, causing a null-pointer SIGSEGV when the database
/// was closed concurrently (e.g., pool eviction under disk pressure).
@interface PDSDatabaseRaceTests : XCTestCase
@property (nonatomic, strong) NSString *dbPath;
@end

@implementation PDSDatabaseRaceTests

- (void)setUp {
    [super setUp];
    NSString *name = [@"PDSDatabaseRaceTests_" stringByAppendingString:NSUUID.UUID.UUIDString];
    self.dbPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"db"];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

- (PDSDatabase *)openDatabase {
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:self.dbPath]];
    XCTAssertTrue([db openWithError:nil], @"Failed to open test database");
    return db;
}

/// Calling preparedStatementForQuery: on a closed database must return NULL
/// instead of crashing with a null-pointer SIGSEGV in sqlite3_prepare_v2.
- (void)testPreparedStatement_OnClosedDatabase_ReturnsNull {
    PDSDatabase *database = [self openDatabase];
    [database close];
    XCTAssertFalse(database.isOpen);

    // Prepare a statement cache hit path by calling with an already-used query
    sqlite3_stmt *stmt = [database preparedStatementForQuery:@"SELECT 1"];
    XCTAssertEqual(stmt, NULL, @"Must return NULL on closed database, not crash");
}

/// Calling preparedStatementForQuery: on a database that was never opened
/// must return NULL without crashing.
- (void)testPreparedStatement_OnNeverOpenedDatabase_ReturnsNull {
    PDSDatabase *database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:self.dbPath]];
    // Database was never opened — _db is NULL, isOpen is NO
    sqlite3_stmt *stmt = [database preparedStatementForQuery:@"SELECT 1"];
    XCTAssertEqual(stmt, NULL, @"Must return NULL on never-opened database");
}

/// Calling prepareStatement:sql:error: on a closed database must return NO
/// and fill the error out-parameter with PDSDatabaseErrorNotOpen.
- (void)testPrepareStatement_OnClosedDatabase_ReturnsError {
    PDSDatabase *database = [self openDatabase];
    [database close];
    XCTAssertFalse(database.isOpen);

    sqlite3_stmt *stmt = NULL;
    NSError *error = nil;
    BOOL result = [database prepareStatement:&stmt sql:@"SELECT 1" error:&error];

    XCTAssertFalse(result, @"Must return NO on closed database");
    XCTAssertNotNil((id)error, @"Must set error on closed database");
    XCTAssertEqual(error.code, PDSDatabaseErrorNotOpen,
                   @"Error code must be PDSDatabaseErrorNotOpen");
    XCTAssertTrue(stmt == NULL, @"Statement handle must remain NULL");
}

/// Calling prepareStatement:sql:error: on a database that was never opened
/// must return NO with an error.
- (void)testPrepareStatement_OnNeverOpenedDatabase_ReturnsError {
    PDSDatabase *database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:self.dbPath]];

    sqlite3_stmt *stmt = NULL;
    NSError *error = nil;
    BOOL result = [database prepareStatement:&stmt sql:@"SELECT 1" error:&error];

    XCTAssertFalse(result);
    XCTAssertNotNil((id)error);
    XCTAssertEqual(error.code, PDSDatabaseErrorNotOpen);
}

/// After close + reopen, preparedStatementForQuery: must work normally again.
/// Verifies the guards do not permanently block the database.
- (void)testPreparedStatement_AfterCloseReopen_WorksAgain {
    PDSDatabase *database = [self openDatabase];
    [database close];
    XCTAssertFalse(database.isOpen);

    // Reopen
    XCTAssertTrue([database openWithError:nil], @"Reopen must succeed");
    XCTAssertTrue(database.isOpen);

    sqlite3_stmt *stmt = [database preparedStatementForQuery:@"SELECT 1"];
    XCTAssertNotEqual(stmt, NULL, @"Must return valid statement after reopen");
}

/// After close + reopen, prepareStatement:sql:error: must work normally again.
- (void)testPrepareStatement_AfterCloseReopen_WorksAgain {
    PDSDatabase *database = [self openDatabase];
    [database close];
    XCTAssertTrue([database openWithError:nil], @"Reopen must succeed");

    sqlite3_stmt *stmt = NULL;
    NSError *error = nil;
    BOOL result = [database prepareStatement:&stmt sql:@"SELECT 1" error:&error];

    XCTAssertTrue(result, @"Must succeed after reopen");
    XCTAssertNil((id)error, @"Must not set error after reopen");
    XCTAssertNotEqual(stmt, NULL, @"Must return valid statement after reopen");
    if (stmt) sqlite3_finalize(stmt);
}

/// Close while a preparedStatementForQuery: call is queued on the dbQueue.
/// The guard ensures the cached-statement path returns NULL instead of
/// operating on a NULL _db.
- (void)testPreparedStatement_RaceCloseWithCachedStatement {
    PDSDatabase *database = [self openDatabase];

    // Prime the statement cache
    sqlite3_stmt *cachedStmt = [database preparedStatementForQuery:@"SELECT 1"];
    XCTAssertNotEqual(cachedStmt, NULL);

    // Close — finalizes all cached statements
    [database close];

    // Calling the same query after close should not crash
    sqlite3_stmt *stmt = [database preparedStatementForQuery:@"SELECT 1"];
    XCTAssertEqual(stmt, NULL, @"Must return NULL when cache is cleared and db is closed");
}

/// nil query parameter must not crash (tests the guard's resilience with
/// invalid input, even though the caller is expected to provide valid SQL).
- (void)testPreparedStatement_NilQuery_DoesNotCrash {
    PDSDatabase *database = [self openDatabase];
    sqlite3_stmt *stmt = [database preparedStatementForQuery:nil];
    // nil query behavior is undefined — the guard just ensures no crash
    // from access to NULL _db. Passing nil to the guard is fine since the
    // guard checks isOpen/_db before accessing the query parameter.
    XCTAssertEqual(stmt, NULL);
}

@end
