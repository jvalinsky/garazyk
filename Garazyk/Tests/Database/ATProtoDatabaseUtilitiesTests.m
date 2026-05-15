// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import <sqlite3.h>

@interface ATProtoDatabaseUtilitiesTests : XCTestCase
@end

@implementation ATProtoDatabaseUtilitiesTests

- (void)testBindEmptyDataAsZeroLengthBlob {
    sqlite3 *db = NULL;
    XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK);
    XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE t (payload BLOB NOT NULL);", NULL, NULL, NULL), SQLITE_OK);

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO t(payload) VALUES (?)", -1, &stmt, NULL), SQLITE_OK);
    ATProtoDBBindValue(stmt, 1, [NSData data]);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT length(payload) FROM t", -1, &stmt, NULL), SQLITE_OK);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW);
    XCTAssertEqual(sqlite3_column_int(stmt, 0), 0);
    sqlite3_finalize(stmt);
    sqlite3_close(db);
}

- (void)testBindNullUsesSQLiteNull {
    sqlite3 *db = NULL;
    XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK);
    XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE t (value BLOB);", NULL, NULL, NULL), SQLITE_OK);

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO t(value) VALUES (?)", -1, &stmt, NULL), SQLITE_OK);
    ATProtoDBBindValue(stmt, 1, [NSNull null]);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT value FROM t", -1, &stmt, NULL), SQLITE_OK);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW);
    XCTAssertEqual(sqlite3_column_type(stmt, 0), SQLITE_NULL);
    sqlite3_finalize(stmt);
    sqlite3_close(db);
}

- (void)testPlaceholdersMatchCount {
    XCTAssertEqualObjects(ATProtoDBPlaceholders(0), @"");
    XCTAssertEqualObjects(ATProtoDBPlaceholders(1), @"?");
    XCTAssertEqualObjects(ATProtoDBPlaceholders(3), @"?, ?, ?");
}

- (void)testColumnValueDecodesSQLiteTypes {
    sqlite3 *db = NULL;
    XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK);
    XCTAssertEqual(sqlite3_exec(db,
                                "CREATE TABLE t (i INTEGER, f REAL, s TEXT, b BLOB, n TEXT);"
                                "INSERT INTO t VALUES (7, 3.5, 'hello', x'0102', NULL);",
                                NULL,
                                NULL,
                                NULL),
                   SQLITE_OK);

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT i, f, s, b, n FROM t", -1, &stmt, NULL), SQLITE_OK);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW);

    XCTAssertEqualObjects(ATProtoDBColumnValue(stmt, 0), @7);
    XCTAssertEqualObjects(ATProtoDBColumnValue(stmt, 1), @3.5);
    XCTAssertEqualObjects(ATProtoDBColumnValue(stmt, 2), @"hello");
    XCTAssertEqualObjects(ATProtoDBColumnValue(stmt, 3), [NSData dataWithBytes:"\x01\x02" length:2]);
    XCTAssertEqualObjects(ATProtoDBColumnValue(stmt, 4), [NSNull null]);

    sqlite3_finalize(stmt);
    sqlite3_close(db);
}

@end
