#import <XCTest/XCTest.h>
#import "AppView/Services/AgeAssuranceService.h"
#import "Database/PDSDatabase.h"

@interface AgeAssuranceServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) AgeAssuranceService *service;
@end

@implementation AgeAssuranceServiceTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"age_test.db"];
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];

    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];

    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);

    [self setupSchema];
    self.service = [[AgeAssuranceService alloc] initWithDatabase:self.database emailProvider:nil];
}

- (void)setupSchema {
    NSError *error = nil;
    NSString *createTable = @"CREATE TABLE IF NOT EXISTS age_assurance_states ("
        @"id TEXT PRIMARY KEY, did TEXT, status TEXT, email TEXT, country_code TEXT, region_code TEXT, "
        @"language TEXT, token TEXT, created_at REAL, updated_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createTable params:@[] error:&error], @"Table create: %@", error);
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

- (void)testBeginAgeAssurance_Valid_ReturnsPending {
    NSError *error = nil;
    NSDictionary *result = [self.service beginAgeAssurance:@"did:plc:test"
                                           email:@"test@example.com"
                                        language:@"en"
                                     countryCode:@"US"
                                      regionCode:nil
                                           error:&error];

    XCTAssertNotNil(result, @"Should return result");
    XCTAssertNil(error, @"No error: %@", error);
    XCTAssertEqualObjects(result[@"status"], @"pending");
}

- (void)testGetAgeAssuranceConfig_ReturnsConfig {
    NSError *error = nil;
    NSDictionary *config = [self.service getAgeAssuranceConfig:&error];

    XCTAssertNotNil(config, @"Should return config");
    XCTAssertNotNil(config[@"regions"], @"Config should have regions");
}

@end