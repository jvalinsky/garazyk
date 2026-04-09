#import "AdminAuthXrpcTestBase.h"

@interface AdminAuthModerationTests : AdminAuthXrpcTestBase
@end

@implementation AdminAuthModerationTests

- (void)testApplicationGetSubjectStatusRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationGetSubjectStatusNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"Forbidden");
}

- (void)testApplicationGetSubjectStatusAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"subject"][@"did"], self.userDid);
}

- (void)testApplicationGetAccountTakedownRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.getAccountTakedown"
                                                      body:@{@"did": self.userDid}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationGetAccountTakedownNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.getAccountTakedown"
                                                      body:@{@"did": self.userDid}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"Forbidden");
}

- (void)testApplicationGetAccountTakedownAdminSuccess {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];

    HttpResponse *before = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.getAccountTakedown"
                                                    body:@{@"did": self.userDid}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(before.statusCode, 200);
    XCTAssertEqualObjects(before.jsonBody[@"did"], self.userDid);
    XCTAssertEqualObjects(before.jsonBody[@"applied"], @NO);

    HttpResponse *update = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateSubjectStatus"
                                                    body:@{@"subject": @{@"did": self.userDid}, @"reason": @"integration-test"}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(update.statusCode, 200);

    HttpResponse *after = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.getAccountTakedown"
                                                   body:@{@"did": self.userDid}
                                                headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(after.statusCode, 200);
    XCTAssertEqualObjects(after.jsonBody[@"did"], self.userDid);
    XCTAssertEqualObjects(after.jsonBody[@"applied"], @YES);
}

- (void)testApplicationUpdateSubjectStatusRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateSubjectStatus"
                                                      body:@{
                                                          @"subject": @{@"did": self.userDid},
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationModerateAccountRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{
                                                          @"did": self.userDid,
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationModerateRecordRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateRecord"
                                                      body:@{
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationCreateLabelRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.label.createLabel"
                                                      body:@{
                                                          @"src": self.userDid,
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"val": @"spam"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationGetLabelsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.label.getLabels"
                                              queryString:@"limit=10"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationSubscribeLabelsRequiresWebSocketUpgrade {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.label.subscribeLabels"
                                              queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 426);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"UpgradeRequired");
}

- (void)testApplicationSubscribeLabelsRejectsFutureCursor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.label.subscribeLabels"
                                              queryString:@"cursor=1"
                                              queryParams:@{@"cursor": @"1"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"FutureCursor");
}

@end
