#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Database/Migration/PDSMigrationManager.h"

@interface PDSMigrationManagerTests : XCTestCase
@end

@implementation PDSMigrationManagerTests

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

@end
