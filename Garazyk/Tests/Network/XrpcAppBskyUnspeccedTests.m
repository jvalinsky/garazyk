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
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.labeler.getServices"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"views"]);
    XCTAssertIsInstance(response.jsonBody[@"views"], [NSArray class]);
}

#pragma mark - Config Tests

- (void)testGetConfig {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getConfig"
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
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getTaggedSuggestions"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"suggestions"]);
    XCTAssertIsInstance(response.jsonBody[@"suggestions"], [NSArray class]);
}

- (void)testGetPopularFeedGenerators {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPopularFeedGenerators"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"feeds"]);
    XCTAssertIsInstance(response.jsonBody[@"feeds"], [NSArray class]);
}

- (void)testGetSuggestedFeeds {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedFeeds"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"feeds"]);
    XCTAssertIsInstance(response.jsonBody[@"feeds"], [NSArray class]);
}

- (void)testGetSuggestedUsers {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsers"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetTrendingTopics {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getTrendingTopics"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"topics"]);
    XCTAssertNotNil(response.jsonBody[@"suggested"]);
}

#pragma mark - Skeleton Endpoint Tests

- (void)testGetSuggestedFeedsSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedFeedsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"feeds"]);
}

- (void)testGetSuggestedUsersSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
}

- (void)testGetSuggestionsSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestionsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"suggestions"]);
}

- (void)testGetTrendsSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getTrendsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"posts"]);
    XCTAssertNotNil(response.jsonBody[@"cursor"]);
}

#pragma mark - Starter Pack Tests

- (void)testGetOnboardingSuggestedStarterPacks {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getOnboardingSuggestedStarterPacks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

- (void)testGetOnboardingSuggestedStarterPacksSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getOnboardingSuggestedStarterPacksSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

- (void)testGetSuggestedStarterPacks {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedStarterPacks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

- (void)testGetSuggestedStarterPacksSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedStarterPacksSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
}

#pragma mark - Search Skeleton Tests

- (void)testSearchActorsSkeletonRequiresQuery {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchActorsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testSearchActorsSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchActorsSkeleton"
                                             queryString:@"q=alice&limit=10"
                                             queryParams:@{@"q": @"alice", @"limit": @"10"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertNotNil(response.jsonBody[@"cursor"]);
}

- (void)testSearchPostsSkeletonRequiresQuery {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchPostsSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testSearchPostsSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchPostsSkeleton"
                                             queryString:@"q=hello&limit=10"
                                             queryParams:@{@"q": @"hello", @"limit": @"10"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"posts"]);
    XCTAssertNotNil(response.jsonBody[@"cursor"]);
}

- (void)testSearchStarterPacksSkeletonRequiresQuery {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchStarterPacksSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testSearchStarterPacksSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.searchStarterPacksSkeleton"
                                             queryString:@"q=starter&limit=10"
                                             queryParams:@{@"q": @"starter", @"limit": @"10"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"starterPacks"]);
    XCTAssertNotNil(response.jsonBody[@"cursor"]);
}

#pragma mark - Thread Tests

- (void)testGetPostThreadV2RequiresUri {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPostThreadV2"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testGetPostThreadV2 {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPostThreadV2"
                                             queryString:@"uri=at%3A%2F%2Fdid%3Aplc%3Atest%2Fapp.bsky.feed.post%2Fabc123"
                                             queryParams:@{@"uri": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"thread"]);
}

- (void)testGetPostThreadOtherV2RequiresUri {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPostThreadOtherV2"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetPostThreadOtherV2 {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getPostThreadOtherV2"
                                             queryString:@"uri=at%3A%2F%2Fdid%3Aplc%3Atest%2Fapp.bsky.feed.post%2Fabc123"
                                             queryParams:@{@"uri": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"thread"]);
}

#pragma mark - Age Assurance Tests

- (void)testInitAgeAssuranceRequiresAssurance {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testInitAgeAssuranceWithNoVerification {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{@"assurance": @"no_verification"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"assurance"], @"no_verification");
    XCTAssertNotNil(response.jsonBody[@"verifiedAt"]);
}

- (void)testInitAgeAssuranceWithVerifiedByAdult {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{@"assurance": @"verified_by_adult"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"assurance"], @"verified_by_adult");
    XCTAssertNotNil(response.jsonBody[@"verifiedAt"]);
}

- (void)testInitAgeAssuranceWithVerifiedByMethod {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{
                                                          @"assurance": @"verified_by_method",
                                                          @"methods": @[@"id_check"]
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"assurance"], @"verified_by_method");
}

- (void)testInitAgeAssuranceInvalidValue {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.unspecced.initAgeAssurance"
                                                      body:@{@"assurance": @"invalid_assurance"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testGetAgeAssuranceState {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getAgeAssuranceState"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"assurance"]);
    XCTAssertEqualObjects(response.jsonBody[@"assurance"], @"no_verification");
}

#pragma mark - User Discovery Tests (Onboarding & Discovery Pages)

- (void)testGetOnboardingSuggestedUsersSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getOnboardingSuggestedUsersSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedOnboardingUsers {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedOnboardingUsers"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForDiscover {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForDiscover"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForDiscoverSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForDiscoverSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForExplore {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForExplore"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForExploreSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForExploreSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForSeeMore {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForSeeMore"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

- (void)testGetSuggestedUsersForSeeMoreSkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.unspecced.getSuggestedUsersForSeeMoreSkeleton"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
    XCTAssertIsInstance(response.jsonBody[@"actors"], [NSArray class]);
}

@end
