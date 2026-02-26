#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuth2Handler.h"
#import "Database/PDSDatabase.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import <CommonCrypto/CommonDigest.h>
#import <XCTest/XCTest.h>

/*!
 @class ATProtoOAuthClientMetadataTests

 @abstract Bug condition exploration test for ATProto OAuth client_metadata
 support.

 @discussion This test verifies that ATProto clients (bsky.app, witchsky.app,
 native apps) can authenticate using the client_metadata parameter without
 database pre-registration, as required by the ATProto OAuth specification.

 CRITICAL: This test MUST FAIL on unfixed code because:
 - validateClient only checks database and returns nil for bsky.app/witchsky.app
 - validateRedirectURI rejects HTTP loopback redirects
 - No client_metadata parameter extraction exists

 The test failure confirms the bug exists. After implementing the fix, this test
 will pass.

 **Validates: Requirements 2.1, 2.2, 2.3, 2.4**
 */
@interface ATProtoOAuthClientMetadataTests : XCTestCase
@property(nonatomic, strong) OAuth2Handler *handler;
@property(nonatomic, strong) PDSDatabase *database;
@end

@implementation ATProtoOAuthClientMetadataTests

- (void)setUp {
  [super setUp];

  // Setup in-memory DB and handler
  NSString *dbPath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
  [self.database openWithError:nil];

  NSError *error = nil;
  BOOL success = [self.database
      executeRawSQL:
          @"CREATE TABLE IF NOT EXISTS clients (client_id TEXT PRIMARY KEY, "
          @"client_secret TEXT, redirect_uris TEXT, grant_types TEXT, "
          @"response_types TEXT, scope TEXT, application_type TEXT)"
              error:&error];
  XCTAssertTrue(success, @"Failed to create clients table: %@", error);

  success = [self.database
      executeRawSQL:
          @"CREATE TABLE IF NOT EXISTS accounts (did TEXT PRIMARY KEY, handle "
          @"TEXT, password_hash TEXT, email TEXT, phone TEXT)"
              error:&error];
  XCTAssertTrue(success, @"Failed to create accounts table: %@", error);

  success = [self.database
      executeRawSQL:
          @"CREATE TABLE IF NOT EXISTS oauth_par_requests (request_uri TEXT "
          @"PRIMARY KEY, client_id TEXT NOT NULL, params_json TEXT NOT NULL, "
          @"expires_at TEXT NOT NULL, consumed_at TEXT)"
              error:&error];
  XCTAssertTrue(success, @"Failed to create par requests table: %@", error);

  self.handler = [[OAuth2Handler alloc] initWithDatabase:self.database];

  // Seed a test user
  PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
  account.did = @"did:plc:testuser";
  account.handle = @"testuser.test";
  account.createdAt = [[NSDate date] timeIntervalSince1970];
  account.updatedAt = [[NSDate date] timeIntervalSince1970];
  success = [self.database createAccount:account error:&error];
  XCTAssertTrue(success, @"Failed to seed user: %@", error);

  // NOTE: We deliberately DO NOT register bsky.app or witchsky.app in the
  // database This is the bug condition - ATProto clients should work via
  // client_metadata
}

- (void)tearDown {
  [super tearDown];
}

// Helper to generate PKCE code challenge
- (NSString *)generateCodeChallenge:(NSString *)verifier {
  NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, hash);
  NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
  NSString *base64Hash = [hashData base64EncodedStringWithOptions:0];
  base64Hash =
      [base64Hash stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
  base64Hash =
      [base64Hash stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  base64Hash =
      [base64Hash stringByReplacingOccurrencesOfString:@"=" withString:@""];
  return base64Hash;
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

  NSData *paramsData =
      [NSJSONSerialization dataWithJSONObject:authorizeParams
                                      options:0
                                        error:&error];
  XCTAssertNotNil(paramsData, @"Failed to serialize authorize params: %@", error);

  NSString *requestURI = [NSString
      stringWithFormat:@"urn:ietf:params:oauth:request_uri:%@",
                       [[NSUUID UUID] UUIDString]];
  NSString *expiresAt =
      [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSinceNow:600]];
  NSString *paramsJSON =
      [[NSString alloc] initWithData:paramsData encoding:NSUTF8StringEncoding];

  BOOL inserted = [self.database executeParameterizedUpdate:
                     @"INSERT INTO oauth_par_requests (request_uri, client_id, params_json, expires_at, consumed_at) VALUES (?, ?, ?, ?, NULL)"
                                                          params:@[
                                                            requestURI,
                                                            clientID ?: @"",
                                                            paramsJSON ?: @"{}",
                                                            expiresAt
                                                          ]
                                                           error:&error];
  XCTAssertTrue(inserted, @"Failed to insert PAR row: %@", error);

  HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                methodString:@"GET"
                                                        path:@"/oauth/authorize"
                                                 queryString:@""
                                                 queryParams:@{
                                                   @"request_uri" : requestURI,
                                                   @"client_id" : clientID ?: @""
                                                 }
                                                     version:@"HTTP/1.1"
                                                     headers:@{}
                                                        body:[NSData data]
                                               remoteAddress:@"127.0.0.1"];
  HttpResponse *response = [[HttpResponse alloc] init];
  [self.handler handleAuthorizeRequest:request response:response];
  return response;
}

/*!
 @test testBskyAppAuthorizationWithClientMetadata

 @abstract Test that bsky.app can authorize with client_metadata parameter.

 @discussion This test simulates bsky.app providing client_id=https://bsky.app
 with valid client_metadata JSON. Per ATProto OAuth spec, this should succeed
 without database pre-registration.

 EXPECTED BEHAVIOR (after fix):
 - Authorization should succeed (statusCode != 400)
 - No "unauthorized_client" error
 - Authorization code should be generated

 EXPECTED FAILURE (on unfixed code):
 - validateClient returns nil because bsky.app not in database
 - Returns 400 with "unauthorized_client" error
 */
- (void)testBskyAppAuthorizationWithClientMetadata {
  NSString *codeVerifier = @"high-entropy-random-string-that-is-long-enough-"
                           @"for-pkce-43-chars-minimum";
  NSString *codeChallenge = [self generateCodeChallenge:codeVerifier];

  // Construct client_metadata per ATProto OAuth spec
  NSDictionary *clientMetadata = @{
    @"client_id" : @"https://bsky.app",
    @"client_name" : @"Bluesky",
    @"redirect_uris" : @[ @"https://bsky.app/oauth/callback" ],
    @"grant_types" : @[ @"authorization_code", @"refresh_token" ],
    @"response_types" : @[ @"code" ],
    @"scope" : @"atproto",
    @"application_type" : @"web",
    @"dpop_bound_access_tokens" : @YES,
    @"token_endpoint_auth_method" : @"none"
  };

  NSError *jsonError = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:clientMetadata
                                                     options:0
                                                       error:&jsonError];
  XCTAssertNil(jsonError, @"Failed to serialize client_metadata: %@",
               jsonError);
  NSString *clientMetadataJSON =
      [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

  NSDictionary *authParams = @{
    @"client_id" : @"https://bsky.app",
    @"response_type" : @"code",
    @"redirect_uri" : @"https://bsky.app/oauth/callback",
    @"scope" : @"atproto",
    @"state" : @"state123",
    @"code_challenge" : codeChallenge,
    @"code_challenge_method" : @"S256",
    @"login_hint" : @"testuser.test",
    @"client_metadata" : clientMetadataJSON
  };

  HttpResponse *authResp =
      [self authorizeViaPARWithParameters:authParams
                                 clientID:@"https://bsky.app"];

  // EXPECTED BEHAVIOR (after fix): Authorization succeeds
  // The handler should validate client_metadata and proceed with authorization
  XCTAssertNotEqual(authResp.statusCode, 400,
                    @"Authorization should not return 400 error");

  // Check that we don't get "unauthorized_client" error
  if (authResp.body && authResp.body.length > 0) {
    NSString *bodyString = [[NSString alloc] initWithData:authResp.body
                                                 encoding:NSUTF8StringEncoding];
    XCTAssertFalse([bodyString containsString:@"unauthorized_client"],
                   @"Should not return unauthorized_client error for valid "
                   @"client_metadata");
  }

  // Should either serve consent page (200) or redirect with code (302)
  BOOL isSuccess = (authResp.statusCode == 200 || authResp.statusCode == 302);
  XCTAssertTrue(isSuccess,
                @"Authorization should succeed with status 200 or 302, got %ld",
                (long)authResp.statusCode);
}

/*!
 @test testWitchskyAppAuthorizationWithClientMetadata

 @abstract Test that witchsky.app can authorize with client_metadata parameter.

 @discussion This test simulates witchsky.app providing
 client_id=https://witchsky.app with valid client_metadata JSON. Per ATProto
 OAuth spec, this should succeed without database pre-registration.

 EXPECTED BEHAVIOR (after fix):
 - Authorization should succeed (statusCode != 400)
 - No "unauthorized_client" error

 EXPECTED FAILURE (on unfixed code):
 - validateClient returns nil because witchsky.app not in database
 - Returns 400 with "unauthorized_client" error
 */
- (void)testWitchskyAppAuthorizationWithClientMetadata {
  NSString *codeVerifier =
      @"another-high-entropy-random-string-for-pkce-with-minimum-43-characters";
  NSString *codeChallenge = [self generateCodeChallenge:codeVerifier];

  NSDictionary *clientMetadata = @{
    @"client_id" : @"https://witchsky.app",
    @"client_name" : @"Witchsky",
    @"redirect_uris" : @[ @"https://witchsky.app/oauth/callback" ],
    @"grant_types" : @[ @"authorization_code", @"refresh_token" ],
    @"response_types" : @[ @"code" ],
    @"scope" : @"atproto",
    @"application_type" : @"web",
    @"dpop_bound_access_tokens" : @YES,
    @"token_endpoint_auth_method" : @"none"
  };

  NSError *jsonError = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:clientMetadata
                                                     options:0
                                                       error:&jsonError];
  XCTAssertNil(jsonError, @"Failed to serialize client_metadata: %@",
               jsonError);
  NSString *clientMetadataJSON =
      [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

  NSDictionary *authParams = @{
    @"client_id" : @"https://witchsky.app",
    @"response_type" : @"code",
    @"redirect_uri" : @"https://witchsky.app/oauth/callback",
    @"scope" : @"atproto",
    @"state" : @"state456",
    @"code_challenge" : codeChallenge,
    @"code_challenge_method" : @"S256",
    @"login_hint" : @"testuser.test",
    @"client_metadata" : clientMetadataJSON
  };

  HttpResponse *authResp =
      [self authorizeViaPARWithParameters:authParams
                                 clientID:@"https://witchsky.app"];

  // EXPECTED BEHAVIOR (after fix): Authorization succeeds
  XCTAssertNotEqual(authResp.statusCode, 400,
                    @"Authorization should not return 400 error");

  if (authResp.body && authResp.body.length > 0) {
    NSString *bodyString = [[NSString alloc] initWithData:authResp.body
                                                 encoding:NSUTF8StringEncoding];
    XCTAssertFalse([bodyString containsString:@"unauthorized_client"],
                   @"Should not return unauthorized_client error for valid "
                   @"client_metadata");
  }

  BOOL isSuccess = (authResp.statusCode == 200 || authResp.statusCode == 302);
  XCTAssertTrue(isSuccess,
                @"Authorization should succeed with status 200 or 302, got %ld",
                (long)authResp.statusCode);
}

/*!
 @test testNativeAppWithLoopbackRedirectIPv4

 @abstract Test that native apps can use loopback redirect_uri (IPv4).

 @discussion This test simulates a native app using
 http://127.0.0.1:8080/callback as redirect_uri. Per RFC 8252 and ATProto OAuth
 spec, loopback redirects should be allowed for native apps.

 EXPECTED BEHAVIOR (after fix):
 - Authorization should succeed
 - Loopback redirect should be validated and accepted

 EXPECTED FAILURE (on unfixed code):
 - validateRedirectURI rejects HTTP loopback redirects
 - Returns 400 with "Invalid redirect_uri" error
 */
- (void)testNativeAppWithLoopbackRedirectIPv4 {
  NSString *codeVerifier = @"native-app-pkce-verifier-with-sufficient-entropy-"
                           @"for-security-requirements";
  NSString *codeChallenge = [self generateCodeChallenge:codeVerifier];

  NSDictionary *clientMetadata = @{
    @"client_id" : @"https://example.com/native-app",
    @"client_name" : @"Native App",
    @"redirect_uris" : @[ @"http://127.0.0.1:8080/callback" ],
    @"grant_types" : @[ @"authorization_code", @"refresh_token" ],
    @"response_types" : @[ @"code" ],
    @"scope" : @"atproto",
    @"application_type" : @"native",
    @"dpop_bound_access_tokens" : @YES,
    @"token_endpoint_auth_method" : @"none"
  };

  NSError *jsonError = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:clientMetadata
                                                     options:0
                                                       error:&jsonError];
  XCTAssertNil(jsonError, @"Failed to serialize client_metadata: %@",
               jsonError);
  NSString *clientMetadataJSON =
      [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

  NSDictionary *authParams = @{
    @"client_id" : @"https://example.com/native-app",
    @"response_type" : @"code",
    @"redirect_uri" : @"http://127.0.0.1:8080/callback",
    @"scope" : @"atproto",
    @"state" : @"state789",
    @"code_challenge" : codeChallenge,
    @"code_challenge_method" : @"S256",
    @"login_hint" : @"testuser.test",
    @"client_metadata" : clientMetadataJSON
  };

  HttpResponse *authResp =
      [self authorizeViaPARWithParameters:authParams
                                 clientID:@"https://example.com/native-app"];

  // EXPECTED BEHAVIOR (after fix): Authorization succeeds with loopback
  // redirect
  XCTAssertNotEqual(authResp.statusCode, 400,
                    @"Authorization should not return 400 error");

  if (authResp.body && authResp.body.length > 0) {
    NSString *bodyString = [[NSString alloc] initWithData:authResp.body
                                                 encoding:NSUTF8StringEncoding];
    XCTAssertFalse([bodyString containsString:@"Invalid redirect_uri"],
                   @"Should not reject loopback redirect_uri per RFC 8252");
    XCTAssertFalse([bodyString containsString:@"unauthorized_client"],
                   @"Should not return unauthorized_client error for valid "
                   @"client_metadata");
  }

  BOOL isSuccess = (authResp.statusCode == 200 || authResp.statusCode == 302);
  XCTAssertTrue(isSuccess,
                @"Authorization should succeed with status 200 or 302, got %ld",
                (long)authResp.statusCode);
}

/*!
 @test testNativeAppWithLoopbackRedirectIPv6

 @abstract Test that native apps can use loopback redirect_uri (IPv6).

 @discussion This test simulates a native app using http://[::1]:3000/callback
 as redirect_uri. Per RFC 8252 and ATProto OAuth spec, IPv6 loopback redirects
 should be allowed for native apps.

 EXPECTED BEHAVIOR (after fix):
 - Authorization should succeed
 - IPv6 loopback redirect should be validated and accepted

 EXPECTED FAILURE (on unfixed code):
 - validateRedirectURI rejects HTTP loopback redirects
 - Returns 400 with "Invalid redirect_uri" error
 */
- (void)testNativeAppWithLoopbackRedirectIPv6 {
  NSString *codeVerifier =
      @"ipv6-native-app-pkce-verifier-with-sufficient-entropy-for-security";
  NSString *codeChallenge = [self generateCodeChallenge:codeVerifier];

  NSDictionary *clientMetadata = @{
    @"client_id" : @"https://example.com/ipv6-app",
    @"client_name" : @"IPv6 Native App",
    @"redirect_uris" : @[ @"http://[::1]:3000/callback" ],
    @"grant_types" : @[ @"authorization_code", @"refresh_token" ],
    @"response_types" : @[ @"code" ],
    @"scope" : @"atproto",
    @"application_type" : @"native",
    @"dpop_bound_access_tokens" : @YES,
    @"token_endpoint_auth_method" : @"none"
  };

  NSError *jsonError = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:clientMetadata
                                                     options:0
                                                       error:&jsonError];
  XCTAssertNil(jsonError, @"Failed to serialize client_metadata: %@",
               jsonError);
  NSString *clientMetadataJSON =
      [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

  NSDictionary *authParams = @{
    @"client_id" : @"https://example.com/ipv6-app",
    @"response_type" : @"code",
    @"redirect_uri" : @"http://[::1]:3000/callback",
    @"scope" : @"atproto",
    @"state" : @"stateABC",
    @"code_challenge" : codeChallenge,
    @"code_challenge_method" : @"S256",
    @"login_hint" : @"testuser.test",
    @"client_metadata" : clientMetadataJSON
  };

  HttpResponse *authResp =
      [self authorizeViaPARWithParameters:authParams
                                 clientID:@"https://example.com/ipv6-app"];

  // EXPECTED BEHAVIOR (after fix): Authorization succeeds with IPv6 loopback
  // redirect
  XCTAssertNotEqual(authResp.statusCode, 400,
                    @"Authorization should not return 400 error");

  if (authResp.body && authResp.body.length > 0) {
    NSString *bodyString = [[NSString alloc] initWithData:authResp.body
                                                 encoding:NSUTF8StringEncoding];
    XCTAssertFalse(
        [bodyString containsString:@"Invalid redirect_uri"],
        @"Should not reject IPv6 loopback redirect_uri per RFC 8252");
    XCTAssertFalse([bodyString containsString:@"unauthorized_client"],
                   @"Should not return unauthorized_client error for valid "
                   @"client_metadata");
  }

  BOOL isSuccess = (authResp.statusCode == 200 || authResp.statusCode == 302);
  XCTAssertTrue(isSuccess,
                @"Authorization should succeed with status 200 or 302, got %ld",
                (long)authResp.statusCode);
}

@end
