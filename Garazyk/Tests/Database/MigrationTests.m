// MigrationTests.m
// Basic tests for PDSMigrationManager without XCTest framework
// Run with: build/tests/migration_tests

#import <Foundation/Foundation.h>
#import "Database/Migrations/PDSMigrationManager.h"
#import "Database/Schema/PDSSchemaManager.h"
#include <sqlite3.h>

@interface MigrationTest : NSObject
- (BOOL)runAllTests;
- (BOOL)testFreshInstall;
- (BOOL)testRollback;
- (BOOL)testReApply;
- (void)logPass:(NSString *)testName;
- (void)logFail:(NSString *)testName message:(NSString *)message;
@end

@implementation MigrationTest {
    NSInteger passCount;
    NSInteger failCount;
}

- (instancetype)init {
    if ((self = [super init])) {
        passCount = 0;
        failCount = 0;
    }
    return self;
}

- (BOOL)runAllTests {
    NSLog(@"=== Migration System Tests ===\n");

    @autoreleasepool {
        if (![self testFreshInstall]) return NO;
    }

    @autoreleasepool {
        if (![self testRollback]) return NO;
    }

    @autoreleasepool {
        if (![self testReApply]) return NO;
    }

    NSLog(@"\n=== Test Results ===");
    NSLog(@"Passed: %ld", (long)passCount);
    NSLog(@"Failed: %ld", (long)failCount);
    NSLog(@"%@", failCount == 0 ? @"✓ ALL TESTS PASSED" : @"✗ SOME TESTS FAILED");

    return failCount == 0;
}

- (BOOL)testFreshInstall {
    NSString *testName = @"testFreshInstall";
    NSLog(@"\nRunning %@...", testName);

    // Create temporary database
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_fresh.db"];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    sqlite3 *db = NULL;
    int result = sqlite3_open(tempPath.UTF8String, &db);
    if (result != SQLITE_OK) {
        [self logFail:testName message:@"Failed to create database"];
        return NO;
    }

    // Create migration manager
    PDSMigrationManager *manager = [PDSMigrationManager actorStoreMigrationManager];

    // Run migration
    NSError *error = nil;
    if (![manager migrateDatabase:db error:&error]) {
        [self logFail:testName message:[NSString stringWithFormat:@"Migration failed: %@", error]];
        sqlite3_close(db);
        return NO;
    }

    // Verify version
    NSInteger version = [manager currentVersion:db];
    if (version != 1) {
        [self logFail:testName message:[NSString stringWithFormat:@"Expected version 1, got %ld", (long)version]];
        sqlite3_close(db);
        return NO;
    }

    // Verify tables exist
    const char *checkSQL = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN "
                          "('repo_root', 'records', 'ipld_blocks', 'record_tombstones', 'blobs')";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, checkSQL, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            if (count != 5) {
                [self logFail:testName message:[NSString stringWithFormat:@"Expected 5 tables, found %d", count]];
                sqlite3_finalize(stmt);
                sqlite3_close(db);
                return NO;
            }
        }
        sqlite3_finalize(stmt);
    }

    sqlite3_close(db);
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    [self logPass:testName];
    return YES;
}

- (BOOL)testRollback {
    NSString *testName = @"testRollback";
    NSLog(@"\nRunning %@...", testName);

    // Create temporary database
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_rollback.db"];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    sqlite3 *db = NULL;
    if (sqlite3_open(tempPath.UTF8String, &db) != SQLITE_OK) {
        [self logFail:testName message:@"Failed to create database"];
        return NO;
    }

    // Run migration
    PDSMigrationManager *manager = [PDSMigrationManager actorStoreMigrationManager];
    NSError *error = nil;
    if (![manager migrateDatabase:db error:&error]) {
        [self logFail:testName message:[NSString stringWithFormat:@"Migration failed: %@", error]];
        sqlite3_close(db);
        return NO;
    }

    // Rollback to version 0
    if (![manager rollbackToVersion:db version:0 error:&error]) {
        [self logFail:testName message:[NSString stringWithFormat:@"Rollback failed: %@", error]];
        sqlite3_close(db);
        return NO;
    }

    // Verify version is 0
    NSInteger version = [manager currentVersion:db];
    if (version != 0) {
        [self logFail:testName message:[NSString stringWithFormat:@"Expected version 0 after rollback, got %ld", (long)version]];
        sqlite3_close(db);
        return NO;
    }

    // Verify tables don't exist
    const char *checkSQL = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='records'";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, checkSQL, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            if (count != 0) {
                [self logFail:testName message:@"Tables still exist after rollback"];
                sqlite3_finalize(stmt);
                sqlite3_close(db);
                return NO;
            }
        }
        sqlite3_finalize(stmt);
    }

    sqlite3_close(db);
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    [self logPass:testName];
    return YES;
}

- (BOOL)testReApply {
    NSString *testName = @"testReApply";
    NSLog(@"\nRunning %@...", testName);

    // Create temporary database
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_reapply.db"];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    sqlite3 *db = NULL;
    if (sqlite3_open(tempPath.UTF8String, &db) != SQLITE_OK) {
        [self logFail:testName message:@"Failed to create database"];
        return NO;
    }

    // Run migration
    PDSMigrationManager *manager = [PDSMigrationManager actorStoreMigrationManager];
    NSError *error = nil;
    if (![manager migrateDatabase:db error:&error]) {
        [self logFail:testName message:[NSString stringWithFormat:@"Initial migration failed: %@", error]];
        sqlite3_close(db);
        return NO;
    }

    // Rollback
    if (![manager rollbackToVersion:db version:0 error:&error]) {
        [self logFail:testName message:[NSString stringWithFormat:@"Rollback failed: %@", error]];
        sqlite3_close(db);
        return NO;
    }

    // Re-apply
    if (![manager migrateDatabase:db error:&error]) {
        [self logFail:testName message:[NSString stringWithFormat:@"Re-apply failed: %@", error]];
        sqlite3_close(db);
        return NO;
    }

    // Verify version is 1
    NSInteger version = [manager currentVersion:db];
    if (version != 1) {
        [self logFail:testName message:[NSString stringWithFormat:@"Expected version 1 after re-apply, got %ld", (long)version]];
        sqlite3_close(db);
        return NO;
    }

    // Verify tables exist again
    const char *checkSQL = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='records'";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, checkSQL, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            if (count != 1) {
                [self logFail:testName message:@"Tables not recreated after re-apply"];
                sqlite3_finalize(stmt);
                sqlite3_close(db);
                return NO;
            }
        }
        sqlite3_finalize(stmt);
    }

    sqlite3_close(db);
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    [self logPass:testName];
    return YES;
}

- (void)logPass:(NSString *)testName {
    passCount++;
    NSLog(@"  ✓ %@ passed", testName);
}

- (void)logFail:(NSString *)testName message:(NSString *)message {
    failCount++;
    NSLog(@"  ✗ %@ failed: %@", testName, message);
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        MigrationTest *test = [[MigrationTest alloc] init];
        BOOL success = [test runAllTests];
        return success ? 0 : 1;
    }
}
