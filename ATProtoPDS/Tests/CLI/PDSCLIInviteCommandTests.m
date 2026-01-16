#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"
#import "CLI/PDSCLIDispatcher.h"

// Mock Context specific to Invite tests to avoid collision
@interface PDSCLIInviteTestContext : PDSCLICommandContext
@property (nonatomic, strong) NSMutableArray<NSString *> *infoMessages;
@property (nonatomic, strong) NSMutableArray<NSString *> *errorMessages;
@property (nonatomic, strong) NSMutableArray<id> *jsonOutputs;
@end

@implementation PDSCLIInviteTestContext

- (instancetype)init {
    self = [super init];
    if (self) {
        _infoMessages = [NSMutableArray array];
        _errorMessages = [NSMutableArray array];
        _jsonOutputs = [NSMutableArray array];
    }
    return self;
}

- (void)printInfo:(NSString *)info {
    if (info) [self.infoMessages addObject:info];
}

- (void)printError:(NSString *)error {
    if (error) [self.errorMessages addObject:error];
}

- (void)printJSON:(id)object {
    if (object) [self.jsonOutputs addObject:object];
}

@end

@interface PDSCLIInviteCommandTests : XCTestCase
@property (nonatomic, strong) PDSCLIDispatcher *dispatcher;
@property (nonatomic, strong) PDSCLIInviteTestContext *context;
@end

@implementation PDSCLIInviteCommandTests

- (void)setUp {
    [super setUp];
    self.dispatcher = [PDSCLIDispatcher sharedDispatcher];
    self.context = [[PDSCLIInviteTestContext alloc] init];
}

- (void)tearDown {
    self.dispatcher = nil;
    self.context = nil;
    [super tearDown];
}

- (void)testListInvitesJSON {
    self.context.jsonOutput = YES;
    
    // The stub manager returns 3 hardcoded invites
    [self.dispatcher dispatchWithCommandName:@"invite" arguments:@[@"list"] context:self.context];
    
    XCTAssertTrue(self.context.jsonOutputs.count > 0);
    NSArray *list = self.context.jsonOutputs.lastObject;
    XCTAssertTrue([list isKindOfClass:[NSArray class]]);
    XCTAssertEqual(list.count, 2, @"Should return 2 active/valid invites by default (excluding used/disabled)");
    
    NSDictionary *invite1 = list[0];
    XCTAssertEqualObjects(invite1[@"code"], @"ABCD-1234-EFGH-5678");
}

- (void)testListInvitesIncludeUsed {
    self.context.jsonOutput = YES;
    
    // The stub manager has 1 used/disabled invite
    [self.dispatcher dispatchWithCommandName:@"invite" arguments:@[@"list", @"--used"] context:self.context];
    
    XCTAssertTrue(self.context.jsonOutputs.count > 0);
    NSArray *list = self.context.jsonOutputs.lastObject;
    XCTAssertEqual(list.count, 3, @"Should return all 3 invites when --used is passed");
}

- (void)testCreateInvite {
    self.context.jsonOutput = YES;
    
    [self.dispatcher dispatchWithCommandName:@"invite" arguments:@[@"create", @"--uses", @"5"] context:self.context];
    
    XCTAssertTrue(self.context.jsonOutputs.count > 0);
    NSDictionary *result = self.context.jsonOutputs.lastObject;
    
    XCTAssertNotNil(result[@"code"]);
    XCTAssertEqual([result[@"uses"] integerValue], 5);
    XCTAssertEqual([result[@"disabled"] boolValue], NO);
}

- (void)testCreateDisabledInvite {
    self.context.jsonOutput = YES;
    
    [self.dispatcher dispatchWithCommandName:@"invite" arguments:@[@"create", @"--disabled"] context:self.context];
    
    XCTAssertTrue(self.context.jsonOutputs.count > 0);
    NSDictionary *result = self.context.jsonOutputs.lastObject;
    
    XCTAssertEqual([result[@"disabled"] boolValue], YES);
}

- (void)testRevokeInvite {
    [self.dispatcher dispatchWithCommandName:@"invite" arguments:@[@"revoke", @"ABCD-1234"] context:self.context];
    
    BOOL foundSuccess = NO;
    for (NSString *msg in self.context.infoMessages) {
        if ([msg containsString:@"Invite code revoked"]) {
            foundSuccess = YES;
            break;
        }
    }
    XCTAssertTrue(foundSuccess);
}

- (void)testRevokeMissingArg {
    [self.dispatcher dispatchWithCommandName:@"invite" arguments:@[@"revoke"] context:self.context];
    
    XCTAssertTrue(self.context.errorMessages.count > 0);
    XCTAssertTrue([self.context.errorMessages[0] containsString:@"Missing invite code"]);
}

@end
