// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Network/GZXrpcRouteSupport.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"

@interface GZXrpcRouteSupportTests : XCTestCase
@property (nonatomic, assign) BOOL oldGlobalDisabled;
@property (nonatomic, assign) BOOL oldEnabled;
@property (nonatomic, assign) NSInteger oldIPLimit;
@property (nonatomic, assign) NSTimeInterval oldIPWindowSeconds;
@end

@implementation GZXrpcRouteSupportTests

- (void)setUp {
    [super setUp];
    RateLimiter *limiter = [RateLimiter sharedLimiter];
    self.oldGlobalDisabled = RateLimiterIsDisabledGlobally();
    self.oldEnabled = limiter.isEnabled;
    self.oldIPLimit = limiter.ipLimit;
    self.oldIPWindowSeconds = limiter.ipWindowSeconds;
}

- (void)tearDown {
    RateLimiter *limiter = [RateLimiter sharedLimiter];
    limiter.ipLimit = self.oldIPLimit;
    limiter.ipWindowSeconds = self.oldIPWindowSeconds;
    limiter.enabled = self.oldEnabled;
    RateLimiterSetDisabledGlobally(self.oldGlobalDisabled);
    [super tearDown];
}

- (HttpRequest *)requestWithQueryParams:(NSDictionary *)queryParams {
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:@"/xrpc/test"
                                   queryString:@""
                                   queryParams:queryParams
                                       version:@"HTTP/1.1"
                                       headers:@{}
                                          body:[NSData data]
                                 remoteAddress:@"203.0.113.9"];
}

- (void)testRequiredQueryParamWritesInvalidRequest {
    HttpRequest *request = [self requestWithQueryParams:@{}];
    HttpResponse *response = [HttpResponse response];

    NSString *value = [GZXrpcRouteSupport requiredQueryParam:@"subject"
                                                     request:request
                                                    response:response];

    XCTAssertNil(value);
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
    XCTAssertEqualObjects(response.jsonBody[@"message"], @"subject parameter is required");
}

- (void)testParseLimitUsesDefaultAndAcceptsBounds {
    NSInteger limit = 0;
    HttpResponse *response = [HttpResponse response];

    XCTAssertTrue([GZXrpcRouteSupport parseLimitForRequest:[self requestWithQueryParams:@{}]
                                              defaultLimit:16
                                                       min:1
                                                       max:100
                                                    output:&limit
                                                  response:response]);
    XCTAssertEqual(limit, 16);

    XCTAssertTrue([GZXrpcRouteSupport parseLimitForRequest:[self requestWithQueryParams:@{@"limit": @"100"}]
                                              defaultLimit:16
                                                       min:1
                                                       max:100
                                                    output:&limit
                                                  response:response]);
    XCTAssertEqual(limit, 100);
}

- (void)testParseLimitRejectsInvalidValues {
    NSArray<NSString *> *invalidValues = @[@"0", @"101", @"1x", @" 1"];
    for (NSString *value in invalidValues) {
        NSInteger limit = 16;
        HttpResponse *response = [HttpResponse response];
        XCTAssertFalse([GZXrpcRouteSupport parseLimitForRequest:[self requestWithQueryParams:@{@"limit": value}]
                                                   defaultLimit:16
                                                            min:1
                                                            max:100
                                                         output:&limit
                                                       response:response]);
        XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
        XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
        XCTAssertEqualObjects(response.jsonBody[@"message"], @"limit must be an integer between 1 and 100");
    }
}

- (void)testRateLimitResponseHeadersAndBody {
    RateLimiter *limiter = [RateLimiter sharedLimiter];
    RateLimiterSetDisabledGlobally(NO);
    limiter.enabled = YES;
    limiter.ipLimit = 0;
    limiter.ipWindowSeconds = 60;
    [limiter reconfigureDatabasePath:@":memory:"];

    HttpResponse *response = [HttpResponse response];
    BOOL allowed = [GZXrpcRouteSupport checkIPRateLimitForRequest:[self requestWithQueryParams:@{}]
                                                         response:response];

    XCTAssertFalse(allowed);
    XCTAssertEqual(response.statusCode, HttpStatusTooManyRequests);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"RateLimitExceeded");
    XCTAssertEqualObjects(response.jsonBody[@"message"], @"Too many requests");
    XCTAssertEqualObjects([response headerForKey:@"X-RateLimit-Limit"], @"0");
    XCTAssertEqualObjects([response headerForKey:@"X-RateLimit-Remaining"], @"0");
    XCTAssertNotNil([response headerForKey:@"X-RateLimit-Reset"]);
    XCTAssertNotNil([response headerForKey:@"Retry-After"]);
}

@end
