// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "PLC/AdminUI/PLCAdminSnapshot.h"
#import "PLC/AdminUI/PLCAdminUIPack.h"
#import "PLC/AdminUI/GZPLCAdminUIConfiguration.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCServer.h"

@interface PLCAdminUIBackendStub : GZAdminUIBackendClient
@end

@implementation PLCAdminUIBackendStub
- (NSDictionary *)fetchPLCMetrics { return @{ @"text": @"plc_requests_total 1\n" }; }
- (NSDictionary *)lookupDID:(NSString *)did { return @{ @"did": did ?: @"" }; }
@end

@interface PLCAdminUIPackTests : XCTestCase
@property(nonatomic, strong) GZAdminUIServiceConfig *config;
@property(nonatomic, strong) GZAdminUIHost *host;
@property(nonatomic, strong) GZPLCAdminSnapshot *snapshot;
@end

@implementation PLCAdminUIPackTests

- (void)setUp {
    [super setUp];
    self.config = [[GZAdminUIServiceConfig alloc] init];
    self.config.host = @"127.0.0.1";
    self.config.port = 0;
    self.config.adminPassword = @"plc-admin-password";
    self.config.serviceIdentifier = @"plc";
    self.config.plcBaseURL = [NSURL URLWithString:@"http://127.0.0.1:2582"];
    self.host = [[GZAdminUIHost alloc] initWithConfiguration:self.config packs:@[GZPLCAdminUIPack.class]];
    self.snapshot = [[GZPLCAdminSnapshot alloc] initWithStore:[[PLCMockStore alloc] init] syncEngine:nil];
    [GZPLCAdminUIPack configureHost:self.host snapshot:self.snapshot];
}

- (void)tearDown {
    [self.host stop];
    [super tearDown];
}

- (ATProtoHttpRequest *)requestWithMethod:(NSString *)method path:(NSString *)path headers:(NSDictionary *)headers body:(NSDictionary *)body {
    NSData *data = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : [NSData data];
    NSMutableDictionary *requestHeaders = [headers mutableCopy] ?: [NSMutableDictionary dictionary];
    if (body) requestHeaders[@"Content-Type"] = @"application/json";
    return [[ATProtoHttpRequest alloc] initWithMethod:[method isEqualToString:@"POST"] ? HttpMethodPOST : HttpMethodGET
                                          methodString:method
                                                  path:path
                                           queryString:@""
                                           queryParams:@{}
                                               version:@"HTTP/1.1"
                                               headers:requestHeaders
                                                  body:data
                                         remoteAddress:@"127.0.0.1"];
}

- (NSDictionary *)authenticatedHeadersWithNonce:(NSString *)nonce {
    NSString *token = [self.host.authManager createSessionToken];
    return @{
        @"Cookie": [NSString stringWithFormat:@"gz_admin_plc_token=%@; gz_admin_plc_nonce=%@", token, nonce],
        @"X-UI-Admin-Nonce": nonce,
    };
}

- (NSString *)newNonce {
    NSString *nonce = nil;
    NSString *cookie = nil;
    [self.host.authManager createCSRFNonce:&nonce cookie:&cookie secure:NO];
    return nonce;
}

- (void)testEmbeddedHostUsesLoopbackAndConcurrencyEight {
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/plc-metrics" headers:@{} body:nil]];
    XCTAssertEqual(response.statusCode, HttpStatusFound);
    XCTAssertEqualObjects(self.host.httpServer.host, @"127.0.0.1");
    XCTAssertEqual(self.host.httpServer.maxConcurrentRequests, (NSUInteger)8);
}

- (void)testProtocolAndAdminListenersStopCleanly {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    PLCServer *protocolServer = [[PLCServer alloc] initWithStore:store
                                                           auditor:[[PLCAuditor alloc] initWithStore:store]
                                                             host:@"127.0.0.1"
                                                             port:0];
    NSError *error = nil;
    if (![protocolServer startWithError:&error]) {
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"Loopback listeners are unavailable in this environment");
            return;
        }
        XCTFail(@"Failed to start protocol listener: %@", error);
        return;
    }
    XCTAssertTrue(protocolServer.httpServer.isRunning);
    XCTAssertTrue([self.host startWithError:&error], @"Failed to start admin listener: %@", error);
    XCTAssertTrue(self.host.isRunning);

    [self.host stop];
    [protocolServer stop];
    XCTAssertFalse(self.host.isRunning);
    XCTAssertFalse(protocolServer.httpServer.isRunning);
}

- (void)testPLCSessionCookieDoesNotAcceptSiblingServiceCookie {
    NSString *foreignToken = [self.host.authManager createSessionToken];
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET"
                                                                                           path:@"/admin/partials/plc-metrics"
                                                                                        headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_relay_token=%@", foreignToken] }
                                                                                           body:nil]];
    XCTAssertEqual(response.statusCode, HttpStatusFound);
}

- (void)testMetricsRouteRequiresThePLCScopedSessionCookie {
    NSString *token = [self.host.authManager createSessionToken];
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET"
                                                                                           path:@"/admin/partials/plc-metrics"
                                                                                        headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_plc_token=%@", token] }
                                                                                           body:nil]];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertTrue([response.bodyString containsString:@"Mode"]);
}

- (void)testLoginRejectsWrongPasswordAndIssuesScopedSessionForCorrectPassword {
    NSString *nonce = [self newNonce];
    NSDictionary *headers = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_plc_nonce=%@", nonce], @"X-UI-Admin-Nonce": nonce };
    ATProtoHttpResponse *wrong = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/login" headers:headers body:@{ @"password": @"wrong" }]];
    XCTAssertEqual(wrong.statusCode, HttpStatusUnauthorized);

    NSString *freshNonce = [self newNonce];
    NSDictionary *freshHeaders = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_plc_nonce=%@", freshNonce], @"X-UI-Admin-Nonce": freshNonce };
    ATProtoHttpResponse *correct = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/login" headers:freshHeaders body:@{ @"password": @"plc-admin-password" }]];
    XCTAssertEqual(correct.statusCode, HttpStatusOK);
    XCTAssertTrue([[correct headerForKey:@"Set-Cookie"] hasPrefix:@"gz_admin_plc_token="]);
    XCTAssertTrue([[correct headerForKey:@"Set-Cookie"] containsString:@"HttpOnly"]);
}

- (void)testReplicaMutationRejectsMissingAndStaleCSRFAndAuditsAcceptedAttempt {
    NSString *nonce = [self newNonce];
    NSString *token = [self.host.authManager createSessionToken];
    NSDictionary *missingHeaders = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_plc_token=%@", token] };
    ATProtoHttpResponse *missing = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/actions/plc-sync" headers:missingHeaders body:@{ @"action": @"pause" }]];
    XCTAssertEqual(missing.statusCode, HttpStatusForbidden);

    NSDictionary *staleHeaders = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_plc_token=%@; gz_admin_plc_nonce=%@", token, nonce], @"X-UI-Admin-Nonce": @"stale" };
    ATProtoHttpResponse *stale = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/actions/plc-sync" headers:staleHeaders body:@{ @"action": @"pause" }]];
    XCTAssertEqual(stale.statusCode, HttpStatusForbidden);

    NSString *validNonce = [self newNonce];
    ATProtoHttpResponse *primary = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/actions/plc-sync" headers:[self authenticatedHeadersWithNonce:validNonce] body:@{ @"action": @"pause" }]];
    XCTAssertEqual(primary.statusCode, HttpStatusBadRequest);
    NSArray *auditEntries = [self.snapshot snapshot][@"adminAudit"];
    NSDictionary *audit = auditEntries.lastObject;
    XCTAssertEqualObjects(audit[@"action"], @"pause");
    XCTAssertEqualObjects(audit[@"succeeded"], @NO);
}

- (void)testCompatibilityHostUsesTheSamePackRoutes {
    GZAdminUIHost *compatibilityHost = [[GZAdminUIHost alloc] initWithConfiguration:self.config packs:@[GZPLCAdminUIPack.class]];
    compatibilityHost.backendClient = [[PLCAdminUIBackendStub alloc] initWithConfiguration:self.config];
    NSString *token = [compatibilityHost.authManager createSessionToken];
    NSDictionary *headers = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_plc_token=%@", token] };
    ATProtoHttpResponse *metrics = [compatibilityHost dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/plc-metrics" headers:headers body:nil]];
    ATProtoHttpResponse *lookup = [compatibilityHost dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/plc-resolve" headers:headers body:nil]];
    XCTAssertEqual(metrics.statusCode, HttpStatusOK);
    XCTAssertTrue([metrics.bodyString containsString:@"plc_requests_total"]);
    XCTAssertEqual(lookup.statusCode, HttpStatusOK);
}

- (void)testPasswordFileLoaderTrimsCredentialNewlinesAndRedactsErrors {
    NSString *secret = @"systemd-credential-secret";
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"plc-password-%@", NSUUID.UUID.UUIDString]];
    XCTAssertTrue([[secret stringByAppendingString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSError *error = nil;
    XCTAssertEqualObjects(GZPLCAdminPasswordFromFile(path, &error), secret);
    XCTAssertNil(error);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSString *missingPath = [path stringByAppendingString:@"-missing"];
    XCTAssertNil(GZPLCAdminPasswordFromFile(missingPath, &error));
    XCTAssertNotNil(error);
    XCTAssertFalse([error.localizedDescription containsString:secret]);
    XCTAssertFalse([error.description containsString:secret]);
}

@end
