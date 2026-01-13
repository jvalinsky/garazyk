#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/OAuth2Handler.h"

@interface OAuth2EndpointTests : XCTestCase
@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, strong) OAuth2Handler *oauthHandler;
@end

@implementation OAuth2EndpointTests

- (void)setUp {
    [super setUp];
    
    self.server = [HttpServer serverWithPort:8443];
    self.oauthHandler = [[OAuth2Handler alloc] init];
    [self.oauthHandler registerRoutesWithServer:self.server];
    
    NSError *error = nil;
    if (![self.server startWithError:&error]) {
        NSLog(@"Failed to start server: %@", error);
    }
}

- (void)tearDown {
    [self.server stop];
    self.server = nil;
    self.oauthHandler = nil;
    [super tearDown];
}

#pragma mark - Authorization Endpoint Tests

- (void)testOAuthAuthorizeEndpointReturnsRedirectForValidRequest {
    NSLog(@"[VERIFY_UPDATE] testOAuthAuthorizeEndpointReturnsRedirectForValidRequest starting with 15s timeout");
    // This test should fail initially since we haven't implemented the handler yet
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8443/oauth/authorize?client_id=test-client&redirect_uri=http://localhost:3000/callback&response_type=code&scope=atproto:identify&state=test123"]];
    request.HTTPMethod = @"GET";
    
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth authorize request"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        NSLog(@"[TEST DEBUG] Status: %ld, Error: %@", (long)httpResponse.statusCode, error);
        if (data) {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[TEST DEBUG] Body: %@", body);
        }
        
        // Should be 302 redirect
        XCTAssertEqual(httpResponse.statusCode, 302, @"Should return 302 redirect");
        
        // Should have Location header with redirect
        NSString *location = httpResponse.allHeaderFields[@"Location"];
        XCTAssertNotNil(location, @"Should have Location header");
        XCTAssertTrue([location containsString:@"http://localhost:3000/callback"], @"Should redirect to callback URL");
        XCTAssertTrue([location containsString:@"code="], @"Should include authorization code");
        XCTAssertTrue([location containsString:@"state=test123"], @"Should preserve state parameter");
        
        [expectation fulfill];
    }];
    
    [task resume];
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testOAuthAuthorizeEndpointRejectsInvalidClient {
    NSLog(@"[VERIFY_UPDATE] testOAuthAuthorizeEndpointRejectsInvalidClient starting with 15s timeout");
    // Test with invalid client_id
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8443/oauth/authorize?client_id=invalid-client&redirect_uri=http://localhost:3000/callback&response_type=code"]];
    request.HTTPMethod = @"GET";
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth authorize invalid client"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        XCTAssertEqual(httpResponse.statusCode, 400, @"Should return 400 for invalid client");
        
        [expectation fulfill];
    }];
    
    [task resume];
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

#pragma mark - Token Endpoint Tests

- (void)testOAuthTokenEndpointExchangesCodeForTokens {
    NSLog(@"[VERIFY_UPDATE] testOAuthTokenEndpointExchangesCodeForTokens starting with 15s timeout");
    // Test token exchange with authorization code
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8443/oauth/token"]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    
    NSString *body = @"grant_type=authorization_code&client_id=test-client&redirect_uri=http://localhost:3000/callback&code=test-auth-code&code_verifier=test-verifier";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth token exchange"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        NSLog(@"[TEST DEBUG] Token Status: %ld, Error: %@", (long)httpResponse.statusCode, error);
        if (data) {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[TEST DEBUG] Token Body: %@", body);
        }
        
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
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testOAuthTokenEndpointRejectsInvalidClient {
    NSLog(@"[VERIFY_UPDATE] testOAuthTokenEndpointRejectsInvalidClient starting with 15s timeout");
    // Test with invalid client_id
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8443/oauth/token"]];
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
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

#pragma mark - Revoke Endpoint Tests

- (void)testOAuthRevokeEndpointRevokesTokens {
    NSLog(@"[VERIFY_UPDATE] testOAuthRevokeEndpointRevokesTokens starting with 15s timeout");
    // Test token revocation
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8443/oauth/revoke"]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    
    NSString *body = @"client_id=test-client&token=test-access-token";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"OAuth token revocation"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should return 200 for successful revocation");
        
        [expectation fulfill];
    }];
    
    [task resume];
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testDirectOAuthHandlerLogic {
    NSLog(@"[TEST] Starting Direct OAuth Handler Logic Test");
    
    NSDictionary *params = @{
        @"client_id": @"test-client",
        @"redirect_uri": @"http://localhost:3000/callback",
        @"response_type": @"code",
        @"scope": @"atproto:identify",
        @"state": @"test123"
    };
    
    HttpRequest *manualRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                       methodString:@"GET"
                                                               path:@"/oauth/authorize"
                                                        queryString:@"client_id=test-client..." 
                                                        queryParams:params
                                                            version:@"HTTP/1.1"
                                                            headers:@{}
                                                               body:nil
                                                      remoteAddress:@"127.0.0.1"];
    
    HttpResponse *manualResponse = [HttpResponse response];
    
    // Invoke handler directly on the current thread
    [self.oauthHandler handleAuthorizeRequest:manualRequest response:manualResponse];
    
    NSLog(@"[TEST] Handler returned status: %ld", (long)manualResponse.statusCode);
    XCTAssertEqual(manualResponse.statusCode, 302, @"Direct handler should return 302");
    
    NSString *location = manualResponse.headers[@"Location"];
    NSLog(@"[TEST] Location header: %@", location);
    XCTAssertNotNil(location, @"Should have Location header");
    XCTAssertTrue([location containsString:@"code="], @"Should include authorization code");
}

@end