#import <XCTest/XCTest.h>
#import "Network/RateLimiter.h"

@interface RateLimiterTests : XCTestCase

@property (nonatomic, strong) RateLimiter *limiter;
@property (nonatomic, copy) NSString *testDbPath;

@end

@implementation RateLimiterTests

- (void)setUp {
    [super setUp];
    RateLimiterSetDisabledGlobally(NO);
    self.testDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ratelimit_test.db"];
    [[NSFileManager defaultManager] removeItemAtPath:self.testDbPath error:nil];
    self.limiter = [[RateLimiter alloc] initWithDatabasePath:self.testDbPath];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.testDbPath error:nil];
    RateLimiterSetDisabledGlobally(YES);
    [super tearDown];
}

- (void)testSingletonTest {
    RateLimiter *singleton1 = [RateLimiter sharedLimiter];
    RateLimiter *singleton2 = [RateLimiter sharedLimiter];
    XCTAssertEqual(singleton1, singleton2, @"Shared limiter should be the same instance");
}

- (void)testDefaultLimitsTest {
    XCTAssertEqual(self.limiter.didLimit, 5000, @"DID limit should be 5000");
    XCTAssertEqual(self.limiter.didWindowSeconds, 3600, @"DID window should be 3600 seconds");
    XCTAssertEqual(self.limiter.ipLimit, 100, @"IP limit should be 100");
    XCTAssertEqual(self.limiter.ipWindowSeconds, 60, @"IP window should be 60 seconds");
    XCTAssertEqual(self.limiter.blobLimit, 50, @"Blob limit should be 50");
    XCTAssertEqual(self.limiter.blobWindowSeconds, 3600, @"Blob window should be 3600 seconds");
}

- (void)testRateLimitAllowedTest {
    RateLimitResult *result = [self.limiter checkRateLimitForDid:@"did:test:user1"];

    XCTAssertTrue(result.allowed, @"First request should be allowed");
    XCTAssertEqual(result.limit, 5000, @"Limit should be 5000");
}

- (void)testRateLimitDecrementsRemaining {
    RateLimitResult *result1 = [self.limiter checkRateLimitForDid:@"did:test:user2"];
    RateLimitResult *result2 = [self.limiter checkRateLimitForDid:@"did:test:user2"];

    XCTAssertTrue(result1.allowed, @"First request should be allowed");
    XCTAssertTrue(result2.allowed, @"Second request should be allowed");
    XCTAssertEqual(result2.remaining, result1.remaining - 1, @"Remaining should decrement by 1");
}

- (void)testRateLimitForIP {
    RateLimitResult *ipResult = [self.limiter checkRateLimitForIP:@"192.168.1.1"];

    XCTAssertTrue(ipResult.allowed, @"IP request should be allowed");
    XCTAssertEqual(ipResult.limit, 100, @"IP limit should be 100");
}

- (void)testBlobUploadRateLimit {
    RateLimitResult *blobResult = [self.limiter checkBlobUploadRateLimitForDid:@"did:test:blobuser"];

    XCTAssertTrue(blobResult.allowed, @"Blob upload should be allowed");
    XCTAssertEqual(blobResult.limit, 50, @"Blob limit should be 50");
}

- (void)testRateLimitHeadersForDID {
    NSDictionary *didHeaders = [self.limiter rateLimitHeadersForDid:@"did:test:headeruser"];

    XCTAssertNotNil(didHeaders[@"X-RateLimit-Limit"], @"Should have limit header");
    XCTAssertNotNil(didHeaders[@"X-RateLimit-Remaining"], @"Should have remaining header");
    XCTAssertNotNil(didHeaders[@"X-RateLimit-Reset"], @"Should have reset header");
    XCTAssertEqualObjects(didHeaders[@"X-RateLimit-Limit"], @"5000", @"DID limit should be 5000");
}

- (void)testRateLimitHeadersForIP {
    NSDictionary *ipHeaders = [self.limiter rateLimitHeadersForIP:@"10.0.0.1"];

    XCTAssertNotNil(ipHeaders[@"X-RateLimit-Limit"], @"Should have limit header");
    XCTAssertEqualObjects(ipHeaders[@"X-RateLimit-Limit"], @"100", @"IP limit should be 100");
}

- (void)testBlobRateLimitHeaders {
    NSDictionary *blobHeaders = [self.limiter blobRateLimitHeadersForDid:@"did:test:blobheader"];

    XCTAssertNotNil(blobHeaders[@"X-RateLimit-Limit"], @"Should have limit header");
    XCTAssertEqualObjects(blobHeaders[@"X-RateLimit-Limit"], @"50", @"Blob limit should be 50");
}

- (void)testNilDIDReturnsAllowed {
    RateLimitResult *nilDidResult = [self.limiter checkRateLimitForDid:nil];

    XCTAssertTrue(nilDidResult.allowed, @"Nil DID should return allowed");
    XCTAssertEqual(nilDidResult.limit, 5000, @"Nil DID limit should be 5000");
    XCTAssertEqual(nilDidResult.remaining, 5000, @"Nil DID remaining should be 5000");
}

- (void)testEmptyDIDReturnsAllowed {
    RateLimitResult *emptyDidResult = [self.limiter checkRateLimitForDid:@""];

    XCTAssertTrue(emptyDidResult.allowed, @"Empty DID should return allowed");
}

- (void)testNilIPReturnsAllowed {
    RateLimitResult *nilIpResult = [self.limiter checkRateLimitForIP:nil];

    XCTAssertTrue(nilIpResult.allowed, @"Nil IP should return allowed");
    XCTAssertEqual(nilIpResult.limit, 100, @"Nil IP limit should be 100");
}

- (void)testDifferentIdentifiersIndependent {
    NSString *did1 = @"did:test:user1";
    NSString *did2 = @"did:test:user2";
    [self.limiter checkRateLimitForDid:did1];
    [self.limiter checkRateLimitForDid:did1];
    RateLimitResult *result1_ind = [self.limiter checkRateLimitForDid:did1];
    RateLimitResult *result2_ind = [self.limiter checkRateLimitForDid:did2];

    XCTAssertLessThan(result1_ind.remaining, result2_ind.remaining, @"did1 should have fewer remaining requests");
}

- (void)testDifferentTypesIndependent {
    NSString *typeTestDid = @"did:test:typespecific";
    NSString *typeTestIp = @"ip:test:typespecific";
    [self.limiter checkRateLimitForDid:typeTestDid];
    [self.limiter checkRateLimitForIP:typeTestIp];
    RateLimitResult *didTypeResult = [self.limiter checkRateLimitForDid:typeTestDid];
    RateLimitResult *ipTypeResult = [self.limiter checkRateLimitForIP:typeTestIp];

    XCTAssertEqual(didTypeResult.limit, 5000, @"DID type limit should be 5000");
    XCTAssertEqual(ipTypeResult.limit, 100, @"IP type limit should be 100");
}

- (void)testCustomLimits {
    self.limiter.didLimit = 100;
    self.limiter.ipLimit = 50;
    self.limiter.blobLimit = 25;

    NSDictionary *customDidHeaders = [self.limiter rateLimitHeadersForDid:@"did:test:custom"];
    NSDictionary *customIpHeaders = [self.limiter rateLimitHeadersForIP:@"1.2.3.4"];
    NSDictionary *customBlobHeaders = [self.limiter blobRateLimitHeadersForDid:@"did:test:blob"];

    XCTAssertEqualObjects(customDidHeaders[@"X-RateLimit-Limit"], @"100", @"Custom DID limit should be 100");
    XCTAssertEqualObjects(customIpHeaders[@"X-RateLimit-Limit"], @"50", @"Custom IP limit should be 50");
    XCTAssertEqualObjects(customBlobHeaders[@"X-RateLimit-Limit"], @"25", @"Custom Blob limit should be 25");
}

@end
