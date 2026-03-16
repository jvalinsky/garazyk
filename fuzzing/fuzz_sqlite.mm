// fuzz_sqlite.mm — libFuzzer entry point for SQL query input sanitization
//
// Exercises the database layer's input handling. Uses an in-memory SQLite
// database to test query construction with fuzz-supplied input strings,
// catching injection, encoding, and parsing edge cases.

#import <Foundation/Foundation.h>
#include <sqlite3.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    @autoreleasepool {
        if (Size == 0) return 0;

        // Limit to printable ASCII range to exercise string handling
        NSData *inputData = [NSData dataWithBytes:Data length:Size];
        NSString *inputString = [[NSString alloc] initWithData:inputData
                                                      encoding:NSUTF8StringEncoding];
        if (!inputString) return 0;

        // Open an in-memory SQLite database
        sqlite3 *db = NULL;
        if (sqlite3_open(":memory:", &db) != SQLITE_OK) return 0;

        // Create a minimal schema
        sqlite3_exec(db, "CREATE TABLE t(col TEXT);", NULL, NULL, NULL);

        // Use a parameterized statement (should be safe regardless of input)
        sqlite3_stmt *stmt = NULL;
        const char *sql = "SELECT * FROM t WHERE col = ?;";
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [inputString UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }

        sqlite3_close(db);
    }
    return 0;
}
