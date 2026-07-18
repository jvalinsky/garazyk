// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"
#import "CLI/PDSCLIDispatcher.h"

extern void PDSCLIRegisterAllCommands(void);

@interface PDSCLIRegisterAllTests : XCTestCase
@property (nonatomic, strong) PDSCLIDispatcher *dispatcher;
@end

@implementation PDSCLIRegisterAllTests

- (void)setUp {
    [super setUp];
    self.dispatcher = [PDSCLIDispatcher sharedDispatcher];
}

- (void)tearDown {
    [self.dispatcher resetCommandsToDefaults];
    self.dispatcher = nil;
    [super tearDown];
}

#pragma mark - Function existence

- (void)testRegisterAllFunctionExists {
    void (*fn)(void) = (void (*)(void))&PDSCLIRegisterAllCommands;
    // ARC forbids XCTAssertNotNil on a C function pointer (it expects `id`).
    // The equivalent nil-check for a function pointer is the comparison form.
    XCTAssertTrue(fn != NULL, @"PDSCLIRegisterAllCommands must be linked");
}

#pragma mark - Commands registered after call

- (void)testRegisterAllAddsHelpCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"help"];
    XCTAssertNotNil(cmd, @"help must be registered");
}

- (void)testRegisterAllAddsVersionCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"version"];
    XCTAssertNotNil(cmd, @"version must be registered");
}

- (void)testRegisterAllAddsServeCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"serve"];
    XCTAssertNotNil(cmd, @"serve must be registered");
}

- (void)testRegisterAllAddsHealthCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"status"];
    XCTAssertNotNil(cmd, @"status (health) must be registered");
}

- (void)testRegisterAllAddsAdminCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    XCTAssertNotNil(cmd, @"admin must be registered");
}

- (void)testRegisterAllAddsNukeCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"nuke-data"];
    XCTAssertNotNil(cmd, @"nuke-data must be registered");
}

- (void)testRegisterAllAddsAccountCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"account"];
    XCTAssertNotNil(cmd, @"account must be registered");
}

- (void)testRegisterAllAddsRepoCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"repo"];
    XCTAssertNotNil(cmd, @"repo must be registered");
}

- (void)testRegisterAllAddsDaemonCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"daemon"];
    XCTAssertNotNil(cmd, @"daemon must be registered");
}

- (void)testRegisterAllAddsOAuthCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    XCTAssertNotNil(cmd, @"oauth must be registered");
}

- (void)testRegisterAllAddsInitCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"init"];
    XCTAssertNotNil(cmd, @"init must be registered");
}

- (void)testRegisterAllAddsInviteCommand {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"invite"];
    XCTAssertNotNil(cmd, @"invite must be registered");
}

#pragma mark - Idempotency

- (void)testRegisterAllIsIdempotent {
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> first = [self.dispatcher commandForName:@"help"];
    PDSCLIRegisterAllCommands();
    id<PDSCLICommand> second = [self.dispatcher commandForName:@"help"];
    XCTAssertEqual(first, second, @"Repeated registration should return same instance");
}

#pragma mark - All registered commands conform to protocol

- (void)testAllRegisteredCommandsConformToProtocol {
    PDSCLIRegisterAllCommands();
    NSArray *names = @[@"help", @"version", @"serve", @"status", @"admin",
                       @"nuke-data", @"account", @"repo", @"daemon",
                       @"oauth", @"init", @"invite"];
    for (NSString *name in names) {
        id<PDSCLICommand> cmd = [self.dispatcher commandForName:name];
        XCTAssertTrue([cmd conformsToProtocol:@protocol(PDSCLICommand)],
                      @"%@ must conform to PDSCLICommand", name);
    }
}

#pragma mark - All registered commands have non-empty metadata

- (void)testAllRegisteredCommandsHaveName {
    PDSCLIRegisterAllCommands();
    NSArray *names = @[@"help", @"version", @"serve", @"status", @"admin",
                       @"nuke-data", @"account", @"repo", @"daemon",
                       @"oauth", @"init", @"invite"];
    for (NSString *name in names) {
        id<PDSCLICommand> cmd = [self.dispatcher commandForName:name];
        XCTAssertNotNil(cmd.name, @"%@ must have a name", name);
        XCTAssertEqualObjects(cmd.name, name, @"%@ name must match", name);
    }
}

- (void)testAllRegisteredCommandsHaveSummary {
    PDSCLIRegisterAllCommands();
    NSArray *names = @[@"help", @"version", @"serve", @"status", @"admin",
                       @"nuke-data", @"account", @"repo", @"daemon",
                       @"oauth", @"init", @"invite"];
    for (NSString *name in names) {
        id<PDSCLICommand> cmd = [self.dispatcher commandForName:name];
        XCTAssertNotNil(cmd.summary, @"%@ must have a summary", name);
        XCTAssertTrue(cmd.summary.length > 0, @"%@ summary must not be empty", name);
    }
}

- (void)testAllRegisteredCommandsHaveUsage {
    PDSCLIRegisterAllCommands();
    NSArray *names = @[@"help", @"version", @"serve", @"status", @"admin",
                       @"nuke-data", @"account", @"repo", @"daemon",
                       @"oauth", @"init", @"invite"];
    for (NSString *name in names) {
        id<PDSCLICommand> cmd = [self.dispatcher commandForName:name];
        XCTAssertNotNil(cmd.usage, @"%@ must have a usage string", name);
        XCTAssertTrue(cmd.usage.length > 0, @"%@ usage must not be empty", name);
    }
}

@end
