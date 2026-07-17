// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/OAuth2Handler.h"
#import "Auth/OAuth2.h"
#import "Auth/PKCEUtil.h"
#import "Auth/DPoPUtil.h"
#import "Auth/TestKeyFixtures.h"
#import "Database/PDSDatabase.h"

@interface OAuth2EndpointTests : XCTestCase
@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, strong) OAuth2Handler *oauthHandler;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *tempPath;
@end

@implementation OAuth2EndpointTests

- (void)setUp {
    [super setUp];
    
    self.tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"oauth-test-%@.db", NSUUID.UUID.UUIDString]];
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:self.tempPath]];
    NSError *error = nil;
    [self.database openWithError:&error];

    self.server = [HttpServer serverWithPort:0];
    self.oauthHandler = [[OAuth2Handler alloc] initWithDatabase:self.database];
    [self.oauthHandler registerRoutesWithServer:self.server];

    // Register "test-client" as a valid OAuth client; without it,
    // validatedClientForClientID: rejects every request below before
    // reaching the behavior under test (mirrors OAuthIntegrationTests).
    NSDictionary *testClient = @{
        @"client_id": @"test-client",
        @"client_secret": @"test-secret",
        @"redirect_uris": @[@"http://localhost:3000/callback"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    [self.database createClient:testClient error:nil];

    // The token exchange resolves the authorization code's login_hint_did to
    // an account (for its handle); without one, it fails before ever
    // reaching scope/token issuance.
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:test-user-did";
    account.handle = @"test-user.test";
    account.email = @"test@test.com";
    [self.database createAccount:account error:nil];
    NSError *startError = nil;
    if (![self.server startWithError:&startError]) {
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
        }
        XCTFail(@"Failed to start OAuth test server: %@", startError);
        return;
    }
    self.baseURL = [NSString stringWithFormat:@"http://127.0.0.1:%lu",
                                              (unsigned long)self.server.port];
}

- (void)tearDown {
    [self.server stop];
    [self.database close];
    self.server = nil;
    self.database = nil;
    self.oauthHandler = nil;
    self.baseURL = nil;
    if (self.tempPath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempPath error:nil];
        self.tempPath = nil;
    }
    [super tearDown];
}

#pragma mark - Authorization Endpoint Tests

#ifndef GNUSTEP
- (void)testOAuthAuthorizeEndpointRequiresRequestURI {
    NSString *url = [self.baseURL stringByAppendingString:@"/oauth/authorize?client_id=test-client&redirect_uri=http://localhost:3000/callback&response_type=code&scope=atproto:identify&state=test123"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"GET";
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth authorize PAR required"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        XCTAssertEqual(httpResponse.statusCode, 400, @"Should reject direct authorize requests when request_uri is missing");

        if (data.length > 0) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            XCTAssertEqualObjects(json[@"error"], @"invalid_request");
        }
        
        [expectation fulfill];
    }];
    
    [task resume];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testOAuthAuthorizeEndpointBlocksBadClient {
    // Test with invalid client_id
    NSString *url = [self.baseURL stringByAppendingString:@"/oauth/authorize?client_id=invalid-client&redirect_uri=http://localhost:3000/callback&response_type=code"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"GET";
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth authorize invalid client"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        XCTAssertEqual(httpResponse.statusCode, 400, @"Should return 400 for invalid client");
        
        [expectation fulfill];
    }];
    
    [task resume];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}
#endif

#pragma mark - Token Endpoint Tests

#ifndef GNUSTEP
- (void)testOAuthTokenEndpointExchangesCodeForTokens {
    // A real exchange needs a genuinely-issued authorization code (PKCE
    // challenge bound to the verifier sent below) and a DPoP-bound request;
    // an ad hoc code/verifier pair can only ever hit invalid_grant, which is
    // correct AT Protocol OAuth behavior, not something to relax server-side.
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];

    NSString *tokenUri = [self.baseURL stringByAppendingString:@"/oauth/token"];

    NSError *keyError = nil;
    SecKeyRef privateKey = PDSTestCreateFixedP256PrivateKey(&keyError);
    XCTAssertNotNil((__bridge id)privateKey, @"Failed to import DPoP key: %@", keyError);

    NSString *(^seedAuthCode)(void) = ^NSString * {
        NSString *code = [[NSUUID UUID] UUIDString];
        self.oauthHandler.oauthServer.authorizationCodes[code] = @{
            @"client_id": @"test-client",
            @"redirect_uri": @"http://localhost:3000/callback",
            @"scope": OAuth2ScopeAtproto,
            @"state": @"test123",
            @"code_challenge": challenge,
            @"code_challenge_method": @"S256",
            @"login_hint": @"test-user.test",
            @"login_hint_did": @"did:plc:test-user-did",
            @"created_at": @([[NSDate date] timeIntervalSince1970])
        };
        return code;
    };

    // First request: no DPoP nonce yet, server challenges with one.
    NSString *authCode1 = seedAuthCode();
    DPoPToken *dpopToken1 = [DPoPUtil createDPoPForMethod:@"POST" uri:tokenUri nonce:nil key:privateKey error:nil];
    XCTAssertNotNil(dpopToken1, @"Failed to create DPoP token");

    NSMutableURLRequest *nonceRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:tokenUri]];
    nonceRequest.HTTPMethod = @"POST";
    [nonceRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [nonceRequest setValue:dpopToken1.jwt forHTTPHeaderField:@"DPoP"];
    nonceRequest.HTTPBody = [[NSString stringWithFormat:@"grant_type=authorization_code&client_id=test-client&redirect_uri=http://localhost:3000/callback&code=%@&code_verifier=%@", authCode1, verifier] dataUsingEncoding:NSUTF8StringEncoding];

    XCTestExpectation *nonceExpectation = [self expectationWithDescription:@"DPoP nonce challenge"];
    __block NSString *dpopNonce = nil;
    [[[NSURLSession sharedSession] dataTaskWithRequest:nonceRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dpopNonce = [(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"DPoP-Nonce"];
        [nonceExpectation fulfill];
    }] resume];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertNotNil(dpopNonce, @"Server should return DPoP-Nonce header");

    // Second request: real DPoP proof with the server-issued nonce, and a
    // freshly-seeded code (the first was consumed by the challenge above).
    NSString *authCode2 = seedAuthCode();
    DPoPToken *dpopToken2 = [DPoPUtil createDPoPForMethod:@"POST" uri:tokenUri nonce:dpopNonce key:privateKey error:nil];
    XCTAssertNotNil(dpopToken2, @"Failed to create DPoP token with nonce");

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:tokenUri]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:dpopToken2.jwt forHTTPHeaderField:@"DPoP"];
    request.HTTPBody = [[NSString stringWithFormat:@"grant_type=authorization_code&client_id=test-client&redirect_uri=http://localhost:3000/callback&code=%@&code_verifier=%@", authCode2, verifier] dataUsingEncoding:NSUTF8StringEncoding];

    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth token exchange"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        XCTAssertEqual(httpResponse.statusCode, 200, @"Should return 200 for valid token exchange");

        // Parse JSON response
        if (data) {
            NSError *jsonError;
            NSDictionary *tokenResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

            XCTAssertNotNil(tokenResponse, @"Should return JSON response");
            XCTAssertNotNil(tokenResponse[@"access_token"], @"Should include access_token");
            XCTAssertEqualObjects(tokenResponse[@"token_type"], @"DPoP", @"Should have DPoP token type");
            XCTAssertNotNil(tokenResponse[@"refresh_token"], @"Should include refresh_token");
            XCTAssertNotNil(tokenResponse[@"expires_in"], @"Should include expires_in");
        }

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    if (privateKey) CFRelease(privateKey);
}
#endif

#ifndef GNUSTEP
- (void)testOAuthTokenEndpointBlocksBadClient {
    // Test with invalid client_id
    NSString *url = [self.baseURL stringByAppendingString:@"/oauth/token"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    NSString *body = @"grant_type=authorization_code&client_id=invalid-client&code=test-code";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth token invalid client"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        XCTAssertEqual(httpResponse.statusCode, 401, @"Should return 401 for invalid client");
        
        [expectation fulfill];
    }];
    
    [task resume];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}
#endif

#pragma mark - Revoke Endpoint Tests

#ifndef GNUSTEP
- (void)testOAuthRevokeEndpointReturnsStatus200ForSuccessfulRevocation {
    // Test token revocation
    NSString *url = [self.baseURL stringByAppendingString:@"/oauth/revoke"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    NSString *body = @"client_id=test-client&token=test-access-token";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth token revocation"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should return 200 for successful revocation");
        
        [expectation fulfill];
    }];
    
    [task resume];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}
#endif

@end
