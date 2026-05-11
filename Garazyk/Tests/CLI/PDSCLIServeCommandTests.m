// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"

@interface PDSCLIServeCommandTests : XCTestCase
@end

@implementation PDSCLIServeCommandTests

- (void)testServeCommand_Name {
    Class cmdClass = NSClassFromString(@"PDSCLIServeCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLIServeCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    XCTAssertEqualObjects([cmd performSelector:NSSelectorFromString(@"name")], @"serve");
}

- (void)testServeCommand_Summary {
    Class cmdClass = NSClassFromString(@"PDSCLIServeCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLIServeCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    NSString *summary = [cmd performSelector:NSSelectorFromString(@"summary")];
    XCTAssertNotNil(summary);
}

@end

#pragma mark - PDSCLIHealthCommand Tests

@interface PDSCLIHealthCommandTests : XCTestCase
@end

@implementation PDSCLIHealthCommandTests

- (void)testHealthCommand_Name {
    Class cmdClass = NSClassFromString(@"PDSCLIHealthCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLIHealthCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    XCTAssertEqualObjects([cmd performSelector:NSSelectorFromString(@"name")], @"status");
    NSArray *aliases = [cmd performSelector:NSSelectorFromString(@"aliases")];
    XCTAssertTrue([aliases containsObject:@"health"]);
}

- (void)testHealthCommand_Exists {
    Class cmdClass = NSClassFromString(@"PDSCLIHealthCommand");
    XCTAssertNotNil(cmdClass);
}

@end

#pragma mark - PDSCLINukeCommand Tests

@interface PDSCLINukeCommandTests : XCTestCase
@end

@implementation PDSCLINukeCommandTests

- (void)testNukeCommand_Name {
    Class cmdClass = NSClassFromString(@"PDSCLINukeCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLINukeCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    XCTAssertEqualObjects([cmd performSelector:NSSelectorFromString(@"name")], @"nuke-data");
    NSArray *aliases = [cmd performSelector:NSSelectorFromString(@"aliases")];
    XCTAssertTrue([aliases containsObject:@"nuke"]);
}

- (void)testNukeCommand_HelpText {
    Class cmdClass = NSClassFromString(@"PDSCLINukeCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLINukeCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    NSString *help = [cmd performSelector:NSSelectorFromString(@"helpText")];
    NSString *lowercaseHelp = [help lowercaseString];
    XCTAssertTrue([lowercaseHelp containsString:@"danger"] || [lowercaseHelp containsString:@"delete"]);
}

@end