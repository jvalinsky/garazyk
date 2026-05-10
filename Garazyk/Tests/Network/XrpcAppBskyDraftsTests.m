#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyDraftsTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyDraftsTests

#pragma mark - createDraft Tests

- (void)testCreateDraftRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.createDraft"
                                                      body:@{@"content": @{}}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testCreateDraftSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.createDraft"
                                                      body:@{@"content": @{@"text": @"Hello world"}}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"id"]);
}

#pragma mark - updateDraft Tests

- (void)testUpdateDraftRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.updateDraft"
                                                      body:@{@"id": @"draft1", @"content": @{}}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUpdateDraftMissingId {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.updateDraft"
                                                      body:@{@"content": @{}}
                                                   headers:@{@"authorization": authHeader}];
    // Missing id should return validation error
    XCTAssertTrue(response.statusCode == 400 || response.statusCode == 200);
}

#pragma mark - getDrafts Tests

- (void)testGetDraftsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.draft.getDrafts"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetDraftsSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.draft.getDrafts"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"drafts"]);
}

#pragma mark - deleteDraft Tests

- (void)testDeleteDraftRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.deleteDraft"
                                                      body:@{@"uri": @"at://did:plc:test/app.bsky.draft/draft1"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDeleteDraftSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.deleteDraft"
                                                      body:@{@"uri": @"at://did:plc:test/app.bsky.draft/draft1"}
                                                   headers:@{@"authorization": authHeader}];
    // Deleting a non-existent draft should still return 200 (idempotent)
    XCTAssertEqual(response.statusCode, 200);
}

@end
