// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIRelayCommand.h"

@interface PDSCLIRelayCommandTests : XCTestCase
@end

@implementation PDSCLIRelayCommandTests

- (void)testCommandName {
    PDSCLIRelayCommand *cmd = [[PDSCLIRelayCommand alloc] init];
    XCTAssertEqualObjects(cmd.name, @"relay");
}

- (void)testCommandAliases {
    PDSCLIRelayCommand *cmd = [[PDSCLIRelayCommand alloc] init];
    NSArray *aliases = cmd.aliases;
    XCTAssertTrue([aliases containsObject:@"bgs"]);
    XCTAssertTrue([aliases containsObject:@"relayd"]);
}

- (void)testCommandSummary {
    PDSCLIRelayCommand *cmd = [[PDSCLIRelayCommand alloc] init];
    XCTAssertTrue([cmd.summary containsString:@"Relay"]);
}

- (void)testCommandHelpText {
    PDSCLIRelayCommand *cmd = [[PDSCLIRelayCommand alloc] init];
    NSString *help = cmd.helpText;
    XCTAssertTrue([help containsString:@"serve"]);
    XCTAssertTrue([help containsString:@"status"]);
    XCTAssertTrue([help containsString:@"upstream"]);
}

- (void)testCommandUsage {
    PDSCLIRelayCommand *cmd = [[PDSCLIRelayCommand alloc] init];
    XCTAssertTrue([cmd.usage containsString:@"relay"]);
}

@end
