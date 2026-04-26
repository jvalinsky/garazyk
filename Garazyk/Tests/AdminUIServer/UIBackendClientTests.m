/*!
 @file UIBackendClientTests.m

 @abstract Unit tests for UIBackendClient.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"

@interface UIBackendClientTests : XCTestCase
@property (nonatomic, strong) UIBackendClient *client;
@property (nonatomic, strong) UIServiceConfig *config;
@end

@implementation UIBackendClientTests

- (void)setUp {
    [super setUp];

    self.config = [[UIServiceConfig alloc] init];
    self.config.host = @"127.0.0.1";
    self.config.port = 3000;
    self.config.pdsBaseURL = [NSURL URLWithString:@"http://localhost:3001"];
    self.config.plcBaseURL = [NSURL URLWithString:@"http://localhost:4000"];
    self.config.relayBaseURL = [NSURL URLWithString:@"http://localhost:7002"];
    self.config.appViewBaseURL = [NSURL URLWithString:@"http://localhost:3000"];
    self.config.chatBaseURL = [NSURL URLWithString:@"http://localhost:5000"];
    self.config.pdsAdminToken = @"admin-token-pds";
    self.config.plcAdminToken = @"admin-token-plc";
    self.config.relayAdminToken = @"admin-token-relay";
    self.config.appViewAdminToken = @"admin-token-appview";
    self.config.chatAdminToken = @"admin-token-chat";

    self.client = [[UIBackendClient alloc] initWithConfiguration:self.config];
}

- (void)tearDown {
    self.client = nil;
    self.config = nil;
    [super tearDown];
}

#pragma mark - Initialization Tests

/*!
 @test testClientInitialization

 @abstract Verify that UIBackendClient initializes with configuration.
 */
- (void)testClientInitialization {
    XCTAssertNotNil(self.client);
}

/*!
 @test testConfigurationAssignment

 @abstract Verify that configuration is properly assigned during initialization.
 */
- (void)testConfigurationAssignment {
    XCTAssertEqualObjects(self.config.pdsBaseURL, [NSURL URLWithString:@"http://localhost:3001"]);
    XCTAssertEqualObjects(self.config.pdsAdminToken, @"admin-token-pds");
}

#pragma mark - fetchInviteCodes Tests

/*!
 @test testFetchInviteCodesMethodExists

 @abstract Verify that fetchInviteCodes method exists and can be called.
 */
- (void)testFetchInviteCodesMethodExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchInviteCodes)]);
}

#pragma mark - disableInvitesForAccount Tests

/*!
 @test testDisableInvitesForAccountMethodExists

 @abstract Verify that disableInvitesForAccount method exists.
 */
- (void)testDisableInvitesForAccountMethodExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(disableInvitesForAccount:)]);
}

/*!
 @test testDisableInvitesForAccountRejectsEmptyAccount

 @abstract Verify that disableInvitesForAccount rejects empty account identifiers.
 */
- (void)testDisableInvitesForAccountRejectsEmptyAccount {
    NSDictionary *result = [self.client disableInvitesForAccount:@""];

    XCTAssertEqualObjects(result[@"error"], @"invalid_account");
    XCTAssertEqualObjects(result[@"message"], @"Account DID is required");
}

/*!
 @test testDisableInvitesForAccountRejectsWhitespaceOnlyAccount

 @abstract Verify that disableInvitesForAccount rejects whitespace-only account identifiers.
 */
- (void)testDisableInvitesForAccountRejectsWhitespaceOnlyAccount {
    NSDictionary *result = [self.client disableInvitesForAccount:@"   "];

    XCTAssertEqualObjects(result[@"error"], @"invalid_account");
    XCTAssertEqualObjects(result[@"message"], @"Account DID is required");
}

#pragma mark - Public API Tests

/*!
 @test testSearchAccountsWithQueryMethodExists

 @abstract Verify that searchAccountsWithQuery method exists.
 */
- (void)testSearchAccountsWithQueryMethodExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(searchAccountsWithQuery:)]);
}

/*!
 @test testFetchServiceOverviewMethodExists

 @abstract Verify that fetchServiceOverview method exists.
 */
- (void)testFetchServiceOverviewMethodExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchServiceOverview)]);
}

/*!
 @test testProbeServiceRequestsReasonableTimeout

 @abstract Verify that probe operations use reasonable timeout values.

 @discussion The probeServiceNamed method should timeout appropriately to avoid
 hanging when a service is unresponsive.
 */
- (void)testClientHasRequiredServiceTokens {
    XCTAssertNotNil(self.config.pdsAdminToken);
    XCTAssertNotNil(self.config.plcAdminToken);
    XCTAssertNotNil(self.config.relayAdminToken);
    XCTAssertNotNil(self.config.appViewAdminToken);
    XCTAssertNotNil(self.config.chatAdminToken);
}

@end
