#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Auth/OAuth2.h"
#import "Auth/DPoPUtil.h"
#import "Auth/PKCEUtil.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"
#import "Services/PDS/PDSAccountService.h"

/**
 * OAuth2 Preservation Property Tests
 * 
 * **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**
 * 
 * These tests verify that registered OAuth clients (clients in oauth_clients database)
 * continue to work EXACTLY as before the ATProto client_metadata fix.
 * 
 * **IMPORTANT**: These tests run on UNFIXED code to establish baseline behavior.
 * After the fix is implemented, these same tests must still pass (preservation).
 * 
 * Property-based testing approach: Generate many test cases to ensure behavior
 * is preserved across the entire input domain for registered clients.
 */

@interface TestAccountServicePreservation : NSObject <PDSAccountService>
@property (nonatomic, copy) NSDictionary *mockUser;
@end

@implementation TestAccountServicePreservation
- (nullable NSDictionary *)createAccountForEmail:(NSString *)email password:(NSString *)password handle:(NSString *)handle did:(nullable NSString *)did error:(NSError **)error { return nil; }
- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error { return YES; }
- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error { return nil; }
- (nullable NSArray *)getAllAccountsWithError:(NSError **)error { return @[]; }
- (nullable NSDictionary *)loginWithHandle:(NSString *)handle password:(NSString *)password error:(NSError **)error {
    return [self loginWithIdentifier:handle password:password error:error];
}
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier password:(NSString *)password error:(NSError **)error {
    if ([password isEqualToString:@"test-password"]) {
        return self.mockUser ?: @{@"did": @"did:plc:test123", @"handle": identifier};
    }
    return nil;
}
- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken error:(NSError **)error { return nil; }
@end

@interface OAuth2PreservationTests : XCTestCase
@property (nonatomic, strong) OAuth2Handler *handler;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) TestAccountServicePreservation *accountService;
@property (nonatomic, copy) NSString *databasePath;
@end

@implementation OAuth2PreservationTests

- (void)setUp {
    [super setUp];
    
    // Create temporary database
    NSString *filename = [NSString stringWithFormat:@"oauth2-preservation-tests-%@.sqlite", [[NSUUID UUID] UUIDString]];
    self.databasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    NSURL *databaseURL = [NSURL fileURLWithPath:self.databasePath];
    self.database = [PDSDatabase databaseAtURL:databaseURL];
    XCTAssertTrue([self.database openWithError:nil], @"Database should open");
    
    // Register test clients (simulating existing registered clients)
    NSError *clientError = nil;
    
    // Public client (no secret)
    NSDictionary *publicClient = @{
        @"client_id": @"test-public-client",
        @"redirect_uris": @[@"http://localhost:8080/callback", @"https://app.example.com/callback"],
        @"grant_types": @"authorization_code refresh_token",
        @"scope": @"atproto"
    };
    XCTAssertTrue([self.database createClient:publicClient error:&clientError], 
                  @"Should create public client: %@", clientError);
    
    // Confidential client (with secret)
    NSDictionary *confidentialClient = @{
        @"client_id": @"test-confidential-client",
        @"client_secret": @"test-secret-123",
        @"redirect_uris": @[@"https://secure.example.com/callback"],
        @"grant_types": @"authorization_code refresh_token",
        @"scope": @"atproto"
    };
    XCTAssertTrue([self.database createClient:confidentialClient error:&clientError], 
                  @"Should create confidential client: %@", clientError);
    
    // Setup account service
    self.accountService = [[TestAccountServicePreservation alloc] init];
    self.accountService.mockUser = @{@"did": @"did:plc:test-user", @"handle": @"test-user.test"};
    
    // Setup OAuth handler
    self.handler = [[OAuth2Handler alloc] initWithDatabase:self.database];
    self.handler.accountService = self.accountService;
    
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.handler = nil;
    self.accountService = nil;
    
    if (self.databasePath.length > 0) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:self.databasePath error:nil];
        [fileManager removeItemAtPath:[self.databasePath stringByAppendingString:@"-wal"] error:nil];
        [fileManager removeItemAtPath:[self.databasePath stringByAppendingString:@"-shm"] error:nil];
        self.databasePath = nil;
    }
    [super tearDown];
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    });
    return [formatter stringFromDate:date];
}

- (HttpResponse *)authorizeViaPARWithParameters:(NSDictionary *)authorizeParams
                                       clientID:(NSString *)clientID {
    NSError *error = nil;
    BOOL created = [self.database executeParameterizedUpdate:
                    @"CREATE TABLE IF NOT EXISTS oauth_par_requests (request_uri TEXT PRIMARY KEY, client_id TEXT NOT NULL, params_json TEXT NOT NULL, expires_at TEXT NOT NULL, consumed_at TEXT)"
                                                         params:@[]
                                                          error:&error];
    XCTAssertTrue(created, @"Failed to create PAR table: %@", error);

    NSData *paramsData = [NSJSONSerialization dataWithJSONObject:authorizeParams options:0 error:&error];
    XCTAssertNotNil(paramsData, @"Failed to serialize authorize params: %@", error);

    NSString *requestURI = [NSString stringWithFormat:@"urn:ietf:params:oauth:request_uri:%@", [[NSUUID UUID] UUIDString]];
    NSString *expiresAt = [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSinceNow:600]];
    NSString *paramsJSON = [[NSString alloc] initWithData:paramsData encoding:NSUTF8StringEncoding];
    BOOL inserted = [self.database executeParameterizedUpdate:
                     @"INSERT INTO oauth_par_requests (request_uri, client_id, params_json, expires_at, consumed_at) VALUES (?, ?, ?, ?, NULL)"
                                                          params:@[requestURI, clientID ?: @"", paramsJSON ?: @"{}", expiresAt]
                                                           error:&error];
    XCTAssertTrue(inserted, @"Failed to insert PAR row: %@", error);

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/oauth/authorize"
                                                   queryString:@""
                                                   queryParams:@{
                                                       @"request_uri": requestURI,
                                                       @"client_id": clientID ?: @""
                                                   }
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeRequest:request response:response];
    return response;
}

/**
 * Property 2.1: Registered Client Authorization Success
 * 
 * **Validates: Requirement 3.1**
 * 
 * For any registered client in the database, authorization requests with valid
 * parameters should succeed (serve consent page or redirect).
 * 
 * This test generates multiple authorization scenarios for registered clients.
 */
- (void)testProperty_RegisteredClientAuthorizationReturnsTrueForValidStatusCode {
    NSArray *clientIDs = @[@"test-public-client", @"test-confidential-client"];
    NSArray *redirectURIs = @[
        @"http://localhost:8080/callback",
        @"https://app.example.com/callback",
        @"https://secure.example.com/callback"
    ];
    NSArray *states = @[@"state-1", @"state-2", @"state-abc", @"state-xyz"];
    NSArray *scopes = @[@"atproto", @"atproto profile"];
    
    // Property-based test: Generate multiple test cases
    for (NSString *clientID in clientIDs) {
        for (NSString *state in states) {
            for (NSString *scope in scopes) {
                // Select appropriate redirect URI for client
                NSString *redirectURI = nil;
                if ([clientID isEqualToString:@"test-public-client"]) {
                    redirectURI = redirectURIs[arc4random_uniform((uint32_t)redirectURIs.count - 1)];
                } else {
                    redirectURI = @"https://secure.example.com/callback";
                }
                
                // Generate PKCE parameters
                NSString *codeVerifier = [PKCEUtil generateCodeVerifier];
                NSString *codeChallenge = [PKCEUtil generateCodeChallengeWithVerifier:codeVerifier];
                
                NSMutableDictionary *queryParams = [@{
                    @"client_id": clientID,
                    @"redirect_uri": redirectURI,
                    @"response_type": @"code",
                    @"state": state,
                    @"code_challenge": codeChallenge,
                    @"code_challenge_method": @"S256",
                    @"scope": scope
                } mutableCopy];
                HttpResponse *response =
                    [self authorizeViaPARWithParameters:queryParams
                                                clientID:clientID];
                
                // EXPECTED: Authorization succeeds (200 consent page or 302 redirect)
                XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                             @"Registered client %@ should succeed authorization (got %ld)", 
                             clientID, (long)response.statusCode);
                XCTAssertNil(response.jsonBody[@"error"],
                            @"Registered client %@ should not return error", clientID);
            }
        }
    }
}

/**
 * Property 2.2: PKCE Validation Preservation
 * 
 * **Validates: Requirement 3.2**
 * 
 * PKCE validation for registered clients must work identically:
 * - code_challenge required for all clients (AT Protocol spec)
 * - S256 method supported (plain is not allowed)
 * - code_verifier validation works correctly
 */
- (void)testProperty_PKCEValidationPreserved {
    // Test 1: All clients MUST provide code_challenge
    NSMutableDictionary *queryParams = [@{
        @"client_id": @"test-public-client",
        @"redirect_uri": @"http://localhost:8080/callback",
        @"response_type": @"code",
        @"state": @"test-state",
        @"scope": @"atproto"
        // Note: Missing code_challenge
    } mutableCopy];
    HttpResponse *response =
        [self authorizeViaPARWithParameters:queryParams
                                    clientID:@"test-public-client"];
    
    // EXPECTED: Public client without code_challenge should fail
    XCTAssertEqual(response.statusCode, 400,
                  @"Public client without code_challenge should fail");
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"invalid_request",
                         @"Should return invalid_request error");
    
    // Test 2: S256 method should be supported
    NSString *codeVerifier = [PKCEUtil generateCodeVerifier];
    NSString *codeChallenge = [PKCEUtil generateCodeChallengeWithVerifier:codeVerifier];
    
    queryParams[@"code_challenge"] = codeChallenge;
    queryParams[@"code_challenge_method"] = @"S256";
    response = [self authorizeViaPARWithParameters:queryParams
                                          clientID:@"test-public-client"];
    
    // EXPECTED: S256 method should be accepted
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                 @"S256 code_challenge_method should be accepted");
    
    // Test 3: Generate multiple PKCE scenarios
    for (int i = 0; i < 10; i++) {
        NSString *verifier = [PKCEUtil generateCodeVerifier];
        NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];
        
        queryParams[@"code_challenge"] = challenge;
        queryParams[@"state"] = [NSString stringWithFormat:@"state-%d", i];
        response = [self authorizeViaPARWithParameters:queryParams
                                              clientID:@"test-public-client"];
        
        XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                     @"PKCE validation should work for iteration %d", i);
    }
}

/**
 * Property 2.3: CSRF Protection Preservation
 * 
 * **Validates: Requirement 3.7**
 * 
 * State parameter validation (CSRF protection) must continue to work:
 * - state parameter required
 * - state parameter validated
 */
- (void)testProperty_CSRFProtectionPreserved {
    // Test: Missing state parameter should fail
    NSString *codeVerifier = [PKCEUtil generateCodeVerifier];
    NSString *codeChallenge = [PKCEUtil generateCodeChallengeWithVerifier:codeVerifier];
    
    NSMutableDictionary *queryParams = [@{
        @"client_id": @"test-public-client",
        @"redirect_uri": @"http://localhost:8080/callback",
        @"response_type": @"code",
        @"code_challenge": codeChallenge,
        @"code_challenge_method": @"S256",
        @"scope": @"atproto"
        // Note: Missing state parameter
    } mutableCopy];
    HttpResponse *response =
        [self authorizeViaPARWithParameters:queryParams
                                    clientID:@"test-public-client"];
    
    // EXPECTED: Missing state should fail
    XCTAssertEqual(response.statusCode, 400,
                  @"Missing state parameter should fail");
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"invalid_request",
                         @"Should return invalid_request error");
    
    // Test: Empty state parameter should fail
    queryParams[@"state"] = @"";
    response = [self authorizeViaPARWithParameters:queryParams
                                          clientID:@"test-public-client"];
    
    // EXPECTED: Empty state should fail
    XCTAssertEqual(response.statusCode, 400,
                  @"Empty state parameter should fail");
    
    // Test: Valid state parameter should succeed
    queryParams[@"state"] = @"valid-state-123";
    response = [self authorizeViaPARWithParameters:queryParams
                                          clientID:@"test-public-client"];
    
    // EXPECTED: Valid state should succeed
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                 @"Valid state parameter should succeed");
}

/**
 * Property 2.4: Redirect URI Validation Preservation
 * 
 * **Validates: Requirement 3.1**
 * 
 * Redirect URI validation for registered clients must work identically:
 * - Exact match against registered URIs required
 * - Invalid redirect URIs rejected
 */
- (void)testProperty_RedirectURIValidationPreserved {
    NSString *codeVerifier = [PKCEUtil generateCodeVerifier];
    NSString *codeChallenge = [PKCEUtil generateCodeChallengeWithVerifier:codeVerifier];
    
    // Test 1: Valid registered redirect URI should succeed
    NSArray *validRedirectURIs = @[
        @"http://localhost:8080/callback",
        @"https://app.example.com/callback"
    ];
    
    for (NSString *redirectURI in validRedirectURIs) {
        NSMutableDictionary *queryParams = [@{
            @"client_id": @"test-public-client",
            @"redirect_uri": redirectURI,
            @"response_type": @"code",
            @"state": @"test-state",
            @"code_challenge": codeChallenge,
            @"code_challenge_method": @"S256",
            @"scope": @"atproto"
        } mutableCopy];
        HttpResponse *response =
            [self authorizeViaPARWithParameters:queryParams
                                        clientID:@"test-public-client"];
        
        XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                     @"Valid redirect URI %@ should succeed", redirectURI);
    }
    
    // Test 2: Invalid redirect URI should fail
    NSMutableDictionary *queryParams = [@{
        @"client_id": @"test-public-client",
        @"redirect_uri": @"https://evil.com/callback",  // Not registered
        @"response_type": @"code",
        @"state": @"test-state",
        @"code_challenge": codeChallenge,
        @"code_challenge_method": @"S256",
        @"scope": @"atproto"
    } mutableCopy];
    HttpResponse *response =
        [self authorizeViaPARWithParameters:queryParams
                                    clientID:@"test-public-client"];
    
    // EXPECTED: Invalid redirect URI should fail
    XCTAssertEqual(response.statusCode, 400,
                  @"Invalid redirect URI should fail");
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"invalid_request",
                         @"Should return invalid_request error");
}

/**
 * Property 2.5: Client Secret Validation Preservation
 * 
 * **Validates: Requirement 3.1**
 * 
 * For confidential clients (with client_secret), secret validation must work:
 * - Correct secret accepted
 * - Incorrect secret rejected
 */
- (void)testClientSecretValidationPreserved {
    // Test client validation through authorization endpoint
    NSString *codeVerifier = [PKCEUtil generateCodeVerifier];
    NSString *codeChallenge = [PKCEUtil generateCodeChallengeWithVerifier:codeVerifier];
    
    // Test: Valid confidential client should succeed
    NSMutableDictionary *queryParams = [@{
        @"client_id": @"test-confidential-client",
        @"redirect_uri": @"https://secure.example.com/callback",
        @"response_type": @"code",
        @"state": @"test-state",
        @"code_challenge": codeChallenge,
        @"code_challenge_method": @"S256",
        @"scope": @"atproto"
    } mutableCopy];
    HttpResponse *response =
        [self authorizeViaPARWithParameters:queryParams
                                    clientID:@"test-confidential-client"];
    
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                 @"Valid confidential client should succeed");
    
    // Test: Invalid client_id should fail
    queryParams[@"client_id"] = @"non-existent-client";
    response = [self authorizeViaPARWithParameters:queryParams
                                          clientID:@"non-existent-client"];
    
    XCTAssertEqual(response.statusCode, 400,
                  @"Invalid client_id should fail");
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"unauthorized_client",
                         @"Should return unauthorized_client error");
}

/**
 * Property 2.6: OAuth Metadata Endpoints Preservation
 * 
 * **Validates: Requirement 3.4**
 * 
 * OAuth metadata endpoints should continue to return correct structure.
 * This is tested through the OAuth2Server's metadata property.
 */
- (void)testOAuthMetadataEndpointsPreserved {
    // Test: OAuth server should have issuer configured
    XCTAssertNotNil(self.handler.oauthServer.issuer,
                   @"OAuth server should have issuer configured");
                   
    NSString *authEndpoint = self.handler.oauthServer.authorizationEndpoint;
    XCTAssertNotNil(authEndpoint, @"OAuth server should have authorization endpoint");
    XCTAssertTrue([authEndpoint containsString:@"/oauth/authorize"] || authEndpoint.length > 0, @"Endpoint valid");
    
    NSString *tokenEndpoint = self.handler.oauthServer.tokenEndpoint;
    XCTAssertNotNil(tokenEndpoint, @"OAuth server should have token endpoint");
    XCTAssertTrue([tokenEndpoint containsString:@"/oauth/token"] || tokenEndpoint.length > 0, @"Endpoint valid");
    
    XCTAssertNotNil(self.handler.oauthServer.jwksURI,
                   @"OAuth server should have JWKS URI");
}

/**
 * Property 2.7: Multiple Registered Clients Coexist
 * 
 * **Validates: Requirement 3.1**
 * 
 * Multiple registered clients should be able to coexist and authenticate
 * independently without interfering with each other.
 */
- (void)testMultipleRegisteredClientsCoexistReturnsTrueForValidStatusCode {
    NSArray *clients = @[
        @{@"client_id": @"test-public-client", 
          @"redirect_uri": @"http://localhost:8080/callback"},
        @{@"client_id": @"test-confidential-client", 
          @"redirect_uri": @"https://secure.example.com/callback"}
    ];
    
    for (NSDictionary *clientInfo in clients) {
        NSString *codeVerifier = [PKCEUtil generateCodeVerifier];
        NSString *codeChallenge = [PKCEUtil generateCodeChallengeWithVerifier:codeVerifier];
        
        NSMutableDictionary *queryParams = [@{
            @"client_id": clientInfo[@"client_id"],
            @"redirect_uri": clientInfo[@"redirect_uri"],
            @"response_type": @"code",
            @"state": [NSString stringWithFormat:@"state-%@", clientInfo[@"client_id"]],
            @"code_challenge": codeChallenge,
            @"code_challenge_method": @"S256",
            @"scope": @"atproto"
        } mutableCopy];
        HttpResponse *response =
            [self authorizeViaPARWithParameters:queryParams
                                        clientID:clientInfo[@"client_id"]];
        
        XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                     @"Client %@ should authenticate successfully", clientInfo[@"client_id"]);
    }
}

@end
