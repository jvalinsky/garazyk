// FuzzPDSDatabase.m - SQLite database fuzzer harness
// Target: Raw SQL execution on a real database

#import <Foundation/Foundation.h>
#import "Database/PDSDatabase.h"

static PDSDatabase *gFuzzDatabase = nil;

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSURL *dbURL = [NSURL fileURLWithPath:
                [NSTemporaryDirectory() stringByAppendingPathComponent:@"fuzz_pds.db"]];
            gFuzzDatabase = [PDSDatabase databaseAtURL:dbURL];
            NSError *error = nil;
            [gFuzzDatabase openWithError:&error];
        });

        if (!gFuzzDatabase) {
            return 0;
        }

        NSString *sql = [[NSString alloc] initWithBytes:data
                                                 length:size
                                               encoding:NSUTF8StringEncoding];
        if (!sql) {
            return 0;
        }

        NSError *error = nil;
        @try {
            // Wrap in savepoint so state doesn't persist across iterations
            [gFuzzDatabase executeRawSQL:@"SAVEPOINT fuzz" error:&error];

            // Test raw SQL path
            [gFuzzDatabase executeRawSQL:sql error:&error];

            // Test parameterized query path (security-critical for injection prevention)
            [gFuzzDatabase executeParameterizedQuery:@"SELECT 1 WHERE ? = ?"
                                              params:@[sql, sql]
                                               error:&error];

            [gFuzzDatabase executeRawSQL:@"ROLLBACK TO SAVEPOINT fuzz" error:&error];
        } @catch (NSException *exception) {
            // SQL parse exceptions are expected; rollback any partial state
            NSError *rollbackErr = nil;
            [gFuzzDatabase executeRawSQL:@"ROLLBACK TO SAVEPOINT fuzz" error:&rollbackErr];
        }
    }
    return 0;
}
