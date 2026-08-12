// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UIAuthManagerTests.m

 @abstract Unit tests for GZAdminUIAuthManager.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AdminUIServer/UIAuthManager.h"
#import "Network/HttpRequest.h"

@interface UIAuthManagerTests : XCTestCase
@property (nonatomic, strong) GZAdminUIAuthManager *authManager;
@end

@implementation UIAuthManagerTests

- (void)setUp {
    [super setUp];
    self.authManager = [[GZAdminUIAuthManager alloc] initWithPassword:@"testpassword123"];
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
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
    GZAdminUIAuthManager *emptyAuthManager = [[GZAdminUIAuthManager alloc] initWithPassword:@""];
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
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

#pragma mark - Service-scoped cookie names

/*! Builds a GET request carrying the supplied Cookie header. */
- (ATProtoHttpRequest *)requestWithCookieHeader:(NSString *)cookieHeader {
    return [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:@"/admin"
                                   queryString:nil
                                   queryParams:nil
                                       version:@"HTTP/1.1"
                                       headers:@{@"Cookie": cookieHeader}
                                          body:nil
                                 remoteAddress:@"127.0.0.1"];
}

/*!
 @test testUnscopedManagerKeepsLegacyCookieNames

 @abstract Verify that a manager built without an identifier keeps the pre-existing names,
 so compatibility consumers are unaffected.
 */
- (void)testUnscopedManagerKeepsLegacyCookieNames {
    XCTAssertNil(self.authManager.serviceIdentifier);
    XCTAssertEqualObjects(self.authManager.sessionCookieName, @"ui_admin_token");
    XCTAssertEqualObjects(self.authManager.csrfCookieName, @"ui_admin_nonce");
}

/*!
 @test testServiceScopedManagerDerivesCookieNames

 @abstract Verify that an identifier produces distinct session and CSRF cookie names.
 */
- (void)testServiceScopedManagerDerivesCookieNames {
    GZAdminUIAuthManager *plc = [[GZAdminUIAuthManager alloc] initWithPassword:@"pw"
                                              serviceIdentifier:@"plc"];
    XCTAssertEqualObjects(plc.sessionCookieName, @"gz_admin_plc_token");
    XCTAssertEqualObjects(plc.csrfCookieName, @"gz_admin_plc_nonce");

    NSString *cookie = [plc cookieHeaderValueForToken:@"abc" secure:NO];
    XCTAssertTrue([cookie hasPrefix:@"gz_admin_plc_token=abc;"]);
}

/*!
 @test testScopedManagerIgnoresSiblingServiceCookie

 @abstract Verify that a UI does not read a sibling UI's session cookie.

 @discussion Cookies are not port-scoped, so two admin UIs on the same host receive each
 other's cookies in the same header. Each must read only its own name.
 */
- (void)testScopedManagerIgnoresSiblingServiceCookie {
    GZAdminUIAuthManager *plc = [[GZAdminUIAuthManager alloc] initWithPassword:@"pw"
                                              serviceIdentifier:@"plc"];
    GZAdminUIAuthManager *relay = [[GZAdminUIAuthManager alloc] initWithPassword:@"pw"
                                                serviceIdentifier:@"relay"];

    NSString *plcToken = [plc createSessionToken];
    NSString *relayToken = [relay createSessionToken];

    // The browser sends both cookies to whichever UI is being addressed.
    NSString *bothCookies = [NSString stringWithFormat:
        @"gz_admin_plc_token=%@; gz_admin_relay_token=%@", plcToken, relayToken];

    XCTAssertEqualObjects([plc extractTokenFromRequest:[self requestWithCookieHeader:bothCookies]],
                          plcToken);
    XCTAssertEqualObjects([relay extractTokenFromRequest:[self requestWithCookieHeader:bothCookies]],
                          relayToken);
}

/*!
 @test testSiblingSessionsRemainIndependent

 @abstract Verify that both UIs stay authorized when both cookies are present.

 @discussion This is the defect the scoping fixes: with one shared cookie name the second
 sign-in evicts the first UI's session in the browser.
 */
- (void)testSiblingSessionsRemainIndependent {
    GZAdminUIAuthManager *plc = [[GZAdminUIAuthManager alloc] initWithPassword:@"pw"
                                              serviceIdentifier:@"plc"];
    GZAdminUIAuthManager *relay = [[GZAdminUIAuthManager alloc] initWithPassword:@"pw"
                                                serviceIdentifier:@"relay"];

    NSString *bothCookies = [NSString stringWithFormat:
        @"gz_admin_plc_token=%@; gz_admin_relay_token=%@",
        [plc createSessionToken], [relay createSessionToken]];
    ATProtoHttpRequest *request = [self requestWithCookieHeader:bothCookies];

    XCTAssertTrue([plc isAuthorizedRequest:request]);
    XCTAssertTrue([relay isAuthorizedRequest:request]);
}

/*!
 @test testScopedManagerRejectsUnscopedCookie

 @abstract Verify that a scoped UI ignores a legacy unscoped session cookie.
 */
- (void)testScopedManagerRejectsUnscopedCookie {
    GZAdminUIAuthManager *plc = [[GZAdminUIAuthManager alloc] initWithPassword:@"pw"
                                              serviceIdentifier:@"plc"];
    NSString *legacy = [NSString stringWithFormat:@"ui_admin_token=%@",
                        [self.authManager createSessionToken]];
    ATProtoHttpRequest *request = [self requestWithCookieHeader:legacy];

    XCTAssertNil([plc extractTokenFromRequest:request]);
    XCTAssertFalse([plc isAuthorizedRequest:request]);
}

@end
