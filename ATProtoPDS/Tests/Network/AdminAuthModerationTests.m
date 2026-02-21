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

@end
