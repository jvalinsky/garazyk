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

    XCTAssertTrue([self waitForHandlerInRouter:router request:request]);

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

@end

NS_ASSUME_NONNULL_END
