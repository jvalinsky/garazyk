/*!
 @file UIAuthManagerTests.m

 @abstract Unit tests for UIAuthManager.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AdminUIServer/UIAuthManager.h"
#import "Network/HttpRequest.h"

@interface UIAuthManagerTests : XCTestCase
@property (nonatomic, strong) UIAuthManager *authManager;
@end

@implementation UIAuthManagerTests

- (void)setUp {
    [super setUp];
    self.authManager = [[UIAuthManager alloc] initWithPassword:@"testpassword123"];
}

- (void)tearDown {
    self.authManager = nil;
    [super tearDown];
}

#pragma mark - createSessionToken Tests

/*!
 @test testCreateSessionTokenReturnsNonEmptyString

 @abstract Verify that createSessionToken returns a non-empty string.

 @discussion The method should generate and return a unique session token.
 */
- (void)testCreateSessionTokenReturnsNonEmptyString {
    NSString *token = [self.authManager createSessionToken];
    XCTAssertNotNil(token);
    XCTAssertGreaterThan(token.length, 0);
}

/*!
 @test testCreateSessionTokenReturnsUniqueTokens

 @abstract Verify that successive calls to createSessionToken return different tokens.
 */
- (void)testCreateSessionTokenReturnsUniqueTokens {
    NSString *token1 = [self.authManager createSessionToken];
    NSString *token2 = [self.authManager createSessionToken];
    XCTAssertNotEqualObjects(token1, token2);
}

#pragma mark - isAuthorizedRequest Tests

/*!
 @test testIsAuthorizedRequestWithNilRequest

 @abstract Verify that isAuthorizedRequest returns NO for a nil request.
 */
- (void)testIsAuthorizedRequestWithNilRequest {
    BOOL result = [self.authManager isAuthorizedRequest:nil];
    XCTAssertFalse(result);
}

/*!
 @test testIsAuthorizedRequestWithBearerToken

 @abstract Verify that isAuthorizedRequest returns YES when request contains a valid bearer token in Authorization header.
 */
- (void)testIsAuthorizedRequestWithBearerToken {
    // Create a session token
    NSString *token = [self.authManager createSessionToken];

    // Create a request with Bearer token in Authorization header
    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:nil
                                                    queryParams:nil
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:nil
                                                   remoteAddress:@"127.0.0.1"];

    BOOL result = [self.authManager isAuthorizedRequest:request];
    XCTAssertTrue(result);
}

/*!
 @test testIsAuthorizedRequestWithCookieToken

 @abstract Verify that isAuthorizedRequest returns YES when request contains a valid token in cookie.
 */
- (void)testIsAuthorizedRequestWithCookieToken {
    // Create a session token
    NSString *token = [self.authManager createSessionToken];

    // Create a request with token in cookie
    NSDictionary *headers = @{@"Cookie": [NSString stringWithFormat:@"ui_admin_token=%@", token]};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:nil
                                                    queryParams:nil
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:nil
                                                   remoteAddress:@"127.0.0.1"];

    BOOL result = [self.authManager isAuthorizedRequest:request];
    XCTAssertTrue(result);
}

/*!
 @test testIsAuthorizedRequestWithInvalidToken

 @abstract Verify that isAuthorizedRequest returns NO when request contains an invalid token.
 */
- (void)testIsAuthorizedRequestWithInvalidToken {
    // Create a request with invalid token
    NSDictionary *headers = @{@"Authorization": @"Bearer invalid-token-12345"};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:nil
                                                    queryParams:nil
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:nil
                                                   remoteAddress:@"127.0.0.1"];

    BOOL result = [self.authManager isAuthorizedRequest:request];
    XCTAssertFalse(result);
}

#pragma mark - invalidateSessionToken Tests

/*!
 @test testIsAuthorizedRequestAfterInvalidatingToken

 @abstract Verify that isAuthorizedRequest returns NO after invalidating a token.
 */
- (void)testIsAuthorizedRequestAfterInvalidatingToken {
    // Create a session token
    NSString *token = [self.authManager createSessionToken];

    // Verify it's authorized
    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:nil
                                                    queryParams:nil
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:nil
                                                   remoteAddress:@"127.0.0.1"];
    XCTAssertTrue([self.authManager isAuthorizedRequest:request]);

    // Invalidate the token
    [self.authManager invalidateSessionToken:token];

    // Verify it's no longer authorized
    XCTAssertFalse([self.authManager isAuthorizedRequest:request]);
}

#pragma mark - validatePassword Tests

/*!
 @test testValidatePasswordWithCorrectPassword

 @abstract Verify that validatePassword returns YES for the correct password.
 */
- (void)testValidatePasswordWithCorrectPassword {
    BOOL result = [self.authManager validatePassword:@"testpassword123"];
    XCTAssertTrue(result);
}

/*!
 @test testValidatePasswordWithWrongPassword

 @abstract Verify that validatePassword returns NO for an incorrect password.
 */
- (void)testValidatePasswordWithWrongPassword {
    BOOL result = [self.authManager validatePassword:@"wrongpassword"];
    XCTAssertFalse(result);
}

/*!
 @test testValidatePasswordWithNilPassword

 @abstract Verify that validatePassword returns NO for nil password.
 */
- (void)testValidatePasswordWithNilPassword {
    BOOL result = [self.authManager validatePassword:nil];
    XCTAssertFalse(result);
}

/*!
 @test testValidatePasswordWithEmptyPassword

 @abstract Verify that validatePassword returns NO for empty password.
 */
- (void)testValidatePasswordWithEmptyPassword {
    BOOL result = [self.authManager validatePassword:@""];
    XCTAssertFalse(result);
}

/*!
 @test testValidatePasswordWithEmptyAuthManagerPassword

 @abstract Verify that validatePassword returns NO when auth manager was initialized with empty password and tested with non-empty input.
 */
- (void)testValidatePasswordWithEmptyAuthManagerPassword {
    UIAuthManager *emptyAuthManager = [[UIAuthManager alloc] initWithPassword:@""];
    BOOL result = [emptyAuthManager validatePassword:@"somepassword"];
    XCTAssertFalse(result);
}

#pragma mark - extractTokenFromRequest Tests

/*!
 @test testExtractTokenFromRequestWithBearerToken

 @abstract Verify that extractTokenFromRequest correctly extracts a bearer token.
 */
- (void)testExtractTokenFromRequestWithBearerToken {
    NSString *token = @"test-token-12345";
    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:nil
                                                    queryParams:nil
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:nil
                                                   remoteAddress:@"127.0.0.1"];

    NSString *extracted = [self.authManager extractTokenFromRequest:request];
    XCTAssertEqualObjects(extracted, token);
}

/*!
 @test testExtractTokenFromRequestWithCookieToken

 @abstract Verify that extractTokenFromRequest correctly extracts a token from cookie.
 */
- (void)testExtractTokenFromRequestWithCookieToken {
    NSString *token = @"cookie-token-12345";
    NSDictionary *headers = @{@"Cookie": [NSString stringWithFormat:@"ui_admin_token=%@", token]};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:nil
                                                    queryParams:nil
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:nil
                                                   remoteAddress:@"127.0.0.1"];

    NSString *extracted = [self.authManager extractTokenFromRequest:request];
    XCTAssertEqualObjects(extracted, token);
}

/*!
 @test testExtractTokenFromRequestWithMultipleCookies

 @abstract Verify that extractTokenFromRequest correctly extracts ui_admin_token when multiple cookies are present.
 */
- (void)testExtractTokenFromRequestWithMultipleCookies {
    NSString *token = @"admin-token-xyz";
    NSDictionary *headers = @{@"Cookie": [NSString stringWithFormat:@"sessionId=abc123; ui_admin_token=%@; other=value", token]};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:nil
                                                    queryParams:nil
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:nil
                                                   remoteAddress:@"127.0.0.1"];

    NSString *extracted = [self.authManager extractTokenFromRequest:request];
    XCTAssertEqualObjects(extracted, token);
}

/*!
 @test testExtractTokenFromRequestWithNoToken

 @abstract Verify that extractTokenFromRequest returns nil when no token is present.
 */
- (void)testExtractTokenFromRequestWithNoToken {
    NSDictionary *headers = @{@"Content-Type": @"application/json"};
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/admin"
                                                   queryString:nil
                                                    queryParams:nil
                                                        version:@"HTTP/1.1"
                                                        headers:headers
                                                           body:nil
                                                   remoteAddress:@"127.0.0.1"];

    NSString *extracted = [self.authManager extractTokenFromRequest:request];
    XCTAssertNil(extracted);
}

@end
