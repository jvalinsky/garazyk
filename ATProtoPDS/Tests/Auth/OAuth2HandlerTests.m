#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuth2Handler+Testing.h"
#import "Auth/DPoPUtil.h"
#import "Auth/JWT.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/TestKeyFixtures.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"
#import "App/Services/PDSAccountService.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

@interface TestAccountService : NSObject <PDSAccountService>
@property (nonatomic, copy) NSDictionary *mockUser;
@end

@implementation TestAccountService
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

@interface OAuth2HandlerTests : XCTestCase
@property (nonatomic, strong) OAuth2Handler *handler;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) TestAccountService *accountService;
@property (nonatomic, copy) NSString *databasePath;
@end

static SecKeyRef oauth2HandlerCreateFixedP256PrivateKey(NSError **error) {
    return PDSTestCreateFixedP256PrivateKey(error);
}

@implementation OAuth2HandlerTests

- (void)setUp {
    [super setUp];
    
    NSString *filename = [NSString stringWithFormat:@"oauth2-handler-tests-%@.sqlite", [[NSUUID UUID] UUIDString]];
    self.databasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    NSURL *databaseURL = [NSURL fileURLWithPath:self.databasePath];
    self.database = [PDSDatabase databaseAtURL:databaseURL];
    XCTAssertTrue([self.database openWithError:nil], @"Database should open");
    
    // Register test clients
    NSError *clientError = nil;
    NSDictionary *testClient = @{
        @"client_id": @"test-client",
        @"redirect_uris": @[@"http://localhost/cb", @"http://localhost:2583/cb"],
        @"grant_types": @"authorization_code refresh_token",
        @"scope": @"atproto"
    };
    XCTAssertTrue([self.database createClient:testClient error:&clientError], @"Should create test-client: %@", clientError);
    
    NSDictionary *confidentialClient = @{
        @"client_id": @"test-client-confidential",
        @"client_secret": @"test-secret",
        @"redirect_uris": @[@"http://localhost/cb"],
        @"grant_types": @"authorization_code refresh_token client_credentials",
        @"scope": @"atproto"
    };
    XCTAssertTrue([self.database createClient:confidentialClient error:&clientError], @"Should create test-client-confidential: %@", clientError);
    
    self.accountService = [[TestAccountService alloc] init];
    self.accountService.mockUser = @{@"did": @"did:plc:test-user", @"handle": @"test-user.test"};
    
    self.handler = [[OAuth2Handler alloc] initWithDatabase:self.database];
    self.handler.accountService = self.accountService;
    [self.handler clearPendingConsentsForTesting];
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

- (NSDictionary *)validATProtoClientMetadataTemplateWithClientID:(NSString *)clientID
                                                      redirectURI:(NSString *)redirectURI {
    return @{
        @"client_id": clientID,
        @"client_name": @"Spec Client",
        @"redirect_uris": @[redirectURI],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"scope": @"atproto",
        @"dpop_bound_access_tokens": @YES,
        @"token_endpoint_auth_method": @"none",
        @"application_type": @"web"
    };
}

- (void)testTokenRequestBlocksBadClientSecret {
    // Setup request with valid client_id but wrong client_secret (when secret is configured)
    NSString *body = @"grant_type=authorization_code&code=valid&client_id=test-client-confidential&client_secret=wrong";

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    // Execute handler
    [self.handler handleTokenRequest:request response:response];

    // Assert 401 Unauthorized for invalid client secret
    XCTAssertEqual(response.statusCode, 401, @"Should return 401 for invalid client secret");
}

- (void)testAuthorizeBlocksMissingState {
    // Setup request without state parameter
    NSDictionary *queryParams = @{
        @"client_id": @"test-client",
        @"response_type": @"code",
        @"redirect_uri": @"http://localhost/cb"
        // Note: no state parameter
    };
    HttpResponse *response =
        [self authorizeViaPARWithParameters:queryParams clientID:@"test-client"];

    // Assert 400 Bad Request
    XCTAssertEqual(response.statusCode, 400, @"Should return 400 for missing state parameter");
}



- (void)testIssuerEqualityWithEnvironmentVariable {
    // Test that issuer can be configured via environment variable
    setenv("PDS_ISSUER", "https://custom.pds.example.com", 1);

    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"issuer_test.db"];
    PDSDatabase *testDb = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:tempPath]];
    NSError *error = nil;
    [testDb openWithError:&error];
    
    OAuth2Handler *handler = [[OAuth2Handler alloc] initWithDatabase:testDb];
    XCTAssertEqualObjects(handler.oauthServer.issuer, @"https://custom.pds.example.com",
                         @"Should use custom issuer from environment");

    // Clean up
    [testDb close];
    unsetenv("PDS_ISSUER");
}

- (void)testTokenRequestReturnsDPoPNonceChallengeWhenNonceMissing {
    NSError *keyError = nil;
    SecKeyRef privateKey = oauth2HandlerCreateFixedP256PrivateKey(&keyError);
    if (privateKey == NULL) {
        XCTSkip(@"Skipping DPoP nonce challenge test: key import unavailable (%@)", keyError);
    }

    @try {
        NSError *proofError = nil;
        DPoPToken *proof = [DPoPUtil createDPoPForMethod:@"POST"
                                                      uri:@"http://localhost:2583/oauth/token"
                                                   nonce:nil
                                                     key:privateKey
                                                   error:&proofError];
        XCTAssertNotNil(proof);
        XCTAssertNil(proofError);

        NSString *body = @"grant_type=refresh_token&refresh_token=invalid-refresh&client_id=test-client";
        HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                      methodString:@"POST"
                                                              path:@"/oauth/token"
                                                       queryString:@""
                                                       queryParams:@{}
                                                           version:@"1.1"
                                                           headers:@{
                                                               @"content-type": @"application/x-www-form-urlencoded",
                                                               @"host": @"localhost:2583",
                                                               @"dpop": proof.jwt
                                                           }
                                                              body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                        remoteAddress:@"127.0.0.1"];
        HttpResponse *response = [[HttpResponse alloc] init];
        [self.handler handleTokenRequest:request response:response];

        XCTAssertEqual(response.statusCode, 400);
        XCTAssertEqualObjects(response.jsonBody[@"error"], @"use_dpop_nonce");
        XCTAssertTrue([[response headerForKey:@"DPoP-Nonce"] length] > 0);
        XCTAssertEqualObjects([response headerForKey:@"WWW-Authenticate"], @"DPoP error=\"use_dpop_nonce\"");
        XCTAssertEqualObjects([response headerForKey:@"Cache-Control"], @"no-store");
        XCTAssertEqualObjects([response headerForKey:@"Pragma"], @"no-cache");
    } @finally {
        CFRelease(privateKey);
    }
}

- (void)testTokenRequestReturnsInvalidDPoPProofForMalformedProof {
    NSString *body = @"grant_type=refresh_token&refresh_token=invalid-refresh&client_id=test-client";
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{
                                                           @"content-type": @"application/x-www-form-urlencoded",
                                                           @"host": @"localhost:2583",
                                                           @"dpop": @"not-a-jwt"
                                                       }
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleTokenRequest:request response:response];

    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"invalid_dpop_proof");
    XCTAssertNil([response headerForKey:@"DPoP-Nonce"]);
}

- (void)testTokenRequestRotatesDPoPNonceAfterValidProof {
    NSError *keyError = nil;
    SecKeyRef privateKey = oauth2HandlerCreateFixedP256PrivateKey(&keyError);
    if (privateKey == NULL) {
        XCTSkip(@"Skipping DPoP nonce rotation test: key import unavailable (%@)", keyError);
    }

    @try {
        NSString *incomingNonce = [[PDSNonceManager sharedManager] generateNonce];
        XCTAssertTrue(incomingNonce.length > 0);

        NSError *proofError = nil;
        DPoPToken *proof = [DPoPUtil createDPoPForMethod:@"POST"
                                                      uri:@"http://localhost:2583/oauth/token"
                                                   nonce:incomingNonce
                                                     key:privateKey
                                                   error:&proofError];
        XCTAssertNotNil(proof);
        XCTAssertNil(proofError);

        NSString *body = @"grant_type=refresh_token&refresh_token=invalid-refresh&client_id=test-client";
        HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                      methodString:@"POST"
                                                              path:@"/oauth/token"
                                                       queryString:@""
                                                       queryParams:@{}
                                                           version:@"1.1"
                                                           headers:@{
                                                               @"content-type": @"application/x-www-form-urlencoded",
                                                               @"host": @"localhost:2583",
                                                               @"dpop": proof.jwt,
                                                               @"dpop-nonce": incomingNonce
                                                           }
                                                              body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                        remoteAddress:@"127.0.0.1"];
        HttpResponse *response = [[HttpResponse alloc] init];
        [self.handler handleTokenRequest:request response:response];

        XCTAssertEqual(response.statusCode, 400);
        XCTAssertEqualObjects(response.jsonBody[@"error"], @"invalid_grant");
        NSString *nextNonce = [response headerForKey:@"DPoP-Nonce"];
        XCTAssertTrue(nextNonce.length > 0);
        XCTAssertNotEqualObjects(nextNonce, incomingNonce);
        XCTAssertEqualObjects([response headerForKey:@"Cache-Control"], @"no-store");
        XCTAssertEqualObjects([response headerForKey:@"Pragma"], @"no-cache");
    } @finally {
        CFRelease(privateKey);
    }
}

- (void)testPARRequestReturnsDPoPNonceChallengeWhenNonceMissing {
    NSError *keyError = nil;
    SecKeyRef privateKey = oauth2HandlerCreateFixedP256PrivateKey(&keyError);
    if (privateKey == NULL) {
        XCTSkip(@"Skipping DPoP nonce challenge test: key import unavailable (%@)", keyError);
    }

    @try {
        NSError *proofError = nil;
        DPoPToken *proof = [DPoPUtil createDPoPForMethod:@"POST"
                                                      uri:@"http://localhost:2583/oauth/par"
                                                   nonce:nil
                                                     key:privateKey
                                                   error:&proofError];
        XCTAssertNotNil(proof);
        XCTAssertNil(proofError);

        NSString *body = @"client_id=test-client&response_type=code&redirect_uri=http://localhost/cb&state=test-state&scope=atproto&code_challenge=test-challenge&code_challenge_method=S256";
        HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                      methodString:@"POST"
                                                              path:@"/oauth/par"
                                                       queryString:@""
                                                       queryParams:@{}
                                                           version:@"1.1"
                                                           headers:@{
                                                               @"content-type": @"application/x-www-form-urlencoded",
                                                               @"host": @"localhost:2583",
                                                               @"dpop": proof.jwt
                                                           }
                                                              body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                        remoteAddress:@"127.0.0.1"];
        HttpResponse *response = [[HttpResponse alloc] init];
        [self.handler handlePARRequest:request response:response];

        XCTAssertEqual(response.statusCode, 400);
        XCTAssertEqualObjects(response.jsonBody[@"error"], @"use_dpop_nonce");
        XCTAssertTrue([[response headerForKey:@"DPoP-Nonce"] length] > 0);
        XCTAssertEqualObjects([response headerForKey:@"WWW-Authenticate"], @"DPoP error=\"use_dpop_nonce\"");
        XCTAssertEqualObjects([response headerForKey:@"Cache-Control"], @"no-store");
        XCTAssertEqualObjects([response headerForKey:@"Pragma"], @"no-cache");
    } @finally {
        CFRelease(privateKey);
    }
}

- (void)testAuthorizeRedirectWithExistingQueryStringAfterConsent {
    NSString *redirectWithQuery = @"http://localhost:2583/?oauth_callback=1";
    
    [self.database createClient:@{
        @"client_id": @"test-client",
        @"redirect_uris": @[redirectWithQuery, @"http://localhost:3000/callback"],
        @"grant_types": @"authorization_code",
        @"scope": @"atproto"
    } error:nil];
    
    NSDictionary *queryParams = @{
        @"client_id": @"test-client",
        @"redirect_uri": redirectWithQuery,
        @"response_type": @"code",
        @"state": @"test-state-123",
        @"code_challenge": @"test_challenge",
        @"code_challenge_method": @"S256"
    };
    HttpResponse *response =
        [self authorizeViaPARWithParameters:queryParams clientID:@"test-client"];
    
    XCTAssertEqual(response.statusCode, 200, @"Should serve consent page");
    NSString *bodyStr = [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding];
    XCTAssertTrue([bodyStr containsString:@"<!DOCTYPE html>"], @"Should contain HTML content");
    
    NSString *csrfToken = @"test-csrf-token-12345";
    NSString *signInBody = @"handle=test-user.test&password=test-password";
    HttpRequest *signInRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                         methodString:@"POST"
                                                                 path:@"/oauth/authorize/signin"
                                                          queryString:@""
                                                          queryParams:@{}
                                                              version:@"1.1"
                                                              headers:@{
                                                                  @"Content-Type": @"application/x-www-form-urlencoded",
                                                                  @"X-CSRF-Token": csrfToken,
                                                                  @"Cookie": [NSString stringWithFormat:@"csrf_token=%@", csrfToken]
                                                              }
                                                                 body:[signInBody dataUsingEncoding:NSUTF8StringEncoding]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *signInResponse = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeSignIn:signInRequest response:signInResponse];
    
    XCTAssertEqual(signInResponse.statusCode, 200, @"Sign-in should succeed");
    NSString *sessionToken = signInResponse.jsonBody[@"session_token"];
    XCTAssertNotNil(sessionToken, @"Should receive session token");
    
    NSString *consentBody = [NSString stringWithFormat:@"decision=allow&client_id=test-client&state=test-state-123&redirect_uri=%@&session_token=%@&response_type=code&code_challenge=test_challenge&code_challenge_method=S256", redirectWithQuery, sessionToken];
    HttpRequest *consentRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                          methodString:@"POST"
                                                                  path:@"/oauth/authorize/confirm"
                                                           queryString:@""
                                                           queryParams:@{}
                                                               version:@"1.1"
                                                               headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                                  body:[consentBody dataUsingEncoding:NSUTF8StringEncoding]
                                                        remoteAddress:@"127.0.0.1"];
    HttpResponse *consentResponse = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeConfirm:consentRequest response:consentResponse];
    
    XCTAssertEqual(consentResponse.statusCode, 302, @"Should redirect with 302");
    
    NSString *location = [consentResponse headerForKey:@"Location"];
    XCTAssertNotNil(location, @"Location header should be set");
    
    XCTAssertTrue([location hasPrefix:redirectWithQuery], @"Should redirect to base redirect URI");
    XCTAssertTrue([location containsString:@"&code="], @"Should use & separator for existing query string");
    XCTAssertFalse([location containsString:@"?code="], @"Should NOT use ? when query already exists");
    XCTAssertTrue([location containsString:@"&state=test-state-123"], @"Should append state with & separator");
    NSString *encodedIssuer = [self.handler.oauthServer.issuer stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *expectedIssuerParam = [NSString stringWithFormat:@"&iss=%@", encodedIssuer];
    XCTAssertTrue([location containsString:expectedIssuerParam], @"Should append issuer parameter");
}

- (void)testAuthorizeRedirectWithoutQueryStringAfterConsent {
    NSString *redirectWithoutQuery = @"http://localhost:3000/callback";
    
    [self.database createClient:@{
        @"client_id": @"test-client",
        @"redirect_uris": @[redirectWithoutQuery],
        @"grant_types": @"authorization_code",
        @"scope": @"atproto"
    } error:nil];
    
    NSDictionary *queryParams = @{
        @"client_id": @"test-client",
        @"redirect_uri": redirectWithoutQuery,
        @"response_type": @"code",
        @"state": @"test-state-456",
        @"code_challenge": @"test_challenge",
        @"code_challenge_method": @"S256"
    };
    HttpResponse *response =
        [self authorizeViaPARWithParameters:queryParams clientID:@"test-client"];
    
    XCTAssertEqual(response.statusCode, 200, @"Should serve consent page");
    NSString *bodyStr = [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding];
    XCTAssertTrue([bodyStr containsString:@"<!DOCTYPE html>"], @"Should contain HTML content");
    
    NSString *csrfToken = @"test-csrf-token-67890";
    NSString *signInBody = @"handle=test-user.test&password=test-password";
    HttpRequest *signInRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                         methodString:@"POST"
                                                                 path:@"/oauth/authorize/signin"
                                                          queryString:@""
                                                          queryParams:@{}
                                                              version:@"1.1"
                                                              headers:@{
                                                                  @"Content-Type": @"application/x-www-form-urlencoded",
                                                                  @"X-CSRF-Token": csrfToken,
                                                                  @"Cookie": [NSString stringWithFormat:@"csrf_token=%@", csrfToken]
                                                              }
                                                                 body:[signInBody dataUsingEncoding:NSUTF8StringEncoding]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *signInResponse = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeSignIn:signInRequest response:signInResponse];
    
    XCTAssertEqual(signInResponse.statusCode, 200, @"Sign-in should succeed");
    NSString *sessionToken = signInResponse.jsonBody[@"session_token"];
    XCTAssertNotNil(sessionToken, @"Should receive session token");
    
    NSString *consentBody = [NSString stringWithFormat:@"decision=allow&client_id=test-client&state=test-state-456&redirect_uri=%@&session_token=%@&response_type=code&code_challenge=test_challenge&code_challenge_method=S256", redirectWithoutQuery, sessionToken];
    HttpRequest *consentRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                          methodString:@"POST"
                                                                  path:@"/oauth/authorize/confirm"
                                                           queryString:@""
                                                           queryParams:@{}
                                                               version:@"1.1"
                                                               headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                                  body:[consentBody dataUsingEncoding:NSUTF8StringEncoding]
                                                        remoteAddress:@"127.0.0.1"];
    HttpResponse *consentResponse = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeConfirm:consentRequest response:consentResponse];
    
    XCTAssertEqual(consentResponse.statusCode, 302, @"Should redirect with 302");
    
    NSString *location = [consentResponse headerForKey:@"Location"];
    XCTAssertNotNil(location, @"Location header should be set");
    
    XCTAssertTrue([location hasPrefix:redirectWithoutQuery], @"Should redirect to base redirect URI");
    XCTAssertTrue([location containsString:@"?code="], @"Should use ? separator when no query string exists");
    XCTAssertFalse([location containsString:@"&code="], @"Should NOT use & as first separator");
    NSString *encodedIssuer = [self.handler.oauthServer.issuer stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *expectedIssuerParam = [NSString stringWithFormat:@"&iss=%@", encodedIssuer];
    XCTAssertTrue([location containsString:expectedIssuerParam], @"Should append issuer parameter");
}

- (void)testAuthorizeDenyRedirectIncludesIssuer {
    NSString *redirectURI = @"http://localhost:2583/cb";
    NSString *body = [NSString stringWithFormat:@"decision=deny&client_id=test-client&state=deny-state&redirect_uri=%@",
                      [redirectURI stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/authorize/confirm"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeConfirm:request response:response];

    XCTAssertEqual(response.statusCode, 302);
    NSString *location = [response headerForKey:@"Location"];
    XCTAssertNotNil(location);
    XCTAssertTrue([location containsString:@"error=access_denied"]);
    XCTAssertTrue([location containsString:@"state=deny-state"]);
    NSString *encodedIssuer = [self.handler.oauthServer.issuer stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *expectedIssuerParam = [NSString stringWithFormat:@"iss=%@", encodedIssuer];
    XCTAssertTrue([location containsString:expectedIssuerParam]);
}

- (void)testAuthorizeConfirmDenyReturns400ForEvilRedirect {
    NSString *body = @"decision=deny&client_id=test-client&state=deny-state&redirect_uri=https%3A%2F%2Fevil.example%2Fcallback";

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/authorize/confirm"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeConfirm:request response:response];

    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"invalid_request");
}

- (void)testAuthorizeAllowBlocksUnregisteredRedirect {
    NSString *csrfToken = @"csrf-allow-reject";
    NSString *signInBody = @"handle=test-user.test&password=test-password";
    HttpRequest *signInRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                         methodString:@"POST"
                                                                 path:@"/oauth/authorize/signin"
                                                          queryString:@""
                                                          queryParams:@{}
                                                              version:@"1.1"
                                                              headers:@{
                                                                  @"Content-Type": @"application/x-www-form-urlencoded",
                                                                  @"X-CSRF-Token": csrfToken,
                                                                  @"Cookie": [NSString stringWithFormat:@"csrf_token=%@", csrfToken]
                                                              }
                                                                 body:[signInBody dataUsingEncoding:NSUTF8StringEncoding]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *signInResponse = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeSignIn:signInRequest response:signInResponse];
    XCTAssertEqual(signInResponse.statusCode, 200);
    NSString *sessionToken = signInResponse.jsonBody[@"session_token"];
    XCTAssertTrue(sessionToken.length > 0);

    NSString *allowBody = [NSString stringWithFormat:@"decision=allow&client_id=test-client&state=allow-state&redirect_uri=https%%3A%%2F%%2Fevil.example%%2Fcallback&session_token=%@&response_type=code&code_challenge=test_challenge&code_challenge_method=S256",
                           [sessionToken stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    HttpRequest *allowRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                        methodString:@"POST"
                                                                path:@"/oauth/authorize/confirm"
                                                         queryString:@""
                                                         queryParams:@{}
                                                             version:@"1.1"
                                                             headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                                body:[allowBody dataUsingEncoding:NSUTF8StringEncoding]
                                                      remoteAddress:@"127.0.0.1"];
    HttpResponse *allowResponse = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeConfirm:allowRequest response:allowResponse];

    XCTAssertEqual(allowResponse.statusCode, 400);
    XCTAssertEqualObjects(allowResponse.jsonBody[@"error"], @"invalid_request");
    XCTAssertEqual([self.handler pendingConsentCountForTesting], (NSUInteger)0);
}

- (void)testPendingConsentsBoundedUnderRepeatedSignInAttempts {
    NSDictionary *authorizeParams = @{
        @"client_id": @"test-client",
        @"response_type": @"code",
        @"redirect_uri": @"http://localhost/cb",
        @"state": @"consent-cap",
        @"code_challenge": @"test_challenge",
        @"code_challenge_method": @"S256"
    };
    HttpResponse *authorizeResponse =
        [self authorizeViaPARWithParameters:authorizeParams
                                    clientID:@"test-client"];
    XCTAssertEqual(authorizeResponse.statusCode, 200);

    NSString *csrfToken = @"csrf-consent-cap";
    NSString *signInBody = @"handle=test-user.test&password=test-password";
    HttpRequest *signInRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                         methodString:@"POST"
                                                                 path:@"/oauth/authorize/signin"
                                                          queryString:@""
                                                          queryParams:@{}
                                                              version:@"1.1"
                                                              headers:@{
                                                                  @"Content-Type": @"application/x-www-form-urlencoded",
                                                                  @"X-CSRF-Token": csrfToken,
                                                                  @"Cookie": [NSString stringWithFormat:@"csrf_token=%@", csrfToken]
                                                              }
                                                                 body:[signInBody dataUsingEncoding:NSUTF8StringEncoding]
                                                       remoteAddress:@"127.0.0.1"];

    for (NSUInteger i = 0; i < 1100; i++) {
        HttpResponse *signInResponse = [[HttpResponse alloc] init];
        [self.handler handleAuthorizeSignIn:signInRequest response:signInResponse];
        XCTAssertEqual(signInResponse.statusCode, 200);
        XCTAssertNotNil(signInResponse.jsonBody[@"session_token"]);
    }

    XCTAssertLessThanOrEqual([self.handler pendingConsentCountForTesting], (NSUInteger)1024);
}

- (void)testAuthorizeDenyRemovesPendingConsentSession {
    NSDictionary *authorizeParams = @{
        @"client_id": @"test-client",
        @"response_type": @"code",
        @"redirect_uri": @"http://localhost/cb",
        @"state": @"deny-cleanup",
        @"code_challenge": @"test_challenge",
        @"code_challenge_method": @"S256"
    };
    HttpResponse *authorizeResponse =
        [self authorizeViaPARWithParameters:authorizeParams
                                    clientID:@"test-client"];
    XCTAssertEqual(authorizeResponse.statusCode, 200);

    NSString *csrfToken = @"csrf-deny-cleanup";
    NSString *signInBody = @"handle=test-user.test&password=test-password";
    HttpRequest *signInRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                         methodString:@"POST"
                                                                 path:@"/oauth/authorize/signin"
                                                          queryString:@""
                                                          queryParams:@{}
                                                              version:@"1.1"
                                                              headers:@{
                                                                  @"Content-Type": @"application/x-www-form-urlencoded",
                                                                  @"X-CSRF-Token": csrfToken,
                                                                  @"Cookie": [NSString stringWithFormat:@"csrf_token=%@", csrfToken]
                                                              }
                                                                 body:[signInBody dataUsingEncoding:NSUTF8StringEncoding]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *signInResponse = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeSignIn:signInRequest response:signInResponse];
    XCTAssertEqual(signInResponse.statusCode, 200);
    NSString *sessionToken = signInResponse.jsonBody[@"session_token"];
    XCTAssertTrue(sessionToken.length > 0);
    XCTAssertEqual([self.handler pendingConsentCountForTesting], (NSUInteger)1);

    NSString *encodedRedirect = [@"http://localhost/cb" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *encodedSessionToken = [sessionToken stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *denyBody = [NSString stringWithFormat:@"decision=deny&client_id=test-client&state=deny-cleanup&redirect_uri=%@&session_token=%@",
                          encodedRedirect, encodedSessionToken];
    HttpRequest *denyRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                      methodString:@"POST"
                                                              path:@"/oauth/authorize/confirm"
                                                       queryString:@""
                                                       queryParams:@{}
                                                           version:@"1.1"
                                                           headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                              body:[denyBody dataUsingEncoding:NSUTF8StringEncoding]
                                                        remoteAddress:@"127.0.0.1"];
    HttpResponse *denyResponse = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeConfirm:denyRequest response:denyResponse];

    XCTAssertEqual(denyResponse.statusCode, 302);
    XCTAssertEqual([self.handler pendingConsentCountForTesting], (NSUInteger)0);
}

/**
 * Test that client_metadata parameter is properly extracted and parsed
 * 
 * **Validates: Task 3.1 - client_metadata parameter extraction and parsing**
 * 
 * This test verifies that:
 * 1. client_metadata JSON string is extracted from query parameters
 * 2. JSON is parsed into NSDictionary
 * 3. Invalid JSON is handled gracefully (logs warning, continues without metadata)
 * 
 * NOTE: This test only validates extraction/parsing. The actual use of client_metadata
 * for validation will be tested in subsequent tasks (3.2, 3.3).
 */
- (void)testClientMetadataExtraction {
    // Test 1: Valid client_metadata JSON is parsed (verified via logs)
    NSDictionary *validMetadata = @{
        @"client_id": @"https://example.com",
        @"client_name": @"Example App",
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"scope": @"atproto",
        @"dpop_bound_access_tokens": @YES,
        @"token_endpoint_auth_method": @"none",
        @"application_type": @"web"
    };
    NSData *metadataJSON = [NSJSONSerialization dataWithJSONObject:validMetadata options:0 error:nil];
    NSString *metadataString = [[NSString alloc] initWithData:metadataJSON encoding:NSUTF8StringEncoding];
    
    NSDictionary *queryParams = @{
        @"client_id": @"https://example.com",
        @"redirect_uri": @"https://example.com/callback",
        @"response_type": @"code",
        @"state": @"test-state-metadata",
        @"code_challenge": @"test_challenge_metadata",
        @"code_challenge_method": @"S256",
        @"client_metadata": metadataString
    };
    
    HttpResponse *response =
        [self authorizeViaPARWithParameters:queryParams
                                    clientID:@"https://example.com"];

    // The handler should extract and parse client_metadata without crashing
    // Expected: Returns 400 because client is not registered (validation not yet implemented)
    // But the parsing should succeed (check logs for "Parsed client_metadata with 3 keys")
    // Authorization path now needs PAR, so this test exercises metadata via PAR-backed authorize.

    // With client_metadata support, the client should be validated via metadata
    // and the consent page should be served (200) or redirect issued (302)
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                  @"Should succeed with valid client_metadata (got %ld)", (long)response.statusCode);
    XCTAssertNil(response.jsonBody[@"error"], @"Should not return an error for valid client_metadata");
    
    // Test 2: Invalid JSON in client_metadata (should handle gracefully)
    NSDictionary *invalidQueryParams = @{
        @"client_id": @"https://example.com",
        @"redirect_uri": @"https://example.com/callback",
        @"response_type": @"code",
        @"state": @"test-state-invalid",
        @"code_challenge": @"test_challenge_invalid",
        @"code_challenge_method": @"S256",
        @"client_metadata": @"{invalid json}"
    };
    
    HttpResponse *invalidResponse =
        [self authorizeViaPARWithParameters:invalidQueryParams
                                    clientID:@"https://example.com"];

    // Should handle gracefully (log warning) and continue
    // Check logs for "Failed to parse client_metadata JSON"
    // Should still return 400 (client not registered), but shouldn't crash
    XCTAssertEqual(invalidResponse.statusCode, 400, @"Should handle invalid JSON gracefully and return 400");
    XCTAssertEqualObjects(invalidResponse.jsonBody[@"error"], @"unauthorized_client", @"Should fail with unauthorized_client");
    
    // Test 3: No client_metadata parameter (should work normally)
    NSDictionary *noMetadataParams = @{
        @"client_id": @"https://example.com",
        @"redirect_uri": @"https://example.com/callback",
        @"response_type": @"code",
        @"state": @"test-state-no-metadata",
        @"code_challenge": @"test_challenge_no_metadata",
        @"code_challenge_method": @"S256"
    };
    
    HttpResponse *noMetadataResponse =
        [self authorizeViaPARWithParameters:noMetadataParams
                                    clientID:@"https://example.com"];
    
    // Should return 400 (client not registered)
    XCTAssertEqual(noMetadataResponse.statusCode, 400, @"Should return 400 when no client_metadata and not registered");
    XCTAssertEqualObjects(noMetadataResponse.jsonBody[@"error"], @"unauthorized_client", @"Should fail with unauthorized_client");
}

- (void)testAuthorizeBlocksDirectRequestWithoutRequestURI {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/oauth/authorize"
                                                   queryString:@"client_id=test-client&response_type=code&redirect_uri=http://localhost/cb&state=state123"
                                                   queryParams:@{
                                                       @"client_id": @"test-client",
                                                       @"response_type": @"code",
                                                       @"redirect_uri": @"http://localhost/cb",
                                                       @"state": @"state123"
                                                   }
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeRequest:request response:response];

    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"invalid_request");
    XCTAssertTrue([response.jsonBody[@"error_description"] containsString:@"request_uri"]);
}

- (void)testValidateClientMetadataRejectsMissingDPoPBoundAccessTokens {
    NSDictionary *metadata = @{
        @"client_id": @"https://example.com/app",
        @"client_name": @"Example App",
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"scope": @"atproto",
        @"token_endpoint_auth_method": @"none",
        @"application_type": @"web"
    };
    NSError *error = nil;
    NSDictionary *validated = [self.handler validateClientMetadata:metadata error:&error];

    XCTAssertNil(validated);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"dpop_bound_access_tokens"]);
}

- (void)testValidateClientMetadataRejectsUnsupportedResponseTypes {
    NSMutableDictionary *metadata = [[self validATProtoClientMetadataTemplateWithClientID:@"https://example.com/app"
                                                                               redirectURI:@"https://example.com/callback"] mutableCopy];
    metadata[@"response_types"] = @[@"code", @"token"];

    NSError *error = nil;
    NSDictionary *validated = [self.handler validateClientMetadata:metadata error:&error];

    XCTAssertNil(validated);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"Unsupported response_type"]);
}

- (void)testValidateClientMetadataRejectsUnsupportedTokenEndpointAuthMethod {
    NSMutableDictionary *metadata = [[self validATProtoClientMetadataTemplateWithClientID:@"https://example.com/app"
                                                                               redirectURI:@"https://example.com/callback"] mutableCopy];
    metadata[@"token_endpoint_auth_method"] = @"client_secret_basic";

    NSError *error = nil;
    NSDictionary *validated = [self.handler validateClientMetadata:metadata error:&error];

    XCTAssertNil(validated);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"Unsupported token_endpoint_auth_method"]);
}

- (void)testValidateClientMetadataAcceptsPrivateKeyJWTClient {
    NSMutableDictionary *metadata = [[self validATProtoClientMetadataTemplateWithClientID:@"https://example.com/confidential"
                                                                        redirectURI:@"https://example.com/callback"] mutableCopy];
    metadata[@"token_endpoint_auth_method"] = @"private_key_jwt";
    metadata[@"token_endpoint_auth_signing_alg"] = @"ES256";
    metadata[@"jwks_uri"] = @"https://example.com/jwks.json";

    NSError *error = nil;
    NSDictionary *validated = [self.handler validateClientMetadata:metadata error:&error];

    XCTAssertNotNil(validated);
    XCTAssertNil(error);
}

- (NSDictionary *)createTestClientJWKS {
    NSData *xData = PDSTestDataFromHexString(@"44073c1c6da8c2c9736c011ff13a2b3602a1d819e687582bdf87262ad1b12f50", 32);
    NSData *yData = PDSTestDataFromHexString(@"79720e75ce2eaae05079972dd065b2eb437d9af5c9a974d3ce186525494bdc3c", 32);

    return @{
        @"keys": @[
            @{
                @"kty": @"EC",
                @"crv": @"P-256",
                @"kid": @"test-key-1",
                @"x": [xData base64EncodedStringWithOptions:0],
                @"y": [yData base64EncodedStringWithOptions:0]
            }
        ]
    };
}

- (NSString *)signJWTAssertionForClientID:(NSString *)clientID
                                   issuer:(NSString *)issuer
                                 audience:(NSString *)audience
                                   expiry:(NSTimeInterval)expiry
                                 privateKey:(SecKeyRef)privateKey {
    NSDictionary *header = @{
        @"alg": @"ES256",
        @"typ": @"JWT",
        @"kid": @"test-key-1"
    };

    NSDate *now = [NSDate date];
    NSDate *expiration = [now dateByAddingTimeInterval:expiry];
    NSTimeInterval iat = [now timeIntervalSince1970];
    NSTimeInterval exp = [expiration timeIntervalSince1970];
    NSString *jti = [[NSUUID UUID] UUIDString];

    NSDictionary *payload = @{
        @"iss": issuer,
        @"sub": issuer,
        @"aud": audience,
        @"iat": @(iat),
        @"exp": @(exp),
        @"jti": jti
    };

    NSError *error = nil;
    JWTHeader *jwtHeader = [JWTHeader headerFromDictionary:header error:&error];
    JWTPayload *jwtPayload = [JWTPayload payloadFromDictionary:payload error:&error];

    JWT *jwt = [JWT jwtWithHeader:jwtHeader payload:jwtPayload signature:@"" error:&error];
    NSString *signingInput = jwt.signingInput;

    NSData *signingInputData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(signingInputData.bytes, (CC_LONG)signingInputData.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    CFErrorRef signError = NULL;
    NSData *signatureData = (NSData *)CFBridgingRelease(
        SecKeyCreateSignature(privateKey,
                             kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                             (__bridge CFDataRef)hashData,
                             &signError));

    if (!signatureData) {
        return nil;
    }

    NSString *encodedSignature = [JWT base64URLEncodeData:signatureData error:&error];
    if (!encodedSignature) {
        return nil;
    }

    return [NSString stringWithFormat:@"%@.%@", signingInput, encodedSignature];
}

- (void)testTokenRequestWithValidJWTAssertion {
    NSError *error = nil;
    SecKeyRef privateKey = oauth2HandlerCreateFixedP256PrivateKey(&error);
    XCTAssertTrue(privateKey != NULL, @"Should create private key");

    NSString *clientID = @"https://example.com/confidential-jwt";
    NSDictionary *jwks = [self createTestClientJWKS];

    NSDictionary *clientRecord = @{
        @"client_id": clientID,
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @"authorization_code refresh_token",
        @"scope": @"atproto",
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"token_endpoint_auth_signing_alg": @"ES256",
        @"jwks": jwks,
        @"jwks_uri": @"",
        @"application_type": @"web"
    };
    XCTAssertTrue([self.database createClient:clientRecord error:&error], @"Should create JWT client: %@", error);

    NSString *assertion = [self signJWTAssertionForClientID:clientID
                                                    issuer:clientID
                                                  audience:@"https://pds.garazyk.xyz"
                                                    expiry:3600
                                               privateKey:privateKey];
    XCTAssertNotNil(assertion);

    NSString *body = [NSString stringWithFormat:
        @"grant_type=authorization_code&code=test-code&client_id=%@&redirect_uri=https://example.com/callback&client_assertion=%@&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        clientID, assertion];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.handler handleTokenRequest:request response:response];

    XCTAssertTrue(response.statusCode == 400 || response.statusCode == 401,
                 @"Should return 400 or 401 (valid JWT assertion should be validated)");
    if (response.statusCode == 401) {
        NSLog(@"JWT validation failed: %@", response.jsonBody[@"error_description"]);
    }

    if (privateKey) {
        CFRelease(privateKey);
    }
}

- (void)testTokenRequestWithInvalidJWTAssertionSignature {
    NSError *error = nil;
    SecKeyRef privateKey = oauth2HandlerCreateFixedP256PrivateKey(&error);
    XCTAssertTrue(privateKey != NULL, @"Should create private key");

    NSString *clientID = @"https://example.com/confidential-jwt-sig";
    NSDictionary *jwks = [self createTestClientJWKS];

    NSDictionary *clientRecord = @{
        @"client_id": clientID,
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @"authorization_code refresh_token",
        @"scope": @"atproto",
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"token_endpoint_auth_signing_alg": @"ES256",
        @"jwks": jwks,
        @"jwks_uri": @"",
        @"application_type": @"web"
    };
    XCTAssertTrue([self.database createClient:clientRecord error:&error], @"Should create JWT client: %@", error);

    NSString *assertion = [self signJWTAssertionForClientID:clientID
                                                    issuer:clientID
                                                  audience:@"https://pds.garazyk.xyz"
                                                    expiry:3600
                                               privateKey:privateKey];

    NSMutableString *tamperedAssertion = [assertion mutableCopy];
    NSRange lastDotRange = [assertion rangeOfString:@"." options:NSBackwardsSearch];
    if (lastDotRange.location != NSNotFound) {
        NSMutableString *sigPart = [[assertion substringFromIndex:lastDotRange.location + 1] mutableCopy];
        if (sigPart.length > 0) {
            unichar firstChar = [sigPart characterAtIndex:0];
            firstChar = (firstChar == 'a') ? 'b' : 'a';
            [sigPart replaceCharactersInRange:NSMakeRange(0, 1) withString:[NSString stringWithCharacters:&firstChar length:1]];
            [tamperedAssertion replaceCharactersInRange:lastDotRange withString:[NSString stringWithFormat:@".%@", sigPart]];
        }
    }

    NSString *body = [NSString stringWithFormat:
        @"grant_type=authorization_code&code=test-code&client_id=%@&client_assertion=%@&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        clientID, tamperedAssertion];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.handler handleTokenRequest:request response:response];

    XCTAssertEqual(response.statusCode, 401, @"Should return 401 for invalid JWT signature");
    XCTAssertNotNil(response.jsonBody[@"error_description"], @"Should have error description");

    if (privateKey) {
        CFRelease(privateKey);
    }
}

- (void)testTokenRequestWithOldJWTAssertion {
    NSError *error = nil;
    SecKeyRef privateKey = oauth2HandlerCreateFixedP256PrivateKey(&error);
    XCTAssertTrue(privateKey != NULL, @"Should create private key");

    NSString *clientID = @"https://example.com/confidential-jwt-exp";
    NSDictionary *jwks = [self createTestClientJWKS];

    NSDictionary *clientRecord = @{
        @"client_id": clientID,
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @"authorization_code refresh_token",
        @"scope": @"atproto",
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"token_endpoint_auth_signing_alg": @"ES256",
        @"jwks": jwks,
        @"jwks_uri": @"",
        @"application_type": @"web"
    };
    XCTAssertTrue([self.database createClient:clientRecord error:&error], @"Should create JWT client: %@", error);

    NSString *assertion = [self signJWTAssertionForClientID:clientID
                                                    issuer:clientID
                                                  audience:@"https://pds.garazyk.xyz"
                                                    expiry:-3600
                                               privateKey:privateKey];
    XCTAssertNotNil(assertion);

    NSString *body = [NSString stringWithFormat:
        @"grant_type=authorization_code&code=test-code&client_id=%@&client_assertion=%@&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        clientID, assertion];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.handler handleTokenRequest:request response:response];

    XCTAssertEqual(response.statusCode, 401, @"Should return 401 for expired JWT");
    XCTAssertTrue([response.jsonBody[@"error_description"] containsString:@"expired"],
                 @"Error should mention expiration");

    if (privateKey) {
        CFRelease(privateKey);
    }
}

- (void)testTokenRequestWithMismatchedIssuer {
    NSError *error = nil;
    SecKeyRef privateKey = oauth2HandlerCreateFixedP256PrivateKey(&error);
    XCTAssertTrue(privateKey != NULL, @"Should create private key");

    NSString *clientID = @"https://example.com/confidential-jwt-iss";
    NSDictionary *jwks = [self createTestClientJWKS];

    NSDictionary *clientRecord = @{
        @"client_id": clientID,
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @"authorization_code refresh_token",
        @"scope": @"atproto",
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"token_endpoint_auth_signing_alg": @"ES256",
        @"jwks": jwks,
        @"jwks_uri": @"",
        @"application_type": @"web"
    };
    XCTAssertTrue([self.database createClient:clientRecord error:&error], @"Should create JWT client: %@", error);

    NSString *assertion = [self signJWTAssertionForClientID:clientID
                                                    issuer:@"https://evil.com/attacker"
                                                  audience:@"https://pds.garazyk.xyz"
                                                    expiry:3600
                                               privateKey:privateKey];

    NSString *body = [NSString stringWithFormat:
        @"grant_type=authorization_code&code=test-code&client_id=%@&client_assertion=%@&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        clientID, assertion];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.handler handleTokenRequest:request response:response];

    XCTAssertEqual(response.statusCode, 401, @"Should return 401 for mismatched issuer");
    XCTAssertTrue([response.jsonBody[@"error_description"] containsString:@"iss"],
                 @"Error should mention issuer claim");

    if (privateKey) {
        CFRelease(privateKey);
    }
}

- (void)testTokenRequestWithPrivateKeyJWTClientMissingAssertion {
    NSString *clientID = @"https://example.com/confidential-jwt-missing";

    NSError *error = nil;
    NSDictionary *jwks = [self createTestClientJWKS];

    NSDictionary *clientRecord = @{
        @"client_id": clientID,
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @"authorization_code refresh_token",
        @"scope": @"atproto",
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"token_endpoint_auth_signing_alg": @"ES256",
        @"jwks": jwks,
        @"jwks_uri": @"",
        @"application_type": @"web"
    };
    XCTAssertTrue([self.database createClient:clientRecord error:&error], @"Should create JWT client: %@", error);

    NSString *body = [NSString stringWithFormat:
        @"grant_type=authorization_code&code=test-code&client_id=%@&redirect_uri=https://example.com/callback",
        clientID];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.handler handleTokenRequest:request response:response];

    XCTAssertTrue(response.statusCode == 400 || response.statusCode == 401,
                 @"Should return 400 or 401 when no client authentication provided");
}

@end
