// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UILabAuthTests.m

 @abstract Unit tests for the Lab login auth boundary.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

typedef void (^UILabRouteHandler)(HttpRequest *request, HttpResponse *response);

@interface UILabAuthTests : XCTestCase
@property(nonatomic, strong) UIServiceConfig *config;
@property(nonatomic, strong) UIServerRuntime *runtime;
@property(nonatomic, strong) UIAuthManager *authManager;
@end

@implementation UILabAuthTests

- (void)setUp {
    [super setUp];

    self.config = [[UIServiceConfig alloc] init];
    self.config.host = @"127.0.0.1";
    self.config.port = 0;
    self.config.adminPassword = @"test-admin-password";
    self.config.pdsBaseURL = [NSURL URLWithString:@"http://localhost:3001"];
    self.config.plcBaseURL = [NSURL URLWithString:@"http://localhost:4000"];
    self.config.relayBaseURL = [NSURL URLWithString:@"http://localhost:7002"];
    self.config.appViewBaseURL = [NSURL URLWithString:@"http://localhost:3000"];
    self.config.chatBaseURL = [NSURL URLWithString:@"http://localhost:5000"];
    self.config.pdsAdminToken = @"admin-token";
    self.config.plcAdminToken = @"admin-token";
    self.config.relayAdminToken = @"admin-token";
    self.config.appViewAdminToken = @"admin-token";
    self.config.chatAdminToken = @"admin-token";

    self.runtime = [[UIServerRuntime alloc] initWithConfiguration:self.config];
    self.authManager = [[UIAuthManager alloc] initWithPassword:@"test-admin-password"];
}

- (void)tearDown {
    if (self.runtime.isRunning) {
        [self.runtime stop];
    }
    self.runtime = nil;
    self.authManager = nil;
    self.config = nil;
    [super tearDown];
}

#pragma mark - Helper Methods

- (HttpRequest *)requestWithPath:(NSString *)path headers:(NSDictionary<NSString *, NSString *> * _Nullable)headers {
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:path
                                   queryString:@""
                                    queryParams:@{}
                                        version:@"HTTP/1.1"
                                        headers:headers
                                           body:[NSData data]
                                   remoteAddress:@"127.0.0.1"];
}

- (nullable NSString *)responseBodyString:(HttpResponse *)response {
    if (!response.body) {
        return nil;
    }
    return [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding];
}

- (BOOL)invokeEnsureAuthorizedForRequest:(HttpRequest *)request response:(HttpResponse *)response {
    SEL selector = NSSelectorFromString(@"ensureAuthorized:response:");
    NSMethodSignature *signature = [self.runtime methodSignatureForSelector:selector];
    if (!signature) {
        XCTFail(@"Runtime does not respond to ensureAuthorized:response:");
        return NO;
    }

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:self.runtime];
    [invocation setSelector:selector];
    [invocation setArgument:&request atIndex:2];
    [invocation setArgument:&response atIndex:3];
    [invocation invoke];

    BOOL result = NO;
    [invocation getReturnValue:&result];
    return result;
}

- (nullable NSString *)invokeRuntimeStringSelector:(SEL)selector {
    NSMethodSignature *sig = [self.runtime methodSignatureForSelector:selector];
    if (!sig) {
        XCTFail(@"Runtime does not respond to %@", NSStringFromSelector(selector));
        return nil;
    }
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:self.runtime];
    [inv setSelector:selector];
    // Pass nil for any argument beyond self and _cmd (e.g. the nonce in labShellHTML:)
    if (sig.numberOfArguments > 2) {
        NSString *nilArg = nil;
        [inv setArgument:&nilArg atIndex:2];
    }
    [inv invoke];
    __unsafe_unretained NSString *result = nil;
    [inv getReturnValue:&result];
    return result;
}

- (nullable UILabRouteHandler)labRouteHandler {
    id httpServer = [self.runtime valueForKey:@"httpServer"];
    if (!httpServer) {
        XCTFail(@"Runtime does not have an HTTP server instance yet");
        return nil;
    }

    SEL selector = NSSelectorFromString(@"handlerForRoute:method:parameters:");
    if (![httpServer respondsToSelector:selector]) {
        XCTFail(@"HttpServer does not respond to handlerForRoute:method:parameters:");
        return nil;
    }

    typedef id (*HandlerLookup)(id, SEL, NSString *, NSString *, NSDictionary **);
    HandlerLookup lookup = (HandlerLookup)[httpServer methodForSelector:selector];
    id handlerObject = lookup(httpServer, selector, @"/lab", @"GET", NULL);
    return (UILabRouteHandler)handlerObject;
}

#pragma mark - Auth Boundary Tests

/*!
 @test testLabRouteDoesNotRequireAdminAuth

 @abstract Verify that the Lab route is registered and bypasses the admin auth boundary.
 */
- (void)testLabRouteDoesNotRequireAdminAuth {
    HttpRequest *request = [self requestWithPath:@"/lab" headers:nil];
    HttpResponse *response = [self.runtime dispatchRequestForTesting:request];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.contentType, @"text/html; charset=utf-8");
    NSString *html = [self responseBodyString:response];
    XCTAssertNotNil(html);
    XCTAssertTrue([html containsString:@"id=\"lab-login-section\""]);
}

/*!
 @test testAdminRouteRequiresAuth

 @abstract Verify that GET /admin without authentication is rejected with a redirect to the login page.
 */
- (void)testAdminRouteRequiresAuth {
    HttpRequest *request = [self requestWithPath:@"/admin" headers:nil];
    HttpResponse *response = [HttpResponse response];

    BOOL authorized = [self invokeEnsureAuthorizedForRequest:request response:response];

    XCTAssertFalse(authorized);
    XCTAssertEqual(response.statusCode, 302);
    XCTAssertEqualObjects([response headerForKey:@"Location"], @"/admin/login");
    XCTAssertEqualObjects(response.contentType, @"text/plain; charset=utf-8");
    XCTAssertEqualObjects([self responseBodyString:response], @"Authentication required\n");
}

/*!
 @test testAdminHTMXRequestReturns401

 @abstract Verify that HX-Request admin access returns a 401 with inline error HTML.
 */
- (void)testAdminHTMXRequestReturns401 {
    NSDictionary *headers = @{@"HX-Request": @"true"};
    HttpRequest *request = [self requestWithPath:@"/admin" headers:headers];
    HttpResponse *response = [HttpResponse response];

    BOOL authorized = [self invokeEnsureAuthorizedForRequest:request response:response];

    XCTAssertFalse(authorized);
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.contentType, @"text/html; charset=utf-8");
    XCTAssertEqualObjects([self responseBodyString:response], @"<div class=\"alert alert-destructive\">Session expired. <a href=\"/admin/login\">Sign in</a></div>");
}

/*!
 @test testAdminHTMXPartialReturns401

 @abstract Verify that HX-Request admin partial access returns a 401 with inline error HTML.
 */
- (void)testAdminHTMXPartialReturns401 {
    NSDictionary *headers = @{@"HX-Request": @"true"};
    HttpRequest *request = [self requestWithPath:@"/admin/partials/overview" headers:headers];
    HttpResponse *response = [HttpResponse response];

    BOOL authorized = [self invokeEnsureAuthorizedForRequest:request response:response];

    XCTAssertFalse(authorized);
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.contentType, @"text/html; charset=utf-8");
    XCTAssertEqualObjects([self responseBodyString:response], @"<div class=\"alert alert-destructive\">Session expired. <a href=\"/admin/login\">Sign in</a></div>");
}

/*!
 @test testAdminLoginWithCorrectPassword

 @abstract Verify that UIAuthManager validates the configured admin password.
 */
- (void)testAdminLoginWithCorrectPassword {
    XCTAssertTrue([self.authManager validatePassword:@"test-admin-password"]);
}

/*!
 @test testAdminLoginWithWrongPassword

 @abstract Verify that UIAuthManager rejects an incorrect admin password.
 */
- (void)testAdminLoginWithWrongPassword {
    XCTAssertFalse([self.authManager validatePassword:@"wrong-password"]);
}

#pragma mark - Client Metadata Tests

/*!
 @test testLabClientMetadataJSONStructure

 @abstract Verify that lab client metadata serializes to valid JSON with the expected OAuth fields.
 */
- (void)testLabClientMetadataJSONStructure {
    NSString *metadataJSON = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labClientMetadataJSON")];
    XCTAssertNotNil(metadataJSON);
    if (!metadataJSON) {
        return;
    }

    NSData *data = [metadataJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(parsed);
    XCTAssertTrue([parsed isKindOfClass:[NSDictionary class]]);

    NSDictionary *metadata = (NSDictionary *)parsed;
    NSArray *expectedKeys = @[
        @"client_id",
        @"client_name",
        @"redirect_uris",
        @"scope",
        @"grant_types",
        @"response_types",
        @"token_endpoint_auth_method",
        @"application_type",
        @"dpop_bound_access_tokens"
    ];

    for (NSString *key in expectedKeys) {
        XCTAssertNotNil(metadata[key]);
    }
}

/*!
 @test testLabClientMetadataDPoPBound

 @abstract Verify that the client metadata declares DPoP-bound access tokens.
 */
- (void)testLabClientMetadataDPoPBound {
    NSString *metadataJSON = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labClientMetadataJSON")];
    if (!metadataJSON) {
        return;
    }
    NSData *data = [metadataJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    XCTAssertNil(error);
    XCTAssertTrue([metadata[@"dpop_bound_access_tokens"] boolValue]);
}

/*!
 @test testLabClientMetadataRedirectUris

 @abstract Verify that the client metadata includes the Lab callback redirect URI.
 */
- (void)testLabClientMetadataRedirectUris {
    NSString *metadataJSON = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labClientMetadataJSON")];
    if (!metadataJSON) {
        return;
    }
    NSData *data = [metadataJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    XCTAssertNil(error);

    NSArray *redirectURIs = metadata[@"redirect_uris"];
    XCTAssertTrue([redirectURIs isKindOfClass:[NSArray class]]);
    XCTAssertTrue([redirectURIs containsObject:@"http://127.0.0.1:0/lab/callback"]);
}

/*!
 @test testLabClientMetadataTokenEndpointAuthNone

 @abstract Verify that the client metadata uses token_endpoint_auth_method=none.
 */
- (void)testLabClientMetadataTokenEndpointAuthNone {
    NSString *metadataJSON = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labClientMetadataJSON")];
    if (!metadataJSON) {
        return;
    }
    NSData *data = [metadataJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    XCTAssertNil(error);
    XCTAssertEqualObjects(metadata[@"token_endpoint_auth_method"], @"none");
}

/*!
 @test testLabClientMetadataApplicationType

 @abstract Verify that the client metadata declares a web application type.
 */
- (void)testLabClientMetadataApplicationType {
    NSString *metadataJSON = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labClientMetadataJSON")];
    if (!metadataJSON) {
        return;
    }
    NSData *data = [metadataJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    XCTAssertNil(error);
    XCTAssertEqualObjects(metadata[@"application_type"], @"web");
}

/*!
 @test testLabClientMetadataScope

 @abstract Verify that the client metadata scope includes atproto.
 */
- (void)testLabClientMetadataScope {
    NSString *metadataJSON = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labClientMetadataJSON")];
    if (!metadataJSON) {
        return;
    }
    NSData *data = [metadataJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    XCTAssertNil(error);
    XCTAssertTrue([metadata[@"scope"] containsString:@"atproto"]);
}

#pragma mark - Lab Shell HTML Tests

/*!
 @test testLabShellHTMLContainsLoginSection

 @abstract Verify that the Lab shell HTML renders the login section.
 */
- (void)testLabShellHTMLContainsLoginSection {
    NSString *html = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labShellHTML:")];
    XCTAssertNotNil(html);
    if (!html) {
        return;
    }
    XCTAssertTrue([html containsString:@"id=\"lab-login-section\""]);
}

/*!
 @test testLabShellHTMLContainsAccountSection

 @abstract Verify that the Lab shell HTML renders the account section.
 */
- (void)testLabShellHTMLContainsAccountSection {
    NSString *html = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labShellHTML:")];
    XCTAssertNotNil(html);
    if (!html) {
        return;
    }
    XCTAssertTrue([html containsString:@"id=\"lab-account-section\""]);
}

/*!
 @test testLabShellHTMLContainsLabConfig

 @abstract Verify that the Lab shell HTML includes the embedded LAB_CONFIG object.
 */
- (void)testLabShellHTMLContainsLabConfig {
    NSString *html = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labShellHTML:")];
    XCTAssertNotNil(html);
    if (!html) {
        return;
    }
    // Config is delivered via <meta name="lab-*"> tags consumed client-side by lab.js
    // (which builds its own frozen LAB_CONFIG object); the literal "LAB_CONFIG" is no
    // longer server-rendered. Assert the pds-url config meta is present instead.
    XCTAssertTrue([html containsString:@"lab-pds-url"]);
}

/*!
 @test testLabShellHTMLReferencesLabJS

 @abstract Verify that the Lab shell HTML references the Lab JavaScript bundle.
 */
- (void)testLabShellHTMLReferencesLabJS {
    NSString *html = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labShellHTML:")];
    XCTAssertNotNil(html);
    if (!html) {
        return;
    }
    XCTAssertTrue([html containsString:@"/js/lab.js"]);
}

/*!
 @test testLabShellHTMLContainsHandleInput

 @abstract Verify that the Lab shell HTML includes the handle input field.
 */
- (void)testLabShellHTMLContainsHandleInput {
    NSString *html = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labShellHTML:")];
    XCTAssertNotNil(html);
    if (!html) {
        return;
    }
    XCTAssertTrue([html containsString:@"lab-handle-input"]);
}

/*!
 @test testLabShellHTMLContainsSignOutButton

 @abstract Verify that the Lab shell HTML includes the OAuth sign-out control.
 */
- (void)testLabShellHTMLContainsSignOutButton {
    NSString *html = [self invokeRuntimeStringSelector:NSSelectorFromString(@"labShellHTML:")];
    XCTAssertNotNil(html);
    if (!html) {
        return;
    }
    // The sign-out control is rendered as <button data-lab-action="sign-out">; the
    // signOutOAuth() handler lives in lab.js and is wired to that attribute. Assert the
    // control rather than the JS-only function name.
    XCTAssertTrue([html containsString:@"data-lab-action=\"sign-out\""]);
}

#pragma mark - Session Token Tests

/*!
 @test testSessionTokenCreationAndValidation

 @abstract Verify that a created session token is accepted by UIAuthManager.
 */
- (void)testSessionTokenCreationAndValidation {
    NSString *token = [self.authManager createSessionToken];
    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    HttpRequest *request = [self requestWithPath:@"/admin" headers:headers];

    XCTAssertTrue([self.authManager isAuthorizedRequest:request]);
}

/*!
 @test testSessionTokenInvalidation

 @abstract Verify that invalidating a session token makes subsequent requests unauthorized.
 */
- (void)testSessionTokenInvalidation {
    NSString *token = [self.authManager createSessionToken];
    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    HttpRequest *request = [self requestWithPath:@"/admin" headers:headers];

    XCTAssertTrue([self.authManager isAuthorizedRequest:request]);

    [self.authManager invalidateSessionToken:token];

    XCTAssertFalse([self.authManager isAuthorizedRequest:request]);
}

/*!
 @test testMultipleSessionsCoexist

 @abstract Verify that multiple session tokens remain independently valid until individually invalidated.
 */
- (void)testMultipleSessionsCoexist {
    NSString *token1 = [self.authManager createSessionToken];
    NSString *token2 = [self.authManager createSessionToken];

    XCTAssertNotEqualObjects(token1, token2);

    NSDictionary *headers1 = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token1]};
    NSDictionary *headers2 = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token2]};
    HttpRequest *request1 = [self requestWithPath:@"/admin" headers:headers1];
    HttpRequest *request2 = [self requestWithPath:@"/admin" headers:headers2];

    XCTAssertTrue([self.authManager isAuthorizedRequest:request1]);
    XCTAssertTrue([self.authManager isAuthorizedRequest:request2]);

    [self.authManager invalidateSessionToken:token1];

    XCTAssertFalse([self.authManager isAuthorizedRequest:request1]);
    XCTAssertTrue([self.authManager isAuthorizedRequest:request2]);
}

@end
