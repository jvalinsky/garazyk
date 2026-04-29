#import <XCTest/XCTest.h>
#import "TutorialSQLiteHelper.h"

@interface TutorialSQLiteHelperTests : XCTestCase
@property (nonatomic, strong) NSString *dbPath;
@property (nonatomic, strong) TutorialSQLiteHelper *db;
@end

@implementation TutorialSQLiteHelperTests

- (void)setUp {
    [super setUp];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"test_%@.db", [[NSUUID UUID] UUIDString]]];
    self.db = [[TutorialSQLiteHelper alloc] initWithPath:self.dbPath];
    XCTAssertNotNil(self.db, @"Database should initialize");
}

- (void)tearDown {
    self.db = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

- (void)testCreateTable {
    NSError *error = nil;
    BOOL success = [self.db executeUpdate:&error sql:
        @"CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT NOT NULL)"];
    XCTAssertTrue(success, @"Table creation should succeed");
    XCTAssertNil(error, @"No error on table creation");
}

- (void)testInsertAndQuery {
    NSError *error = nil;
    [self.db executeUpdate:&error sql:@"CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"];
    [self.db executeUpdate:&error sql:@"INSERT INTO test (id, name) VALUES (1, 'alice')"];
    [self.db executeUpdate:&error sql:@"INSERT INTO test (id, name) VALUES (2, 'bob')"];

    NSNumber *count = [self.db executeQuery:&error block:^id(sqlite3 *db) {
        sqlite3_stmt *stmt;
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM test", -1, &stmt, NULL);
        NSNumber *result = nil;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = @(sqlite3_column_int(stmt, 0));
        }
        sqlite3_finalize(stmt);
        return result;
    }];
    XCTAssertEqual(count.integerValue, 2, @"Should have 2 rows");
}

- (void)testExecuteSync {
    NSError *error = nil;
    [self.db executeUpdate:&error sql:@"CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)"];

    __block BOOL executed = NO;
    [self.db executeSync:&error block:^(sqlite3 *db) {
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, "INSERT INTO test (id, value) VALUES (1, 'hello')", -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            executed = YES;
        }
    }];
    XCTAssertTrue(executed, @"Block should have executed");
}

- (void)testInvalidSQL {
    NSError *error = nil;
    BOOL success = [self.db executeUpdate:&error sql:@"INVALID SQL STATEMENT"];
    XCTAssertFalse(success, @"Invalid SQL should fail");
    XCTAssertNotNil(error, @"Should return error for invalid SQL");
}

- (void)testWALMode {
    NSError *error = nil;
    NSString *mode = [self.db executeQuery:&error block:^id(sqlite3 *db) {
        sqlite3_stmt *stmt;
        sqlite3_prepare_v2(db, "PRAGMA journal_mode", -1, &stmt, NULL);
        NSString *result = nil;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        }
        sqlite3_finalize(stmt);
        return result;
    }];
    XCTAssertEqualObjects(mode.lowercaseString, @"wal", @"WAL mode should be enabled");
}

@end
