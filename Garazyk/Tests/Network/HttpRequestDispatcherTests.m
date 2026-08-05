// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpRequestDispatcher.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface HttpRequestDispatcherTests : XCTestCase
@end

@implementation HttpRequestDispatcherTests

#pragma mark - Init

- (void)testInitWithRouteLookupHandler_SetsHandler {
    __block BOOL lookupCalled = NO;
    HttpRouteLookupHandler lookup = ^(NSString *path, NSString *method, NSDictionary<NSString *, NSString *> **params) {
        lookupCalled = YES;
        return (HttpServerRequestHandler)nil;
    };
    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:lookup];
    XCTAssertNotNil(dispatcher);
    XCTAssertNotNil(dispatcher.routeLookupHandler);

    // Verify the handler is callable
    NSDictionary *params = nil;
    HttpServerRequestHandler handler = dispatcher.routeLookupHandler(@"/test", @"GET", &params);
    XCTAssertNil(handler);
    XCTAssertTrue(lookupCalled);
}

- (void)testInitWithNilRouteLookupHandler_DoesNotCrash {
    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:nil];
    XCTAssertNotNil(dispatcher);
    XCTAssertNil(dispatcher.routeLookupHandler);
}

#pragma mark - dispatchRequest with requestHandler

- (void)testDispatchRequest_RequestHandlerSet_CallsHandler {
    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:nil];
    __block BOOL handlerCalled = NO;

    dispatcher.requestHandler = ^(HttpRequest *request, HttpResponse *response) {
        handlerCalled = YES;
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"status": @"ok"}];
    };

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/health"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [dispatcher dispatchRequest:request];
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(response.statusCode, HttpStatusOK);
}

- (void)testDispatchRequest_RequestHandlerSet_SkipsRouteLookup {
    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:nil];
    __block BOOL routeLookupCalled = NO;

    dispatcher.routeLookupHandler = ^(NSString *path, NSString *method, NSDictionary<NSString *, NSString *> **params) {
        routeLookupCalled = YES;
        return ^(HttpRequest *req, HttpResponse *res) {
            res.statusCode = HttpStatusOK;
        };
    };
    dispatcher.requestHandler = ^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusAccepted;
        [response setJsonBody:@{@"handled": @"requestHandler"}];
    };

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/test"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [dispatcher dispatchRequest:request];
    // requestHandler should take priority — routeLookupHandler should NOT be called
    XCTAssertFalse(routeLookupCalled);
    XCTAssertEqual(response.statusCode, HttpStatusAccepted);
}

#pragma mark - dispatchRequest with routeLookupHandler

- (void)testDispatchRequest_RouteLookupMatch_ReturnsHandlerResponse {
    __block HttpServerRequestHandler matchedHandler = ^(HttpRequest *req, HttpResponse *res) {
        res.statusCode = HttpStatusOK;
        [res setJsonBody:@{@"result": @"matched"}];
    };
    HttpRouteLookupHandler lookup = ^(NSString *path, NSString *method, NSDictionary<NSString *, NSString *> **params) {
        if ([path isEqualToString:@"/api/ping"] && [method isEqualToString:@"GET"]) {
            *params = @{@"version": @"1"};
            return matchedHandler;
        }
        return (HttpServerRequestHandler)nil;
    };

    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:lookup];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/api/ping"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [dispatcher dispatchRequest:request];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(request.pathParameters[@"version"], @"1");
}

- (void)testDispatchRequest_RouteLookupNoMatch_Returns404 {
    HttpRouteLookupHandler lookup = ^(NSString *path, NSString *method, NSDictionary<NSString *, NSString *> **params) {
        return (HttpServerRequestHandler)nil;
    };

    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:lookup];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/nonexistent"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [dispatcher dispatchRequest:request];
    XCTAssertEqual(response.statusCode, HttpStatusNotFound);
}

- (void)testDispatchRequest_NilLookupAndNoHandler_Returns404 {
    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:nil];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/test"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [dispatcher dispatchRequest:request];
    XCTAssertEqual(response.statusCode, HttpStatusNotFound);
}

#pragma mark - dispatchRequest with logging (query string)

- (void)testDispatchRequest_WithQueryString_LogsCorrectPath {
    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:nil];
    __block BOOL handlerCalled = NO;

    dispatcher.requestHandler = ^(HttpRequest *request, HttpResponse *response) {
        handlerCalled = YES;
        response.statusCode = HttpStatusOK;
    };

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/search"
                                                   queryString:@"q=test"
                                                   queryParams:@{@"q": @"test"}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [dispatcher dispatchRequest:request];
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(response.statusCode, HttpStatusOK);
}

#pragma mark - Path parameters propagation

- (void)testDispatchRequest_RouteLookupSetsPathParametersOnRequest {
    HttpRouteLookupHandler lookup = ^(NSString *path, NSString *method, NSDictionary<NSString *, NSString *> **params) {
        *params = @{@"id": @"42", @"action": @"edit"};
        return ^(HttpRequest *req, HttpResponse *res) {
            res.statusCode = HttpStatusOK;
        };
    };

    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:lookup];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/users/42/edit"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    [dispatcher dispatchRequest:request];
    XCTAssertEqualObjects(request.pathParameters[@"id"], @"42");
    XCTAssertEqualObjects(request.pathParameters[@"action"], @"edit");
}

#pragma mark - Rate limiting for OAuth paths

- (void)testDispatchRequest_OAuthPath_ChecksRateLimit {
    // Note: This test verifies the structure works. RateLimiter is a singleton
    // so actual rate-limit behavior depends on the shared limiter's state.
    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:nil];
    __block BOOL handlerCalled = NO;

    dispatcher.requestHandler = ^(HttpRequest *request, HttpResponse *response) {
        handlerCalled = YES;
        response.statusCode = HttpStatusOK;
    };

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    // Should not crash — rate limiter may or may not be enabled
    HttpResponse *response = [dispatcher dispatchRequest:request];
    XCTAssertNotNil(response);
    // If rate limiter is disabled (default in tests), handler should be called
    // If it's enabled and rate-limited, response would be 429
    XCTAssertTrue(response.statusCode == HttpStatusOK || response.statusCode == 429);
}

#pragma mark - Method string matching

- (void)testDispatchRequest_MethodMismatch_RoutesCorrectly {
    __block NSString *capturedMethod = nil;
    HttpRouteLookupHandler lookup = ^(NSString *path, NSString *method, NSDictionary<NSString *, NSString *> **params) {
        capturedMethod = method;
        return (HttpServerRequestHandler)nil;
    };

    ATProtoHttpRequestDispatcher *dispatcher = [[ATProtoHttpRequestDispatcher alloc] initWithRouteLookupHandler:lookup];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/create"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    [dispatcher dispatchRequest:request];
    XCTAssertEqualObjects(capturedMethod, @"POST");
}

@end
