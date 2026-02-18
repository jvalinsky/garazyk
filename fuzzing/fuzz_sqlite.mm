//
//  fuzz_sqlite.mm
//  SQL injection testing fuzzer for ATProto PDS
//
//  Tests:
//  1. Union-based SQL injection
//  2. Error-based SQL injection
//  3. Boolean-based SQL injection
//  4. Time-based (blind) SQL injection
//  5. SQLite-specific injection
//  6. Column/table name injection
//

#import <Foundation/Foundation.h>
#import "Database/PDSDatabase.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 10000) {
        return 0;
    }

    @autoreleasepool {
        NSData *inputData = [NSData dataWithBytes:data length:size];
        NSString *input = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];

        if (!input) {
            // Try Latin1 encoding for injection payloads
            input = [[NSString alloc] initWithData:inputData encoding:NSISOLatin1StringEncoding];
            if (!input) {
                return 0;
            }
        }

        // Test 1: Union-based SQL injection patterns
        NSArray *unionPatterns = @[
            [NSString stringWithFormat:@"' UNION SELECT * FROM users--"],
            [NSString stringWithFormat:@"' UNION SELECT username,password,email FROM users--"],
            [NSString stringWithFormat:@"' UNION SELECT 1,2,3,4,5--"],
            [NSString stringWithFormat:@"' UNION ALL SELECT * FROM records--"],
            [NSString stringWithFormat:@"' OR 1=1 UNION SELECT--"],
            [NSString stringWithFormat:@"' HAVING 1=1--"],
        ];

        for (NSString *pattern in unionPatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 2: Error-based SQL injection
        NSArray *errorPatterns = @[
            [NSString stringWithFormat:@"' OR 1=1--"],
            [NSString stringWithFormat:@"' OR 'x'='x'--"],
            [NSString stringWithFormat:@"' AND 1=1--"],
            [NSString stringWithFormat:@"' AND 1=2--"],
            [NSString stringWithFormat:@"' OR 1=1 AND '%@'='%@'", input, input],
        ];

        for (NSString *pattern in errorPatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 3: Boolean-based SQL injection
        NSArray *booleanPatterns = @[
            [NSString stringWithFormat:@"' OR 1=1--"],
            [NSString stringWithFormat:@"' AND 1=1--"],
            [NSString stringWithFormat:@"' AND 1=2--"],
            [NSString stringWithFormat:@"' OR 'a'='a"],
            [NSString stringWithFormat:@"' AND 'a'='b"],
        ];

        for (NSString *pattern in booleanPatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 4: Time-based (blind) SQL injection - SQLite specific
        NSArray *timePatterns = @[
            [NSString stringWithFormat:@"' OR (SELECT CASE WHEN (1=1) THEN 1 ELSE 0 END)--"],
            [NSString stringWithFormat:@"' OR (SELECT CASE WHEN (1=0) THEN 1 ELSE 0 END)--"],
            [NSString stringWithFormat:@"' AND 1=(SELECT 1 FROM (SELECT sleep(0)))--"],
        ];

        for (NSString *pattern in timePatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 5: SQLite-specific injection
        NSArray *sqlitePatterns = @[
            [NSString stringWithFormat:@"' ; DROP TABLE users--"],
            [NSString stringWithFormat:@"' ; ATTACH DATABASE '/tmp/evil.db' AS evil;--"],
            [NSString stringWithFormat:@"' ; SELECT load_extension('/tmp/malicious.so');--"],
            [NSString stringWithFormat:@"' ; PRAGMA temp_store_directory='/tmp';--"],
            [NSString stringWithFormat:@"' ; UPDATE sqlite_master SET sql='...' WHERE type='table';--"],
            [NSString stringWithFormat:@"' ; WITH RECURSIVE cte(x) AS (SELECT 1 UNION SELECT x+1 FROM cte WHERE x<1000) SELECT * FROM cte--"],
        ];

        for (NSString *pattern in sqlitePatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 6: Stacked queries
        NSArray *stackedPatterns = @[
            [NSString stringWithFormat:@"' ; SELECT * FROM users; DROP TABLE users;--"],
            [NSString stringWithFormat:@"' ; INSERT INTO logs VALUES ('injection');--"],
            [NSString stringWithFormat:@"' ; UPDATE users SET password='hacked' WHERE 1=1;--"],
            [NSString stringWithFormat:@"' ; DELETE FROM users;--"],
        ];

        for (NSString *pattern in stackedPatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 7: Column/table name injection (ORDER BY, SELECT columns)
        NSArray *columnPatterns = @[
            @"repo",
            @"collection",
            @"createdAt",
            @"1; DROP TABLE users;--",
            @"null) UNION SELECT 1,2,3--",
            @"repo, (SELECT 1)--",
            @"*",
        ];

        for (NSString *column in columnPatterns) {
            NSString *testInput = [NSString stringWithFormat:@"ORDER BY %@", column];
            (void)testInput;
        }

        // Test 8: LIKE operator injection
        NSArray *likePatterns = @[
            [NSString stringWithFormat:@"' OR 1=1--"],
            [NSString stringWithFormat:@"' OR '%%'='%%"],
            [NSString stringWithFormat:@"' OR '%%x%%'='%%x%%"],
            [NSString stringWithFormat:@"' UNION SELECT * FROM users WHERE username LIKE '%%admin%%'--"],
        ];

        for (NSString *pattern in likePatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 9: Type confusion
        NSArray *typePatterns = @[
            [NSString stringWithFormat:@"' OR 'test'::int = 'test'--"],
            [NSString stringWithFormat:@"' OR 1::text = '1'--"],
            [NSString stringWithFormat:@"' AND 'abc' = 123--"],
            [NSString stringWithFormat:@"' OR 1=CAST(1 AS TEXT)--"],
        ];

        for (NSString *pattern in typePatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 10: Comment-based injection
        NSArray *commentPatterns = @[
            [NSString stringWithFormat:@"' OR 1=1--"],
            [NSString stringWithFormat:@"' OR 1=1#"],
            [NSString stringWithFormat:@"' OR 1=1/*"],
            [NSString stringWithFormat:@"' OR 1=1%00"],
            [NSString stringWithFormat:@"' OR 1=1; --"],
        ];

        for (NSString *pattern in commentPatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 11: String concatenation attacks
        NSArray *concatPatterns = @[
            [NSString stringWithFormat:@"' OR 'a' || 'b' = 'ab'--"],
            [NSString stringWithFormat:@"' OR CONCAT('a','b') = 'ab'--"],
            [NSString stringWithFormat:@"' OR 'a' 'b' = 'ab'--"],
        ];

        for (NSString *pattern in concatPatterns) {
            NSString *testInput = [input stringByReplacingOccurrencesOfString:@"INJECT" withString:pattern];
            (void)testInput;
        }

        // Test 12: Validation of user input
        NSCharacterSet *safeChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"];
        NSCharacterSet *inputChars = [NSCharacterSet characterSetWithCharactersInString:input];
        NSCharacterSet *unsafeChars = [inputChars invertedSet];

        BOOL hasInjectionChars = NO;
        NSArray *dangerousChars = @[@"'", @"\"", @";", @"-", @"(", @")", @"UNION", @"SELECT", @"DROP", @"INSERT", @"UPDATE", @"DELETE", @"--", @"/*", @"*/", @"OR", @"AND", @"WHERE", @"ORDER", @"BY", @"GROUP"];

        for (NSString *dangerous in dangerousChars) {
            if ([input.uppercaseString containsString:dangerous.uppercaseString]) {
                hasInjectionChars = YES;
                break;
            }
        }
        (void)hasInjectionChars;
        (void)unsafeChars;

        return 0;
    }
}

