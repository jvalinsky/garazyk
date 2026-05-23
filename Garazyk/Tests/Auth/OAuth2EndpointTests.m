// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/OAuth2Handler.h"
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
    // Test token exchange with authorization code
    NSString *url = [self.baseURL stringByAppendingString:@"/oauth/token"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    NSString *body = @"grant_type=authorization_code&client_id=test-client&redirect_uri=http://localhost:3000/callback&code=test-auth-code&code_verifier=test-verifier";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    
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
