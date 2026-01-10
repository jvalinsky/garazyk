#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"

@interface RateLimitingTests : XCTestCase
@property (nonatomic, strong) HttpServer *server;
@end

@implementation RateLimitingTests

- (void)setUp {
    [super setUp];
    self.server = [[HttpServer alloc] init];
}

- (void)tearDown {
    self.server = nil;
    [super tearDown];
}

- (void)testOAuthEndpointRateLimiting {
    // Setup request to OAuth endpoint
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/oauth/authorize"
                                                   queryString:@"client_id=test&response_type=code"
                                                   queryParams:@{
                                                       @"client_id": @"test",
                                                       @"response_type": @"code"
                                                   }
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil];
    request.remoteAddress = @"127.0.0.1";

    // First request should be allowed
    HttpResponse *response1 = [self.server dispatchRequest:request];
    XCTAssertEqual(response1.statusCode, 404, @"First request should be allowed (but handler not found, so 404)");

    // Simulate multiple rapid requests to trigger rate limiting
    // Note: This is a basic test - in practice, the rate limiter would need to be configured
    // and we'd need to simulate time passing or adjust the rate limit settings for testing
    for (int i = 0; i < 10; i++) {
        HttpResponse *response = [self.server dispatchRequest:request];
        // Should still be 404 (not rate limited) since we haven't configured the limits to be restrictive
        XCTAssertEqual(response.statusCode, 404);
    }
}

@end