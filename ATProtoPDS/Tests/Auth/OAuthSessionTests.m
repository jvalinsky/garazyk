#import <XCTest/XCTest.h>
#import "Auth/OAuthSession.h"

@interface OAuthSessionTests : XCTestCase
@end

@implementation OAuthSessionTests

- (void)testSessionInitialization {
    NSString *sid = [[NSUUID UUID] UUIDString];
    OAuthSession *session = [OAuthSession sessionWithId:sid];
    
    XCTAssertNotNil(session);
    XCTAssertEqualObjects(session.sessionId, sid);
    XCTAssertNotNil(session.createdAt);
    XCTAssertFalse(session.authenticated);
}

- (void)testPARRequestValidationSuccess {
    OAuthPARRequest *req = [[OAuthPARRequest alloc] init];
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
    OAuthPARRequest *req = [[OAuthPARRequest alloc] init];
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
    req.scope = @"atproto";
    
    // Success
    XCTAssertTrue([req validateWithError:&error]);
}

- (void)testTokenRequestValidationAuthorizationCode {
    OAuthTokenRequest *req = [[OAuthTokenRequest alloc] init];
    req.grantType = @"authorization_code";
    req.code = @"auth-code";
    req.redirectUri = @"https://cb.com";
    req.dpopJwt = @"dpop-proof";
    
    NSError *error = nil;
    XCTAssertTrue([req validateWithError:&error]);
}

- (void)testTokenRequestValidationRefreshToken {
    OAuthTokenRequest *req = [[OAuthTokenRequest alloc] init];
    req.grantType = @"refresh_token";
    req.refreshToken = @"refresh-token";
    req.dpopJwt = @"dpop-proof";
    
    // Assuming refresh token validation doesn't require code/redirectUri
    // Let's verify implementation details in OAuthSession.m:106
    // It checks grantType first.
    // If 'authorization_code', checks code & redirectUri.
    // DPoP is checked for ALL types.
    
    NSError *error = nil;
    XCTAssertTrue([req validateWithError:&error]);
}

- (void)testTokenRequestMissingDPoP {
    OAuthTokenRequest *req = [[OAuthTokenRequest alloc] init];
    req.grantType = @"authorization_code";
    req.code = @"code";
    req.redirectUri = @"uri";
    req.dpopJwt = nil;
    
    NSError *error = nil;
    XCTAssertFalse([req validateWithError:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"Missing DPoP"]);
}

@end
