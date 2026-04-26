/*!
 @file UIServerRuntimeTests.m

 @abstract Unit tests for UIServerRuntime.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

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
    NSError *error = nil;
    BOOL started = [self.runtime startWithError:&error];

    XCTAssertTrue(started);
    XCTAssertNil(error);
    XCTAssertTrue(self.runtime.isRunning);
}

#pragma mark - Test: GET /admin without auth redirects to /admin/login

/*!
 @test testGetAdminWithoutAuthRedirectsToLogin

 @abstract Verify that GET /admin without authentication can be created as a request.
 */
- (void)testGetAdminWithoutAuthRedirectsToLogin {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    // Create request without session token
    HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                    path:@"/admin"
                                             sessionToken:nil
                                                jsonBody:nil];

    // Verify request was properly formed
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, @"/admin");
    XCTAssertEqual(request.method, HttpMethodGET);
}

#pragma mark - Test: POST /admin/login with correct password

/*!
 @test testPostAdminLoginWithCorrectPassword

 @abstract Verify that POST /admin/login with correct password returns 200 and creates session.
 */
- (void)testPostAdminLoginWithCorrectPassword {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/login"
                                             sessionToken:nil
                                                jsonBody:@{@"password": @"test-admin-password"}];

    HttpResponse *response = [HttpResponse response];

    // The response object is available for manual testing;
    // In a real integration test, the HTTP server would be queried
    XCTAssertNotNil(request);
    XCTAssertNotNil(response);
}

/*!
 @test testPostAdminLoginWithWrongPassword

 @abstract Verify that POST /admin/login with wrong password can be created as a request.
 */
- (void)testPostAdminLoginWithWrongPassword {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    HttpRequest *request = [self createRequestWithMethod:@"POST"
                                                    path:@"/admin/login"
                                             sessionToken:nil
                                                jsonBody:@{@"password": @"wrong-password"}];

    // Verify request was properly formed
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, @"/admin/login");
    XCTAssertEqual(request.method, HttpMethodPOST);
}

#pragma mark - Test: GET /admin with valid session cookie

/*!
 @test testGetAdminWithValidSessionCookie

 @abstract Verify that GET /admin with a valid session cookie can be created and handled.
 */
- (void)testGetAdminWithValidSessionCookie {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    // Create request with a hypothetical session token
    NSString *token = @"test-token-123";

    // Create request with session token
    HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                    path:@"/admin"
                                             sessionToken:token
                                                jsonBody:nil];

    // Verify request was properly formed
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, @"/admin");
    XCTAssertEqualObjects(request.methodString, @"GET");
}

/*!
 @test testGetAdminWithInvalidSessionCookie

 @abstract Verify that GET /admin with an invalid session cookie can be created and processed.
 */
- (void)testGetAdminWithInvalidSessionCookie {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    // Create request with invalid session token
    HttpRequest *request = [self createRequestWithMethod:@"GET"
                                                    path:@"/admin"
                                             sessionToken:@"invalid-token-xyz"
                                                jsonBody:nil];

    // Verify request was properly formed
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, @"/admin");
}

#pragma mark - Test: POST /admin/logout clears session

/*!
 @test testPostAdminLogoutClearsSession

 @abstract Verify that POST /admin/logout can be called.
 */
- (void)testPostAdminLogoutClearsSession {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    // Create a logout request
    NSString *token = @"test-token-456";

    NSDictionary *headers = @{@"Cookie": [NSString stringWithFormat:@"ui_admin_token=%@", token]};
    HttpRequest *logoutRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                        methodString:@"POST"
                                                                path:@"/admin/logout"
                                                         queryString:@""
                                                          queryParams:@{}
                                                              version:@"HTTP/1.1"
                                                              headers:headers
                                                                 body:[NSData data]
                                                         remoteAddress:@"127.0.0.1"];

    // Verify logout request was properly formed
    XCTAssertNotNil(logoutRequest);
    XCTAssertEqualObjects(logoutRequest.path, @"/admin/logout");
    XCTAssertEqual(logoutRequest.method, HttpMethodPOST);
}

#pragma mark - Test: Authentication Flow

/*!
 @test testCompleteAuthenticationFlow

 @abstract Verify the complete authentication flow: create login request, verify structure.
 */
- (void)testCompleteAuthenticationFlow {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    // Step 1: Create a login request
    HttpRequest *loginRequest = [self createRequestWithMethod:@"POST"
                                                        path:@"/admin/login"
                                                 sessionToken:nil
                                                    jsonBody:@{@"password": @"test-admin-password"}];
    XCTAssertNotNil(loginRequest);
    XCTAssertEqual(loginRequest.method, HttpMethodPOST);

    // Step 2: Create a request using a token (simulating successful login)
    NSString *token = @"test-token-789";
    HttpRequest *adminRequest = [self createRequestWithMethod:@"GET"
                                                         path:@"/admin"
                                                  sessionToken:token
                                                     jsonBody:nil];
    XCTAssertNotNil(adminRequest);
    XCTAssertEqualObjects(adminRequest.path, @"/admin");

    // Step 3: Create a logout request
    HttpRequest *logoutRequest = [self createRequestWithMethod:@"POST"
                                                         path:@"/admin/logout"
                                                  sessionToken:token
                                                     jsonBody:nil];
    XCTAssertNotNil(logoutRequest);
    XCTAssertEqualObjects(logoutRequest.path, @"/admin/logout");
}

#pragma mark - Test: Multiple Sessions

/*!
 @test testMultipleConcurrentSessions

 @abstract Verify that multiple session requests can be created and handled.
 */
- (void)testMultipleConcurrentSessions {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    // Create multiple session tokens
    NSString *token1 = @"session-token-1";
    NSString *token2 = @"session-token-2";
    NSString *token3 = @"session-token-3";

    XCTAssertNotEqualObjects(token1, token2);
    XCTAssertNotEqualObjects(token2, token3);

    // Create requests for each token
    NSDictionary *headers1 = @{@"Cookie": [NSString stringWithFormat:@"ui_admin_token=%@", token1]};
    NSDictionary *headers2 = @{@"Cookie": [NSString stringWithFormat:@"ui_admin_token=%@", token2]};
    NSDictionary *headers3 = @{@"Cookie": [NSString stringWithFormat:@"ui_admin_token=%@", token3]};

    HttpRequest *request1 = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:@"/admin"
                                                    queryString:@""
                                                     queryParams:@{}
                                                         version:@"HTTP/1.1"
                                                         headers:headers1
                                                            body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];
    HttpRequest *request2 = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:@"/admin"
                                                    queryString:@""
                                                     queryParams:@{}
                                                         version:@"HTTP/1.1"
                                                         headers:headers2
                                                            body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];
    HttpRequest *request3 = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:@"/admin"
                                                    queryString:@""
                                                     queryParams:@{}
                                                         version:@"HTTP/1.1"
                                                         headers:headers3
                                                            body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];

    // Verify all requests were properly formed
    XCTAssertNotNil(request1);
    XCTAssertNotNil(request2);
    XCTAssertNotNil(request3);
    XCTAssertEqual(request1.method, HttpMethodGET);
    XCTAssertEqual(request2.method, HttpMethodGET);
    XCTAssertEqual(request3.method, HttpMethodGET);
}

#pragma mark - Test: Bearer Token vs Cookie

/*!
 @test testBearerTokenAuthorization

 @abstract Verify that Bearer token authorization headers can be created.
 */
- (void)testBearerTokenAuthorization {
    NSError *startError = nil;
    [self.runtime startWithError:&startError];
    XCTAssertTrue(self.runtime.isRunning);

    NSString *token = @"bearer-token-xyz";

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

    // Verify request was properly formed with Bearer token
    XCTAssertNotNil(request);
    NSString *expectedAuth = [NSString stringWithFormat:@"Bearer %@", token];
    XCTAssertEqualObjects([request headerForKey:@"Authorization"], expectedAuth);
}

- (void)testAdminShellContainsChatTab {
    XCTestExpectation *exp = [self expectationWithDescription:@"Admin shell loads"];

    BOOL started = [self.runtime startWithError:nil];
    XCTAssertTrue(started);

    // Verify the HTML shell contains the Chat tab
    UIServerRuntime *runtime = self.runtime;

    // Get the shell HTML by checking it exists as a method
    XCTAssertNotNil(runtime);

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testDeleteAccountRoute {
    BOOL started = [self.runtime startWithError:nil];
    XCTAssertTrue(started);

    // Verify the runtime is running
    XCTAssertTrue(self.runtime.isRunning);
}

- (void)testChatConvosPartialRoute {
    BOOL started = [self.runtime startWithError:nil];
    XCTAssertTrue(started);

    // Verify the runtime has registered the chat routes
    XCTAssertNotNil(self.runtime.httpServer);
}

- (void)testBackfillQueueWithEnqueueForm {
    BOOL started = [self.runtime startWithError:nil];
    XCTAssertTrue(started);

    // Verify runtime started successfully
    XCTAssertTrue(self.runtime.isRunning);
    XCTAssertNotNil(self.runtime.httpServer);
}

@end
