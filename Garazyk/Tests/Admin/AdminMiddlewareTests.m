// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/AdminMiddleware.h"
#import "Auth/Session.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface AdminMiddlewareTests : XCTestCase
@property (nonatomic, strong, nullable) AdminMiddleware *middleware;
@property (nonatomic, strong, nullable) SessionStore *sessionStore;
@end

@implementation AdminMiddlewareTests

- (void)setUp {
    [super setUp];
    self.middleware = [AdminMiddleware sharedMiddleware];
    self.middleware.adminDids = @[];
    self.middleware.customAdminCheck = nil;
    self.sessionStore = [SessionStore sharedStore];
}

- (void)tearDown {
    self.middleware.customAdminCheck = nil;
    self.middleware.adminDids = @[];
    self.middleware = nil;
    self.sessionStore = nil;
    [super tearDown];
}

- (HttpRequest *)requestWithAuthorization:(nullable NSString *)token {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (token) {
        headers[@"authorization"] = [NSString stringWithFormat:@"Bearer %@", token];
    }
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                   methodString:@"GET"
                                           path:@"/xrpc/com.atproto.admin.getAccountInfo"
                                    queryString:@""
                                    queryParams:@{}
                                        version:@"HTTP/1.1"
                                        headers:headers
                                           body:[NSData data]
                                   remoteAddress:@"127.0.0.1"];
}

- (void)testMissingAuthorizationHeader {
    HttpRequest *request = [self requestWithAuthorization:nil];
    HttpResponse *response = [[HttpResponse alloc] init];
    NSError *error = nil;

    BOOL allowed = [self.middleware verifyAdminAccessForRequest:request response:response error:&error];
    XCTAssertFalse(allowed);
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertNotNil(error);
}

- (void)testInvalidToken {
    HttpRequest *request = [self requestWithAuthorization:@"invalid-token"];
    HttpResponse *response = [[HttpResponse alloc] init];
    NSError *error = nil;

    BOOL allowed = [self.middleware verifyAdminAccessForRequest:request response:response error:&error];
    XCTAssertFalse(allowed);
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertNotNil(error);
}

- (void)testNonAdminTokenForbidden {
    Session *session = [self.sessionStore createSessionForDID:@"did:plc:user123"
                                                       handle:@"user.example.com"
                                                        scope:@"atproto"
                                                      dpopJWK:nil
                                                        error:nil];
    HttpRequest *request = [self requestWithAuthorization:session.accessToken];
    HttpResponse *response = [[HttpResponse alloc] init];
    NSError *error = nil;

    BOOL allowed = [self.middleware verifyAdminAccessForRequest:request response:response error:&error];
    XCTAssertFalse(allowed);
    XCTAssertEqual(response.statusCode, HttpStatusForbidden);
    XCTAssertNotNil(error);
}

- (void)testAdminDidAllowed {
    Session *session = [self.sessionStore createSessionForDID:@"did:plc:admin123"
                                                       handle:@"administrator.example.com"
                                                        scope:@"atproto"
                                                      dpopJWK:nil
                                                        error:nil];
    self.middleware.adminDids = @[session.did];

    HttpRequest *request = [self requestWithAuthorization:session.accessToken];
    HttpResponse *response = [[HttpResponse alloc] init];
    NSError *error = nil;

    BOOL allowed = [self.middleware verifyAdminAccessForRequest:request response:response error:&error];
    XCTAssertTrue(allowed);
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertNil(error);
}

- (void)testCustomAdminCheckAllows {
    Session *session = [self.sessionStore createSessionForDID:@"did:plc:custom123"
                                                       handle:@"user.example.com"
                                                        scope:@"atproto"
                                                      dpopJWK:nil
                                                        error:nil];
    self.middleware.customAdminCheck = ^BOOL(Session *sessionToCheck) {
        return [sessionToCheck.did isEqualToString:@"did:plc:custom123"];
    };

    HttpRequest *request = [self requestWithAuthorization:session.accessToken];
    HttpResponse *response = [[HttpResponse alloc] init];
    NSError *error = nil;

    BOOL allowed = [self.middleware verifyAdminAccessForRequest:request response:response error:&error];
    XCTAssertTrue(allowed);
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertNil(error);
}

@end

NS_ASSUME_NONNULL_END
