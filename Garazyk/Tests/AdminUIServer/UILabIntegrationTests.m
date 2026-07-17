// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UILabIntegrationTests.m

 @abstract Integration tests for the Admin UI lab and authentication routes.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import <dispatch/dispatch.h>
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

static NSString * const UILabIntegrationTestHost = @"127.0.0.1";
static const NSUInteger UILabIntegrationTestPort = 25999;
static const NSTimeInterval UILabIntegrationTestTimeout = 10.0;

@interface UILabHTTPRedirectBlockingDelegate : NSObject <NSURLSessionTaskDelegate>
@end

@implementation UILabHTTPRedirectBlockingDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(nil);
}

@end

@interface UILabIntegrationTests : XCTestCase
@property (nonatomic, strong) UIServiceConfig *config;
@property (nonatomic, strong) UIServerRuntime *runtime;
@end

@implementation UILabIntegrationTests

- (void)setUp {
    [super setUp];

    self.config = [[UIServiceConfig alloc] init];
    self.config.host = UILabIntegrationTestHost;
    self.config.port = UILabIntegrationTestPort;
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
}

- (void)tearDown {
    if (self.runtime.isRunning) {
        [self.runtime stop];
    }
    self.runtime = nil;
    self.config = nil;
    [super tearDown];
}

#pragma mark - Helper Methods

- (NSData *)jsonDataFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    return [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:error];
}

- (HttpMethod)httpMethodFromString:(NSString *)method {
    if ([method isEqualToString:@"POST"]) {
        return HttpMethodPOST;
    }
    if ([method isEqualToString:@"PUT"]) {
        return HttpMethodPUT;
    }
    if ([method isEqualToString:@"DELETE"]) {
        return HttpMethodDELETE;
    }
    return HttpMethodGET;
}

- (NSString *)headerValueForName:(NSString *)headerName response:(NSHTTPURLResponse *)response {
    if (!response) {
        return nil;
    }

    NSDictionary *headers = response.allHeaderFields;
    for (NSString *key in headers) {
        if ([key caseInsensitiveCompare:headerName] == NSOrderedSame) {
            id value = headers[key];
            if ([value isKindOfClass:[NSString class]]) {
                return value;
            }
            return [value description];
        }
    }

    return nil;
}

- (NSString *)cookiePairFromSetCookieHeader:(NSString *)setCookieHeader {
    if (setCookieHeader.length == 0) {
        return nil;
    }

    NSString *cookiePair = [[setCookieHeader componentsSeparatedByString:@";"] firstObject];
    return [cookiePair stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/*!
 @abstract GETs `path` and returns headers carrying the CSRF nonce it issues.

 @discussion validateCSRFForRequest: (UIAuthManager) requires the same
 one-time nonce in both the `ui_admin_nonce` cookie and the
 `X-UI-Admin-Nonce` header on the next state-changing request. Any
 unauthenticated GET to /admin/login, or an authenticated GET to /admin,
 issues a fresh nonce this way.
 */
- (NSDictionary<NSString *, NSString *> *)csrfHeadersFromPath:(NSString *)path
                                                 extraHeaders:(NSDictionary<NSString *, NSString *> *)extraHeaders {
    NSURLResponse *response = nil;
    NSError *error = nil;
    [self sendRequestToPath:path method:@"GET" headers:extraHeaders ?: @{} body:nil response:&response error:&error];

    NSString *setCookie = [self headerValueForName:@"Set-Cookie" response:(NSHTTPURLResponse *)response];
    NSString *cookiePair = [self cookiePairFromSetCookieHeader:setCookie];
    NSRange equalsRange = [cookiePair rangeOfString:@"="];
    if (!cookiePair || equalsRange.location == NSNotFound) {
        return @{};
    }
    NSString *nonceValue = [cookiePair substringFromIndex:equalsRange.location + 1];

    NSMutableDictionary<NSString *, NSString *> *headers = [extraHeaders mutableCopy] ?: [NSMutableDictionary dictionary];
    headers[@"Cookie"] = extraHeaders[@"Cookie"] ? [NSString stringWithFormat:@"%@; %@", extraHeaders[@"Cookie"], cookiePair] : cookiePair;
    headers[@"X-UI-Admin-Nonce"] = nonceValue;
    return headers;
}

- (NSData *)sendRequestToPath:(NSString *)path
                       method:(NSString *)method
                      headers:(NSDictionary<NSString *, NSString *> *)headers
                         body:(NSData *)body
                     response:(NSURLResponse **)outResponse
                        error:(NSError **)outError {
    NSString *urlString = [NSString stringWithFormat:@"http://%@:%lu%@",
                           UILabIntegrationTestHost,
                           (unsigned long)UILabIntegrationTestPort,
                           path];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary *queryParams = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        queryParams[item.name] = item.value ?: @"";
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:[self httpMethodFromString:method]
                                                  methodString:method
                                                          path:components.path ?: path
                                                   queryString:components.percentEncodedQuery ?: @""
                                                    queryParams:queryParams
                                                        version:@"HTTP/1.1"
                                                        headers:headers ?: @{}
                                                           body:body ?: [NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    HttpResponse *runtimeResponse = [self.runtime dispatchRequestForTesting:request];

    NSMutableDictionary *responseHeaders = [runtimeResponse.headers mutableCopy] ?: [NSMutableDictionary dictionary];
    if (runtimeResponse.contentType.length > 0) {
        responseHeaders[@"Content-Type"] = runtimeResponse.contentType;
    }
    NSHTTPURLResponse *resultResponse = [[NSHTTPURLResponse alloc] initWithURL:url
                                                                    statusCode:runtimeResponse.statusCode
                                                                   HTTPVersion:@"HTTP/1.1"
                                                                  headerFields:responseHeaders];
    NSData *resultData = runtimeResponse.body ?: [NSData data];
    NSError *resultError = nil;

    if (outResponse) {
        *outResponse = resultResponse;
    }
    if (outError) {
        *outError = resultError;
    }

    return resultData;
}

- (NSString *)responseStringFromData:(NSData *)data {
    if (data.length == 0) {
        return @"";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (NSDictionary *)sendJSONRequestToPath:(NSString *)path
                                 method:(NSString *)method
                                headers:(NSDictionary<NSString *, NSString *> *)headers
                              jsonObject:(NSDictionary *)jsonObject
                               response:(NSURLResponse **)outResponse
                                  error:(NSError **)outError {
    NSError *serializationError = nil;
    NSData *body = [self jsonDataFromDictionary:jsonObject error:&serializationError];
    if (serializationError) {
        if (outError) {
            *outError = serializationError;
        }
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *combinedHeaders = [headers mutableCopy] ?: [NSMutableDictionary dictionary];
    combinedHeaders[@"Content-Type"] = @"application/json";

    NSData *data = [self sendRequestToPath:path
                                    method:method
                                   headers:combinedHeaders
                                      body:body
                                  response:outResponse
                                     error:outError];
    if (data.length == 0) {
        return nil;
    }

    NSError *parseError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    if (parseError) {
        if (outError && !*outError) {
            *outError = parseError;
        }
        return nil;
    }

    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

#pragma mark - Lab Route Tests

/*!
 @test testGetLabReturns200

 @abstract Verify that GET /lab returns a successful HTML response.
 */
- (void)testGetLabReturns200 {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/lab"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 200);
    NSString *contentType = [self headerValueForName:@"Content-Type" response:httpResponse];
    XCTAssertNotNil(contentType);
    XCTAssertTrue([contentType containsString:@"text/html"]);
}

/*!
 @test testGetLabContainsLoginSection

 @abstract Verify that GET /lab contains the login section markup.
 */
- (void)testGetLabContainsLoginSection {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/lab"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    NSString *body = [self responseStringFromData:data];
    XCTAssertTrue([body containsString:@"lab-login-section"]);
}

/*!
 @test testGetLabContainsLabConfig

 @abstract Verify that GET /lab includes the LAB_CONFIG bootstrap data.

 @discussion The CSP hardening in workstream 04 U2 moved this from an
 inline `LAB_CONFIG` object literal into `<meta>` tags read by the external
 /js/lab.js (see labConfigValue() there), so the literal symbol no longer
 appears in the page body; assert on the meta tag + script include instead.
 */
- (void)testGetLabContainsLabConfig {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/lab"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    NSString *body = [self responseStringFromData:data];
    XCTAssertTrue([body containsString:@"meta name=\"lab-pds-url\""]);
    XCTAssertTrue([body containsString:@"/js/lab.js"]);
}

/*!
 @test testGetLabCallbackReturns200

 @abstract Verify that GET /lab/callback returns the lab shell successfully.
 */
- (void)testGetLabCallbackReturns200 {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/lab/callback"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 200);
}

/*!
 @test testGetLabCallbackWithCodeParam

 @abstract Verify that GET /lab/callback with OAuth query parameters returns the lab shell.
 */
- (void)testGetLabCallbackWithCodeParam {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/lab/callback?code=abc&state=xyz"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 200);
    NSString *body = [self responseStringFromData:data];
    XCTAssertTrue([body containsString:@"lab-login-section"]);
}

/*!
 @test testGetLabClientMetadataReturnsJSON

 @abstract Verify that GET /lab/client-metadata.json returns JSON.
 */
- (void)testGetLabClientMetadataReturnsJSON {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/lab/client-metadata.json"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 200);
    NSString *contentType = [self headerValueForName:@"Content-Type" response:httpResponse];
    XCTAssertNotNil(contentType);
    XCTAssertTrue([contentType containsString:@"json"]);
}

/*!
 @test testLabClientMetadataHasRequiredFields

 @abstract Verify that the lab client metadata includes the required OAuth fields.
 */
- (void)testLabClientMetadataHasRequiredFields {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/lab/client-metadata.json"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSError *parseError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);

    NSString *expectedClientID = [NSString stringWithFormat:@"http://%@:%lu/lab/client-metadata.json",
                                  UILabIntegrationTestHost,
                                  (unsigned long)UILabIntegrationTestPort];
    NSString *expectedRedirectURI = [NSString stringWithFormat:@"http://%@:%lu/lab/callback",
                                     UILabIntegrationTestHost,
                                     (unsigned long)UILabIntegrationTestPort];

    XCTAssertEqualObjects(json[@"client_id"], expectedClientID);
    XCTAssertEqualObjects(json[@"redirect_uris"], (@[expectedRedirectURI]));
    XCTAssertEqualObjects(json[@"scope"], @"atproto transition:generic");
    XCTAssertEqualObjects(json[@"dpop_bound_access_tokens"], @YES);
}

#pragma mark - Admin Auth Boundary Tests

/*!
 @test testGetAdminWithoutAuthRedirects

 @abstract Verify that GET /admin without auth redirects to the login page.
 */
- (void)testGetAdminWithoutAuthRedirects {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/admin"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 302);
    NSString *location = [self headerValueForName:@"Location" response:httpResponse];
    XCTAssertEqualObjects(location, @"/admin/login");
}

/*!
 @test testGetAdminHTMXWithoutAuthReturns401

 @abstract Verify that HTMX requests to /admin without auth return 401.
 */
- (void)testGetAdminHTMXWithoutAuthReturns401 {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/admin"
                                    method:@"GET"
                                   headers:@{@"HX-Request": @"true"}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 401);
}

/*!
 @test testGetAdminPartialHTMXWithoutAuthReturns401

 @abstract Verify that HTMX requests to admin partial routes without auth return 401.
 */
- (void)testGetAdminPartialHTMXWithoutAuthReturns401 {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/admin/partials/overview"
                                    method:@"GET"
                                   headers:@{@"HX-Request": @"true"}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 401);
}

#pragma mark - Admin Login Flow Tests

/*!
 @test testPostAdminLoginCorrectPassword

 @abstract Verify that POST /admin/login with the correct password succeeds and sets a session cookie.
 */
- (void)testPostAdminLoginCorrectPassword {
    NSDictionary<NSString *, NSString *> *csrfHeaders = [self csrfHeadersFromPath:@"/admin/login" extraHeaders:@{}];

    NSURLResponse *response = nil;
    NSError *error = nil;
    NSDictionary *json = [self sendJSONRequestToPath:@"/admin/login"
                                              method:@"POST"
                                             headers:csrfHeaders
                                           jsonObject:@{@"password": @"test-admin-password"}
                                            response:&response
                                               error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(json);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 200);
    NSString *setCookie = [self headerValueForName:@"Set-Cookie" response:httpResponse];
    XCTAssertNotNil(setCookie);
    XCTAssertTrue([setCookie containsString:@"ui_admin_token="]);
}

/*!
 @test testPostAdminLoginWrongPassword

 @abstract Verify that POST /admin/login with the wrong password is rejected.
 */
- (void)testPostAdminLoginWrongPassword {
    NSDictionary<NSString *, NSString *> *csrfHeaders = [self csrfHeadersFromPath:@"/admin/login" extraHeaders:@{}];

    NSURLResponse *response = nil;
    NSError *error = nil;
    NSDictionary *json = [self sendJSONRequestToPath:@"/admin/login"
                                              method:@"POST"
                                             headers:csrfHeaders
                                           jsonObject:@{@"password": @"wrong"}
                                            response:&response
                                               error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(json);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 401);
    XCTAssertEqualObjects(json[@"error"], @"invalid_credentials");
}

/*!
 @test testAdminLoginFlowFull

 @abstract Verify that a login cookie grants access to /admin.
 */
- (void)testAdminLoginFlowFull {
    NSDictionary<NSString *, NSString *> *csrfHeaders = [self csrfHeadersFromPath:@"/admin/login" extraHeaders:@{}];

    NSURLResponse *loginResponse = nil;
    NSError *loginError = nil;
    NSDictionary *loginJSON = [self sendJSONRequestToPath:@"/admin/login"
                                                   method:@"POST"
                                                  headers:csrfHeaders
                                                jsonObject:@{@"password": @"test-admin-password"}
                                                 response:&loginResponse
                                                    error:&loginError];

    XCTAssertNil(loginError);
    XCTAssertNotNil(loginResponse);
    XCTAssertNotNil(loginJSON);

    NSHTTPURLResponse *loginHTTPResponse = (NSHTTPURLResponse *)loginResponse;
    NSString *setCookie = [self headerValueForName:@"Set-Cookie" response:loginHTTPResponse];
    NSString *cookiePair = [self cookiePairFromSetCookieHeader:setCookie];
    XCTAssertNotNil(cookiePair);

    NSURLResponse *adminResponse = nil;
    NSError *adminError = nil;
    NSData *adminData = [self sendRequestToPath:@"/admin"
                                         method:@"GET"
                                        headers:@{@"Cookie": cookiePair}
                                           body:nil
                                       response:&adminResponse
                                          error:&adminError];

    XCTAssertNil(adminError);
    XCTAssertNotNil(adminResponse);
    XCTAssertNotNil(adminData);

    NSHTTPURLResponse *adminHTTPResponse = (NSHTTPURLResponse *)adminResponse;
    XCTAssertEqual(adminHTTPResponse.statusCode, 200);
    NSString *body = [self responseStringFromData:adminData];
    XCTAssertTrue([body containsString:@"Garazyk UI Service"]);
}

/*!
 @test testAdminLogoutFlow

 @abstract Verify that logout invalidates the session and restores the redirect behavior.
 */
- (void)testAdminLogoutFlow {
    NSDictionary<NSString *, NSString *> *loginCSRFHeaders = [self csrfHeadersFromPath:@"/admin/login" extraHeaders:@{}];

    NSURLResponse *loginResponse = nil;
    NSError *loginError = nil;
    NSDictionary *loginJSON = [self sendJSONRequestToPath:@"/admin/login"
                                                   method:@"POST"
                                                  headers:loginCSRFHeaders
                                                jsonObject:@{@"password": @"test-admin-password"}
                                                 response:&loginResponse
                                                    error:&loginError];

    XCTAssertNil(loginError);
    XCTAssertNotNil(loginResponse);
    XCTAssertNotNil(loginJSON);

    NSHTTPURLResponse *loginHTTPResponse = (NSHTTPURLResponse *)loginResponse;
    NSString *setCookie = [self headerValueForName:@"Set-Cookie" response:loginHTTPResponse];
    NSString *cookiePair = [self cookiePairFromSetCookieHeader:setCookie];
    XCTAssertNotNil(cookiePair);

    NSURLResponse *adminResponseBeforeLogout = nil;
    NSError *adminBeforeLogoutError = nil;
    NSData *adminBeforeLogoutData = [self sendRequestToPath:@"/admin"
                                                    method:@"GET"
                                                   headers:@{@"Cookie": cookiePair}
                                                      body:nil
                                                  response:&adminResponseBeforeLogout
                                                     error:&adminBeforeLogoutError];
    XCTAssertNil(adminBeforeLogoutError);
    XCTAssertNotNil(adminResponseBeforeLogout);
    XCTAssertNotNil(adminBeforeLogoutData);
    XCTAssertEqual([(NSHTTPURLResponse *)adminResponseBeforeLogout statusCode], 200);

    // GET /admin (above) rotated in a fresh CSRF nonce for this session;
    // logout is itself a mutation and needs it.
    NSDictionary<NSString *, NSString *> *logoutCSRFHeaders = [self csrfHeadersFromPath:@"/admin" extraHeaders:@{@"Cookie": cookiePair}];

    NSURLResponse *logoutResponse = nil;
    NSError *logoutError = nil;
    NSDictionary *logoutJSON = [self sendJSONRequestToPath:@"/admin/logout"
                                                    method:@"POST"
                                                   headers:logoutCSRFHeaders
                                                 jsonObject:@{}
                                                  response:&logoutResponse
                                                     error:&logoutError];

    XCTAssertNil(logoutError);
    XCTAssertNotNil(logoutResponse);
    XCTAssertNotNil(logoutJSON);

    NSHTTPURLResponse *logoutHTTPResponse = (NSHTTPURLResponse *)logoutResponse;
    XCTAssertEqual(logoutHTTPResponse.statusCode, 200);

    NSURLResponse *adminResponseAfterLogout = nil;
    NSError *adminAfterLogoutError = nil;
    NSData *adminAfterLogoutData = [self sendRequestToPath:@"/admin"
                                                   method:@"GET"
                                                  headers:@{@"Cookie": cookiePair}
                                                     body:nil
                                                 response:&adminResponseAfterLogout
                                                    error:&adminAfterLogoutError];

    XCTAssertNil(adminAfterLogoutError);
    XCTAssertNotNil(adminResponseAfterLogout);
    XCTAssertNotNil(adminAfterLogoutData);

    NSHTTPURLResponse *adminAfterLogoutHTTPResponse = (NSHTTPURLResponse *)adminResponseAfterLogout;
    XCTAssertEqual(adminAfterLogoutHTTPResponse.statusCode, 302);
    NSString *location = [self headerValueForName:@"Location" response:adminAfterLogoutHTTPResponse];
    XCTAssertEqualObjects(location, @"/admin/login");
}

/*!
 @test testAdminLoginCookieAttributes

 @abstract Verify that the login cookie is marked HttpOnly and SameSite=Strict.
 */
- (void)testAdminLoginCookieAttributes {
    NSDictionary<NSString *, NSString *> *csrfHeaders = [self csrfHeadersFromPath:@"/admin/login" extraHeaders:@{}];

    NSURLResponse *response = nil;
    NSError *error = nil;
    NSDictionary *json = [self sendJSONRequestToPath:@"/admin/login"
                                              method:@"POST"
                                             headers:csrfHeaders
                                           jsonObject:@{@"password": @"test-admin-password"}
                                            response:&response
                                               error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(json);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSString *setCookie = [self headerValueForName:@"Set-Cookie" response:httpResponse];
    XCTAssertNotNil(setCookie);
    XCTAssertTrue([setCookie containsString:@"HttpOnly"]);
    XCTAssertTrue([setCookie containsString:@"SameSite=Strict"]);
    XCTAssertTrue([setCookie containsString:@"Path=/"]);
}

#pragma mark - Root Redirect Tests

/*!
 @test testRootRedirectsToAdmin

 @abstract Verify that GET / redirects to /admin.
 */
- (void)testRootRedirectsToAdmin {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendRequestToPath:@"/"
                                    method:@"GET"
                                   headers:@{}
                                      body:nil
                                  response:&response
                                     error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(response);
    XCTAssertNotNil(data);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    XCTAssertEqual(httpResponse.statusCode, 302);
    NSString *location = [self headerValueForName:@"Location" response:httpResponse];
    XCTAssertEqualObjects(location, @"/admin");
}

@end
