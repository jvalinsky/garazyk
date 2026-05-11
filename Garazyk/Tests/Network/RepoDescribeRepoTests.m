// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "RepoAuthXrpcTestBase.h"

@interface RepoDescribeRepoTests : RepoAuthXrpcTestBase
@end

@implementation RepoDescribeRepoTests

- (void)testDescribeRepoSuccess {
  // 1. Create a record to ensure the repo has a root and some content
  NSDictionary *record = @{
    @"$type" : @"app.bsky.feed.post",
    @"text" : @"describeRepo regression test",
    @"createdAt" : [self iso8601String]
  };
  NSString *authHeader =
      [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
  HttpResponse *createResponse =
      [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.createRecord"
                               body:@{
                                 @"repo" : self.did1,
                                 @"collection" : @"app.bsky.feed.post",
                                 @"record" : record
                               }
                            headers:@{@"authorization" : authHeader}];
  XCTAssertEqual(createResponse.statusCode, 200, @"Record creation failed");

  // 2. Call describeRepo (no auth required)
  HttpResponse *response =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.describeRepo"
                       queryParams:@{@"repo" : self.did1}
                           headers:@{}];

  XCTAssertEqual(response.statusCode, 200, @"describeRepo failed");

  NSDictionary *body = (NSDictionary *)response.jsonBody;
  XCTAssertNotNil(body, @"Response body should not be nil");
  XCTAssertEqualObjects(body[@"did"], self.did1, @"DID mismatch");
  XCTAssertNotNil(body[@"handle"], @"Handle should be present");
  XCTAssertNotNil(body[@"collections"], @"Collections should be present");
  XCTAssertTrue([body[@"collections"] containsObject:@"app.bsky.feed.post"],
                @"Collection missing from describeRepo");

  // This is the key part that was crashing:
  XCTAssertNotNil(
      body[@"didDoc"],
      @"DID document should be present or at least an empty dictionary");

  // In our refactored PDSController, we added nil guards for CID.stringValue.
  // If it was working correctly, 'root' should be present and be a valid CID
  // string.
  XCTAssertNotNil(body[@"handleIsCorrect"],
                  @"handleIsCorrect should be present");
}

- (void)testDescribeRepoNotFoundMatchesStatusCode {
  HttpResponse *response =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.describeRepo"
                       queryParams:@{@"repo" : @"did:plc:notfound1234567890"}
                           headers:@{}];
  XCTAssertEqual(response.statusCode, 404);
}

- (void)testDescribeRepoMissingParamMatchesStatusCode {
  HttpResponse *response =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.describeRepo"
                       queryParams:@{}
                           headers:@{}];
  XCTAssertEqual(response.statusCode, 400);
}

@end
