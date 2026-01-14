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

- (void)testRepoListCommand {
    // Check if repo command exists
    id repoCmd = [self.dispatcher commandForName:@"repo"];
    if (repoCmd) {
        XCTAssertNoThrow([self.dispatcher dispatchWithCommandName:@"repo" arguments:@[@"list"] context:self.context], @"Repo list command should not throw");
    }
}

- (void)testVersionCommand {
    XCTAssertNoThrow([self.dispatcher dispatchWithCommandName:@"version" arguments:@[] context:self.context], @"Version command should not throw");
}

@end
