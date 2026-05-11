// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDispatcher.h"
#import "CLI/PDSCLIDefinitions.h"
#import "Admin/PDSAdminAuth.h"
#import "Database/PDSDatabase.h"

@interface PDSCLIDaemonCommandTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSCLICommandContext *testContext;
@end

@implementation PDSCLIDaemonCommandTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    self.testContext = [[PDSCLICommandContext alloc] init];
    self.testContext.dataDir = self.testDirectory;
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testContext_Init {
    XCTAssertNotNil(self.testContext);
    XCTAssertEqualObjects(self.testContext.dataDir, self.testDirectory);
}

- (void)testContext_DataDir {
    XCTAssertNotNil(self.testContext.dataDir);
}

- (void)testContext_JsonOutput_DefaultFalse {
    XCTAssertFalse(self.testContext.jsonOutput);
}

- (void)testContext_JsonOutput_Set {
    self.testContext.jsonOutput = YES;
    XCTAssertTrue(self.testContext.jsonOutput);
}

- (void)testContext_PrintInfo {
    XCTAssertNoThrow([self.testContext printInfo:@"test info"]);
}

- (void)testContext_PrintError {
    XCTAssertNoThrow([self.testContext printError:@"test error"]);
}

- (void)testContext_PrintJSON {
    XCTAssertNoThrow([self.testContext printJSON:@{@"key": @"value"}]);
}

@end