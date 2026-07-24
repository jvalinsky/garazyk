// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

/// Failure-path coverage for -[PDSDatabase openWithError:]: a failed
/// sqlite3_open must not leak its error-holding handle or leave a stale
/// non-NULL handle behind, and the open must report NO with an error.
@interface PDSDatabaseOpenFailureTests : XCTestCase
@property (nonatomic, strong) NSString *blockingDirPath;
@end

@implementation PDSDatabaseOpenFailureTests

- (void)setUp {
    [super setUp];
    NSString *name = [@"PDSDatabaseOpenFailureTests_" stringByAppendingString:NSUUID.UUID.UUIDString];
    self.blockingDirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.blockingDirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.blockingDirPath error:nil];
    [super tearDown];
}

- (void)testOpenFailureReportsErrorAndClearsHandle {
    // sqlite3_open on a directory path fails with SQLITE_CANTOPEN.
    PDSDatabase *database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:self.blockingDirPath]];
    NSError *error = nil;
    BOOL opened = [database openWithError:&error];

    XCTAssertFalse(opened);
    XCTAssertNotNil(error);
    XCTAssertFalse(database.isOpen);
    XCTAssertTrue(database.internalSQLiteHandle == NULL,
                  @"failed open must close and clear the error-holding handle");
}

- (void)testRepeatedFailedOpenStaysClosedWithoutCrashing {
    PDSDatabase *database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:self.blockingDirPath]];
    XCTAssertFalse([database openWithError:nil]);
    XCTAssertFalse([database openWithError:nil]);
    XCTAssertFalse(database.isOpen);
    XCTAssertTrue(database.internalSQLiteHandle == NULL);
    [database close];
}

@end
