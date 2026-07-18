// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"
#import "CLI/PDSCLIDispatcher.h"

@interface PDSCLIOAuthCommandTests : XCTestCase
@property (nonatomic, strong) PDSCLIDispatcher *dispatcher;
@property (nonatomic, strong) PDSCLICommandContext *context;
@property (nonatomic, strong) NSString *testDirectory;
@end

@implementation PDSCLIOAuthCommandTests

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

- (void)testOAuthCommandClassExists {
    Class cls = NSClassFromString(@"PDSCLIOAuthCommand");
    XCTAssertNotNil(cls, @"PDSCLIOAuthCommand class must be linked");
}

#pragma mark - Metadata via dispatcher lookup

- (void)testOAuthCommandRegisteredByName {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    XCTAssertNotNil(cmd);
}

- (void)testOAuthCommandNameIsOAuth {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    XCTAssertEqualObjects(cmd.name, @"oauth");
}

- (void)testOAuthCommandSummaryNotNil {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    XCTAssertNotNil(cmd.summary);
    XCTAssertTrue(cmd.summary.length > 0);
}

- (void)testOAuthCommandUsageContainsKaszlak {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    XCTAssertTrue([cmd.usage containsString:@"kaszlak"]);
}

- (void)testOAuthCommandHelpTextNotNil {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    XCTAssertNotNil(cmd.helpText);
}

#pragma mark - No args prints help

- (void)testOAuthNoArgsReturnsZero {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    int rc = [cmd executeWithArguments:@[] context:self.context];
    XCTAssertEqual(rc, 0, @"oauth with no args should print help and return 0");
}

#pragma mark - Unknown top-level subcommand

- (void)testOAuthUnknownSubcommandReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    int rc = [cmd executeWithArguments:@[@"frobnicate"] context:self.context];
    XCTAssertEqual(rc, 1, @"Unknown subcommand should return 1");
}

#pragma mark - client subcommand

- (void)testOAuthClientNoArgsReturnsZero {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    int rc = [cmd executeWithArguments:@[@"client"] context:self.context];
    XCTAssertEqual(rc, 0, @"oauth client with no args should print client help");
}

#pragma mark - client register (missing flags)

- (void)testOAuthClientRegisterMissingClientIdReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    int rc = [cmd executeWithArguments:@[@"client", @"register"] context:self.context];
    XCTAssertEqual(rc, 1, @"Missing --client-id should fail");
}

- (void)testOAuthClientRegisterMissingRedirectUriReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    int rc = [cmd executeWithArguments:@[@"client", @"register", @"--client-id", @"my-app"] context:self.context];
    XCTAssertEqual(rc, 1, @"Missing --redirect-uri should fail");
}

#pragma mark - client delete (missing arg)

- (void)testOAuthClientDeleteMissingIdReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    int rc = [cmd executeWithArguments:@[@"client", @"delete"] context:self.context];
    XCTAssertEqual(rc, 1, @"Missing client-id should fail");
}

#pragma mark - client unknown subcommand

- (void)testOAuthClientUnknownSubSubcommandReturnsError {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    int rc = [cmd executeWithArguments:@[@"client", @"frobnicate"] context:self.context];
    XCTAssertEqual(rc, 1, @"Unknown client sub-subcommand should fail");
}

#pragma mark - Aliases

- (void)testOAuthAliasesContainOAuth {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    NSArray *aliases = [cmd aliases];
    XCTAssertTrue([aliases containsObject:@"oauth"], @"OAuth command should list 'oauth' as alias");
}

#pragma mark - Protocol conformance

- (void)testOAuthCommandConformsToProtocol {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    XCTAssertTrue([cmd conformsToProtocol:@protocol(PDSCLICommand)]);
}

#pragma mark - Help text content

- (void)testOAuthHelpTextMentionsClient {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    NSString *help = cmd.helpText;
    XCTAssertTrue([help containsString:@"client"], @"Help should mention 'client' subcommand");
}

- (void)testOAuthHelpTextMentionsRegister {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    NSString *help = cmd.helpText;
    XCTAssertTrue([help containsString:@"register"], @"Help should mention 'register' subcommand");
}

- (void)testOAuthHelpTextMentionsList {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    NSString *help = cmd.helpText;
    XCTAssertTrue([help containsString:@"list"], @"Help should mention 'list' subcommand");
}

- (void)testOAuthHelpTextMentionsDelete {
    id<PDSCLICommand> cmd = [self.dispatcher commandForName:@"oauth"];
    NSString *help = cmd.helpText;
    XCTAssertTrue([help containsString:@"delete"], @"Help should mention 'delete' subcommand");
}

@end
