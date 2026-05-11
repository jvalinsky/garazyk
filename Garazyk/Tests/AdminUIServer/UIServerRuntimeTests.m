// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UIServerRuntimeTests.m

 @abstract Unit tests for UIServerRuntime.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@interface UIServerRuntimeBackendStub : UIBackendClient
@property(nonatomic, strong) NSMutableArray<NSString *> *calls;
@property(nonatomic, copy) NSString *lastDID;
@property(nonatomic, copy) NSString *lastConvoID;
@property(nonatomic, copy) NSString *lastServiceName;
@property(nonatomic, strong) NSURL *lastBaseURL;
@property(nonatomic, copy) NSString *lastAdminToken;
@end

@implementation UIServerRuntimeBackendStub

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        _calls = [NSMutableArray array];
    }
    return self;
}

- (void)recordCall:(NSString *)call {
    [self.calls addObject:call ?: @""];
}

- (NSDictionary *)fetchServiceOverview {
    [self recordCall:NSStringFromSelector(_cmd)];
    return @{@"services": @[@{@"name": @"pds", @"status": @"online", @"url": @"http://localhost:3001"}]};
}

- (NSDictionary *)fetchActiveSessionsForDID:(NSString *)did {
    [self recordCall:NSStringFromSelector(_cmd)];
    self.lastDID = did;
    return @{@"sessions": @[@{@"id": @"session-hash", @"did": did ?: @"", @"createdAt": @"2026-04-28T00:00:00Z"}]};
}

- (NSDictionary *)fetchAppPasswordsForDID:(NSString *)did {
    [self recordCall:NSStringFromSelector(_cmd)];
    self.lastDID = did;
    return @{@"passwords": @[@{@"name": @"ops", @"did": did ?: @"", @"createdAt": @"2026-04-28T00:00:00Z"}]};
}

- (NSDictionary *)fetchModerationReportsWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    [self recordCall:NSStringFromSelector(_cmd)];
    return @{@"reports": @[@{@"subject": @"did:plc:alice", @"reason": @"spam", @"reportedBy": @"did:plc:reporter"}]};
}

- (NSDictionary *)listOzoneSettings {
    [self recordCall:NSStringFromSelector(_cmd)];
    return @{@"options": @[@{@"key": @"triageMode", @"value": @"manual"}]};
}

- (NSDictionary *)fetchPLCList {
    [self recordCall:NSStringFromSelector(_cmd)];
    return @{@"dids": @[@"did:plc:alice"]};
}

- (NSDictionary *)lockChatConvo:(NSString *)convoID {
    [self recordCall:NSStringFromSelector(_cmd)];
    self.lastConvoID = convoID;
    return @{@"ok": @YES};
}

- (NSDictionary *)testConnectionForService:(NSString *)serviceName
                                   baseURL:(NSURL *)baseURL
                                adminToken:(NSString *)adminToken {
    [self recordCall:NSStringFromSelector(_cmd)];
    self.lastServiceName = serviceName;
    self.lastBaseURL = baseURL;
    self.lastAdminToken = adminToken;
    return @{@"name": serviceName ?: @"", @"status": @"online", @"url": baseURL.absoluteString ?: @""};
}

@end

@interface UIServerRuntimeTests : XCTestCase
@property (nonatomic, strong) UIServiceConfig *config;
@property (nonatomic, strong) UIServerRuntime *runtime;
@end

@implementation UIServerRuntimeTests

- (void)setUp {
    [super setUp];

    self.config = [[UIServiceConfig alloc] init];
    self.config.host = @"127.0.0.1";
    self.config.port = 0; // Use ephemeral port
    self.config.adminPassword = @"test-admin-password";
    self.config.pdsBaseURL = [NSURL URLWithString:@"http://localhost:3001"];
    self.config.plcBaseURL = [NSURL URLWithString:@"http://localhost:4000"];
    self.config.relayBaseURL = [NSURL URLWithString:@"http://localhost:7002"];
    self.config.appViewBaseURL = [NSURL URLWithString:@"http://localhost:3000"];
    self.config.chatBaseURL = [NSURL URLWithString:@"http://localhost:5000"];
    self.config.pdsAdminToken = @"admin-token";
    self.config.plcAdminToken = @"admin-token";
    self.config.relayAdminToken = @"admin-token";
    self.config.appViewAdminToken = @"admin-token";
    self.config.chatAdminToken = @"admin-token";

    self.runtime = [[UIServerRuntime alloc] initWithConfiguration:self.config];
}

- (void)tearDown {
    if (self.runtime.isRunning) {
        [self.runtime stop];
    }
    self.runtime = nil;
    self.config = nil;
    [super tearDown];
}

#pragma mark - Helper Methods

/*!
 @abstract Creates an HttpRequest with the specified method, path, and optional token.
 */
- (HttpRequest *)createRequestWithMethod:(NSString *)method
                                    path:(NSString *)path
                             sessionToken:(NSString *)token
                                jsonBody:(NSDictionary *)jsonBody {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];

    if (token) {
        headers[@"Cookie"] = [NSString stringWithFormat:@"ui_admin_token=%@", token];
    }

    if (jsonBody) {
        headers[@"Content-Type"] = @"application/json";
    }

    NSData *bodyData = nil;
    if (jsonBody) {
        NSError *error = nil;
        bodyData = [NSJSONSerialization dataWithJSONObject:jsonBody options:0 error:&error];
        if (error) {
            XCTFail(@"Failed to serialize JSON body: %@", error);
        }
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:[self httpMethodFromString:method]
                                                  methodString:method
                                                          path:path
                                                   queryString:@""
                                                    queryParams:@{}
                                                        version:@"HTTP/1.1"
                                                        headers:[headers copy]
                                                           body:(bodyData ?: [NSData data])
                                                   remoteAddress:@"127.0.0.1"];

    return request;
}

/*!
 @abstract Converts HTTP method string to HttpMethod enum.
 */
- (HttpMethod)httpMethodFromString:(NSString *)method {
    if ([method isEqualToString:@"GET"]) {
        return HttpMethodGET;
    } else if ([method isEqualToString:@"POST"]) {
        return HttpMethodPOST;
    } else if ([method isEqualToString:@"PUT"]) {
        return HttpMethodPUT;
    } else if ([method isEqualToString:@"DELETE"]) {
        return HttpMethodDELETE;
    }
    return HttpMethodGET;
}

- (NSString *)loginAndReturnSessionToken {
    HttpRequest *loginRequest = [self createRequestWithMethod:@"POST"
                                                         path:@"/admin/login"
                                                  sessionToken:nil
                                                     jsonBody:@{@"password": @"test-admin-password"}];
    HttpResponse *loginResponse = [self.runtime dispatchRequestForTesting:loginRequest];
    XCTAssertEqual(loginResponse.statusCode, 200);

    NSString *setCookie = [loginResponse headerForKey:@"Set-Cookie"];
    XCTAssertTrue(setCookie.length > 0);
    NSString *tokenCookie = [[setCookie componentsSeparatedByString:@";"] firstObject];
    XCTAssertTrue([tokenCookie hasPrefix:@"ui_admin_token="]);
    return [tokenCookie stringByReplacingOccurrencesOfString:@"ui_admin_token=" withString:@""];
}

- (NSDictionary *)jsonFromResponse:(HttpResponse *)response {
    XCTAssertGreaterThan(response.body.length, 0);
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (UIServerRuntimeBackendStub *)installBackendStub {
    UIServerRuntimeBackendStub *stub = [[UIServerRuntimeBackendStub alloc] initWithConfiguration:self.config];
    [self.runtime setValue:stub forKey:@"backendClient"];
    return stub;
}

#pragma mark - Test: Initialization and Startup

/*!
 @test testRuntimeInitialization

 @abstract Verify that UIServerRuntime initializes with the provided configuration.
 */
- (void)testRuntimeInitialization {
    XCTAssertNotNil(self.runtime);
    XCTAssertEqualObjects(self.runtime.configuration, self.config);
    XCTAssertFalse(self.runtime.isRunning);
}

/*!
 @test testRuntimeStartsSuccessfully

 @abstract Verify that the runtime starts successfully and sets the running flag.
 */
- (void)testRuntimeStartsSuccessfully {
    HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                    path:@"/"
                                             sessionToken:nil
                                                jsonBody:nil];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 302);
    XCTAssertEqualObjects([response headerForKey:@"Location"], @"/admin");
}

#pragma mark - Test: GET /admin without auth redirects to /admin/login

/*!
 @test testGetAdminWithoutAuthRedirectsToLogin

 @abstract Verify that GET /admin without authentication can be created as a request.
 */
- (void)testGetAdminWithoutAuthRedirectsToLogin {
    HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                    path:@"/admin"
                                             sessionToken:nil
                                                jsonBody:nil];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 302);
    XCTAssertEqualObjects([response headerForKey:@"Location"], @"/admin/login");
}

#pragma mark - Test: POST /admin/login with correct password

/*!
 @test testPostAdminLoginWithCorrectPassword

 @abstract Verify that POST /admin/login with correct password returns 200 and creates session.
 */
- (void)testPostAdminLoginWithCorrectPassword {
    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/login"
                                             sessionToken:nil
                                                jsonBody:@{@"password": @"test-admin-password"}];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"ok"], @YES);
    XCTAssertTrue([[response headerForKey:@"Set-Cookie"] hasPrefix:@"ui_admin_token="]);
}

/*!
 @test testPostAdminLoginWithWrongPassword

 @abstract Verify that POST /admin/login with wrong password can be created as a request.
 */
- (void)testPostAdminLoginWithWrongPassword {
    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/login"
                                             sessionToken:nil
                                                jsonBody:@{@"password": @"wrong-password"}];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"ok"], @NO);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"invalid_credentials");
}

#pragma mark - Test: GET /admin with valid session cookie

/*!
 @test testGetAdminWithValidSessionCookie

 @abstract Verify that GET /admin with a valid session cookie can be created and handled.
 */
- (void)testGetAdminWithValidSessionCookie {
    NSString *token = [self loginAndReturnSessionToken];
    HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                    path:@"/admin"
                                             sessionToken:token
                                                jsonBody:nil];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.bodyString containsString:@"Garazyk UI Service"]);
}

/*!
 @test testGetAdminWithInvalidSessionCookie

 @abstract Verify that GET /admin with an invalid session cookie can be created and processed.
 */
- (void)testGetAdminWithInvalidSessionCookie {
    HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                    path:@"/admin"
                                             sessionToken:@"invalid-token-xyz"
                                                jsonBody:nil];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 302);
    XCTAssertEqualObjects([response headerForKey:@"Location"], @"/admin/login");
}

#pragma mark - Test: POST /admin/logout clears session

/*!
 @test testPostAdminLogoutClearsSession

 @abstract Verify that POST /admin/logout can be called.
 */
- (void)testPostAdminLogoutClearsSession {
    NSString *token = [self loginAndReturnSessionToken];
    HttpRequest *logoutRequest = [self createRequestWithMethod:@"POST"
                                                          path:@"/admin/logout"
                                                   sessionToken:token
                                                      jsonBody:nil];
    HttpResponse *logoutResponse = [self.runtime dispatchRequestForTesting:logoutRequest];

    XCTAssertEqual(logoutResponse.statusCode, 200);
    XCTAssertEqualObjects(logoutResponse.jsonBody[@"ok"], @YES);
    XCTAssertTrue([[logoutResponse headerForKey:@"Set-Cookie"] containsString:@"Max-Age=0"]);

    HttpRequest *adminRequest = [self createRequestWithMethod:@"GET"
                                                         path:@"/admin"
                                                  sessionToken:token
                                                     jsonBody:nil];
    HttpResponse *adminResponse = [self.runtime dispatchRequestForTesting:adminRequest];
    XCTAssertEqual(adminResponse.statusCode, 302);
}

#pragma mark - Test: Authentication Flow

/*!
 @test testCompleteAuthenticationFlow

 @abstract Verify the complete authentication flow: create login request, verify structure.
 */
- (void)testCompleteAuthenticationFlow {
    HttpRequest *loginRequest = [self createRequestWithMethod:@"POST"
                                                        path:@"/admin/login"
                                                 sessionToken:nil
                                                    jsonBody:@{@"password": @"test-admin-password"}];
    HttpResponse *loginResponse = [self.runtime dispatchRequestForTesting:loginRequest];
    XCTAssertEqual(loginResponse.statusCode, 200);
    NSString *setCookie = [loginResponse headerForKey:@"Set-Cookie"];
    NSString *token = [[setCookie componentsSeparatedByString:@";"].firstObject stringByReplacingOccurrencesOfString:@"ui_admin_token=" withString:@""];

    HttpRequest *adminRequest = [self createRequestWithMethod:@"GET"
                                                         path:@"/admin"
                                                  sessionToken:token
                                                     jsonBody:nil];
    HttpResponse *adminResponse = [self.runtime dispatchRequestForTesting:adminRequest];
    XCTAssertEqual(adminResponse.statusCode, 200);

    HttpRequest *logoutRequest = [self createRequestWithMethod:@"POST"
                                                         path:@"/admin/logout"
                                                  sessionToken:token
                                                     jsonBody:nil];
    HttpResponse *logoutResponse = [self.runtime dispatchRequestForTesting:logoutRequest];
    XCTAssertEqual(logoutResponse.statusCode, 200);
}

#pragma mark - Test: Multiple Sessions

/*!
 @test testMultipleConcurrentSessions

 @abstract Verify that multiple session requests can be created and handled.
 */
- (void)testMultipleConcurrentSessions {
    NSString *token1 = [self loginAndReturnSessionToken];
    NSString *token2 = [self loginAndReturnSessionToken];
    NSString *token3 = [self loginAndReturnSessionToken];

    XCTAssertNotEqualObjects(token1, token2);
    XCTAssertNotEqualObjects(token2, token3);

    NSArray<NSString *> *tokens = @[token1, token2, token3];
    for (NSString *token in tokens) {
        HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                        path:@"/admin"
                                                 sessionToken:token
                                                    jsonBody:nil];
        HttpResponse *response = [self.runtime dispatchRequestForTesting:request];
        XCTAssertEqual(response.statusCode, 200);
    }
}

#pragma mark - Test: Bearer Token vs Cookie

/*!
 @test testBearerTokenAuthorization

 @abstract Verify that Bearer token authorization headers can be created.
 */
- (void)testBearerTokenAuthorization {
    NSString *token = [self loginAndReturnSessionToken];

    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:@""
                                                    queryParams:@{}
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:[NSData data]
                                                   remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 200);
}

- (void)testAdminShellContainsChatTab {
    HttpRequest *loginRequest = [self createRequestWithMethod:@"POST"
                                                         path:@"/admin/login"
                                                  sessionToken:nil
                                                     jsonBody:@{@"password": @"test-admin-password"}];
    HttpResponse *loginResponse = [self.runtime dispatchRequestForTesting:loginRequest];
    XCTAssertEqual(loginResponse.statusCode, 200);

    NSString *setCookie = [loginResponse headerForKey:@"Set-Cookie"];
    NSArray<NSString *> *cookieParts = [setCookie componentsSeparatedByString:@";"];
    NSString *token = cookieParts.firstObject;
    XCTAssertTrue(token.length > 0);

    HttpRequest *adminRequest = [self createRequestWithMethod:@"GET"
                                                         path:@"/admin"
                                                  sessionToken:[token stringByReplacingOccurrencesOfString:@"ui_admin_token=" withString:@""]
                                                     jsonBody:nil];
    HttpResponse *adminResponse = [self.runtime dispatchRequestForTesting:adminRequest];
    XCTAssertEqual(adminResponse.statusCode, 200);
    XCTAssertTrue([adminResponse.bodyString containsString:@"data-tab=\"chat\""]);
    XCTAssertTrue([adminResponse.bodyString containsString:@"Chat"]);
}

- (void)testDeleteAccountRoute {
    NSString *token = [self loginAndReturnSessionToken];
    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/actions/delete-account"
                                             sessionToken:token
                                                jsonBody:@{@"did": @"did:example:alice"}];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertNotEqual(response.statusCode, 404);
    XCTAssertTrue([response.bodyString containsString:@"alert"]);
}

- (void)testChatConvosPartialRoute {
    NSString *token = [self loginAndReturnSessionToken];
    HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                    path:@"/admin/partials/chat-convos"
                                             sessionToken:token
                                                jsonBody:nil];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue(response.bodyString.length > 0);
    XCTAssertNotEqual([response.bodyString rangeOfString:@"Not Found"].location, 0);
}

- (void)testBackfillQueueWithEnqueueForm {
    NSString *token = [self loginAndReturnSessionToken];
    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/actions/appview-enqueue-dids"
                                             sessionToken:token
                                                jsonBody:@{@"dids": @[@"did:example:alice"]}];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertNotEqual(response.statusCode, 404);
    XCTAssertTrue([response.bodyString containsString:@"alert"]);
}

- (void)testDisplayedPartialsCallExpectedBackendMethods {
    UIServerRuntimeBackendStub *stub = [self installBackendStub];
    NSString *token = [self loginAndReturnSessionToken];

    NSArray<NSDictionary *> *cases = @[
        @{@"path": @"/admin/partials/overview", @"call": @"fetchServiceOverview"},
        @{@"path": @"/admin/partials/sessions?did=did:plc:alice", @"call": @"fetchActiveSessionsForDID:"},
        @{@"path": @"/admin/partials/app-passwords?did=did:plc:alice", @"call": @"fetchAppPasswordsForDID:"},
        @{@"path": @"/admin/partials/ozone-reports?cursor=cursor-a", @"call": @"fetchModerationReportsWithCursor:limit:"},
        @{@"path": @"/admin/partials/ozone-settings", @"call": @"listOzoneSettings"},
        @{@"path": @"/admin/partials/plc-list", @"call": @"fetchPLCList"}
    ];

    for (NSDictionary *testCase in cases) {
        [stub.calls removeAllObjects];
        HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                        path:testCase[@"path"]
                                                 sessionToken:token
                                                    jsonBody:nil];
        HttpResponse *response = [self.runtime dispatchRequestForTesting:request];
        XCTAssertEqual(response.statusCode, 200, @"%@", testCase[@"path"]);
        XCTAssertEqualObjects(stub.calls.lastObject, testCase[@"call"], @"%@", testCase[@"path"]);
        XCTAssertFalse([response.bodyString containsString:@"Not Found"], @"%@", testCase[@"path"]);
    }

    XCTAssertEqualObjects(stub.lastDID, @"did:plc:alice");
}

- (void)testLockChatActionCallsBackendWithConvoID {
    UIServerRuntimeBackendStub *stub = [self installBackendStub];
    NSString *token = [self loginAndReturnSessionToken];
    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/actions/lock-chat-convo"
                                             sessionToken:token
                                                jsonBody:@{@"convoID": @"convo-123"}];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(stub.calls.lastObject, @"lockChatConvo:");
    XCTAssertEqualObjects(stub.lastConvoID, @"convo-123");
    XCTAssertTrue([response.bodyString containsString:@"Conversation locked"]);
}

- (void)testConnectionsUpdateActionAcceptsJSONAndRerendersMatchingInputIDs {
    NSString *token = [self loginAndReturnSessionToken];
    NSDictionary *body = @{
        @"pdsURL": @"http://pds.example",
        @"pdsToken": @"pds-token",
        @"plcURL": @"http://plc.example",
        @"plcToken": @"plc-token",
        @"relayURL": @"http://relay.example",
        @"relayToken": @"relay-token",
        @"appViewURL": @"http://appview.example",
        @"appViewToken": @"appview-token",
        @"chatURL": @"http://chat.example",
        @"chatToken": @"chat-token"
    };
    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/actions/update-connections"
                                             sessionToken:token
                                                jsonBody:body];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(self.config.appViewBaseURL.absoluteString, @"http://appview.example");
    XCTAssertEqualObjects(self.config.appViewAdminToken, @"appview-token");
    XCTAssertTrue([response.bodyString containsString:@"Connections updated"]);
    XCTAssertTrue([response.bodyString containsString:@"id=\"conn-appview-url\""]);
    XCTAssertTrue([response.bodyString containsString:@"id=\"conn-appview-token\""]);
    XCTAssertTrue([response.bodyString containsString:@"onclick=\"testConnection('appview')\""]);
}

- (void)testConnectionTestActionRunsServerSideProbe {
    UIServerRuntimeBackendStub *stub = [self installBackendStub];
    NSString *token = [self loginAndReturnSessionToken];
    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/actions/test-connection"
                                             sessionToken:token
                                                jsonBody:@{
                                                    @"service": @"appview",
                                                    @"url": @"http://appview.example",
                                                    @"token": @"appview-token"
                                                }];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];
    NSDictionary *json = [self jsonFromResponse:response];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(stub.calls.lastObject, @"testConnectionForService:baseURL:adminToken:");
    XCTAssertEqualObjects(stub.lastServiceName, @"appview");
    XCTAssertEqualObjects(stub.lastBaseURL.absoluteString, @"http://appview.example");
    XCTAssertEqualObjects(stub.lastAdminToken, @"appview-token");
    XCTAssertEqualObjects(json[@"status"], @"online");
}

@end
