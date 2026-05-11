// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpRouter.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpRouterTests : XCTestCase
@end

@implementation HttpRouterTests

- (BOOL)waitForHandlerInRouter:(HttpRouter *)router request:(HttpRequest *)request {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        if ([router handlerForRequest:request] != nil) {
            return YES;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return NO;
}

- (void)testExactMatchHandlesRequest {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block BOOL called = NO;

    [router addRoute:@"GET" pattern:@"health" handler:^(HttpRequest *request, HttpResponse *response) {
        called = YES;
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/health"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self waitForHandlerInRouter:router request:request]);

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:request response:response];

    XCTAssertTrue(called);
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testMethodMismatchReturnsNotFound {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block BOOL called = NO;

    [router addRoute:@"GET" pattern:@"health" handler:^(HttpRequest *request, HttpResponse *response) {
        called = YES;
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *readyRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                        methodString:@"GET"
                                                                path:@"/health"
                                                         queryString:@""
                                                          queryParams:@{}
                                                              version:@"HTTP/1.1"
                                                              headers:@{}
                                                                 body:[NSData data]
                                                         remoteAddress:@"127.0.0.1"];
    XCTAssertTrue([self waitForHandlerInRouter:router request:readyRequest]);

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/health"
                                                   queryString:@""
                                                    queryParams:@{}
                                                        version:@"HTTP/1.1"
                                                        headers:@{}
                                                           body:[NSData data]
                                                   remoteAddress:@"127.0.0.1"];

    XCTAssertFalse([self waitForHandlerInRouter:router request:request]);

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:request response:response];

    XCTAssertFalse(called);
    XCTAssertEqual(response.statusCode, 404);
}

- (void)testParameterizedRouteAndExtraction {
    HttpRouter *router = [[HttpRouter alloc] init];
    __weak HttpRouter *weakRouter = router;
    __block NSString *userId = nil;

    [router addRoute:@"GET" pattern:@"users/:id" handler:^(HttpRequest *request, HttpResponse *response) {
        HttpRouter *strongRouter = weakRouter;
        NSDictionary *params = [strongRouter extractParametersFromPath:@"users/123" pattern:@"users/:id"];
        userId = params[@"id"];
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/users/123"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self waitForHandlerInRouter:router request:request]);

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:request response:response];

    XCTAssertEqualObjects(userId, @"123");
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testWildcardRouteMatch {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block BOOL called = NO;

    [router addRoute:@"GET" pattern:@"files/*" handler:^(HttpRequest *request, HttpResponse *response) {
        called = YES;
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/files/abc"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self waitForHandlerInRouter:router request:request]);

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:request response:response];

    XCTAssertTrue(called);
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testWildcardRouteDeepPathMatch {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block BOOL called = NO;

    [router addRoute:@"GET" pattern:@"explore/*" handler:^(HttpRequest *request, HttpResponse *response) {
        called = YES;
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/explore/css/style.css"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self waitForHandlerInRouter:router request:request]);

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:request response:response];

    XCTAssertTrue(called, @"Wildcard route should match /explore/css/style.css");
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testWildcardRouteWithMultiplePathSegmentsIsSuccessful {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block BOOL called = NO;

    [router addRoute:@"GET" pattern:@"api/*" handler:^(HttpRequest *request, HttpResponse *response) {
        called = YES;
        response.statusCode = 200;
    } priority:1000];

    NSArray *paths = @[
        @"/api/users",
        @"/api/users/123",
        @"/api/users/123/posts",
        @"/api/v1/users/123/posts/456"
    ];

    for (NSString *path in paths) {
        HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                      methodString:@"GET"
                                                              path:path
                                                       queryString:@""
                                                       queryParams:@{}
                                                           version:@"HTTP/1.1"
                                                           headers:@{}
                                                              body:[NSData data]
                                                      remoteAddress:@"127.0.0.1"];

        XCTAssertTrue([self waitForHandlerInRouter:router request:request],
                      @"Wildcard route should match %@", path);
    }
}

- (void)testWildcardRouteNoMatchForDifferentPrefix {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block BOOL exploreCalled = NO;
    __block BOOL apiCalled = NO;

    [router addRoute:@"GET" pattern:@"explore/*" handler:^(HttpRequest *request, HttpResponse *response) {
        exploreCalled = YES;
        response.statusCode = 200;
    } priority:1000];

    [router addRoute:@"GET" pattern:@"api/*" handler:^(HttpRequest *request, HttpResponse *response) {
        apiCalled = YES;
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *exploreRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                          methodString:@"GET"
                                                                  path:@"/explore/index.html"
                                                           queryString:@""
                                                           queryParams:@{}
                                                               version:@"HTTP/1.1"
                                                               headers:@{}
                                                                  body:[NSData data]
                                                          remoteAddress:@"127.0.0.1"];

    HttpRequest *apiRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                      methodString:@"GET"
                                                              path:@"/api/users"
                                                       queryString:@""
                                                       queryParams:@{}
                                                           version:@"HTTP/1.1"
                                                           headers:@{}
                                                              body:[NSData data]
                                                      remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self waitForHandlerInRouter:router request:exploreRequest]);
    XCTAssertTrue([self waitForHandlerInRouter:router request:apiRequest]);

    [router handleRequest:exploreRequest response:[[HttpResponse alloc] init]];
    [router handleRequest:apiRequest response:[[HttpResponse alloc] init]];

    XCTAssertTrue(exploreCalled, @"Explore handler should be called");
    XCTAssertTrue(apiCalled, @"API handler should be called");
}

- (void)testWildcardRouteMatchesExactPathToo {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block BOOL called = NO;

    [router addRoute:@"GET" pattern:@"explore/*" handler:^(HttpRequest *request, HttpResponse *response) {
        called = YES;
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/explore"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self waitForHandlerInRouter:router request:request],
                  @"Wildcard route /explore/* matches /explore (base path with wildcard catches all)");

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:request response:response];

    XCTAssertTrue(called);
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testWildcardWithParameterRoute {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block NSString *paramValue = nil;

    [router addRoute:@"GET" pattern:@"users/:id/posts/*" handler:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *params = [router extractParametersFromPath:request.path pattern:@"users/:id/posts/*"];
        paramValue = params[@"id"];
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/users/123/posts/456/comments"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self waitForHandlerInRouter:router request:request]);

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:request response:response];

    XCTAssertEqualObjects(paramValue, @"123", @"Parameter :id should be extracted as '123'");
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testWildcardRouteCaseSensitivity {
    HttpRouter *router = [[HttpRouter alloc] init];
    __block BOOL upperCaseCalled = NO;
    __block BOOL lowerCaseCalled = NO;

    [router addRoute:@"GET" pattern:@"Files/*" handler:^(HttpRequest *request, HttpResponse *response) {
        upperCaseCalled = YES;
        response.statusCode = 200;
    } priority:1000];

    [router addRoute:@"GET" pattern:@"files/*" handler:^(HttpRequest *request, HttpResponse *response) {
        lowerCaseCalled = YES;
        response.statusCode = 200;
    } priority:1000];

    HttpRequest *upperRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                        methodString:@"GET"
                                                                path:@"/Files/test"
                                                         queryString:@""
                                                         queryParams:@{}
                                                             version:@"HTTP/1.1"
                                                             headers:@{}
                                                                body:[NSData data]
                                                        remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([self waitForHandlerInRouter:router request:upperRequest]);

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:upperRequest response:response];

    XCTAssertTrue(upperCaseCalled);
    XCTAssertFalse(lowerCaseCalled, @"Case-sensitive routing should match only Files/*");
}

@end

NS_ASSUME_NONNULL_END
