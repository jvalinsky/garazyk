// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpRetryPolicy.h"

@interface HttpRetryPolicyTests : XCTestCase
@property (nonatomic, strong) HttpRetryPolicy *policy;
@end

@implementation HttpRetryPolicyTests

- (void)setUp {
    [super setUp];
    self.policy = [[HttpRetryPolicy alloc] init];
}

- (void)tearDown {
    self.policy = nil;
    [super tearDown];
}

- (void)testSucceedsOn200MatchesDecisionSucceed {
    HttpRetryResult *result = [self.policy evaluateStatusCode:200 networkError:nil attemptNumber:0];
    XCTAssertEqual(result.decision, HttpRetryDecisionSucceed);
    XCTAssertEqual(result.retryDelay, 0.0);
}

- (void)testFailsImmediatelyOn404MatchesDecisionFail {
    HttpRetryResult *result = [self.policy evaluateStatusCode:404 networkError:nil attemptNumber:0];
    XCTAssertEqual(result.decision, HttpRetryDecisionFail);
    XCTAssertEqual(result.retryDelay, 0.0);
}

- (void)testRetriesOn500WithExponentialBackoff {
    // Attempt 0
    HttpRetryResult *result0 = [self.policy evaluateStatusCode:500 networkError:nil attemptNumber:0];
    XCTAssertEqual(result0.decision, HttpRetryDecisionRetryAfter);
    XCTAssertEqualWithAccuracy(result0.retryDelay, 0.5, 0.01);

    // Attempt 1
    HttpRetryResult *result1 = [self.policy evaluateStatusCode:500 networkError:nil attemptNumber:1];
    XCTAssertEqual(result1.decision, HttpRetryDecisionRetryAfter);
    XCTAssertEqualWithAccuracy(result1.retryDelay, 1.0, 0.01);

    // Attempt 2
    HttpRetryResult *result2 = [self.policy evaluateStatusCode:502 networkError:nil attemptNumber:2];
    XCTAssertEqual(result2.decision, HttpRetryDecisionRetryAfter);
    XCTAssertEqualWithAccuracy(result2.retryDelay, 2.0, 0.01);

    // Attempt 3 (Max retries reached)
    HttpRetryResult *result3 = [self.policy evaluateStatusCode:503 networkError:nil attemptNumber:3];
    XCTAssertEqual(result3.decision, HttpRetryDecisionFail);
    XCTAssertEqual(result3.retryDelay, 0.0);
}

- (void)testRetriesOnNetworkError {
    NSError *error = [NSError errorWithDomain:@"TestDomain" code:-1001 userInfo:nil];
    
    // Attempt 0
    HttpRetryResult *result0 = [self.policy evaluateStatusCode:0 networkError:error attemptNumber:0];
    XCTAssertEqual(result0.decision, HttpRetryDecisionRetryAfter);
    XCTAssertEqualWithAccuracy(result0.retryDelay, 0.5, 0.01);
    
    // Attempt 3 (Max retries reached)
    HttpRetryResult *result3 = [self.policy evaluateStatusCode:0 networkError:error attemptNumber:3];
    XCTAssertEqual(result3.decision, HttpRetryDecisionFail);
}

- (void)testCustomPolicySettings {
    self.policy.maxRetries = 5;
    self.policy.initialDelay = 1.0;
    self.policy.backoffMultiplier = 3.0;
    
    HttpRetryResult *result1 = [self.policy evaluateStatusCode:500 networkError:nil attemptNumber:1];
    XCTAssertEqual(result1.decision, HttpRetryDecisionRetryAfter);
    XCTAssertEqualWithAccuracy(result1.retryDelay, 3.0, 0.01); // 1.0 * 3.0^1
    
    HttpRetryResult *result5 = [self.policy evaluateStatusCode:500 networkError:nil attemptNumber:5];
    XCTAssertEqual(result5.decision, HttpRetryDecisionFail);
}

@end