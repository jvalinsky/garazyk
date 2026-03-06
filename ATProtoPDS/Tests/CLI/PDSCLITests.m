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

- (void)testHelpCommandMatchesRc {
    int rc = [self.dispatcher dispatchWithCommandName:@"help" arguments:@[] context:self.context];
    XCTAssertEqual(rc, 0);
}

- (void)testHealthCommandMatchesRc {
    int rc = [self.dispatcher dispatchWithCommandName:@"health" arguments:@[] context:self.context];
    XCTAssertEqual(rc, 0);
}

- (void)testVersionCommandMatchesRc {
    int rc = [self.dispatcher dispatchWithCommandName:@"version" arguments:@[] context:self.context];
    XCTAssertEqual(rc, 0);
}

- (void)testUnknownCommandMatchesReturnCode {
    int rc = [self.dispatcher dispatchWithCommandName:@"nonexistent" arguments:@[] context:self.context];
    XCTAssertEqual(rc, 1);
}

- (void)testHelpWithCommandArgumentMatchesRc {
    int rc = [self.dispatcher dispatchWithCommandName:@"help" arguments:@[@"serve"] context:self.context];
    XCTAssertEqual(rc, 0);
}

- (void)testServeCommandExists {
    id serveCmd = [self.dispatcher commandForName:@"serve"];
    XCTAssertNotNil(serveCmd, @"Serve command should exist");
    XCTAssertTrue([serveCmd conformsToProtocol:@protocol(PDSCLICommand)]);
}

- (void)testAccountCommandExists {
    id accountCmd = [self.dispatcher commandForName:@"account"];
    XCTAssertNotNil(accountCmd, @"Account command should exist");
    XCTAssertTrue([accountCmd conformsToProtocol:@protocol(PDSCLICommand)]);
}

- (void)testRepoCommandExists {
    id repoCmd = [self.dispatcher commandForName:@"repo"];
    XCTAssertNotNil(repoCmd, @"Repo command should exist");
    XCTAssertTrue([repoCmd conformsToProtocol:@protocol(PDSCLICommand)]);
}

- (void)testInviteCommandExists {
    id inviteCmd = [self.dispatcher commandForName:@"invite"];
    XCTAssertNotNil(inviteCmd, @"Invite command should exist");
    XCTAssertTrue([inviteCmd conformsToProtocol:@protocol(PDSCLICommand)]);
}

- (void)testNukeCommandExists {
    id nukeCmd = [self.dispatcher commandForName:@"nuke"];
    XCTAssertNotNil(nukeCmd, @"Nuke command should exist");
    XCTAssertTrue([nukeCmd conformsToProtocol:@protocol(PDSCLICommand)]);
}

- (void)testContextInitialization {
    XCTAssertNotNil(self.context);
    XCTAssertNotNil(self.context.dataDir);
    XCTAssertTrue([self.context isKindOfClass:[PDSCLICommandContext class]]);
}

- (void)testContextWithArgumentsMatchesDataDir {
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
