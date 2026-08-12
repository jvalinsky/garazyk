// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/OAuthSession.h"

@interface OAuthSessionTests : XCTestCase
@end

@implementation OAuthSessionTests

- (void)testSessionInitialization {
    NSString *sid = [[NSUUID UUID] UUIDString];
    ATProtoOAuthSession *session = [ATProtoOAuthSession sessionWithId:sid];
    
    XCTAssertNotNil(session);
    XCTAssertEqualObjects(session.sessionId, sid);
    XCTAssertNotNil(session.createdAt);
    XCTAssertFalse(session.authenticated);
}

- (void)testPARRequestValidationSuccess {
    ATProtoOAuthPARRequest *req = [[ATProtoOAuthPARRequest alloc] init];
    req.clientId = @"client-id";
    req.responseType = @"code";
    req.codeChallenge = @"challenge";
    req.codeChallengeMethod = @"S256";
    req.state = @"state";
    req.redirectUri = @"https://client.com/cb";
    req.scope = @"atproto";
    
    NSError *error = nil;
    XCTAssertTrue([req validateWithError:&error]);
    XCTAssertNil(error);
}

- (void)testPARRequestValidationFailures {
    ATProtoOAuthPARRequest *req = [[ATProtoOAuthPARRequest alloc] init];
    NSError *error = nil;
    
    // Missing client_id
    XCTAssertFalse([req validateWithError:&error]);
    XCTAssertNotNil(error);
    req.clientId = @"client-id";
    
    // Invalid response_type
    req.responseType = @"token";
    XCTAssertFalse([req validateWithError:&error]);
    req.responseType = @"code";
    
    // Missing challenge
    XCTAssertFalse([req validateWithError:&error]);
    req.codeChallenge = @"challenge";
    
    // Invalid method
    req.codeChallengeMethod = @"plain";
    XCTAssertFalse([req validateWithError:&error]);
    req.codeChallengeMethod = @"S256";
    
    // Missing state
    XCTAssertFalse([req validateWithError:&error]);
    req.state = @"state";
    
    // Missing redirect
    XCTAssertFalse([req validateWithError:&error]);
    req.redirectUri = @"https://cb.com";
    
    // Invalid scope
    req.scope = @"email";
    XCTAssertFalse([req validateWithError:&error]);
    req.scope = @"notatproto";
    XCTAssertFalse([req validateWithError:&error]);
    req.scope = @"atproto space:not-a-valid-nsid?authority=not-a-did";
    XCTAssertFalse([req validateWithError:&error]);
    req.scope = @"atproto";
    
    // Success
    XCTAssertTrue([req validateWithError:&error]);
}

- (void)testPARRequestValidationAcceptsStandardPermissionScopes {
    ATProtoOAuthPARRequest *req = [[ATProtoOAuthPARRequest alloc] init];
    req.clientId = @"client-id";
    req.responseType = @"code";
    req.codeChallenge = @"challenge";
    req.codeChallengeMethod = @"S256";
    req.state = @"state";
    req.redirectUri = @"https://client.com/cb";
    req.scope = @"atproto repo:app.bsky.feed.post?action=create blob:image/png account:email identity:handle";

    NSError *error = nil;
    XCTAssertTrue([req validateWithError:&error]);
    XCTAssertNil(error);
}

- (void)testPARRequestValidationRejectsUnknownOrMalformedPermissionScopes {
    ATProtoOAuthPARRequest *req = [[ATProtoOAuthPARRequest alloc] init];
    req.clientId = @"client-id";
    req.responseType = @"code";
    req.codeChallenge = @"challenge";
    req.codeChallengeMethod = @"S256";
    req.state = @"state";
    req.redirectUri = @"https://client.com/cb";

    req.scope = @"atproto unknown:permission";
    XCTAssertFalse([req validateWithError:nil]);
    req.scope = @"atproto repo:?action=create";
    XCTAssertFalse([req validateWithError:nil]);
    req.scope = @"atproto include:app.example.permissions";
    XCTAssertTrue([req validateWithError:nil]);
}

- (void)testTokenRequestValidationAuthorizationCode {
    ATProtoOAuthTokenRequest *req = [[ATProtoOAuthTokenRequest alloc] init];
    req.grantType = @"authorization_code";
    req.code = @"auth-code";
    req.redirectUri = @"https://cb.com";
    req.codeVerifier = @"verifier";
    req.dpopJwt = @"dpop-proof";
    
    NSError *error = nil;
    XCTAssertTrue([req validateWithError:&error]);
}

- (void)testTokenRequestValidationRefreshToken {
    ATProtoOAuthTokenRequest *req = [[ATProtoOAuthTokenRequest alloc] init];
    req.grantType = @"refresh_token";
    req.refreshToken = @"refresh-token";
    req.dpopJwt = @"dpop-proof";
    
    // Assuming refresh token validation doesn't require code/redirectUri
    // Let's verify implementation details in ATProtoOAuthSession.m:106
    // It primarily checks grantType.
    // If 'authorization_code', checks code & redirectUri.
    // DPoP is checked for ALL types.
    
    NSError *error = nil;
    XCTAssertTrue([req validateWithError:&error]);
}

- (void)testTokenRequestMissingDPoP {
    ATProtoOAuthTokenRequest *req = [[ATProtoOAuthTokenRequest alloc] init];
    req.grantType = @"authorization_code";
    req.code = @"code";
    req.redirectUri = @"uri";
    req.codeVerifier = @"verifier";
    req.dpopJwt = nil;
    
    NSError *error = nil;
    XCTAssertFalse([req validateWithError:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"Missing DPoP"]);
}

@end
