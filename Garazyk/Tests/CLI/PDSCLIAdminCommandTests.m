// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"
#import "CLI/PDSCLIDispatcher.h"

@interface PDSCLIAdminCommandTests : XCTestCase
@property (nonatomic, strong) PDSCLIDispatcher *dispatcher;
@property (nonatomic, strong) PDSCLICommandContext *context;
@property (nonatomic, strong) NSString *testDirectory;
@end

@implementation PDSCLIAdminCommandTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    self.dispatcher = [PDSCLIDispatcher sharedDispatcher];
    self.context = [[PDSCLICommandContext alloc] init];
    self.context.dataDir = self.testDirectory;
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [self.dispatcher resetCommandsToDefaults];
    self.dispatcher = nil;
    self.context = nil;
    [super tearDown];
}

#pragma mark - Class existence

- (void)testAdminCommandClassExists {
    Class cls = NSClassFromString(@"PDSCLIAdminCommand");
    XCTAssertNotNil(cls, @"PDSCLIAdminCommand class must be linked");
}

#pragma mark - Metadata via dispatcher lookup

- (void)testAdminCommandRegisteredByName {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    XCTAssertNotNil(cmd);
}

- (void)testAdminCommandNameIsAdmin {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    XCTAssertEqualObjects(cmd.name, @"admin");
}

- (void)testAdminCommandSummaryNotNil {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    XCTAssertNotNil(cmd.summary);
    XCTAssertTrue(cmd.summary.length > 0);
}

- (void)testAdminCommandUsageContainsKaszlak {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    XCTAssertTrue([cmd.usage containsString:@"kaszlak"]);
}

- (void)testAdminCommandHelpTextNotNil {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    XCTAssertNotNil(cmd.helpText);
}

#pragma mark - Subcommand parsing (no args -> help text)

- (void)testAdminNoArgsReturnsZero {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    int rc = [cmd executeWithArguments:@[] context:self.context];
    XCTAssertEqual(rc, 0, @"admin with no args should print help and return 0");
}

#pragma mark - Unknown subcommand

- (void)testAdminUnknownSubcommandReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    int rc = [cmd executeWithArguments:@[@"frobnicate"] context:self.context];
    XCTAssertEqual(rc, 1, @"Unknown subcommand should return 1");
}

#pragma mark - list subcommand

- (void)testAdminListSubcommandReturnsZero {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    int rc = [cmd executeWithArguments:@[@"list"] context:self.context];
    XCTAssertEqual(rc, 0);
}

#pragma mark - add subcommand (missing argument)

- (void)testAdminAddMissingArgReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    int rc = [cmd executeWithArguments:@[@"add"] context:self.context];
    XCTAssertEqual(rc, 1, @"admin add with no identifier should fail");
}

#pragma mark - remove subcommand (missing argument)

- (void)testAdminRemoveMissingArgReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    int rc = [cmd executeWithArguments:@[@"remove"] context:self.context];
    XCTAssertEqual(rc, 1, @"admin remove with no DID should fail");
}

#pragma mark - create subcommand (missing required flags)

- (void)testAdminCreateMissingFlagsReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    int rc = [cmd executeWithArguments:@[@"create"] context:self.context];
    XCTAssertEqual(rc, 1, @"admin create without --email/--handle should fail in non-interactive mode");
}

- (void)testAdminCreateOnlyEmailReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    int rc = [cmd executeWithArguments:@[@"create", @"--email", @"test@example.com"] context:self.context];
    XCTAssertEqual(rc, 1, @"admin create without --handle should fail");
}

- (void)testAdminCreateOnlyHandleReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    int rc = [cmd executeWithArguments:@[@"create", @"--handle", @"admin.test.xyz"] context:self.context];
    XCTAssertEqual(rc, 1, @"admin create without --email should fail");
}

#pragma mark - Aliases

- (void)testAdminAliasesIncludeAdmin {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    NSArray *aliases = [cmd aliases];
    XCTAssertTrue([aliases containsObject:@"admin"], @"Admin command should list 'admin' as alias");
}

#pragma mark - Protocol conformance

- (void)testAdminCommandConformsToProtocol {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    XCTAssertTrue([cmd conformsToProtocol:@protocol(PDSCLICommand)]);
}

#pragma mark - Help text content

- (void)testAdminHelpTextMentionsSubcommands {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"admin"];
    NSString *help = cmd.helpText;
    XCTAssertTrue([help containsString:@"list"], @"Help should mention 'list' subcommand");
    XCTAssertTrue([help containsString:@"add"], @"Help should mention 'add' subcommand");
    XCTAssertTrue([help containsString:@"remove"], @"Help should mention 'remove' subcommand");
    XCTAssertTrue([help containsString:@"create"], @"Help should mention 'create' subcommand");
}

@end
