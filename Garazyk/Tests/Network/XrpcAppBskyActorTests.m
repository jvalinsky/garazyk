// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyActorTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyActorTests

#pragma mark - getPreferences Tests (PDS-level)

- (void)testGetPreferencesRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.getPreferences"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetPreferencesSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.getPreferences"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"preferences"]);
}

- (void)testGetPreferencesBypassesProxyInterceptor {
    self.dispatcher.requestInterceptor = ^BOOL(HttpRequest *request, HttpResponse *response, NSString *methodId, BOOL hasLocalHandler) {
        response.statusCode = 502;
        [response setJsonBody:@{@"error": @"UnexpectedProxy", @"message": methodId ?: @""}];
        return YES;
    };

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.getPreferences"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"preferences"]);
}

#pragma mark - putPreferences Tests (PDS-level)

- (void)testPutPreferencesRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.actor.putPreferences"
                                                      body:@{@"preferences": @[]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutPreferencesRequiresValidBody {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.actor.putPreferences"
                                                      body:@{@"preferences": @"not-an-array"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testPutPreferencesSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.actor.putPreferences"
                                                      body:@{@"preferences": @[@{@"$type": @"app.bsky.actor.defs#feedViewPref", @"feed": @"timeline"}]}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - getProfile Tests

- (void)testGetProfileSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.getProfile"
                                             queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                             queryParams:@{@"actor": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"did"], self.userDid);
}

#pragma mark - getProfiles Tests

- (void)testGetProfilesSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.getProfiles"
                                             queryString:[NSString stringWithFormat:@"actors=%@", self.userDid]
                                             queryParams:@{@"actors": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSArray *profiles = response.jsonBody[@"profiles"];
    XCTAssertTrue([profiles isKindOfClass:[NSArray class]]);
    XCTAssertEqual(profiles.count, 1U);
}

#pragma mark - searchActors Tests

- (void)testSearchActorsSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.searchActors"
                                             queryString:@"q=test"
                                             queryParams:@{@"q": @"test"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
}

#pragma mark - searchActorsTypeahead Tests (local AppView)

- (void)testSearchActorsTypeaheadRequiresQuery {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.searchActorsTypeahead"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testSearchActorsTypeaheadSuccess {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.searchActorsTypeahead"
                                             queryString:@"q=test"
                                             queryParams:@{@"q": @"test"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
}

#pragma mark - getSuggestions Tests

- (void)testGetSuggestionsSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.actor.getSuggestions"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"actors"]);
}

@end
