// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"
#import "CLI/PDSCLIDispatcher.h"
#import "Database/PDSDatabase.h"
#import "Core/ATProtoValidator.h"

@interface PDSCLIRepoTestContext : PDSCLICommandContext
@property (nonatomic, strong) NSMutableArray<NSString *> *infoMessages;
@property (nonatomic, strong) NSMutableArray<NSString *> *errorMessages;
@property (nonatomic, strong) NSMutableArray<id> *jsonOutputs;
@end

@implementation PDSCLIRepoTestContext

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

@interface PDSCLIRepoCommandTests : XCTestCase
@property (nonatomic, strong) PDSCLIDispatcher *dispatcher;
@property (nonatomic, strong) PDSCLIRepoTestContext *context;
@property (nonatomic, copy) NSString *tempDir;
@end

@implementation PDSCLIRepoCommandTests

- (void)setUp {
    [super setUp];

    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"pds-test-%@", uuid]];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.tempDir stringByAppendingPathComponent:@"service"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    XCTAssertNil(error, @"Failed to create temp directory");

    self.dispatcher = [PDSCLIDispatcher sharedDispatcher];
    self.context = [[PDSCLIRepoTestContext alloc] init];
    self.context.dataDir = self.tempDir;
    self.context.configPath = [self.tempDir stringByAppendingPathComponent:@"config.json"];

    NSDictionary *dummyConfig = @{@"server": @{}, @"plc": @{@"url": @"mock"}};
    NSData *configData = [NSJSONSerialization dataWithJSONObject:dummyConfig options:0 error:nil];
    [configData writeToFile:self.context.configPath atomically:YES];

    setenv("PDS_NON_INTERACTIVE", "1", 1);
    setenv("PLC_URL", "mock", 1);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    self.dispatcher = nil;
    self.context = nil;
    [super tearDown];
}

- (NSString *)createTestAccountWithHandle:(NSString *)handle email:(NSString *)email {
    NSArray *args = @[@"create", @"--email", email, @"--handle", handle, @"--password", @"password123"];
    int rc = [self.dispatcher dispatchWithCommandName:@"account" arguments:args context:self.context];
    XCTAssertEqual(rc, 0);
    XCTAssertEqual(self.context.errorMessages.count, 0);

    NSString *dbPath = [[self.tempDir stringByAppendingPathComponent:@"service"] stringByAppendingPathComponent:@"service.db"];
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    NSError *dbError = nil;
    XCTAssertTrue([db openWithError:&dbError], @"Failed to open test database: %@", dbError.localizedDescription);

    PDSDatabaseAccount *account = [db getAccountByHandle:handle error:&dbError];
    XCTAssertNotNil(account, @"Expected created account for handle %@ (error=%@)", handle, dbError.localizedDescription);
    NSString *did = account.did;
    [db close];

    [self.context.infoMessages removeAllObjects];
    [self.context.errorMessages removeAllObjects];
    [self.context.jsonOutputs removeAllObjects];

    return did;
}

- (void)testCreateRecordWithoutRkeyAutoGeneratesTIDForPost {
    NSString *did = [self createTestAccountWithHandle:@"post-rkey.example.com" email:@"post-rkey@example.com"];
    NSString *postJSON = @"{\"$type\":\"app.bsky.feed.post\",\"text\":\"CLI post\",\"createdAt\":\"2026-03-06T12:00:00Z\"}";

    int rc = [self.dispatcher dispatchWithCommandName:@"repo"
                                            arguments:@[@"create-record", did, @"app.bsky.feed.post", postJSON]
                                              context:self.context];
    XCTAssertEqual(rc, 0);
    XCTAssertEqual(self.context.errorMessages.count, 0, @"Unexpected errors: %@", self.context.errorMessages);

    self.context.jsonOutput = YES;
    [self.dispatcher dispatchWithCommandName:@"repo" arguments:@[@"list", did] context:self.context];
    XCTAssertTrue(self.context.jsonOutputs.count > 0);

    NSArray *records = self.context.jsonOutputs.lastObject;
    XCTAssertTrue([records isKindOfClass:[NSArray class]]);
    XCTAssertEqual(records.count, 1);

    NSDictionary *record = records.firstObject;
    XCTAssertEqualObjects(record[@"collection"], @"app.bsky.feed.post");
    NSString *rkey = record[@"rkey"];
    XCTAssertTrue([rkey isKindOfClass:[NSString class]]);
    XCTAssertTrue([ATProtoValidator validateTID:rkey error:nil], @"Expected post rkey to be a valid TID, got: %@", rkey);
}

- (void)testCreateRecordWithoutRkeyFailsForNonPostCollection {
    NSString *did = [self createTestAccountWithHandle:@"profile-rkey.example.com" email:@"profile-rkey@example.com"];
    NSString *profileJSON = @"{\"$type\":\"app.bsky.actor.profile\",\"displayName\":\"Profile Test\"}";

    int rc = [self.dispatcher dispatchWithCommandName:@"repo"
                                            arguments:@[@"create-record", did, @"app.bsky.actor.profile", profileJSON]
                                              context:self.context];
    XCTAssertEqual(rc, 0);
    XCTAssertTrue(self.context.errorMessages.count > 0);
    XCTAssertTrue([self.context.errorMessages.lastObject containsString:@"rkey is required for non-post collections"]);
}

@end
