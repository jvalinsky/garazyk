#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyGraphListTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyGraphListTests

// MARK: - app.bsky.graph.getListMutes Tests

- (void)testGetListMutesRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListMutes"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testGetListMutesReturnsEmptyForNewUser {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListMutes"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"lists"]);
    XCTAssertEqual([response.jsonBody[@"lists"] count], 0);
}

- (void)testGetListMutesWithPagination {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // First request without cursor
    HttpResponse *response1 = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListMutes"
                                              queryString:@""
                                              queryParams:@{}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response1.statusCode, 200);
    NSArray *lists1 = response1.jsonBody[@"lists"];
    XCTAssertNotNil(lists1);

    // Response should have empty lists array when no lists are muted
    XCTAssertEqual([lists1 count], 0);

    // No cursor should be present when list fits in page
    XCTAssertNil(response1.jsonBody[@"cursor"]);
}

// MARK: - app.bsky.graph.getListBlocks Tests

- (void)testGetListBlocksRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListBlocks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testGetListBlocksReturnsEmptyForNewUser {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListBlocks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"blocks"]);
    XCTAssertEqual([response.jsonBody[@"blocks"] count], 0);
}

// MARK: - app.bsky.graph.getListsWithMembership Tests

- (void)testGetListsWithMembershipRequireActorParam {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListsWithMembership"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testGetListsWithMembershipForUser {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListsWithMembership"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"lists"]);
    XCTAssertEqual([response.jsonBody[@"lists"] count], 0);
}

- (void)testGetListsWithMembershipForInvalidActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListsWithMembership"
                                             queryString:@"actor=did:plc:invalid"
                                             queryParams:@{@"actor": @"did:plc:invalid"}
                                                 headers:@{}];
    // Should return 400 for invalid actor or 200 with empty lists
    XCTAssertTrue(response.statusCode == 400 || response.statusCode == 200);
}

@end
