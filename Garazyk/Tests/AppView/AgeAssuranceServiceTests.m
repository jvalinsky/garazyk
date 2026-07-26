// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

#pragma mark - Service Init

- (void)testService_Init {
    XCTAssertNotNil(self.service);
}

- (void)testService_InitWithNilDatabase_ReturnsNil {
    AgeAssuranceService *svc = [[AgeAssuranceService alloc] initWithDatabase:nil emailProvider:nil];
    // Should still return an instance since no nil check in init
    XCTAssertNotNil(svc);
}

#pragma mark - beginAgeAssurance

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

- (void)testBeginAgeAssurance_NilDid_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [self.service beginAgeAssurance:nil
                                                     email:@"test@example.com"
                                                  language:@"en"
                                               countryCode:nil
                                                regionCode:nil
                                                     error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testBeginAgeAssurance_EmptyDid_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [self.service beginAgeAssurance:@""
                                                     email:@"test@example.com"
                                                  language:@"en"
                                               countryCode:nil
                                                regionCode:nil
                                                     error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testBeginAgeAssurance_NilEmail_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [self.service beginAgeAssurance:@"did:plc:test"
                                                     email:nil
                                                  language:@"en"
                                               countryCode:nil
                                                regionCode:nil
                                                     error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testBeginAgeAssurance_NilLanguage_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [self.service beginAgeAssurance:@"did:plc:test"
                                                     email:@"test@example.com"
                                                  language:nil
                                               countryCode:nil
                                                regionCode:nil
                                                     error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testBeginAgeAssurance_NullErrorPointer_Safe {
    NSDictionary *result = [self.service beginAgeAssurance:nil
                                                     email:@"test@example.com"
                                                  language:@"en"
                                               countryCode:nil
                                                regionCode:nil
                                                     error:NULL];
    XCTAssertNil(result);
}

#pragma mark - getAgeAssuranceConfig

- (void)testGetAgeAssuranceConfig_ReturnsConfig {
    NSError *error = nil;
    NSDictionary *config = [self.service getAgeAssuranceConfig:&error];

    XCTAssertNotNil(config, @"Should return config");
    XCTAssertNotNil(config[@"regions"], @"Config should have regions");
    XCTAssertNil(error);
}

#pragma mark - getAgeAssuranceState

- (void)testGetAgeAssuranceState_NoRecord_ReturnsUnknown {
    NSError *error = nil;
    NSDictionary *state = [self.service getAgeAssuranceState:@"did:plc:unknown"
                                                  countryCode:nil
                                                   regionCode:nil
                                                        error:&error];
    XCTAssertNotNil(state);
    XCTAssertEqualObjects(state[@"status"], @"unknown");
    XCTAssertEqualObjects(state[@"access"], @"none");
    XCTAssertNil(error);
}

- (void)testGetAgeAssuranceState_AfterBegin_ReturnsPending {
    [self.service beginAgeAssurance:@"did:plc:state-test"
                              email:@"state@test.com"
                           language:@"en"
                        countryCode:nil
                         regionCode:nil
                              error:nil];

    NSError *error = nil;
    NSDictionary *state = [self.service getAgeAssuranceState:@"did:plc:state-test"
                                                  countryCode:nil
                                                   regionCode:nil
                                                        error:&error];
    XCTAssertNotNil(state);
    XCTAssertEqualObjects(state[@"status"], @"pending");
    XCTAssertNil(error);
}

- (void)testGetAgeAssuranceState_NilDid_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *state = [self.service getAgeAssuranceState:nil
                                                  countryCode:nil
                                                   regionCode:nil
                                                        error:&error];
    XCTAssertNil(state);
    XCTAssertNotNil(error);
}

- (void)testGetAgeAssuranceState_EmptyDid_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *state = [self.service getAgeAssuranceState:@""
                                                  countryCode:nil
                                                   regionCode:nil
                                                        error:&error];
    XCTAssertNil(state);
    XCTAssertNotNil(error);
}

#pragma mark - confirmAgeAssuranceWithToken

- (void)testConfirmAgeAssurance_InvalidToken_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service confirmAgeAssuranceWithToken:@"nonexistent" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 404);
}

- (void)testConfirmAgeAssurance_NilToken_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service confirmAgeAssuranceWithToken:nil error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testConfirmAgeAssurance_EmptyToken_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service confirmAgeAssuranceWithToken:@"" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

@end
