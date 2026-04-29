#import "AdminAuthXrpcTestBase.h"
#import "Database/PDSDatabase.h"
#import "Video/VideoXrpcPack.h"

// Expose private class methods for testing
@interface ATProtoVideoXrpcPack (Testing)
+ (NSDictionary *)formatJobResponse:(NSDictionary *)job;
+ (NSDictionary *)getUploadLimitsForDid:(NSString *)did
                                jobStore:(id<VideoJobStore>)jobStore;
+ (BOOL)validateVideoContentType:(NSData *)data declaredMimeType:(NSString *)mimeType;
@end

@interface ATProtoVideoXrpcPackTests : AdminAuthXrpcTestBase
@end

@implementation ATProtoVideoXrpcPackTests

#pragma mark - getJobStatus Tests

- (void)testGetJobStatusRequiresJobId {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.video.getJobStatus"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetJobStatusNotFound {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.video.getJobStatus"
                                             queryString:@""
                                             queryParams:@{@"jobId": @"nonexistent-job-id"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 404);
}

- (void)testGetJobStatusWithValidJob {
    // Create a job directly in the database
    PDSDatabase *db = self.application.legacyController.database;
    [db createVideoJobWithId:@"test-job-status"
                         did:self.userDid
                      blobCid:@"bafyreitest123"
                     mimeType:@"video/mp4"
                     fileSize:@(2048)
              serviceAuthToken:nil
                         error:nil];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.video.getJobStatus"
                                             queryString:@""
                                             queryParams:@{@"jobId": @"test-job-status"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *body = response.jsonBody;
    XCTAssertNotNil(body);
    XCTAssertEqualObjects(body[@"jobId"], @"test-job-status");
    XCTAssertEqualObjects(body[@"state"], @"JOB_STATE_PENDING");
}

#pragma mark - uploadVideo Tests

- (void)testUploadVideoRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.video.uploadVideo"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUploadVideoEmptyBody {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendRawRequestWithPath:@"/xrpc/app.bsky.video.uploadVideo"
                                                     body:[NSData data]
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
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

- (void)testGetUploadLimitsReturnsCorrectShape {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.video.getUploadLimits"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *body = response.jsonBody;
    XCTAssertTrue([body[@"canUpload"] isKindOfClass:[NSNumber class]]);
    XCTAssertTrue([body[@"remainingDailyVideos"] isKindOfClass:[NSNumber class]]);
    XCTAssertTrue([body[@"remainingDailyBytes"] isKindOfClass:[NSNumber class]]);
    XCTAssertTrue([body[@"message"] isKindOfClass:[NSString class]]);
}

#pragma mark - formatJobResponse Tests

- (void)testFormatJobResponsePending {
    NSDictionary *job = @{
        @"job_id": @"job-1",
        @"did": @"did:web:test.example.com",
        @"state": @"PENDING",
        @"progress": @0
    };
    NSDictionary *response = [ATProtoVideoXrpcPack formatJobResponse:job];
    XCTAssertEqualObjects(response[@"state"], @"JOB_STATE_PENDING");
    XCTAssertEqualObjects(response[@"jobId"], @"job-1");
}

- (void)testFormatJobResponseCompleted {
    NSDictionary *job = @{
        @"job_id": @"job-2",
        @"did": @"did:web:test.example.com",
        @"state": @"COMPLETED",
        @"progress": @100,
        @"processed_blob_cid": @"bafyreiprocessed",
        @"mime_type": @"video/mp4"
    };
    NSDictionary *response = [ATProtoVideoXrpcPack formatJobResponse:job];
    XCTAssertEqualObjects(response[@"state"], @"JOB_STATE_COMPLETED");
    XCTAssertNotNil(response[@"blob"]);
    XCTAssertEqualObjects(response[@"blob"][@"$type"], @"blob");
}

- (void)testFormatJobResponseFailed {
    NSDictionary *job = @{
        @"job_id": @"job-3",
        @"did": @"did:web:test.example.com",
        @"state": @"FAILED",
        @"progress": @0,
        @"error_message": @"Transcoding failed"
    };
    NSDictionary *response = [ATProtoVideoXrpcPack formatJobResponse:job];
    XCTAssertEqualObjects(response[@"state"], @"JOB_STATE_FAILED");
    XCTAssertEqualObjects(response[@"error"], @"Transcoding failed");
}

#pragma mark - Content Type Validation Tests

- (void)testValidateVideoContentTypeAcceptsMP4 {
    // Create minimal MP4 data with ftyp box
    NSMutableData *data = [NSMutableData dataWithLength:12];
    uint8_t *bytes = (uint8_t *)data.mutableBytes;
    // ftyp at offset 4
    bytes[4] = 'f'; bytes[5] = 't'; bytes[6] = 'y'; bytes[7] = 'p';
    XCTAssertTrue([ATProtoVideoXrpcPack validateVideoContentType:data declaredMimeType:@"video/mp4"]);
}

- (void)testValidateVideoContentTypeRejectsNonVideo {
    NSData *data = [@"this is plain text, not a video" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([ATProtoVideoXrpcPack validateVideoContentType:data declaredMimeType:@"video/mp4"]);
}

- (void)testValidateVideoContentTypeRejectsTooShort {
    NSData *data = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([ATProtoVideoXrpcPack validateVideoContentType:data declaredMimeType:@"video/mp4"]);
}

#pragma mark - Helper

- (HttpResponse *)sendRawRequestWithPath:(NSString *)path
                                     body:(NSData *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [@{@"content-type": @"application/octet-stream"} mutableCopy];
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
                                                          body:body ?: [NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

@end
