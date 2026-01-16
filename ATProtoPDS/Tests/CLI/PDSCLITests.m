#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"

@interface PDSCLITests : XCTestCase
@property (nonatomic, strong) PDSCLIDispatcher *dispatcher;
@property (nonatomic, strong) PDSCLICommandContext *context;
@end

@implementation PDSCLITests

- (void)setUp {
    [super setUp];
    self.dispatcher = [PDSCLIDispatcher sharedDispatcher];
    self.context = [[PDSCLICommandContext alloc] init];
}

- (void)tearDown {
    self.dispatcher = nil;
    self.context = nil;
    [super tearDown];
}

- (void)testHelpCommand {
    XCTAssertNoThrow([self.dispatcher dispatchWithCommandName:@"help" arguments:@[] context:self.context], @"Help command should not throw");
}

- (void)testHealthCommand {
    XCTAssertNoThrow([self.dispatcher dispatchWithCommandName:@"health" arguments:@[] context:self.context], @"Health command should not throw");
}

- (void)testVersionCommand {
    XCTAssertNoThrow([self.dispatcher dispatchWithCommandName:@"version" arguments:@[] context:self.context], @"Version command should not throw");
}

- (void)testUnknownCommand {
    XCTAssertNoThrow([self.dispatcher dispatchWithCommandName:@"nonexistent" arguments:@[] context:self.context], @"Unknown command should not throw");
}

- (void)testHelpWithCommandArgument {
    XCTAssertNoThrow([self.dispatcher dispatchWithCommandName:@"help" arguments:@[@"serve"] context:self.context], @"Help with command should not throw");
}

- (void)testServeCommandExists {
    id serveCmd = [self.dispatcher commandForName:@"serve"];
    XCTAssertNotNil(serveCmd, @"Serve command should exist");
}

- (void)testAccountCommandExists {
    id accountCmd = [self.dispatcher commandForName:@"account"];
    XCTAssertNotNil(accountCmd, @"Account command should exist");
}

- (void)testRepoCommandExists {
    id repoCmd = [self.dispatcher commandForName:@"repo"];
    XCTAssertNotNil(repoCmd, @"Repo command should exist");
}

- (void)testInviteCommandExists {
    id inviteCmd = [self.dispatcher commandForName:@"invite"];
    XCTAssertNotNil(inviteCmd, @"Invite command should exist");
}

- (void)testDatabaseCommandExists {
    id dbCmd = [self.dispatcher commandForName:@"database"];
    XCTAssertNotNil(dbCmd, @"Database command should exist");
}

- (void)testNukeCommandExists {
    id nukeCmd = [self.dispatcher commandForName:@"nuke"];
    XCTAssertNotNil(nukeCmd, @"Nuke command should exist");
}

- (void)testContextInitialization {
    XCTAssertNotNil(self.context);
    XCTAssertNotNil(self.context.dataDir);
}

- (void)testContextWithArguments {
    PDSCLICommandContext *ctx = [[PDSCLICommandContext alloc] init];
    ctx.dataDir = @"/test/path";
    XCTAssertNotNil(ctx);
    XCTAssertEqualObjects(ctx.dataDir, @"/test/path");
}

- (void)testDispatcherIsSingleton {
    PDSCLIDispatcher *dispatcher1 = [PDSCLIDispatcher sharedDispatcher];
    PDSCLIDispatcher *dispatcher2 = [PDSCLIDispatcher sharedDispatcher];
    XCTAssertEqualObjects(dispatcher1, dispatcher2);
}

@end
