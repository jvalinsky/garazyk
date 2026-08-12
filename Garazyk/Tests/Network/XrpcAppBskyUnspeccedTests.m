// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"

// Define XCTAssertIsInstance macro if not available
#ifndef XCTAssertIsInstance
#define XCTAssertIsInstance(expr, classExpr) \
    XCTAssertTrue([(expr) isKindOfClass:(classExpr)], @"Expected %@ to be instance of %@", (expr), (classExpr))
#endif

@interface XrpcAppBskyUnspeccedTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyUnspeccedTests

#pragma mark - Labeler Tests

- (void)testLabelerGetServices {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.labeler.getServices"
                                             queryString:@"dids=did:plc:test123"
                                             queryParams:@{@"dids": @[@"did:plc:test123"]}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"views"]);
    XCTAssertIsInstance(response.jsonBody[@"views"], [NSArray class]);
}

- (void)testLabelerGetServicesRequiresDids {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.labeler.getServices"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

#pragma mark - Config Tests

- (void)testGetConfig {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getConfig"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"checkEmailConfirmed"]);
    XCTAssertNotNil(response.jsonBody[@"labelerDefinitions"]);
    XCTAssertNotNil(response.jsonBody[@"generators"]);
    XCTAssertNotNil(response.jsonBody[@"feeds"]);
}

#pragma mark - Suggestions & Discovery Tests

- (void)testGetTaggedSuggestions {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getTaggedSuggestions"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"suggestions"]);
    XCTAssertIsInstance(response.jsonBody[@"suggestions"], [NSArray class]);
}

- (void)testGetPopularFeedGenerators {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPopularFeedGenerators"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"feeds"]);
    XCTAssertIsInstance(response.jsonBody[@"feeds"], [NSArray class]);
}

- (void)testGetSuggestedFeeds {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedFeeds"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"feeds"]);
    XCTAssertIsInstance(response.jsonBody[@"feeds"], [NSArray class]);
}

- (void)testGetSuggestedUsers {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsers"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetTrendingTopics {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getTrendingTopics"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"topics"]);
    XCTAssertNotNil(response.jsonBody[@"suggested"]);
}

#pragma mark - Skeleton Endpoint Tests

- (void)testGetSuggestedFeedsSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedFeedsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"feeds"]);
}

- (void)testGetSuggestedUsersSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
}

- (void)testGetSuggestionsSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestionsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"suggestions"]);
}

- (void)testGetTrendsSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getTrendsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"posts"]);
    XCTAssertNotNil(response.jsonBody[@"cursor"]);
}

#pragma mark - Starter Pack Tests

- (void)testGetOnboardingSuggestedStarterPacks {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getOnboardingSuggestedStarterPacks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

- (void)testGetOnboardingSuggestedStarterPacksSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getOnboardingSuggestedStarterPacksSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

- (void)testGetSuggestedStarterPacks {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedStarterPacks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

- (void)testGetSuggestedStarterPacksSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedStarterPacksSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

#pragma mark - Search Skeleton Tests

- (void)testSearchActorsSkeletonRequiresQuery {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchActorsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testSearchActorsSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchActorsSkeleton"
                                             queryString:@"q=alice&limit=10"
                                             queryParams:@{@"q": @"alice", @"limit": @"10"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertNotNil(response.jsonBody[@"cursor"]);
}

- (void)testSearchPostsSkeletonRequiresQuery {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchPostsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testSearchPostsSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchPostsSkeleton"
                                             queryString:@"q=hello&limit=10"
                                             queryParams:@{@"q": @"hello", @"limit": @"10"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"posts"]);
    XCTAssertNotNil(response.jsonBody[@"cursor"]);
}

- (void)testSearchStarterPacksSkeletonRequiresQuery {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchStarterPacksSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testSearchStarterPacksSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchStarterPacksSkeleton"
                                             queryString:@"q=starter&limit=10"
                                             queryParams:@{@"q": @"starter", @"limit": @"10"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
    XCTAssertNotNil(response.jsonBody[@"cursor"]);
}

#pragma mark - Thread Tests

- (void)testGetPostThreadV2RequiresUri {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPostThreadV2"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testGetPostThreadV2 {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPostThreadV2"
                                             queryString:@"anchor=at%3A%2F%2Fdid%3Aplc%3Atest%2Fapp.bsky.feed.post%2Fabc123"
                                             queryParams:@{@"anchor": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                 headers:@{}];
    // V2 thread returns 404 for non-existent post (delegates to PDSFeedService)
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 404,
                  @"Expected 200 or 404, got %ld", (long)response.statusCode);
}

- (void)testGetPostThreadOtherV2RequiresUri {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPostThreadOtherV2"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetPostThreadOtherV2 {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPostThreadOtherV2"
                                             queryString:@"anchor=at%3A%2F%2Fdid%3Aplc%3Atest%2Fapp.bsky.feed.post%2Fabc123"
                                             queryParams:@{@"anchor": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                 headers:@{}];
    // V2 other thread returns empty thread (no hidden replies)
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"thread"]);
}

#pragma mark - Age Assurance Tests

- (void)testInitAgeAssuranceRequiresAssurance {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testInitAgeAssuranceWithNoVerification {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{@"assurance": @"no_verification"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"assurance"], @"no_verification");
    XCTAssertNotNil(response.jsonBody[@"verifiedAt"]);
}

- (void)testInitAgeAssuranceWithVerifiedByAdult {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{@"assurance": @"verified_by_adult"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"assurance"], @"verified_by_adult");
    XCTAssertNotNil(response.jsonBody[@"verifiedAt"]);
}

- (void)testInitAgeAssuranceWithVerifiedByMethod {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{
                                                          @"assurance": @"verified_by_method",
                                                          @"methods": @[@"id_check"]
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"assurance"], @"verified_by_method");
}

- (void)testInitAgeAssuranceInvalidValue {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{@"assurance": @"invalid_assurance"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testGetAgeAssuranceState {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getAgeAssuranceState"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"assurance"]);
    XCTAssertEqualObjects(response.jsonBody[@"assurance"], @"no_verification");
}

#pragma mark - User Discovery Tests (Onboarding & Discovery Pages)

- (void)testGetOnboardingSuggestedUsersSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getOnboardingSuggestedUsersSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedOnboardingUsers {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedOnboardingUsers"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForDiscover {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForDiscover"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForDiscoverSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForDiscoverSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForExplore {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForExplore"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForExploreSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForExploreSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForSeeMore {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForSeeMore"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForSeeMoreSkeleton {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForSeeMoreSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

@end
