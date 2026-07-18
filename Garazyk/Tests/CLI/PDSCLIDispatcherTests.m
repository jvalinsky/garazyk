// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"
#import "CLI/PDSCLIDispatcher.h"

@interface PDSCLIDispatcherTests : XCTestCase
@property (nonatomic, strong) PDSCLIDispatcher *dispatcher;
@property (nonatomic, strong) PDSCLICommandContext *context;
@end

@implementation PDSCLIDispatcherTests

- (void)setUp {
    [super setUp];
    self.dispatcher = [PDSCLIDispatcher sharedDispatcher];
    self.context = [[PDSCLICommandContext alloc] init];
}

- (void)tearDown {
    [self.dispatcher resetCommandsToDefaults];
    self.dispatcher = nil;
    self.context = nil;
    [super tearDown];
}

#pragma mark - Registration

- (void)testAddCommandMakesItDispatchable {
    PDSBaseCommand *cmd = [[PDSBaseCommand alloc] init];
    [self.dispatcher addCommand:cmd];
    id<PDSCLICommand> found = [self.dispatcher commandForName:@"base"];
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.name, @"base");
}

- (void)testAddCommandRegistersAliases {
    PDSBaseCommand *cmd = [[PDSBaseCommand alloc] init];
    [self.dispatcher addCommand:cmd];
    id<PDSCLICommand> found = [self.dispatcher commandForName:@"base"];
    XCTAssertNotNil(found);
}

- (void)testRemoveCommandMakesItUnresolvable {
    PDSBaseCommand *cmd = [[PDSBaseCommand alloc] init];
    [self.dispatcher addCommand:cmd];
    [self.dispatcher removeCommandWithName:@"base"];
    id<PDSCLICommand> found = [self.dispatcher commandForName:@"base"];
    XCTAssertNil(found);
}

- (void)testResetCommandsToDefaultsRestoresBuiltinCommands {
    [self.dispatcher removeCommandWithName:@"help"];
    id<PDSCLICommand> gone = [self.dispatcher commandForName:@"help"];
    XCTAssertNil(gone);

    [self.dispatcher resetCommandsToDefaults];
    id<PDSCLICommand> restored = [self.dispatcher commandForName:@"help"];
    XCTAssertNotNil(restored);
}

#pragma mark - Dispatch

- (void)testDispatchHelpReturnsZero {
    int rc = [self.dispatcher dispatchWithCommandName:@"help" arguments:@[] context:self.context];
    XCTAssertEqual(rc, 0);
}

- (void)testDispatchVersionReturnsZero {
    int rc = [self.dispatcher dispatchWithCommandName:@"version" arguments:@[] context:self.context];
    XCTAssertEqual(rc, 0);
}

- (void)testDispatchUnknownReturnsNotFound {
    int rc = [self.dispatcher dispatchWithCommandName:@"nonexistent-cmd" arguments:@[] context:self.context];
    XCTAssertEqual(rc, PDSCLIExitCodeNotFound);
}

- (void)testDispatchEmptyStringReturnsNotFound {
    int rc = [self.dispatcher dispatchWithCommandName:@"" arguments:@[] context:self.context];
    XCTAssertEqual(rc, PDSCLIExitCodeNotFound);
}

- (void)testDispatchHelpWithSubcommandReturnsZero {
    int rc = [self.dispatcher dispatchWithCommandName:@"help" arguments:@[@"version"] context:self.context];
    XCTAssertEqual(rc, 0);
}

- (void)testDispatchHelpWithUnknownSubcommandReturnsError {
    int rc = [self.dispatcher dispatchWithCommandName:@"help" arguments:@[@"no-such-command"] context:self.context];
    XCTAssertEqual(rc, 1);
}

#pragma mark - Command Lookup

- (void)testCommandForNameReturnsNilForUnknown {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"zzz-not-real"];
    XCTAssertNil(cmd);
}

- (void)testCommandForNameReturnsSameInstance {
    id<PDSCLICommand> a = [self.dispatcher commandForName:@"help"];
    id<PDSCLICommand> b = [self.dispatcher commandForName:@"help"];
    XCTAssertEqual(a, b);
}

- (void)testCommandConformsToProtocol {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"help"];
    XCTAssertTrue([cmd conformsToProtocol:@protocol(PDSCLICommand)]);
}

#pragma mark - Context Defaults

- (void)testContextDefaultsVerboseFalse {
    PDSCLICommandContext *ctx = [[PDSCLICommandContext alloc] init];
    XCTAssertFalse(ctx.verbose);
}

- (void)testContextDefaultsJsonOutputFalse {
    PDSCLICommandContext *ctx = [[PDSCLICommandContext alloc] init];
    XCTAssertFalse(ctx.jsonOutput);
}

- (void)testContextDefaultsDataDirNotNil {
    PDSCLICommandContext *ctx = [[PDSCLICommandContext alloc] init];
    XCTAssertNotNil(ctx.dataDir);
}

- (void)testContextConfigPathDefault {
    PDSCLICommandContext *ctx = [[PDSCLICommandContext alloc] init];
    XCTAssertEqualObjects(ctx.configPath, @"./config.json");
}

- (void)testContextPrintInfoDoesNotThrow {
    XCTAssertNoThrow([self.context printInfo:@"info"]);
}

- (void)testContextPrintErrorDoesNotThrow {
    XCTAssertNoThrow([self.context printError:@"error"]);
}

- (void)testContextPrintJSONDoesNotThrow {
    XCTAssertNoThrow([self.context printJSON:@{@"k": @"v"}]);
}

@end
