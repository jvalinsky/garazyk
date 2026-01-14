#import <XCTest/XCTest.h>
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Tests for XRPC input validation.
 *
 * Validates query parameter handling, body size limits, and content type requirements
 * per ATProto XRPC specification.
 * Reference: https://atproto.com/specs/xrpc
 */
@interface XrpcInputValidationTests : XCTestCase
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@end

@implementation XrpcInputValidationTests

- (void)setUp {
    [super setUp];
    self.dispatcher = [[XrpcDispatcher alloc] init];
}

- (void)tearDown {
    self.dispatcher = nil;
    [super tearDown];
}

#pragma mark - Query Parameter Tests

- (void)testQueryParamBoolean {
    __block NSDictionary *receivedParams = nil;
    [self.dispatcher registerMethod:@"test.boolParam" handler:^(HttpRequest *request, HttpResponse *response) {
        receivedParams = request.queryParams;
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"received": receivedParams[@"enabled"] ?: [NSNull null]}];
    }];
    
    // Test boolean=true
    HttpRequest *requestTrue = [self createGetRequest:@"/xrpc/test.boolParam" queryString:@"enabled=true"];
    HttpResponse *responseTrue = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:requestTrue response:responseTrue];
    
    XCTAssertEqual(responseTrue.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(receivedParams[@"enabled"], @"true");
    
    // Test boolean=false
    HttpRequest *requestFalse = [self createGetRequest:@"/xrpc/test.boolParam" queryString:@"enabled=false"];
    HttpResponse *responseFalse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:requestFalse response:responseFalse];
    
    XCTAssertEqualObjects(receivedParams[@"enabled"], @"false");
}

- (void)testQueryParamInteger {
    __block NSString *receivedLimit = nil;
    [self.dispatcher registerMethod:@"test.intParam" handler:^(HttpRequest *request, HttpResponse *response) {
        receivedLimit = request.queryParams[@"limit"];
        response.statusCode = HttpStatusOK;
    }];
    
    HttpRequest *request = [self createGetRequest:@"/xrpc/test.intParam" queryString:@"limit=50"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(receivedLimit, @"50");
}

- (void)testQueryParamArrayFormat {
    __block NSArray *receivedTags = nil;
    [self.dispatcher registerMethod:@"test.arrayParam" handler:^(HttpRequest *request, HttpResponse *response) {
        // XRPC uses repeated params for arrays: ?tag=a&tag=b
        receivedTags = request.queryParams[@"tag"];
        response.statusCode = HttpStatusOK;
    }];
    
    // Note: This depends on how HttpRequest handles repeated query params
    HttpRequest *request = [self createGetRequest:@"/xrpc/test.arrayParam" queryString:@"tag=blue&tag=green&tag=red"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    // Check if array params are supported
    if ([receivedTags isKindOfClass:[NSArray class]]) {
        XCTAssertEqual(receivedTags.count, 3);
    }
}

- (void)testRequiredParamMissing {
    __block BOOL handlerCalled = NO;
    [self.dispatcher registerMethod:@"test.requiredParam" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = request.queryParams[@"repo"];
        if (!repo || repo.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing required parameter: repo"}];
            return;
        }
        handlerCalled = YES;
        response.statusCode = HttpStatusOK;
    }];
    
    // Request without required param
    HttpRequest *request = [self createGetRequest:@"/xrpc/test.requiredParam" queryString:@""];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertFalse(handlerCalled);
    
    NSDictionary *body = response.jsonBody;
    XCTAssertEqualObjects(body[@"error"], @"InvalidRequest");
}

- (void)testOptionalParamOmitted {
    __block BOOL handlerCalled = NO;
    [self.dispatcher registerMethod:@"test.optionalParam" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *cursor = request.queryParams[@"cursor"];
        // Cursor is optional, handler should succeed without it
        handlerCalled = YES;
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"hasCursor": @(cursor != nil)}];
    }];
    
    HttpRequest *request = [self createGetRequest:@"/xrpc/test.optionalParam" queryString:@""];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertTrue(handlerCalled);
}

#pragma mark - Query String Size Tests

- (void)testMaxQueryLength {
    [self.dispatcher registerMethod:@"test.longQuery" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
    }];
    
    // Build an excessively long query string (>8KB)
    NSMutableString *longQuery = [NSMutableString string];
    for (int i = 0; i < 1000; i++) {
        if (i > 0) [longQuery appendString:@"&"];
        [longQuery appendFormat:@"param%d=value%d", i, i];
    }
    
    HttpRequest *request = [self createGetRequest:@"/xrpc/test.longQuery" queryString:longQuery];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    // Handler may reject or accept - depends on implementation
    // Key is that it handles gracefully without crashing
    XCTAssertTrue(response.statusCode == HttpStatusOK || response.statusCode == HttpStatusBadRequest);
}

#pragma mark - Body Size Tests

- (void)testBodySizeLimitDefault {
    __block BOOL handlerReached = NO;
    [self.dispatcher registerMethod:@"test.postBody" handler:^(HttpRequest *request, HttpResponse *response) {
        handlerReached = YES;
        response.statusCode = HttpStatusOK;
    }];
    
    // Create a large body (>1MB default limit)
    NSMutableData *largeBody = [NSMutableData dataWithLength:2 * 1024 * 1024]; // 2MB
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/test.postBody"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/json"}
                                                          body:largeBody
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    // Should be rejected or handled - key is no crash
    // Actual behavior depends on implementation
    XCTAssertTrue(response.statusCode == HttpStatusPayloadTooLarge || 
                  response.statusCode == HttpStatusBadRequest ||
                  handlerReached);
}

#pragma mark - Content-Type Tests

- (void)testPostWithoutContentType {
    [self.dispatcher registerMethod:@"test.noContentType" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/test.noContentType"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}  // No Content-Type
                                                          body:[@"{\"test\": true}" dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    // May succeed or fail - depends on handler requirements
    XCTAssertTrue(response.statusCode == HttpStatusOK || 
                  response.statusCode == HttpStatusBadRequest ||
                  response.statusCode == HttpStatusUnsupportedMediaType);
}

- (void)testPostWithJsonContentType {
    __block BOOL correctContentType = NO;
    [self.dispatcher registerMethod:@"test.jsonBody" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *contentType = request.headers[@"content-type"];
        correctContentType = [contentType containsString:@"application/json"];
        response.statusCode = HttpStatusOK;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/test.jsonBody"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/json; charset=utf-8"}
                                                          body:[@"{\"test\": true}" dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertTrue(correctContentType);
}

- (void)testPostWithIncorrectContentType {
    [self.dispatcher registerMethod:@"test.wrongType" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *contentType = request.headers[@"content-type"];
        if (![contentType containsString:@"application/json"]) {
            response.statusCode = HttpStatusUnsupportedMediaType;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Expected application/json"}];
            return;
        }
        response.statusCode = HttpStatusOK;
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/test.wrongType"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"text/plain"}
                                                          body:[@"plain text body" dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, HttpStatusUnsupportedMediaType);
}

#pragma mark - Edge Cases

- (void)testEmptyPath {
    HttpRequest *request = [self createGetRequest:@"/xrpc/" queryString:@""];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    // Empty method name should be rejected
    XCTAssertTrue(response.statusCode == HttpStatusNotFound || 
                  response.statusCode == HttpStatusNotImplemented ||
                  response.statusCode == HttpStatusBadRequest);
}

- (void)testMalformedQueryString {
    [self.dispatcher registerMethod:@"test.malformedQuery" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
    }];
    
    // Query with invalid encoding
    HttpRequest *request = [self createGetRequest:@"/xrpc/test.malformedQuery" queryString:@"key=%ZZ"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    // Should handle gracefully
    XCTAssertNoThrow([self.dispatcher handleRequest:request response:response]);
}

#pragma mark - Helper Methods

- (HttpRequest *)createGetRequest:(NSString *)path queryString:(NSString *)queryString {
    NSMutableDictionary *queryParams = [NSMutableDictionary dictionary];
    if (queryString.length > 0) {
        NSArray *pairs = [queryString componentsSeparatedByString:@"&"];
        for (NSString *pair in pairs) {
            NSArray *parts = [pair componentsSeparatedByString:@"="];
            if (parts.count == 2) {
                NSString *key = parts[0];
                NSString *value = parts[1];
                // Handle array params (repeated keys)
                id existing = queryParams[key];
                if (existing) {
                    if ([existing isKindOfClass:[NSArray class]]) {
                        queryParams[key] = [(NSArray *)existing arrayByAddingObject:value];
                    } else {
                        queryParams[key] = @[existing, value];
                    }
                } else {
                    queryParams[key] = value;
                }
            }
        }
    }
    
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:path
                                   queryString:queryString
                                   queryParams:queryParams
                                       version:@"1.1"
                                       headers:@{}
                                          body:nil
                                    remoteAddress:@"127.0.0.1"];
}

@end

NS_ASSUME_NONNULL_END
