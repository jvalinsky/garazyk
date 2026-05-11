// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyGraphTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyGraphTests

#pragma mark - getMutes Tests

- (void)testGetMutesRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getMutes"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetMutesSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getMutes"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - getBlocks Tests

- (void)testGetBlocksRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getBlocks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetBlocksSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getBlocks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - getFollowers Tests

- (void)testGetFollowersRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getFollowers"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetFollowersSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getFollowers"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - getFollows Tests

- (void)testGetFollowsRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getFollows"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetFollowsSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getFollows"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - muteActor Tests

- (void)testMuteActorRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActor"
                                                      body:@{@"actor": @"did:plc:other"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testMuteActorRequiresBody {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActor"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testMuteActorSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActor"
                                                      body:@{@"actor": @"did:plc:other"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - unmuteActor Tests

- (void)testUnmuteActorRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteActor"
                                                      body:@{@"actor": @"did:plc:other"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUnmuteActorSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteActor"
                                                      body:@{@"actor": @"did:plc:other"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - getRelationships Tests

- (void)testGetRelationshipsRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getRelationships"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetRelationshipsSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getRelationships"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"relationships"]);
}

#pragma mark - getLists Tests

- (void)testGetListsRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getLists"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetListsSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getLists"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - getList Tests

- (void)testGetListRequiresList {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getList"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

#pragma mark - getKnownFollowers Tests

- (void)testGetKnownFollowersRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getKnownFollowers"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetKnownFollowersSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getKnownFollowers"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - getSuggestedFollowsByActor Tests

- (void)testGetSuggestedFollowsByActorSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getSuggestedFollowsByActor"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"suggestions"]);
}

#pragma mark - muteActorList Tests

- (void)testMuteActorListRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActorList"
                                                      body:@{@"list": @"at://did:plc:test/app.bsky.graph.list/abc123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testMuteActorListInvalidURI {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActorList"
                                                      body:@{@"list": @"not-a-valid-uri"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testMuteActorListSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActorList"
                                                      body:@{@"list": @"at://did:plc:test/app.bsky.graph.list/abc123"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - unmuteActorList Tests

- (void)testUnmuteActorListRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteActorList"
                                                      body:@{@"list": @"at://did:plc:test/app.bsky.graph.list/abc123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUnmuteActorListSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteActorList"
                                                      body:@{@"list": @"at://did:plc:test/app.bsky.graph.list/abc123"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - muteThread Tests

- (void)testMuteThreadRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteThread"
                                                      body:@{@"root": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testMuteThreadInvalidURI {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteThread"
                                                      body:@{@"root": @"not-a-valid-uri"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testMuteThreadSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteThread"
                                                      body:@{@"root": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - unmuteThread Tests

- (void)testUnmuteThreadRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteThread"
                                                      body:@{@"root": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUnmuteThreadSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteThread"
                                                      body:@{@"root": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - searchStarterPacks Tests

- (void)testSearchStarterPacksSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.searchStarterPacks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

#pragma mark - getStarterPack Tests

- (void)testGetStarterPackRequiresUri {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getStarterPack"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetStarterPackSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getStarterPack"
                                             queryString:@"uri=at://did:plc:test/app.bsky.graph.starterpack/abc"
                                             queryParams:@{@"uri": @"at://did:plc:test/app.bsky.graph.starterpack/abc"}
                                                 headers:@{}];
    // Non-existent starter pack returns 404; valid pack would return 200
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 404);
}

#pragma mark - getActorStarterPacks Tests

- (void)testGetActorStarterPacksRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getActorStarterPacks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetActorStarterPacksSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getActorStarterPacks"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

#pragma mark - getStarterPacks Tests

- (void)testGetStarterPacksSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getStarterPacks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

#pragma mark - getStarterPacksWithMembership Tests

- (void)testGetStarterPacksWithMembershipRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getStarterPacksWithMembership"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetStarterPacksWithMembershipRequiresActor {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getStarterPacksWithMembership"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetStarterPacksWithMembershipSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getStarterPacksWithMembership"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacksWithMembership"]);
}

#pragma mark - getListsWithMembership Tests

- (void)testGetListsWithMembershipRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListsWithMembership"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetListsWithMembershipSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.graph.getListsWithMembership"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
}

@end
