#import <XCTest/XCTest.h>

// Sample Network domain test: SSRF and async patterns
@interface SSRFValidatorTests : XCTestCase
@end

@implementation SSRFValidatorTests

- (void)testSSRFBlocksPrivateIPs {
    // Good SSRF test with rejection
    NSURL *privateURL = [NSURL URLWithString:@"http://192.168.1.1/admin"];
    NSError *error = nil;
    BOOL allowed = [self validateURL:privateURL error:&error];
    XCTAssertFalse(allowed, @"Private IPs should be blocked");
    XCTAssertNotNil(error);
}

- (void)testAsyncNetworkRequest {
    // Async test without proper expectation handling
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [self fetchData];
        XCTAssertNotNil(data);
    });
}

- (void)testAsyncWithProperExpectation {
    XCTestExpectation *expectation = [self expectationWithDescription:@"network call"];
    [self performNetworkCallWithCompletion:^(NSData *data, NSError *error) {
        XCTAssertNotNil(data);
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testHTTPErrorHandling {
    // Claims to test error handling but doesn't verify rejection
    NSURLResponse *response = [self sendRequestToServer];
    XCTAssertNotNil(response);
}

@end
