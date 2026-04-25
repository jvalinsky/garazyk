#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyDraftsTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyDraftsTests

#pragma mark - createDraft Tests

- (void)testCreateDraftRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.createDraft"
                                                      body:@{@"text": @"Hello world"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testCreateDraftNotImplemented {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.createDraft"
                                                      body:@{@"text": @"Hello world"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 501);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"NotImplemented");
}

#pragma mark - updateDraft Tests

- (void)testUpdateDraftRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.updateDraft"
                                                      body:@{@"draftId": @"draft1", @"text": @"Updated"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUpdateDraftNotImplemented {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.updateDraft"
                                                      body:@{@"draftId": @"draft1", @"text": @"Updated"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 501);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"NotImplemented");
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
                                                      body:@{@"draftId": @"draft1"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDeleteDraftSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.draft.deleteDraft"
                                                      body:@{@"draftId": @"draft1"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

@end
