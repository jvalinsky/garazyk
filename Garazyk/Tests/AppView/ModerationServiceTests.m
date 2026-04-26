#import <XCTest/XCTest.h>
#import "AppView/Services/ModerationService.h"
#import "Database/PDSDatabase.h"

@interface ModerationServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) ModerationService *service;
@end

@implementation ModerationServiceTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"mod_test.db"];
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];

    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];

    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);

    [self setupSchema];
    self.service = [[ModerationService alloc] initWithDatabase:self.database];
}

- (void)setupSchema {
    NSError *error = nil;
    NSString *createTable = @"CREATE TABLE IF NOT EXISTS moderation_events ("
        @"id TEXT PRIMARY KEY, subject_did TEXT, action TEXT, reason TEXT, "
        @"moderator_did TEXT, created_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createTable params:@[] error:&error], @"Table: %@", error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testService_Init {
    XCTAssertNotNil(self.service);
}

@end