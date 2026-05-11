// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/OAuth2.h"
#import "Auth/Session.h"

@interface OAuth2Tests : XCTestCase
@property (nonatomic, strong) OAuth2Server *server;
@end

@implementation OAuth2Tests

- (void)setUp {
    [super setUp];
    self.server = [[OAuth2Server alloc] init];
}

- (void)tearDown {
    self.server = nil;
    [super tearDown];
}

- (void)testAuthorizationRedirectIncludesIssuerParameter {
    self.server.issuer = @"https://pds.example.com";

    OAuth2AuthorizationRequest *request = [[OAuth2AuthorizationRequest alloc] init];
    request.clientID = @"test-client";
    request.redirectURI = @"https://client.example.com/callback";
    request.responseType = @"code";
    request.state = @"state-123";

    XCTestExpectation *expectation = [self expectationWithDescription:@"authorization redirect"];
    [self.server handleAuthorizationRequest:request
                                 completion:^(NSURL * _Nullable authorizationURL,
                                              NSString * _Nullable authorizationCode,
                                              NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertNotNil(authorizationURL);
        XCTAssertNotNil(authorizationCode);

        NSURLComponents *components = [NSURLComponents componentsWithURL:authorizationURL
                                                 resolvingAgainstBaseURL:NO];
        NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in components.queryItems) {
            if (item.name) {
                query[item.name] = item.value ?: @"";
            }
        }

        XCTAssertEqualObjects(query[@"code"], authorizationCode);
        XCTAssertEqualObjects(query[@"state"], @"state-123");
        XCTAssertEqualObjects(query[@"iss"], @"https://pds.example.com");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testAuthorizationRedirectFragmentMode {
    self.server.issuer = @"https://pds.example.com";

    OAuth2AuthorizationRequest *request = [[OAuth2AuthorizationRequest alloc] init];
    request.clientID = @"test-client";
    request.redirectURI = @"https://client.example.com/callback";
    request.responseType = @"code";
    request.state = @"state-456";
    request.responseMode = @"fragment";

    XCTestExpectation *expectation = [self expectationWithDescription:@"authorization redirect fragment"];
    [self.server handleAuthorizationRequest:request
                                 completion:^(NSURL * _Nullable authorizationURL,
                                              NSString * _Nullable authorizationCode,
                                              NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertNotNil(authorizationURL);
        XCTAssertNotNil(authorizationCode);

        NSURLComponents *components = [NSURLComponents componentsWithURL:authorizationURL
                                                 resolvingAgainstBaseURL:NO];
        // Fragment mode: response params in the fragment, not query
        XCTAssertNil(components.queryItems);
        XCTAssertNotNil(components.fragment);

        // Parse fragment as query-string params
        NSURLComponents *fragComponents = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"https://dummy?%@", components.fragment]];
        NSMutableDictionary<NSString *, NSString *> *fragParams = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in fragComponents.queryItems) {
            if (item.name) {
                fragParams[item.name] = item.value ?: @"";
            }
        }

        XCTAssertEqualObjects(fragParams[@"code"], authorizationCode);
        XCTAssertEqualObjects(fragParams[@"state"], @"state-456");
        XCTAssertEqualObjects(fragParams[@"iss"], @"https://pds.example.com");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testAuthorizationResponseParsesIssuerParameter {
    NSURL *url = [NSURL URLWithString:@"https://client.example.com/callback?code=abc123&state=state-xyz&iss=https%3A%2F%2Fpds.example.com"];
    NSError *error = nil;
    OAuth2AuthorizationResponse *response = [OAuth2AuthorizationResponse responseFromURL:url
                                                                            expectedState:@"state-xyz"
                                                                                    error:&error];
    XCTAssertNotNil(response);
    XCTAssertNil(error);
    XCTAssertEqualObjects(response.code, @"abc123");
    XCTAssertEqualObjects(response.state, @"state-xyz");
    XCTAssertEqualObjects(response.issuer, @"https://pds.example.com");
}

#ifndef GNUSTEP
- (void)testRefreshToken {
    Session *session = [[Session alloc] initWithDID:@"did:plc:test"
                                             handle:@"test.bsky.social"
                                              scope:@"atproto"];
    NSLog(@"[DEBUG] Created session: %@", session);
    NSLog(@"[DEBUG] Session ID: %@", session.sessionID);
    NSLog(@"[DEBUG] Active Sessions before: %@", self.server.activeSessions);
    self.server.activeSessions[session.sessionID] = session;
    NSLog(@"[DEBUG] Active Sessions after: %@", self.server.activeSessions);
    
    NSString *refreshToken = session.refreshToken;
    NSLog(@"[DEBUG] Refresh Token: %@", refreshToken);
    XCTAssertNotNil(refreshToken, @"Should have a refresh token");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Refresh token"];
    
    [self.server refreshAccessToken:refreshToken
                              scope:nil
                            dpopJWK:nil
                         completion:^(NSString * _Nullable accessToken, NSError * _Nullable error) {
        NSLog(@"[DEBUG] Refresh completion block called");
        XCTAssertNotNil(accessToken, @"Should return new access token");
        XCTAssertNil(error, @"Should not have error");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testRefreshTokenInvalid {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Refresh token invalid"];
    
    [self.server refreshAccessToken:@"invalid-token"
                              scope:nil
                            dpopJWK:nil
                         completion:^(NSString * _Nullable accessToken, NSError * _Nullable error) {
        XCTAssertNil(accessToken, @"Should not return access token");
        XCTAssertNotNil(error, @"Should have error");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testRefreshTokenRotation {
    Session *session = [[Session alloc] initWithDID:@"did:plc:test"
                                             handle:@"test.bsky.social"
                                              scope:@"atproto"];
    NSString *originalRefreshToken = session.refreshToken;
    XCTAssertNotNil(originalRefreshToken, @"Should have initial refresh token");
    
    self.server.activeSessions[session.sessionID] = session;
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Refresh token rotation"];
    
    [self.server refreshAccessToken:originalRefreshToken
                              scope:nil
                            dpopJWK:nil
                         completion:^(NSString * _Nullable accessToken, NSError * _Nullable error) {
        XCTAssertNotNil(accessToken, @"Should return new access token");
        XCTAssertNil(error, @"Should not have error");
        
        NSString *newRefreshToken = session.refreshToken;
        XCTAssertNotNil(newRefreshToken, @"Should have new refresh token after rotation");
        
        BOOL rotated = ![originalRefreshToken isEqualToString:newRefreshToken];
        XCTAssertTrue(rotated, @"Refresh token should be rotated (new token different from old)");
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}
#endif

@end
