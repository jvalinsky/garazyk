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

// MARK: - Deprecated Endpoints (410 Gone - migrated to tools.ozone.*)

- (void)testApplicationGetAccountTakedownRequiresAuth {
    // DEPRECATED: com.atproto.admin.getAccountTakedown -> tools.ozone.moderation.getRepo
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.getAccountTakedown"
                                                      body:@{@"did": self.userDid}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
}

- (void)testApplicationGetAccountTakedownNonAdminForbidden {
    // DEPRECATED: com.atproto.admin.getAccountTakedown -> tools.ozone.moderation.getRepo
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.getAccountTakedown"
                                                      body:@{@"did": self.userDid}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
}

- (void)testApplicationGetAccountTakedownAdminSuccess {
    // DEPRECATED: com.atproto.admin.getAccountTakedown -> tools.ozone.moderation.getRepo
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.getAccountTakedown"
                                                    body:@{@"did": self.userDid}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
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
    // DEPRECATED: com.atproto.admin.moderateAccount -> tools.ozone.moderation.emitEvent
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{
                                                          @"did": self.userDid,
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
}

- (void)testApplicationModerateRecordRequiresAuth {
    // DEPRECATED: com.atproto.admin.moderateRecord -> tools.ozone.moderation.emitEvent
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateRecord"
                                                      body:@{
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
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
