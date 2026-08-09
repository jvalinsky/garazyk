// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/MSTViewer/MSTViewerHandler.h"
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Admin/PDSAdminAuth.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface ATProtoServiceConfiguration (MSTViewerTestAccess)
- (void)applyConfig:(NSDictionary *)config;
@end

@interface MSTViewerHandlerTests : XCTestCase
@property (nonatomic, strong) MSTViewerHandler *handler;
@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *adminJwt;
@end

@implementation MSTViewerHandlerTests

- (void)setUp {
    [super setUp];

    unsetenv("PDS_APPVIEW_URL");
    unsetenv("PDS_CHAT_URL");
    unsetenv("PDS_ISSUER");
    setenv("PDS_AVAILABLE_USER_DOMAINS", "test", 1);
    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    setenv("PDS_MASTER_SECRET", "test-master-secret-123", 1);
    setenv("PDS_PLC_URL", "mock", 1);
    [[ATProtoServiceConfiguration sharedConfiguration] applyConfig:@{@"server": @{}}];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError *dirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&dirError];
    XCTAssertNil(dirError, @"Failed to create temp directory: %@", dirError);

    self.application = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];

    NSError *error = nil;
    [self.application.legacyController createAccountForEmail:@"admin-mst@example.com"
                                                     password:@"password"
                                                       handle:@"admin.mst.test"
                                                          did:nil
                                                        error:&error];
    XCTAssertNil(error, @"Failed to create admin account: %@", error);

    NSError *adminAuthError = nil;
    [PDSAdminAuth sharedAuth].dataDirectory = self.tempURL.path;
    [PDSAdminAuth sharedAuth].controller = self.application.legacyController;
    BOOL adminAuthSuccess = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"password" error:&adminAuthError];
    XCTAssertTrue(adminAuthSuccess, @"Admin authentication failed: %@", adminAuthError);
    self.adminJwt = [PDSAdminAuth sharedAuth].adminToken;
    XCTAssertTrue(self.adminJwt.length > 0);

    self.handler = [MSTViewerHandler sharedHandler];
}

- (void)tearDown {
    [self.application stop];
    [PDSAdminAuth sharedAuth].dataDirectory = nil;
    [PDSAdminAuth sharedAuth].controller = nil;
    self.application = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (void)testCanHandleRequest {
    ATProtoHttpRequest *req1 = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/mst-viewer" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    XCTAssertTrue([self.handler canHandleRequest:req1]);

    ATProtoHttpRequest *req2 = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/api/mst/tree" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    XCTAssertTrue([self.handler canHandleRequest:req2]);

    ATProtoHttpRequest *req3 = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/other" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    XCTAssertFalse([self.handler canHandleRequest:req3]);
}

- (void)testHandleRequestRejectsUnauthenticated {
    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/mst-viewer" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    [self.handler handleRequest:req response:res];

    XCTAssertEqual(res.statusCode, HttpStatusUnauthorized);
}

- (void)testHandleRequestIndexReturns200HtmlContentWithAuth {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/mst-viewer" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{@"authorization": authHeader} body:nil remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    [self.handler handleRequest:req response:res];

    XCTAssertEqual(res.statusCode, 200);
    XCTAssertTrue([[res headerForKey:@"Content-Type"] containsString:@"text/html"]);
}

- (void)testApiMstAccountsRejectsUnauthenticated {
    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/api/mst/accounts" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    [self.handler handleRequest:req response:res];

    XCTAssertEqual(res.statusCode, HttpStatusUnauthorized);
}

@end
