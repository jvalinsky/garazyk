#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyVideoTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyVideoTests

#pragma mark - getJobStatus Tests

- (void)testGetJobStatusRequiresJobId {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.video.getJobStatus"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

#pragma mark - uploadVideo Tests

- (void)testUploadVideoRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.video.uploadVideo"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - getUploadLimits Tests

- (void)testGetUploadLimitsSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.video.getUploadLimits"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"canUpload"]);
    XCTAssertNotNil(response.jsonBody[@"remainingDailyVideos"]);
    XCTAssertNotNil(response.jsonBody[@"remainingDailyBytes"]);
}

- (void)testGetUploadLimitsWithAuth {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.video.getUploadLimits"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"canUpload"]);
    XCTAssertNotNil(response.jsonBody[@"remainingDailyVideos"]);
    XCTAssertNotNil(response.jsonBody[@"remainingDailyBytes"]);
}

@end
