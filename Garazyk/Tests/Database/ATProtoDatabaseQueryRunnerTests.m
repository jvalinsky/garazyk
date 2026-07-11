// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import <sqlite3.h>

#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"

static NSString * const ATProtoDatabaseQueryRunnerTestDomain = @"blue.microcosm.tests.query-runner";

static void ATProtoDatabaseQueryRunnerFail(sqlite3_context *context,
                                           int argc,
                                           sqlite3_value **argv) {
    (void)argc;
    (void)argv;
    sqlite3_result_error(context, "forced step failure", -1);
}

@interface ATProtoDatabaseQueryRunnerTests : XCTestCase
@property (nonatomic, strong) ATProtoConnectionManagerSerial *manager;
@property (nonatomic, strong) ATProtoDatabaseQueryRunner *runner;
@end

@implementation ATProtoDatabaseQueryRunnerTests

- (void)setUp {
    [super setUp];
    self.manager = [[ATProtoConnectionManagerSerial alloc] initWithLabel:
        [NSString stringWithFormat:@"blue.microcosm.tests.query-runner.%@", self.name]];

    NSError *error = nil;
    XCTAssertTrue([self.manager openWithPath:@":memory:"
                                      config:ATProtoDBConfigDefault
                                       error:&error], @"open sqlite: %@", error);
    self.runner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:self.manager
                                                                    errorDomain:ATProtoDatabaseQueryRunnerTestDomain];
}

- (void)tearDown {
    [self.manager close];
    self.runner = nil;
    self.manager = nil;
    [super tearDown];
}

- (void)testQueryReturnsTypedValuesNullsAndBlobs {
    NSError *error = nil;
    NSData *blob = [NSData dataWithBytes:"\x01\x02\x03" length:3];
    BOOL seeded = [self.runner performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        if (![tx executeUpdate:@"CREATE TABLE values_test(i INTEGER, f REAL, t TEXT, b BLOB, n TEXT)"
                        params:nil
                         error:innerError]) {
            return NO;
        }
        return [tx executeUpdate:@"INSERT INTO values_test(i, f, t, b, n) VALUES(?,?,?,?,?)"
                          params:@[@7, @(3.5), @"hello", blob, [NSNull null]]
                           error:innerError];
    } error:&error];
    XCTAssertTrue(seeded, @"seed values: %@", error);

    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.runner executeQuery:@"SELECT i, f, t, b, n FROM values_test"
                           params:nil
                            error:&error];
    XCTAssertEqual(rows.count, 1u, @"query values: %@", error);
    NSDictionary<NSString *, id> *row = rows.firstObject;
    XCTAssertEqualObjects(row[@"i"], @7);
    XCTAssertEqualObjects(row[@"f"], @3.5);
    XCTAssertEqualObjects(row[@"t"], @"hello");
    XCTAssertEqualObjects(row[@"b"], blob);
    XCTAssertEqualObjects(row[@"n"], [NSNull null]);
}

- (void)testPrepareFailureUsesServiceErrorDomain {
    NSError *error = nil;
    NSArray *rows = [self.runner executeQuery:@"SELECT * FROM missing_table"
                                       params:nil
                                        error:&error];
    XCTAssertNil(rows);
    XCTAssertEqualObjects(error.domain, ATProtoDatabaseQueryRunnerTestDomain);
    XCTAssertEqual(error.code, SQLITE_ERROR);
}

- (void)testStepFailureUsesServiceErrorDomain {
    __block int createResult = SQLITE_OK;
    NSError *error = nil;
    BOOL installed = [self.manager execute:^(sqlite3 *db) {
        createResult = sqlite3_create_function(db,
                                               "runner_fail",
                                               0,
                                               SQLITE_UTF8,
                                               NULL,
                                               ATProtoDatabaseQueryRunnerFail,
                                               NULL,
                                               NULL);
    } error:&error];
    XCTAssertTrue(installed, @"install function: %@", error);
    XCTAssertEqual(createResult, SQLITE_OK);

    NSArray *rows = [self.runner executeQuery:@"SELECT runner_fail() AS value"
                                       params:nil
                                        error:&error];
    XCTAssertNil(rows);
    XCTAssertEqualObjects(error.domain, ATProtoDatabaseQueryRunnerTestDomain);
    XCTAssertEqual(error.code, SQLITE_ERROR);
}

- (void)testUpdateFailureUsesServiceErrorDomain {
    NSError *error = nil;
    BOOL updated = [self.runner performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        if (![tx executeUpdate:@"CREATE TABLE unique_test(value TEXT UNIQUE)"
                        params:nil
                         error:innerError]) {
            return NO;
        }
        if (![tx executeUpdate:@"INSERT INTO unique_test(value) VALUES(?)"
                        params:@[@"one"]
                         error:innerError]) {
            return NO;
        }
        return [tx executeUpdate:@"INSERT INTO unique_test(value) VALUES(?)"
                          params:@[@"one"]
                           error:innerError];
    } error:&error];
    XCTAssertFalse(updated);
    XCTAssertEqualObjects(error.domain, ATProtoDatabaseQueryRunnerTestDomain);
    XCTAssertEqual(error.code, SQLITE_CONSTRAINT);
}

- (void)testTransactionRollbackPreservesBlockError {
    NSError *error = nil;
    BOOL created = [self.runner performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        return [tx executeUpdate:@"CREATE TABLE rollback_test(value TEXT)"
                          params:nil
                           error:innerError];
    } error:&error];
    XCTAssertTrue(created, @"create table: %@", error);

    BOOL rolledBack = [self.runner performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        if (![tx executeUpdate:@"INSERT INTO rollback_test(value) VALUES(?)"
                        params:@[@"kept-out"]
                         error:innerError]) {
            return NO;
        }
        return [tx executeUpdate:@"INSERT INTO missing_table(value) VALUES(?)"
                          params:@[@"fail"]
                           error:innerError];
    } error:&error];
    XCTAssertFalse(rolledBack);
    XCTAssertEqualObjects(error.domain, ATProtoDatabaseQueryRunnerTestDomain);

    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.runner executeQuery:@"SELECT value FROM rollback_test"
                           params:nil
                            error:&error];
    XCTAssertEqual(rows.count, 0u, @"transaction should roll back inserted row");
}

- (void)testTransactorReadsUncommittedWriteWithinTransaction {
    NSError *error = nil;
    __block NSInteger seenWithinTx = -1;
    __block NSString *seenValue = nil;
    BOOL ok = [self.runner performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        if (![tx executeUpdate:@"CREATE TABLE tx_read_test(value TEXT)"
                        params:nil
                         error:innerError]) {
            return NO;
        }
        if (![tx executeUpdate:@"INSERT INTO tx_read_test(value) VALUES(?)"
                        params:@[@"inside"]
                         error:innerError]) {
            return NO;
        }
        // The transactor's read must see the not-yet-committed write on the same connection.
        NSArray<NSDictionary<NSString *, id> *> *seen =
            [tx executeQuery:@"SELECT value FROM tx_read_test" params:nil error:innerError];
        if (!seen) return NO;
        seenWithinTx = (NSInteger)seen.count;
        seenValue = seen.firstObject[@"value"];
        return YES;
    } error:&error];

    XCTAssertTrue(ok, @"transactor read+write: %@", error);
    XCTAssertEqual(seenWithinTx, 1, @"read within the transaction should see the uncommitted insert");
    XCTAssertEqualObjects(seenValue, @"inside");

    // And it committed: a fresh self-managed read sees the row too.
    NSArray<NSDictionary<NSString *, id> *> *committed =
        [self.runner executeQuery:@"SELECT value FROM tx_read_test" params:nil error:&error];
    XCTAssertEqual(committed.count, 1u, @"committed row visible after transaction: %@", error);
}

- (void)testSelfManagedExecuteUpdateReportsAffectedRows {
    NSError *error = nil;
    XCTAssertEqual([self.runner executeUpdate:@"CREATE TABLE affected_test(id TEXT PRIMARY KEY, n INTEGER)"
                                       params:nil
                                        error:&error], 0, @"create table: %@", error);

    // Array-literal params are hoisted into locals so their internal comma is not
    // mis-parsed as an extra XCTAssertEqual macro argument (only () protects commas,
    // not @[]); the commas inside the SQL string literals are safe.
    NSArray *insertRow = @[@"a", @1];
    XCTAssertEqual([self.runner executeUpdate:@"INSERT INTO affected_test(id, n) VALUES(?, ?)"
                                       params:insertRow
                                        error:&error], 1, @"insert one row: %@", error);

    NSArray *updateRow = @[@2, @"a"];
    XCTAssertEqual([self.runner executeUpdate:@"UPDATE affected_test SET n = ? WHERE id = ?"
                                       params:updateRow
                                        error:&error], 1, @"update matching row: %@", error);

    NSArray *missingRow = @[@9, @"missing"];
    XCTAssertEqual([self.runner executeUpdate:@"UPDATE affected_test SET n = ? WHERE id = ?"
                                       params:missingRow
                                        error:&error], 0, @"update non-matching row returns 0 changes");
}

- (void)testSelfManagedExecuteUpdateReportsErrorWithDomain {
    NSError *error = nil;
    NSInteger changed = [self.runner executeUpdate:@"INSERT INTO missing_table(value) VALUES(?)"
                                            params:@[@"x"]
                                             error:&error];
    XCTAssertTrue(changed < 0, @"failed update should return a negative row count");
    XCTAssertEqualObjects(error.domain, ATProtoDatabaseQueryRunnerTestDomain);
    XCTAssertEqual(error.code, SQLITE_ERROR);
}

- (void)testCustomErrorFactoryIsUsed {
    ATProtoDatabaseQueryRunner *custom =
        [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:self.manager
                                                         errorFactory:^NSError *(sqlite3 *db,
                                                                                 NSInteger code,
                                                                                 NSString *fallback) {
            (void)db;
            return [NSError errorWithDomain:@"blue.microcosm.tests.custom-query-runner"
                                       code:code
                                   userInfo:@{NSLocalizedDescriptionKey: fallback ?: @"custom error"}];
        }];

    NSError *error = nil;
    XCTAssertNil([custom executeQuery:@"SELECT * FROM missing_table" params:nil error:&error]);
    XCTAssertEqualObjects(error.domain, @"blue.microcosm.tests.custom-query-runner");
}

@end
