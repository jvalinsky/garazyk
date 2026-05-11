// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"

@interface PDSCLICommandEdgeCaseTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSCLICommandContext *testContext;
@end

@implementation PDSCLICommandEdgeCaseTests

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

- (void)testContext_InitWithDirectory {
    XCTAssertNotNil(self.testContext);
    XCTAssertEqualObjects(self.testContext.dataDir, self.testDirectory);
}

- (void)testContext_NilJsonOutput {
    XCTAssertFalse(self.testContext.jsonOutput);
}

- (void)testContext_SetJsonOutput {
    self.testContext.jsonOutput = YES;
    XCTAssertTrue(self.testContext.jsonOutput);
}

- (void)testPDSBaseCommand_Exists {
    Class cmdClass = NSClassFromString(@"PDSBaseCommand");
    XCTAssertNotNil(cmdClass);
}

- (void)testPDSCLICommandContext_Exists {
    XCTAssertTrue([self.testContext isKindOfClass:[PDSCLICommandContext class]]);
}

@end