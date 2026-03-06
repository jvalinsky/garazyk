#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"

@interface RepoAuthRepoTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthRepoTests

- (void)testDeleteRecordReturns401WithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"delete auth test",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                        record:record
                                                validationMode:PDSValidationModeRequired
                                                         error:nil];
    XCTAssertNotNil(created);
    NSString *uri = created[@"uri"];
    NSString *rkey = [[uri componentsSeparatedByString:@"/"] lastObject];

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.deleteRecord"
                                                      body:@{@"repo": self.did1,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": rkey}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutRecordReturns401WithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"put auth test",
        @"createdAt": [self iso8601String]
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.putRecord"
                                                      body:@{@"repo": self.did1,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": @"auth-test",
                                                             @"record": record}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testApplyWritesReturns401WithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"apply auth test",
        @"createdAt": [self iso8601String]
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                      body:@{@"repo": self.did1,
                                                             @"writes": @[@{@"action": @"create",
                                                                            @"collection": @"app.bsky.feed.post",
                                                                            @"record": record}]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutRecordRepoMismatchForbidden {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"put mismatch test",
        @"createdAt": [self iso8601String]
    };
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.putRecord"
                                                      body:@{@"repo": self.did2,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": @"auth-mismatch",
                                                             @"record": record}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testRepoListMissingBlobsReturns401WithoutAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.listMissingBlobs"
                                               queryParams:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRepoListMissingBlobsReturnsEmptyList {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.listMissingBlobs"
                                               queryParams:@{@"limit": @"10"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"blobs"]);
    XCTAssertTrue([response.jsonBody[@"blobs"] isKindOfClass:[NSArray class]]);
}

- (void)testRepoImportRepoReturns401WithoutAuth {
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"content-type": @"application/vnd.ipld.car",
                                                          @"content-length": [NSString stringWithFormat:@"%lu", (unsigned long)carData.length]
                                                      }];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRepoImportRepoReturnsBadRequestWithoutContentLengthHeader {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"authorization": authHeader,
                                                          @"content-type": @"application/vnd.ipld.car"
                                                      }];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testRepoImportRepoReturnsNotImplemented {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"authorization": authHeader,
                                                          @"content-type": @"application/vnd.ipld.car",
                                                          @"content-length": [NSString stringWithFormat:@"%lu", (unsigned long)carData.length]
                                                      }];
    XCTAssertEqual(response.statusCode, 501);
    NSDictionary *body = (NSDictionary *)response.jsonBody;
    XCTAssertEqualObjects(body[@"error"], @"NotImplemented");
}

@end
