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
    BOOL seeded = [self.runner performWriteTransaction:^BOOL(sqlite3 *db, NSError **innerError) {
        if (![self.runner executeUpdate:@"CREATE TABLE values_test(i INTEGER, f REAL, t TEXT, b BLOB, n TEXT)"
                                 params:nil
                             connection:db
                                  error:innerError]) {
            return NO;
        }
        return [self.runner executeUpdate:@"INSERT INTO values_test(i, f, t, b, n) VALUES(?,?,?,?,?)"
                                   params:@[@7, @(3.5), @"hello", blob, [NSNull null]]
                               connection:db
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
    BOOL updated = [self.runner performWriteTransaction:^BOOL(sqlite3 *db, NSError **innerError) {
        if (![self.runner executeUpdate:@"CREATE TABLE unique_test(value TEXT UNIQUE)"
                                 params:nil
                             connection:db
                                  error:innerError]) {
            return NO;
        }
        if (![self.runner executeUpdate:@"INSERT INTO unique_test(value) VALUES(?)"
                                 params:@[@"one"]
                             connection:db
                                  error:innerError]) {
            return NO;
        }
        return [self.runner executeUpdate:@"INSERT INTO unique_test(value) VALUES(?)"
                                   params:@[@"one"]
                               connection:db
                                    error:innerError];
    } error:&error];
    XCTAssertFalse(updated);
    XCTAssertEqualObjects(error.domain, ATProtoDatabaseQueryRunnerTestDomain);
    XCTAssertEqual(error.code, SQLITE_CONSTRAINT);
}

- (void)testTransactionRollbackPreservesBlockError {
    NSError *error = nil;
    BOOL created = [self.runner performWriteTransaction:^BOOL(sqlite3 *db, NSError **innerError) {
        return [self.runner executeUpdate:@"CREATE TABLE rollback_test(value TEXT)"
                                   params:nil
                               connection:db
                                    error:innerError];
    } error:&error];
    XCTAssertTrue(created, @"create table: %@", error);

    BOOL rolledBack = [self.runner performWriteTransaction:^BOOL(sqlite3 *db, NSError **innerError) {
        if (![self.runner executeUpdate:@"INSERT INTO rollback_test(value) VALUES(?)"
                                 params:@[@"kept-out"]
                             connection:db
                                  error:innerError]) {
            return NO;
        }
        return [self.runner executeUpdate:@"INSERT INTO missing_table(value) VALUES(?)"
                                   params:@[@"fail"]
                               connection:db
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
