#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Database/Migrations/PDSMigrationManager.h"
#import <sqlite3.h>

@interface PDSMigrationManagerTests : XCTestCase
@end

@implementation PDSMigrationManagerTests

- (NSString *)createSourceDatabaseWithAccounts:(BOOL)includeAccount {
    NSString *dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"migration-source-%@.db", [[NSUUID UUID] UUIDString]]];
    sqlite3 *db = NULL;
    XCTAssertEqual(SQLITE_OK, sqlite3_open(dbPath.UTF8String, &db));

    const char *schema[] = {
        "CREATE TABLE accounts (did TEXT, handle TEXT, email TEXT, password_hash BLOB, password_salt BLOB, access_jwt BLOB, refresh_jwt BLOB, created_at REAL, updated_at REAL);",
        "CREATE TABLE repos (owner_did TEXT, root_cid BLOB, collection_data BLOB, created_at REAL, updated_at REAL);",
        "CREATE TABLE records (uri TEXT, did TEXT, collection TEXT, rkey TEXT, cid TEXT, created_at REAL);",
        "CREATE TABLE blocks (cid BLOB, repo_did TEXT, block_data BLOB, content_type TEXT, size INTEGER, created_at REAL);"
    };
    for (NSUInteger i = 0; i < sizeof(schema) / sizeof(schema[0]); i++) {
        char *err = NULL;
        XCTAssertEqual(SQLITE_OK, sqlite3_exec(db, schema[i], NULL, NULL, &err));
        if (err) {
            sqlite3_free(err);
        }
    }

    if (includeAccount) {
        const char *insertAccount =
            "INSERT INTO accounts (did, handle, email, created_at, updated_at) VALUES ('did:plc:test1', 'test.example', 'a@example.com', 1, 1);";
        char *err = NULL;
        XCTAssertEqual(SQLITE_OK, sqlite3_exec(db, insertAccount, NULL, NULL, &err));
        if (err) {
            sqlite3_free(err);
        }
    }

    sqlite3_close(db);
    return dbPath;
}

- (void)testSharedManagerReturnsSameInstance {
    PDSMigrationManager *a = [PDSMigrationManager sharedManager];
    PDSMigrationManager *b = [PDSMigrationManager sharedManager];
    XCTAssertEqual(a, b);
}

- (void)testEstimatedMigrateTimeUsesFileSizeInMiB {
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"migration-size-%@.db", [[NSUUID UUID] UUIDString]]];
    NSMutableData *data = [NSMutableData dataWithLength:(2 * 1024 * 1024) + 123];
    XCTAssertTrue([data writeToFile:tmpPath atomically:YES]);

    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSUInteger estimate = [manager estimatedMigrateTimeWithSourcePath:tmpPath];
    XCTAssertEqual(estimate, (NSUInteger)2);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

- (void)testMigrateFromMissingSourceReturnsSourceNotFound {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSString *missingPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"missing-%@.db", [[NSUUID UUID] UUIDString]]];
    NSError *error = nil;
    BOOL ok = [manager migrateFromMonolithicDatabase:missingPath
                             toSingleTenantDirectory:NSTemporaryDirectory()
                                               error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqualObjects(error.domain, PDSMigrationErrorDomain);
    XCTAssertEqual(error.code, PDSMigrationErrorSourceNotFound);
}

- (void)testMigrateAsyncInvokesCompletionWithErrorForMissingSource {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSString *missingPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"missing-async-%@.db", [[NSUUID UUID] UUIDString]]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    __block NSError *completionError = nil;

    [manager migrateFromMonolithicDatabaseAsync:missingPath
                        toSingleTenantDirectory:NSTemporaryDirectory()
                                     completion:^(NSError * _Nullable error) {
        completionError = error;
        [expectation fulfill];
    }];

    [self waitForExpectations:@[expectation] timeout:2.0];
    XCTAssertNotNil(completionError);
    XCTAssertEqualObjects(completionError.domain, PDSMigrationErrorDomain);
    XCTAssertEqual(completionError.code, PDSMigrationErrorSourceNotFound);
}

- (void)testMigrateEmptyDatabaseSucceedsAndReportsCompletionProgress {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSString *sourcePath = [self createSourceDatabaseWithAccounts:NO];
    NSString *destination = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"migration-dest-%@", [[NSUUID UUID] UUIDString]]];
    __block double lastProgress = 0.0;
    __block NSString *lastStatus = nil;
    XCTestExpectation *progressExpectation = [self expectationWithDescription:@"progress complete"];
    manager.progressBlock = ^(double progress, NSString *status) {
        lastProgress = progress;
        lastStatus = status;
        if (progress >= 1.0) {
            [progressExpectation fulfill];
        }
    };

    NSError *error = nil;
    BOOL ok = [manager migrateFromMonolithicDatabase:sourcePath toSingleTenantDirectory:destination error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    [self waitForExpectations:@[progressExpectation] timeout:2.0];
    XCTAssertEqual(lastProgress, 1.0);
    XCTAssertEqualObjects(lastStatus, @"Migration complete");

    [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
}

- (void)testMigrateCancellationReturnsCancelledError {
    PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
    NSString *sourcePath = [self createSourceDatabaseWithAccounts:YES];
    NSString *destination = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"migration-cancel-%@", [[NSUUID UUID] UUIDString]]];
    manager.cancelBlock = ^BOOL{
        return YES;
    };

    NSError *error = nil;
    BOOL ok = [manager migrateFromMonolithicDatabase:sourcePath toSingleTenantDirectory:destination error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSMigrationErrorDomain);
    XCTAssertEqual(error.code, PDSMigrationErrorCancelled);

    [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
}

@end
