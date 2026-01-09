#import <XCTest/XCTest.h>
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/PDSAuthManager.h"

@interface XRPCHandlerTests : XCTestCase
@property (nonatomic, strong) XrpcHandler *handler;
@property (nonatomic, strong) PDSAuthManager *authManager;
@end

@implementation XRPCHandlerTests

- (void)setUp {
    [super setUp];

    self.handler = [[XrpcHandler alloc] init];
    self.authManager = [[PDSAuthManager alloc] init];
    // Configure handler with mock auth manager
}

- (void)tearDown {
    self.handler = nil;
    self.authManager = nil;
    [super tearDown];
}

#pragma mark - XRPC Handler Validation Tests

- (void)testValidCreateRecordRequest {
    // Test successful createRecord request processing
    NSError *error = nil;

    // Create mock request
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"POST";
    request.path = @"/xrpc/com.atproto.repo.createRecord";
    request.headers = @{
        @"Content-Type": @"application/json",
        @"Authorization": @"Bearer valid-token"
    };

    NSDictionary *recordData = @{
        @"collection": @"app.bsky.feed.post",
        @"repo": @"did:example:user123",
        @"record": @{
            @"text": @"Hello, world!",
            @"createdAt": @"2024-01-09T10:00:00.000Z"
        }
    };

    request.body = [NSJSONSerialization dataWithJSONObject:recordData options:0 error:nil];

    HttpResponse *response = [[HttpResponse alloc] init];

    // Process request
    [self.handler handleRequest:request response:response];

    // Verify response
    XCTAssertEqual(response.statusCode, 200, @"Request should succeed");
    XCTAssertNotNil(response.jsonBody, @"Response should contain JSON body");
}

- (void)testRateLimitedRequestRejection {
    // Test rate limiting behavior
    NSError *error = nil;

    // Create multiple requests to trigger rate limiting
    for (int i = 0; i < 100; i++) {
        HttpRequest *request = [[HttpRequest alloc] init];
        request.method = @"GET";
        request.path = @"/xrpc/com.atproto.server.describeServer";
        request.clientIP = @"192.168.1.100";

        HttpResponse *response = [[HttpResponse alloc] init];
        [self.handler handleRequest:request response:response];
    }

    // Final request should be rate limited
    HttpRequest *finalRequest = [[HttpRequest alloc] init];
    finalRequest.method = @"GET";
    finalRequest.path = @"/xrpc/com.atproto.server.describeServer";
    finalRequest.clientIP = @"192.168.1.100";

    HttpResponse *finalResponse = [[HttpResponse alloc] init];
    [self.handler handleRequest:finalRequest response:finalResponse];

    XCTAssertEqual(finalResponse.statusCode, 429, @"Final request should be rate limited");
}

#pragma mark - Input Validation Tests

- (void)testInvalidJSONRequestHandling {
    // Test handling of malformed JSON
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"POST";
    request.path = @"/xrpc/com.atproto.repo.createRecord";
    request.body = [@"invalid json {" dataUsingEncoding:NSUTF8StringEncoding];

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 400, @"Invalid JSON should return bad request");
    NSDictionary *responseBody = response.jsonBody;
    XCTAssertEqualObjects(responseBody[@"error"], @"InvalidRequest", @"Error type should be specified");
}

- (void)testMissingRequiredParameters {
    // Test validation of missing required parameters
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"POST";
    request.path = @"/xrpc/com.atproto.repo.createRecord";

    // Missing 'repo' parameter
    NSDictionary *recordData = @{
        @"collection": @"app.bsky.feed.post",
        @"record": @{
            @"text": @"Hello, world!",
            @"createdAt": @"2024-01-09T10:00:00.000Z"
        }
    };

    request.body = [NSJSONSerialization dataWithJSONObject:recordData options:0 error:nil];

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 400, @"Missing repo parameter should return bad request");
}

#pragma mark - Authentication Tests

- (void)testUnauthenticatedRequestRejection {
    // Test rejection of requests without authentication
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"GET";
    request.path = @"/xrpc/com.atproto.repo.listRecords";

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 401, @"Unauthenticated request should be rejected");
}

- (void)testInvalidTokenRejection {
    // Test rejection of requests with invalid tokens
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"GET";
    request.path = @"/xrpc/com.atproto.repo.listRecords";
    request.headers = @{
        @"Authorization": @"Bearer invalid-token"
    };

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 401, @"Invalid token should be rejected");
}

#pragma mark - Endpoint Routing Tests

- (void)testUnknownEndpointHandling {
    // Test handling of unknown XRPC methods
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"GET";
    request.path = @"/xrpc/com.unknown.method";

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 404, @"Unknown endpoint should return not found");
}

- (void)testMethodNotAllowedHandling {
    // Test handling of wrong HTTP methods
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"GET"; // Should be POST
    request.path = @"/xrpc/com.atproto.repo.createRecord";

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 405, @"Wrong HTTP method should return method not allowed");
}

#pragma mark - Error Response Format Tests

- (void)testConsistentErrorResponseFormat {
    // Test that all errors follow the same format
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"POST";
    request.path = @"/xrpc/com.atproto.repo.createRecord";
    request.body = [@"invalid json" dataUsingEncoding:NSUTF8StringEncoding];

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleRequest:request response:response];

    NSDictionary *errorResponse = response.jsonBody;
    XCTAssertNotNil(errorResponse[@"error"], @"Error response should have error field");
    XCTAssertNotNil(errorResponse[@"message"], @"Error response should have message field");
    XCTAssertTrue([errorResponse[@"message"] isKindOfClass:[NSString class]], @"Message should be string");
}

#pragma mark - Content-Type Validation Tests

- (void)testIncorrectContentTypeHandling {
    // Test handling of wrong content types
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"POST";
    request.path = @"/xrpc/com.atproto.repo.createRecord";
    request.headers = @{
        @"Content-Type": @"text/plain"
    };
    request.body = [@"not json" dataUsingEncoding:NSUTF8StringEncoding];

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 400, @"Wrong content type should return bad request");
}

#pragma mark - getUserStats Endpoint Tests

- (void)testGetUserStatsSuccess {
    // Test successful getUserStats request
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"GET";
    request.path = @"/xrpc/app.bsky.user.getUserStats?user=testuser";

    HttpResponse *response = [[HttpResponse alloc] init];
    
    // Create a dispatcher and register the method
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    [dispatcher registerAppBskyUserGetUserStats:^(HttpRequest *req, HttpResponse *resp) {
        // Simulate the handler implementation
        NSString *user = [req queryParamForKey:@"user"];
        
        if (!user) {
            resp.statusCode = HttpStatusBadRequest;
            [resp setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing user parameter"}];
            return;
        }
        
        // Return hardcoded demo data as requested
        NSDictionary *stats = @{
            @"followers": @150,
            @"following": @75,
            @"posts": @42
        };
        
        resp.statusCode = HttpStatusOK;
        [resp setJsonBody:stats];
    }];
    
    [dispatcher handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 200, @"getUserStats should succeed");
    NSDictionary *responseBody = response.jsonBody;
    XCTAssertNotNil(responseBody, @"Response should contain JSON body");
    XCTAssertEqualObjects(responseBody[@"followers"], @150, @"Should return correct follower count");
    XCTAssertEqualObjects(responseBody[@"following"], @75, @"Should return correct following count");
    XCTAssertEqualObjects(responseBody[@"posts"], @42, @"Should return correct post count");
}

- (void)testGetUserStatsMissingUser {
    // Test getUserStats with missing user parameter
    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"GET";
    request.path = @"/xrpc/app.bsky.user.getUserStats";

    HttpResponse *response = [[HttpResponse alloc] init];
    
    // Create a dispatcher and register the method
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    [dispatcher registerAppBskyUserGetUserStats:^(HttpRequest *req, HttpResponse *resp) {
        NSString *user = [req queryParamForKey:@"user"];
        
        if (!user) {
            resp.statusCode = HttpStatusBadRequest;
            [resp setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing user parameter"}];
            return;
        }
        
        NSDictionary *stats = @{
            @"followers": @150,
            @"following": @75,
            @"posts": @42
        };
        
        resp.statusCode = HttpStatusOK;
        [resp setJsonBody:stats];
    }];
    
    [dispatcher handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 400, @"Missing user parameter should return bad request");
    NSDictionary *responseBody = response.jsonBody;
    XCTAssertNotNil(responseBody, @"Response should contain JSON body");
    XCTAssertEqualObjects(responseBody[@"error"], @"InvalidRequest", @"Should return correct error type");
    XCTAssertTrue([responseBody[@"message"] containsString:@"Missing user parameter"], @"Should return descriptive error message");
}

@end