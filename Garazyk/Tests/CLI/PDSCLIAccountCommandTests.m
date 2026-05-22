// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"
#import "CLI/PDSCLIDispatcher.h"
#import "Database/PDSDatabase.h"

// Mock Context to capture output
@interface MockCLICommandContext : PDSCLICommandContext
@property (nonatomic, strong) NSMutableArray<NSString *> *infoMessages;
@property (nonatomic, strong) NSMutableArray<NSString *> *errorMessages;
@property (nonatomic, strong) NSMutableArray<id> *jsonOutputs;
@end

@implementation MockCLICommandContext

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

@interface PDSCLIAccountCommandTests : XCTestCase
@property (nonatomic, strong) PDSCLIDispatcher *dispatcher;
@property (nonatomic, strong) MockCLICommandContext *context;
@property (nonatomic, copy) NSString *tempDir;
@end

@implementation PDSCLIAccountCommandTests

- (void)setUp {
    [super setUp];
    
    // Create a temporary directory for the test execution
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"pds-test-%@", uuid]];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.tempDir stringByAppendingPathComponent:@"service"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    XCTAssertNil(error, @"Failed to create temp directory");
    
    self.dispatcher = [PDSCLIDispatcher sharedDispatcher];
    self.context = [[MockCLICommandContext alloc] init];
    self.context.dataDir = self.tempDir;
    self.context.dataDirExplicitlySet = YES;
    self.context.configPath = [self.tempDir stringByAppendingPathComponent:@"config.json"];
    
    // Write a dummy config file to avoid picking up the project's config.json
    NSDictionary *dummyConfig = @{@"server": @{}, @"plc": @{@"url": @"mock"}};
    NSData *configData = [NSJSONSerialization dataWithJSONObject:dummyConfig options:0 error:nil];
    [configData writeToFile:self.context.configPath atomically:YES];
    
    // Ensure we start with a clean state for the command execution
    // (Though PDSDatabase handles schema creation, we rely on the command to open it)
    setenv("PDS_NON_INTERACTIVE", "1", 1);
    setenv("PLC_URL", "mock", 1);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    self.dispatcher = nil;
    self.context = nil;
    [super tearDown];
}

- (void)testCreateAccountSuccess {
    NSArray *args = @[@"create", @"--email", @"test@example.com", @"--handle", @"test.example.com", @"--password", @"password123"];
    
    int rc = [self.dispatcher dispatchWithCommandName:@"account" arguments:args context:self.context];
    XCTAssertEqual(rc, 0);
    
    // Verify output
    BOOL foundSuccessMessage = NO;
    for (NSString *msg in self.context.infoMessages) {
        if ([msg containsString:@"Account created successfully"]) {
            foundSuccessMessage = YES;
            break;
        }
    }
    XCTAssertTrue(foundSuccessMessage, @"Should output success message");
    
    // Verify database content
    NSString *dbPath = [[self.tempDir stringByAppendingPathComponent:@"service"] stringByAppendingPathComponent:@"service.db"];
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    NSError *error = nil;
    XCTAssertTrue([db openWithError:&error]);
    
    PDSDatabaseAccount *account = [db getAccountByHandle:@"test.example.com" error:&error];
    XCTAssertNotNil(account);
    XCTAssertEqualObjects(account.email, @"test@example.com");
    XCTAssertTrue([account.did hasPrefix:@"did:plc:"], @"DID should be generated");
    
    [db close];
}

- (void)testCreateAccountMissingArguments {
    NSArray *args = @[@"create", @"--email", @"test@example.com"];
    
    [self.dispatcher dispatchWithCommandName:@"account" arguments:args context:self.context];
    
    XCTAssertTrue(self.context.errorMessages.count > 0);
    XCTAssertTrue([self.context.errorMessages[0] containsString:@"Missing required arguments"]);
}

- (void)testCreateAccountDuplicateHandle {
    // Set up original account
    NSArray *args = @[@"create", @"--email", @"test1@example.com", @"--handle", @"duplicate.example.com", @"--password", @"pw1"];
    [self.dispatcher dispatchWithCommandName:@"account" arguments:args context:self.context];
    
    // Try to create second account with same handle
    NSArray *args2 = @[@"create", @"--email", @"test2@example.com", @"--handle", @"duplicate.example.com", @"--password", @"pw2"];
    [self.dispatcher dispatchWithCommandName:@"account" arguments:args2 context:self.context];
    
    BOOL foundErrorMessage = NO;
    for (NSString *msg in self.context.errorMessages) {
        if ([msg containsString:@"Failed to create account"]) {
            foundErrorMessage = YES;
            break;
        }
    }
    XCTAssertTrue(foundErrorMessage, @"Should report failure for duplicate handle");
}

- (void)testListAccounts {
    // Create two accounts
    NSArray *createAArgs = @[@"create", @"--email", @"a@e.com", @"--handle", @"a.example.com", @"--password", @"pw-a"];
    XCTAssertEqual([self.dispatcher dispatchWithCommandName:@"account" arguments:createAArgs context:self.context], 0);
    NSArray *createBArgs = @[@"create", @"--email", @"b@e.com", @"--handle", @"b.example.com", @"--password", @"pw-b"];
    XCTAssertEqual([self.dispatcher dispatchWithCommandName:@"account" arguments:createBArgs context:self.context], 0);
    
    // Clear messages from creation
    [self.context.infoMessages removeAllObjects];
    [self.context.errorMessages removeAllObjects];
    
    // List
    [self.dispatcher dispatchWithCommandName:@"account" arguments:@[@"list"] context:self.context];
    
    // Check output contains handles - capturing stdout via printf is hard, but PDSCLIAccountCommand uses printf for table output.
    // Wait, PDSCLIAccountCommand uses printf directly for the list table! 
    // `printf` writes to stdout, which MockCLICommandContext cannot capture via `printInfo`.
    // However, `PDSCLIAccountCommand` prints "Total accounts: 2" using printf as well.
    // BUT, if we use --json, it uses context.printJSON.
    
    // Let's rely on JSON output test for verifying content.
    // For text output, we can't easily assert on the table content without redirecting stdout, 
    // which is risky in parallel tests. 
    // But we can check that it didn't error.
    XCTAssertEqual(self.context.errorMessages.count, 0);
}

- (void)testListAccountsJSON {
    // Create account
    NSArray *createArgs = @[@"create", @"--email", @"json@e.com", @"--handle", @"json.example.com", @"--password", @"pw-json"];
    XCTAssertEqual([self.dispatcher dispatchWithCommandName:@"account" arguments:createArgs context:self.context], 0);
    
    self.context.jsonOutput = YES;
    [self.dispatcher dispatchWithCommandName:@"account" arguments:@[@"list"] context:self.context];
    
    XCTAssertTrue(self.context.jsonOutputs.count > 0);
    NSArray *list = self.context.jsonOutputs.lastObject;
    XCTAssertTrue([list isKindOfClass:[NSArray class]]);
    XCTAssertEqual(list.count, 1);
    XCTAssertEqualObjects(list[0][@"handle"], @"json.example.com");
}

- (void)testInfoCommand {
    // Create account
    NSArray *createArgs = @[@"create", @"--email", @"info@e.com", @"--handle", @"info.example.com", @"--password", @"pw-info"];
    XCTAssertEqual([self.dispatcher dispatchWithCommandName:@"account" arguments:createArgs context:self.context], 0);
    
    // Get info
    self.context.jsonOutput = YES; // Use JSON to capture output easily
    [self.dispatcher dispatchWithCommandName:@"account" arguments:@[@"info", @"info.example.com"] context:self.context];
    
    XCTAssertTrue(self.context.jsonOutputs.count > 0);
    NSDictionary *info = self.context.jsonOutputs.lastObject;
    XCTAssertEqualObjects(info[@"email"], @"info@e.com");
}

@end
