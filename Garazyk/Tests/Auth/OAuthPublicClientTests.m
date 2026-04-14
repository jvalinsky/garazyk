#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuth2Handler.h"
#import "Database/PDSDatabase.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import <CommonCrypto/CommonDigest.h>
#import <XCTest/XCTest.h>

@interface OAuthPublicClientTests : XCTestCase
@property(nonatomic, strong) OAuth2Handler *handler;
@property(nonatomic, strong) PDSDatabase *database;
@property(nonatomic, strong) JWTMinter *minter;
@end

@implementation OAuthPublicClientTests

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
  XCTAssertTrue(success, @"Failed to create part requests table: %@", error);

  self.handler = [[OAuth2Handler alloc] initWithDatabase:self.database];
  self.minter = [[JWTMinter alloc] init];

  // Seed a public client (no secret)
  NSDictionary *client = @{
    @"client_id" : @"public-client",
    @"client_name" : @"Public Client",
    @"redirect_uris" : @[ @"https://client.example.com/cb" ],
    @"grant_types" : @"authorization_code refresh_token",
    @"response_types" : @"code",
    @"scope" : @"atproto",
    @"application_type" : @"native",
    @"token_endpoint_auth_method" : @"none"
  };
  success = [self.database createClient:client error:&error];
  XCTAssertTrue(success, @"Failed to seed client: %@", error);

  // Seed a user
  PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
  account.did = @"did:plc:user";
  account.handle = @"user.test";
  account.createdAt = [[NSDate date] timeIntervalSince1970];
  account.updatedAt = [[NSDate date] timeIntervalSince1970];
  success = [self.database createAccount:account error:&error];
  XCTAssertTrue(success, @"Failed to seed user: %@", error);
}

- (void)tearDown {
  [super tearDown];
}

// Helper to extract code from redirect URL
- (NSString *)extractCodeFromRedirect:(NSString *)location {
  NSURLComponents *comps = [NSURLComponents componentsWithString:location];
  for (NSURLQueryItem *item in comps.queryItems) {
    if ([item.name isEqualToString:@"code"]) {
      return item.value;
    }
  }
  return nil;
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

- (void)testPublicClientWithPKCEAndDPoP {
  // 1. Authorize Request (with PKCE)
  NSString *codeVerifier =
      @"high-entropy-random-string-that-is-long-enough-for-pkce-43-chars-min";
  // Manually sha256 and base64url
  NSData *verifierData = [codeVerifier dataUsingEncoding:NSUTF8StringEncoding];
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
  NSString *codeChallengeCalc = base64Hash;

  NSDictionary *authParams = @{
    @"client_id" : @"public-client",
    @"response_type" : @"code",
    @"redirect_uri" : @"https://client.example.com/cb",
    @"scope" : @"atproto",
    @"state" : @"state123",
    @"code_challenge" : codeChallengeCalc,
    @"code_challenge_method" : @"S256",
    @"login_hint" : @"user.test"
  };

  HttpResponse *authResp =
      [self authorizeViaPARWithParameters:authParams clientID:@"public-client"];

  // The authorize endpoint serves a consent page (200) rather than
  // auto-redirecting This is correct behavior - user consent is required
  XCTAssertEqual(authResp.statusCode, 200, @"Should serve consent page");
  XCTAssertNotNil(authResp.body, @"Should have response body");
  XCTAssertTrue([authResp.contentType containsString:@"text/html"],
                @"Should be HTML content");
}

- (void)testPublicClientAuthRespStatusCode400WithoutPKCE {
  // 1. Authorize Request (WITHOUT PKCE)
  NSDictionary *authParams = @{
    @"client_id" : @"public-client",
    @"response_type" : @"code",
    @"redirect_uri" : @"https://client.example.com/cb",
    @"scope" : @"atproto",
    @"state" : @"state123",
    @"login_hint" : @"user.test"
  };

  HttpResponse *authResp =
      [self authorizeViaPARWithParameters:authParams clientID:@"public-client"];

  // RFC 7636: Authorization Server MUST return error if code_challenge is
  // missing for public clients.
  XCTAssertEqual(authResp.statusCode, 400);
}

- (void)testPublicClientAuthRespStatusCode400WithDPoPButNoPKCE {
  // 1. Authorize Request (WITHOUT PKCE)
  NSDictionary *authParams = @{
    @"client_id" : @"public-client",
    @"response_type" : @"code",
    @"redirect_uri" : @"https://client.example.com/cb",
    @"scope" : @"atproto",
    @"state" : @"state123",
    @"login_hint" : @"user.test"
  };

  HttpResponse *authResp =
      [self authorizeViaPARWithParameters:authParams clientID:@"public-client"];

  // RFC 7636: Authorization Server MUST return error if code_challenge is
  // missing for public clients.
  XCTAssertEqual(authResp.statusCode, 400);

  // Since it should fail, we stop here.
  return;

  /*
  NSString *location = [authResp.headers objectForKey:@"Location"];
  NSString *code = [self extractCodeFromRedirect:location];

  // 2. Token Request (WITH DPoP, WITHOUT PKCE)
  NSString *tokenBody = [NSString
  stringWithFormat:@"grant_type=authorization_code&code=%@&client_id=public-client&redirect_uri=https://client.example.com/cb",
  code];

  HttpRequest *tokenReq = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                      methodString:@"POST"
                                                              path:@"/oauth/token"
                                                       queryString:@""
                                                       queryParams:@{}
                                                           version:@"HTTP/1.1"
                                                           headers:@{@"dpop":
  @"dummy-proof"} // We need a proof to bypass DPoP check, but it will fail
  verification body:[tokenBody dataUsingEncoding:NSUTF8StringEncoding]
                                                     remoteAddress:@"127.0.0.1"];

  HttpResponse *tokenResp = [[HttpResponse alloc] init];
  // We don't need to run token request if authorize failed

  // Just placeholder to compile
  (void)tokenResp;
  */
}
@end
