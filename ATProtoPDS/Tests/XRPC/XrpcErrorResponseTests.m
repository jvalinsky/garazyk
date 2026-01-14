#import <XCTest/XCTest.h>
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface XrpcErrorResponseTests : XCTestCase
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@end

@implementation XrpcErrorResponseTests

- (void)setUp {
    [super setUp];
    self.dispatcher = [[XrpcDispatcher alloc] init];
}

- (void)tearDown {
    self.dispatcher = nil;
    [super tearDown];
}

- (void)testErrorResponseFormat {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.method"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    XCTAssertEqual(response.statusCode, HttpStatusNotImplemented);
    NSDictionary *body = response.jsonBody;
    XCTAssertNotNil(body, @"Error response should have a body");
    XCTAssertNotNil(body[@"error"], @"Error response should have 'error' field");
    XCTAssertNotNil(body[@"message"], @"Error response should have 'message' field");
}

- (void)testUnknownMethodReturnsNotImplemented {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.example.unknown"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    XCTAssertEqual(response.statusCode, HttpStatusNotImplemented);
}

- (void)testRateLimitResponse {
    __block BOOL rateLimited = NO;
    [self.dispatcher registerMethod:@"test.rateLimited" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusTooManyRequests;
        [response setJsonBody:@{@"error": @"RateLimitExceeded", @"message": @"Rate limit exceeded"}];
        [response setHeader:@"100" forKey:@"X-RateLimit-Limit"];
        [response setHeader:@"0" forKey:@"X-RateLimit-Remaining"];
        [response setHeader:@"1700000000" forKey:@"X-RateLimit-Reset"];
        rateLimited = YES;
    }];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.rateLimited"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    XCTAssertEqual(response.statusCode, HttpStatusTooManyRequests);
    XCTAssertTrue(rateLimited);
    XCTAssertEqualObjects(response.headers[@"X-RateLimit-Limit"], @"100");
}

- (void)testUnauthorizedForMissingAuth {
    __block BOOL authRequiredCalled = NO;
    [self.dispatcher registerMethod:@"test.authRequired" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *auth = [request headerForKey:@"Authorization"];
        if (!auth) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"Unauthorized", @"message": @"Authentication required"}];
            authRequiredCalled = YES;
        } else {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"result": @"success"}];
        }
    }];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.authRequired"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertTrue(authRequiredCalled);
}

- (void)testForbiddenForInsufficientScope {
    __block BOOL scopeErrorCalled = NO;
    [self.dispatcher registerMethod:@"test.privileged" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Insufficient scope"}];
        scopeErrorCalled = YES;
    }];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.privileged"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    XCTAssertEqual(response.statusCode, HttpStatusForbidden);
    XCTAssertTrue(scopeErrorCalled);
}

- (void)testNotFoundForMissingResource {
    __block BOOL notFoundCalled = NO;
    [self.dispatcher registerMethod:@"test.getRecord" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = request.queryParams[@"repo"];
        if (!did) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Record not found"}];
            notFoundCalled = YES;
        } else {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"result": @"success"}];
        }
    }];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.getRecord"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    XCTAssertEqual(response.statusCode, HttpStatusNotFound);
    XCTAssertTrue(notFoundCalled);
}

- (void)testMissingRequiredParameter {
    __block BOOL paramErrorCalled = NO;
    [self.dispatcher registerMethod:@"test.requiredParams" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *required = request.queryParams[@"required"];
        if (!required) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing required parameter: required"}];
            paramErrorCalled = YES;
        } else {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"result": @"success"}];
        }
    }];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.requiredParams"
                                                   queryString:@"optional=value"
                                                   queryParams:@{@"optional": @"value"}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    XCTAssertTrue(paramErrorCalled);
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
}

#pragma mark - Phase 2 Extended Error Response Tests

- (void)testRecordNotFoundError {
    __block BOOL handlerCalled = NO;
    [self.dispatcher registerMethod:@"com.atproto.repo.getRecord" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Record not found"}];
        handlerCalled = YES;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.repo.getRecord"
                                                   queryString:@"repo=did:plc:test&collection=app.bsky.feed.post&rkey=nonexistent"
                                                   queryParams:@{@"repo": @"did:plc:test", @"collection": @"app.bsky.feed.post", @"rkey": @"nonexistent"}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"RecordNotFound");
}

- (void)testRepoNotFoundError {
    __block BOOL handlerCalled = NO;
    [self.dispatcher registerMethod:@"com.atproto.repo.describeRepo" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
        handlerCalled = YES;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.repo.describeRepo"
                                                   queryString:@"repo=did:plc:nonexistent"
                                                   queryParams:@{@"repo": @"did:plc:nonexistent"}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"RepoNotFound");
}

- (void)testInvalidTokenError {
    __block BOOL handlerCalled = NO;
    [self.dispatcher registerMethod:@"test.invalidToken" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Token is malformed or invalid"}];
        handlerCalled = YES;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.invalidToken"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Authorization": @"Bearer invalid.token.here"}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testExpiredTokenError {
    __block BOOL handlerCalled = NO;
    [self.dispatcher registerMethod:@"test.expiredToken" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"ExpiredToken", @"message": @"Token has expired"}];
        handlerCalled = YES;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.expiredToken"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Authorization": @"Bearer expired.jwt.token"}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"ExpiredToken");
}

- (void)testUpstreamFailureError {
    __block BOOL handlerCalled = NO;
    [self.dispatcher registerMethod:@"test.upstreamTimeout" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGatewayTimeout;
        [response setJsonBody:@{@"error": @"UpstreamFailure", @"message": @"Upstream service timed out"}];
        handlerCalled = YES;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.upstreamTimeout"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(response.statusCode, HttpStatusGatewayTimeout);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"UpstreamFailure");
}

- (void)testInternalServerError {
    __block BOOL handlerCalled = NO;
    [self.dispatcher registerMethod:@"test.serverError" handler:^(HttpRequest *request, HttpResponse *response) {
        // Simulate an internal error
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": @"InternalServerError", @"message": @"An unexpected error occurred"}];
        handlerCalled = YES;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.serverError"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(response.statusCode, HttpStatusInternalServerError);
    XCTAssertNotNil(response.jsonBody[@"error"]);
}

- (void)testErrorResponseStructure {
    // All XRPC errors must have 'error' field, 'message' is optional
    [self.dispatcher registerMethod:@"test.errorStructure" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"TestError",
            @"message": @"This is a test error message"
        }];
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.errorStructure"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    NSDictionary *body = response.jsonBody;
    XCTAssertNotNil(body, @"Error response must have a body");
    XCTAssertNotNil(body[@"error"], @"Error response must have 'error' field");
    XCTAssertTrue([body[@"error"] isKindOfClass:[NSString class]], @"Error field must be a string");
    
    // Message is optional but if present must be a string
    if (body[@"message"]) {
        XCTAssertTrue([body[@"message"] isKindOfClass:[NSString class]], @"Message field must be a string");
    }
}

@end

NS_ASSUME_NONNULL_END

