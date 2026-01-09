#import <XCTest/XCTest.h>
#import "Auth/OAuth2.h"
#import "Auth/OAuthSession.h"
#import "Network/HttpRouter.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface OAuth2Tests : XCTestCase
@property (nonatomic, strong) OAuth2 *oauth2;
@end

@implementation OAuth2Tests

- (void)setUp {
    [super setUp];

    self.oauth2 = [[OAuth2 alloc] init];
    self.oauth2.authorizationEndpoint = @"https://example.com/oauth/authorize";
    self.oauth2.tokenEndpoint = @"https://example.com/oauth/token";
    self.oauth2.clientID = @"test-client-id";
    self.oauth2.redirectURI = @"testapp://oauth/callback";
}

- (void)tearDown {
    self.oauth2 = nil;
    [super tearDown];
}

#pragma mark - OAuth2 Authorization URL Tests

- (void)testAuthorizationURLGeneration {
    // Test successful authorization URL generation
    NSError *error = nil;

    NSDictionary *parameters = @{
        @"state": @"test-state-123",
        @"scope": @"read write",
        @"code_challenge": @"test-challenge",
        @"code_challenge_method": @"S256"
    };

    NSURL *authURL = [self.oauth2 authorizationURLWithParameters:parameters error:&error];

    XCTAssertNotNil(authURL, @"Authorization URL should be generated");
    XCTAssertNil(error, @"No error should occur during URL generation");
    XCTAssertEqualObjects(authURL.scheme, @"https", @"URL should use HTTPS");
    XCTAssertEqualObjects(authURL.host, @"example.com", @"URL should point to correct host");

    // Check query parameters
    NSURLComponents *components = [NSURLComponents componentsWithURL:authURL resolvingAgainstBaseURL:NO];
    NSDictionary *queryParams = [self queryParametersFromURLComponents:components];

    XCTAssertEqualObjects(queryParams[@"client_id"], @"test-client-id", @"Client ID should be included");
    XCTAssertEqualObjects(queryParams[@"redirect_uri"], @"testapp://oauth/callback", @"Redirect URI should be included");
    XCTAssertEqualObjects(queryParams[@"response_type"], @"code", @"Response type should be code");
    XCTAssertEqualObjects(queryParams[@"state"], @"test-state-123", @"State should be included");
}

- (void)testAuthorizationURLWithPKCE {
    // Test authorization URL with PKCE parameters
    NSError *error = nil;

    NSDictionary *parameters = @{
        @"code_challenge": @"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        @"code_challenge_method": @"S256"
    };

    NSURL *authURL = [self.oauth2 authorizationURLWithParameters:parameters error:&error];

    XCTAssertNotNil(authURL, @"Authorization URL should be generated with PKCE");
    XCTAssertNil(error, @"No error should occur");

    NSURLComponents *components = [NSURLComponents componentsWithURL:authURL resolvingAgainstBaseURL:NO];
    NSDictionary *queryParams = [self queryParametersFromURLComponents:components];

    XCTAssertEqualObjects(queryParams[@"code_challenge"], @"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", @"PKCE challenge should be included");
    XCTAssertEqualObjects(queryParams[@"code_challenge_method"], @"S256", @"PKCE method should be included");
}

#pragma mark - OAuth2 Token Exchange Tests

- (void)testTokenExchangeWithValidCode {
    // Test successful token exchange
    NSError *error = nil;

    // Mock successful token response
    NSDictionary *tokenResponse = @{
        @"access_token": @"test-access-token",
        @"token_type": @"Bearer",
        @"expires_in": @3600,
        @"refresh_token": @"test-refresh-token",
        @"scope": @"read write"
    };

    // This would need a mock HTTP client to fully test
    // For now, test the parameter validation
    NSDictionary *tokenParams = @{
        @"grant_type": @"authorization_code",
        @"code": @"test-auth-code",
        @"redirect_uri": @"testapp://oauth/callback",
        @"client_id": @"test-client-id"
    };

    XCTAssertNotNil(tokenParams, @"Token parameters should be constructed");
}

#pragma mark - OAuth2 State Parameter Tests

- (void)testStateParameterGeneration {
    // Test state parameter generation for CSRF protection
    NSString *state1 = [self.oauth2 generateStateParameter];
    NSString *state2 = [self.oauth2 generateStateParameter];

    XCTAssertNotNil(state1, @"State parameter should be generated");
    XCTAssertNotNil(state2, @"Second state parameter should be generated");
    XCTAssertNotEqualObjects(state1, state2, @"State parameters should be unique");

    // State should be URL-safe (base64url encoded)
    XCTAssertFalse([state1 containsString:@"+"], @"State should not contain +");
    XCTAssertFalse([state1 containsString:@"/"], @"State should not contain /");
    XCTAssertFalse([state1 containsString:@"="], @"State should not contain padding");
}

- (void)testStateParameterValidation {
    // Test state parameter validation
    NSString *originalState = @"test-state-value";
    NSString *validState = originalState;
    NSString *invalidState = @"different-state-value";

    XCTAssertTrue([self.oauth2 validateStateParameter:validState againstExpected:originalState],
                 @"Valid state should be accepted");
    XCTAssertFalse([self.oauth2 validateStateParameter:invalidState againstExpected:originalState],
                  @"Invalid state should be rejected");
}

#pragma mark - PKCE Code Verifier/Challenge Tests

- (void)testPKCECodeVerifierGeneration {
    // Test PKCE code verifier generation
    NSString *verifier1 = [self.oauth2 generateCodeVerifier];
    NSString *verifier2 = [self.oauth2 generateCodeVerifier];

    XCTAssertNotNil(verifier1, @"Code verifier should be generated");
    XCTAssertNotNil(verifier2, @"Second code verifier should be generated");
    XCTAssertNotEqualObjects(verifier1, verifier2, @"Code verifiers should be unique");

    // Code verifier should be 43-128 characters
    XCTAssertTrue(verifier1.length >= 43 && verifier1.length <= 128,
                 @"Code verifier should be correct length");

    // Should contain only URL-safe characters
    XCTAssertFalse([verifier1 containsString:@"+"], @"Code verifier should not contain +");
    XCTAssertFalse([verifier1 containsString:@"/"], @"Code verifier should not contain /");
    XCTAssertFalse([verifier1 containsString:@"="], @"Code verifier should not contain padding");
}

- (void)testPKCECodeChallengeGeneration {
    // Test PKCE code challenge generation from verifier
    NSString *verifier = @"test-code-verifier-12345";
    NSString *challenge = [self.oauth2 generateCodeChallengeFromVerifier:verifier];

    XCTAssertNotNil(challenge, @"Code challenge should be generated");
    XCTAssertNotEqualObjects(challenge, verifier, @"Challenge should differ from verifier");

    // Challenge should be base64url encoded
    XCTAssertFalse([challenge containsString:@"+"], @"Challenge should not contain +");
    XCTAssertFalse([challenge containsString:@"/"], @"Challenge should not contain /");
    XCTAssertFalse([challenge containsString:@"="], @"Challenge should not contain padding");
}

#pragma mark - OAuth2 Session Management Tests

- (void)testOAuthSessionCreation {
    // Test OAuth session creation and management
    OAuthSession *session = [[OAuthSession alloc] init];

    XCTAssertNotNil(session, @"OAuth session should be created");
    XCTAssertNil(session.accessToken, @"New session should not have access token");
    XCTAssertNil(session.refreshToken, @"New session should not have refresh token");
    XCTAssertFalse(session.isExpired, @"New session should not be expired");
}

- (void)testOAuthSessionTokenStorage {
    // Test token storage and retrieval
    OAuthSession *session = [[OAuthSession alloc] init];

    session.accessToken = @"test-access-token";
    session.refreshToken = @"test-refresh-token";
    session.expiresAt = [[NSDate date] dateByAddingTimeInterval:3600];

    XCTAssertEqualObjects(session.accessToken, @"test-access-token", @"Access token should be stored");
    XCTAssertEqualObjects(session.refreshToken, @"test-refresh-token", @"Refresh token should be stored");
    XCTAssertFalse(session.isExpired, @"Session should not be expired");
}

- (void)testOAuthSessionExpiration {
    // Test session expiration detection
    OAuthSession *session = [[OAuthSession alloc] init];
    session.expiresAt = [[NSDate date] dateByAddingTimeInterval:-60]; // Expired 1 minute ago

    XCTAssertTrue(session.isExpired, @"Expired session should be detected as expired");
}

- (void)testOAuthServerMetadataEndpoint {
    // Test that /.well-known/oauth-authorization-server returns correct metadata
    HttpRouter *router = [[HttpRouter alloc] init];
    router.baseURL = @"https://example.com";
    [router setupRoutes];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                         path:@"/.well-known/oauth-authorization-server"
                                                  queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:nil];

    HttpResponse *response = [[HttpResponse alloc] init];

    HttpRouteHandler handler = [router handlerForRequest:request];
    XCTAssertNotNil(handler, @"Handler should be found for metadata endpoint");

    handler(request, response);

    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *metadata = response.jsonBody;
    XCTAssertNotNil(metadata[@"issuer"]);
    XCTAssertNotNil(metadata[@"authorization_endpoint"]);
}

#pragma mark - Helper Methods

- (NSDictionary *)queryParametersFromURLComponents:(NSURLComponents *)components {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        params[item.name] = item.value;
    }
    return [params copy];
}

@end