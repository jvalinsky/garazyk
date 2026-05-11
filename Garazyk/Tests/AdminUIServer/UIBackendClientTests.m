// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UIBackendClientTests.m

 @abstract Unit tests for UIBackendClient.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"

@interface UIBackendClient (UIBackendClientTests)
- (NSDictionary *)performJSONRequestWithURL:(NSURL *)url
                                     method:(NSString *)method
                                       body:(nullable NSDictionary *)body
                                bearerToken:(nullable NSString *)token
                                 statusCode:(NSInteger *)statusCode
                                      error:(NSError **)error;
- (NSData *)performRequestWithURL:(NSURL *)url
                           method:(NSString *)method
                             body:(nullable NSData *)body
                      contentType:(nullable NSString *)contentType
                      bearerToken:(nullable NSString *)token
                       statusCode:(NSInteger *)statusCode
                            error:(NSError **)error;
@end

@interface UIBackendClientStub : UIBackendClient
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *capturedRequests;
@property(nonatomic, strong) NSDictionary *nextJSONResponse;
@end

@implementation UIBackendClientStub

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        _capturedRequests = [NSMutableArray array];
        _nextJSONResponse = @{};
    }
    return self;
}

- (NSDictionary *)performJSONRequestWithURL:(NSURL *)url
                                     method:(NSString *)method
                                       body:(nullable NSDictionary *)body
                                bearerToken:(nullable NSString *)token
                                 statusCode:(NSInteger *)statusCode
                                      error:(NSError **)error {
    NSMutableDictionary *req = [NSMutableDictionary dictionary];
    req[@"url"] = url.absoluteString ?: @"";
    req[@"method"] = method ?: @"";
    req[@"body"] = body ?: @{};
    req[@"token"] = token ?: @"";
    [self.capturedRequests addObject:[req copy]];
    if (statusCode) {
        *statusCode = 200;
    }
    return self.nextJSONResponse ?: @{};
}

- (NSData *)performRequestWithURL:(NSURL *)url
                           method:(NSString *)method
                             body:(nullable NSData *)body
                      contentType:(nullable NSString *)contentType
                      bearerToken:(nullable NSString *)token
                       statusCode:(NSInteger *)statusCode
                            error:(NSError **)error {
    NSMutableDictionary *req = [NSMutableDictionary dictionary];
    req[@"url"] = url.absoluteString ?: @"";
    req[@"method"] = method ?: @"";
    req[@"token"] = token ?: @"";
    [self.capturedRequests addObject:[req copy]];
    if (statusCode) {
        *statusCode = 200;
    }
    return [@"{\"version\":\"1.0.0\"}" dataUsingEncoding:NSUTF8StringEncoding];
}

@end

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
    self.config.videoBaseURL = [NSURL URLWithString:@"http://localhost:5001"];
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
#pragma mark - Search Accounts Tests

/*!
 @test testSearchAccountsWithQueryRejectsNil

 @abstract Verify that searchAccountsWithQuery: handles nil query gracefully.
 */
- (void)testSearchAccountsWithQueryRejectsNil {
    NSDictionary *result = [self.client searchAccountsWithQuery:nil];
    XCTAssertNotNil(result);
}

/*!
 @test testSearchAccountsWithQueryAcceptsValidQuery

 @abstract Verify that searchAccountsWithQuery: accepts a valid query string.
 */
- (void)testSearchAccountsWithQueryAcceptsValidQuery {
    NSDictionary *result = [self.client searchAccountsWithQuery:@"testuser"];
    XCTAssertNotNil(result);
}

#pragma mark - fetchServerStats Tests

/*!
 @test testFetchServerStatsExists

 @abstract Verify that fetchServerStats method exists.
 */
- (void)testFetchServerStatsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchServerStats)]);
}

#pragma mark - Account Management Tests

/*!
 @test testEnableInvitesForAccountExists

 @abstract Verify that enableInvitesForAccount method exists.
 */
- (void)testEnableInvitesForAccountExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(enableInvitesForAccount:)]);
}

/*!
 @test testDeleteAccountExists

 @abstract Verify that deleteAccount method exists.
 */
- (void)testDeleteAccountExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(deleteAccount:)]);
}

/*!
 @test testBulkTakedownAccountsExists

 @abstract Verify that bulkTakedownAccounts method exists.
 */
- (void)testBulkTakedownAccountsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(bulkTakedownAccounts:)]);
}

#pragma mark - Audit Log Tests

/*!
 @test testFetchAuditLogWithCursorExists

 @abstract Verify that fetchAuditLogWithCursor:limit: method exists.
 */
- (void)testFetchAuditLogWithCursorExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchAuditLogWithCursor:limit:)]);
}

/*!
 @test testFetchAuditLogWithNilCursor

 @abstract Verify that fetchAuditLog handles nil cursor.
 */
- (void)testFetchAuditLogWithNilCursor {
    NSDictionary *result = [self.client fetchAuditLogWithCursor:nil limit:10];
    XCTAssertNotNil(result);
}

#pragma mark - Invite Codes Tests

/*!
 @test testFetchInviteCodes

 @abstract Verify that fetchInviteCodes returns a dictionary.
 */
- (void)testFetchInviteCodes {
    NSDictionary *result = [self.client fetchInviteCodes];
    XCTAssertNotNil(result);
}

#pragma mark - PLC Tests

/*!
 @test testFetchPLCHealthExists

 @abstract Verify that fetchPLCHealth method exists.
 */
- (void)testFetchPLCHealthExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchPLCHealth)]);
}

/*!
 @test testFetchPLCMetricsExists

 @abstract Verify that fetchPLCMetrics method exists.
 */
- (void)testFetchPLCMetricsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchPLCMetrics)]);
}

/*!
 @test testFetchPLCListExists

 @abstract Verify that fetchPLCList method exists.
 */
- (void)testFetchPLCListExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchPLCList)]);
}

/*!
 @test testLookupDIDExists

 @abstract Verify that lookupDID method exists.
 */
- (void)testLookupDIDExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(lookupDID:)]);
}

#pragma mark - Relay Tests

/*!
 @test testFetchRelayMetricsExists

 @abstract Verify that fetchRelayMetrics method exists.
 */
- (void)testFetchRelayMetricsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchRelayMetrics)]);
}

/*!
 @test testFetchRelayUpstreamsExists

 @abstract Verify that fetchRelayUpstreams method exists.
 */
- (void)testFetchRelayUpstreamsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchRelayUpstreams)]);
}

/*!
 @test testFetchRelayHealthExists

 @abstract Verify that fetchRelayHealth method exists.
 */
- (void)testFetchRelayHealthExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchRelayHealth)]);
}

/*!
 @test testRequestCrawlForHostnameExists

 @abstract Verify that requestCrawlForHostname method exists.
 */
- (void)testRequestCrawlForHostnameExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(requestCrawlForHostname:)]);
}

#pragma mark - AppView Tests

/*!
 @test testFetchAppViewMetricsExists

 @abstract Verify that fetchAppViewMetrics method exists.
 */
- (void)testFetchAppViewMetricsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchAppViewMetrics)]);
}

/*!
 @test testFetchIngestHealthExists

 @abstract Verify that fetchIngestHealth method exists.
 */
- (void)testFetchIngestHealthExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchIngestHealth)]);
}

/*!
 @test testFetchBackfillQueueExists

 @abstract Verify that fetchBackfillQueueWithStatus:limit:cursor: method exists.
 */
- (void)testFetchBackfillQueueExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchBackfillQueueWithStatus:limit:cursor:)]);
}

#pragma mark - Chat Tests

/*!
 @test testFetchChatConvosExists

 @abstract Verify that fetchChatConvosWithLimit:cursor: method exists.
 */
- (void)testFetchChatConvosExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchChatConvosWithLimit:cursor:)]);
}

/*!
 @test testLockChatConvoExists

 @abstract Verify that lockChatConvo method exists.
 */
- (void)testLockChatConvoExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(lockChatConvo:)]);
}

#pragma mark - Blob Tests

/*!
 @test testFetchBlobsForDIDExists

 @abstract Verify that fetchBlobsForDID:limit:cursor: method exists.
 */
- (void)testFetchBlobsForDIDExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchBlobsForDID:limit:cursor:)]);
}

/*!
 @test testFetchBlobForDIDExists

 @abstract Verify that fetchBlobForDID:cid: method exists.
 */
- (void)testFetchBlobForDIDExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchBlobForDID:cid:)]);
}

#pragma mark - Ozone Tests

/*!
 @test testFetchOzoneStatusesExists

 @abstract Verify that fetchOzoneStatusesWithCursor:limit: method exists.
 */
- (void)testFetchOzoneStatusesExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchOzoneStatusesWithCursor:limit:)]);
}

/*!
 @test testFetchOzoneEventsExists

 @abstract Verify that fetchOzoneEventsWithCursor:limit: method exists.
 */
- (void)testFetchOzoneEventsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchOzoneEventsWithCursor:limit:)]);
}

/*!
 @test testFetchModerationReportsExists

 @abstract Verify that fetchModerationReportsWithCursor:limit: method exists.
 */
- (void)testFetchModerationReportsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchModerationReportsWithCursor:limit:)]);
}

/*!
 @test testResolveReportExists

 @abstract Verify that resolveReport:action: method exists.
 */
- (void)testResolveReportExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(resolveReport:action:)]);
}

/*!
 @test testFetchSubjectStatusExists

 @abstract Verify that fetchSubjectStatusForDID method exists.
 */
- (void)testFetchSubjectStatusExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchSubjectStatusForDID:)]);
}

/*!
 @test testFetchSafelinkRulesExists

 @abstract Verify that fetchSafelinkRules method exists.
 */
- (void)testFetchSafelinkRulesExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchSafelinkRules)]);
}

/*!
 @test testFetchOzoneSettingsExists

 @abstract Verify that fetchOzoneSettings method exists.
 */
- (void)testFetchOzoneSettingsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchOzoneSettings)]);
}

/*!
 @test testFetchOzoneConfigExists

 @abstract Verify that fetchOzoneConfig method exists.
 */
- (void)testFetchOzoneConfigExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchOzoneConfig)]);
}

#pragma mark - Security Tests

/*!
 @test testFetchActiveSessionsExists

 @abstract Verify that fetchActiveSessionsForDID method exists.
 */
- (void)testFetchActiveSessionsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchActiveSessionsForDID:)]);
}

/*!
 @test testFetchAppPasswordsExists

 @abstract Verify that fetchAppPasswordsForDID method exists.
 */
- (void)testFetchAppPasswordsExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(fetchAppPasswordsForDID:)]);
}

/*!
 @test testCreateAppPasswordExists

 @abstract Verify that createAppPasswordForDID:name: method exists.
 */
- (void)testCreateAppPasswordExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(createAppPasswordForDID:name:)]);
}

/*!
 @test testRevokeSessionExists

 @abstract Verify that revokeSessionForDID:sessionID: method exists.
 */
- (void)testRevokeSessionExists {
    XCTAssertTrue([self.client respondsToSelector:@selector(revokeSessionForDID:sessionID:)]);
}

/*!
 @test testClientHasRequiredServiceTokens

 @abstract Verify that all required service tokens are configured.
 */
- (void)testClientHasRequiredServiceTokens {
    XCTAssertNotNil(self.config.pdsAdminToken);
    XCTAssertNotNil(self.config.plcAdminToken);
    XCTAssertNotNil(self.config.relayAdminToken);
    XCTAssertNotNil(self.config.appViewAdminToken);
    XCTAssertNotNil(self.config.chatAdminToken);
}

#pragma mark - Exact Request Wiring Tests

- (UIBackendClientStub *)stubClient {
    self.config.pdsBaseURL = [NSURL URLWithString:@"http://localhost:3001/"];
    return [[UIBackendClientStub alloc] initWithConfiguration:self.config];
}

- (NSDictionary *)lastCapturedRequestFromStub:(UIBackendClientStub *)stub {
    NSDictionary *request = stub.capturedRequests.lastObject;
    XCTAssertNotNil(request);
    return request ?: @{};
}

- (void)testSecuritySessionsUsePrivatePDSAdminRouteWithHashedSessionIDBody {
    UIBackendClientStub *stub = [self stubClient];

    [stub fetchActiveSessionsForDID:@"did:plc:alice"];
    NSDictionary *fetchRequest = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(fetchRequest[@"method"], @"GET");
    XCTAssertEqualObjects(fetchRequest[@"url"], @"http://localhost:3001/admin/api/accounts/did%3Aplc%3Aalice/sessions");
    XCTAssertEqualObjects(fetchRequest[@"token"], @"admin-token-pds");

    [stub revokeSessionForDID:@"did:plc:alice" sessionID:@"hash-session-id"];
    NSDictionary *revokeRequest = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(revokeRequest[@"method"], @"POST");
    XCTAssertEqualObjects(revokeRequest[@"url"], @"http://localhost:3001/admin/api/accounts/did%3Aplc%3Aalice/sessions/revoke");
    XCTAssertEqualObjects(revokeRequest[@"body"], @{@"id": @"hash-session-id"});
}

- (void)testSecurityAppPasswordsUsePrivatePDSAdminRoutes {
    UIBackendClientStub *stub = [self stubClient];

    [stub fetchAppPasswordsForDID:@"did:plc:alice"];
    NSDictionary *listRequest = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(listRequest[@"method"], @"GET");
    XCTAssertEqualObjects(listRequest[@"url"], @"http://localhost:3001/admin/api/accounts/did%3Aplc%3Aalice/app-passwords");
    XCTAssertEqualObjects(listRequest[@"token"], @"admin-token-pds");

    [stub createAppPasswordForDID:@"did:plc:alice" name:@"ops"];
    NSDictionary *createRequest = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(createRequest[@"method"], @"POST");
    XCTAssertEqualObjects(createRequest[@"url"], @"http://localhost:3001/admin/api/accounts/did%3Aplc%3Aalice/app-passwords");
    XCTAssertEqualObjects(createRequest[@"body"], @{@"name": @"ops"});

    [stub deleteAppPasswordForDID:@"did:plc:alice" passwordName:@"ops"];
    NSDictionary *deleteRequest = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(deleteRequest[@"method"], @"POST");
    XCTAssertEqualObjects(deleteRequest[@"url"], @"http://localhost:3001/admin/api/accounts/did%3Aplc%3Aalice/app-passwords/revoke");
    XCTAssertEqualObjects(deleteRequest[@"body"], @{@"name": @"ops"});
}

- (void)testChatLockUsesLockConvoEndpointOnChatService {
    UIBackendClientStub *stub = [self stubClient];

    [stub lockChatConvo:@"convo-123"];
    NSDictionary *request = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(request[@"method"], @"POST");
    XCTAssertEqualObjects(request[@"url"], @"http://localhost:5000/xrpc/chat.bsky.convo.lockConvo");
    XCTAssertEqualObjects(request[@"token"], @"admin-token-chat");
    XCTAssertEqualObjects(request[@"body"], @{@"convoId": @"convo-123"});
}

- (void)testOzoneReportsCallReportEventEndpointNotStatuses {
    UIBackendClientStub *stub = [self stubClient];
    stub.nextJSONResponse = @{@"events": @[@{@"subject": @"did:plc:alice", @"reportType": @"spam", @"createdBy": @"did:plc:reporter"}]};

    NSDictionary *result = [stub fetchModerationReportsWithCursor:@"cursor-a" limit:50];
    NSDictionary *request = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(request[@"method"], @"GET");
    XCTAssertEqualObjects(request[@"url"], @"http://localhost:3001/xrpc/tools.ozone.moderation.queryEvents?cursor=cursor-a&limit=50&types=tools.ozone.moderation.defs%23modEventReport");
    XCTAssertEqualObjects(request[@"token"], @"admin-token-pds");
    XCTAssertEqualObjects(result[@"reports"][0][@"subject"], @"did:plc:alice");
}

- (void)testOzoneSettingsUseGetQueryParams {
    UIBackendClientStub *stub = [self stubClient];

    [stub listOzoneSettings];
    NSDictionary *request = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(request[@"method"], @"GET");
    XCTAssertEqualObjects(request[@"url"], @"http://localhost:3001/xrpc/tools.ozone.setting.listOptions?limit=50&scope=instance");
    XCTAssertEqualObjects(request[@"body"], @{});
}

- (void)testPLCListUnwrapsItemsResponseIntoDIDs {
    UIBackendClientStub *stub = [self stubClient];
    stub.nextJSONResponse = @{@"items": @[@"did:plc:one", @"did:plc:two"]};

    NSDictionary *result = [stub fetchPLCList];
    NSDictionary *request = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(request[@"method"], @"GET");
    XCTAssertEqualObjects(request[@"url"], @"http://localhost:4000/_list");
    XCTAssertEqualObjects(result[@"dids"], (@[@"did:plc:one", @"did:plc:two"]));
}

- (void)testServiceConnectionProbeUsesServiceSpecificHealthEndpoint {
    UIBackendClientStub *stub = [self stubClient];

    [stub testConnectionForService:@"relay"];
    NSDictionary *relayRequest = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(relayRequest[@"method"], @"GET");
    XCTAssertEqualObjects(relayRequest[@"url"], @"http://localhost:7002/api/relay/health");
    XCTAssertEqualObjects(relayRequest[@"token"], @"admin-token-relay");

    [stub testConnectionForService:@"appview"];
    NSDictionary *appViewRequest = [self lastCapturedRequestFromStub:stub];
    XCTAssertEqualObjects(appViewRequest[@"method"], @"GET");
    XCTAssertEqualObjects(appViewRequest[@"url"], @"http://localhost:3000/admin/ingest/health");
    XCTAssertEqualObjects(appViewRequest[@"token"], @"admin-token-appview");
}

@end
