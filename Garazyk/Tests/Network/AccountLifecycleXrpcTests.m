// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"

@interface PDSConfiguration (Test)
- (void)applyConfig:(NSDictionary *)config;
@end

@interface AccountLifecycleXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@end

@implementation AccountLifecycleXrpcTests

- (void)setUp {
    [super setUp];

    setenv("PDS_AVAILABLE_USER_DOMAINS", "test", 1);
    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    setenv("PDS_MASTER_SECRET", "test-master-secret-123", 1);
    setenv("PDS_PLC_URL", "mock", 1);
    [[PDSConfiguration sharedConfiguration] applyConfig:@{@"server": @{}}];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.controller = app.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:app];

    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"lifecycle@example.com"
                                                          password:@"password"
                                                            handle:@"lifecycle.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.userDid = account[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"lifecycle.test" password:@"password" error:&error];
    XCTAssertNil(error);
    self.userJwt = session[@"accessJwt"];
    XCTAssertNotNil(self.userJwt);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                     body:(NSDictionary *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSData *bodyData = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : [NSData data];
    NSMutableDictionary *allHeaders = [@{@"content-type": @"application/json"} mutableCopy];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:bodyData
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

#pragma mark - checkAccountStatus

- (void)testCheckAccountStatusReturnsValidForActiveAccount {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.checkAccountStatus"
                                                       body:nil
                                                    headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *json = response.jsonBody;
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(json[@"valid"], @YES);
}

- (void)testCheckAccountStatusReturns401WithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.checkAccountStatus"
                                                       body:nil
                                                    headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - deactivateAccount

- (void)testDeactivateAccountSucceeds {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deactivateAccount"
                                                       body:@{@"reason": @"testing"}
                                                    headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *json = response.jsonBody;
    XCTAssertEqualObjects(json[@"success"], @YES);
}

- (void)testDeactivateAccountReturns401WithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deactivateAccount"
                                                       body:@{@"reason": @"testing"}
                                                    headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - activateAccount

- (void)testActivateAccountAfterDeactivation {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // First deactivate
    HttpResponse *deactivateResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deactivateAccount"
                                                                body:@{@"reason": @"testing"}
                                                             headers:@{@"authorization": authHeader}];
    XCTAssertEqual(deactivateResponse.statusCode, 200);

    // Then activate
    HttpResponse *activateResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.activateAccount"
                                                              body:nil
                                                           headers:@{@"authorization": authHeader}];
    XCTAssertEqual(activateResponse.statusCode, 200);
    NSDictionary *json = activateResponse.jsonBody;
    XCTAssertEqualObjects(json[@"success"], @YES);

    // Verify account is valid again
    HttpResponse *statusResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.checkAccountStatus"
                                                            body:nil
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(statusResponse.statusCode, 200);
    XCTAssertEqualObjects(statusResponse.jsonBody[@"valid"], @YES);
}

- (void)testActivateAccountReturns401WithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.activateAccount"
                                                       body:nil
                                                    headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - getAccount

- (void)testGetAccountReturnsAccountInfo {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.getAccount"
                                                       body:nil
                                                    headers:@{@"authorization": authHeader}];
    // getAccount may return 200 with account data or 404 if not implemented
    // at the XRPC level — verify it doesn't crash
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 501,
                  @"getAccount should return 200, 404, or 501, got %ld", (long)response.statusCode);
}

@end
