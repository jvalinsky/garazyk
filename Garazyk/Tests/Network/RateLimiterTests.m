// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/RateLimiter.h"

@interface RateLimiterTests : XCTestCase

@property (nonatomic, strong) RateLimiter *limiter;
@property (nonatomic, copy) NSString *testDbPath;

@end

@implementation RateLimiterTests

- (void)removeDbFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDbPath error:nil];
    [fm removeItemAtPath:[self.testDbPath stringByAppendingString:@"-wal"] error:nil];
    [fm removeItemAtPath:[self.testDbPath stringByAppendingString:@"-shm"] error:nil];
}

- (void)setUp {
    [super setUp];
    RateLimiterSetDisabledGlobally(NO);
    self.testDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ratelimit_test.db"];
    [self removeDbFiles];
    self.limiter = [[RateLimiter alloc] initWithDatabasePath:self.testDbPath];
}

- (void)tearDown {
    [self removeDbFiles];
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

- (void)testDifferentIdentifiersIndependentHasFewerRemainingRequests {
    NSString *did1 = @"did:test:user1";
    NSString *did2 = @"did:test:user2";
    [self.limiter checkRateLimitForDid:did1];
    [self.limiter checkRateLimitForDid:did1];
    RateLimitResult *result1_ind = [self.limiter checkRateLimitForDid:did1];
    RateLimitResult *result2_ind = [self.limiter checkRateLimitForDid:did2];

    XCTAssertLessThan(result1_ind.remaining, result2_ind.remaining, @"did1 should have fewer remaining requests");
}

- (void)testDifferentTypesIndependentPreserveLimits {
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

- (void)testRateLimitExceededReturnsNotAllowed {
    self.limiter.didLimit = 2;
    NSString *did = @"did:test:exceed";
    
    RateLimitResult *r1 = [self.limiter checkRateLimitForDid:did];
    XCTAssertTrue(r1.allowed, @"First request allowed");
    RateLimitResult *r2 = [self.limiter checkRateLimitForDid:did];
    XCTAssertTrue(r2.allowed, @"Second request allowed");
    RateLimitResult *r3 = [self.limiter checkRateLimitForDid:did];
    XCTAssertFalse(r3.allowed, @"Third request should be rejected when limit is 2");
    XCTAssertEqual(r3.remaining, 0, @"Remaining should be 0 when rejected");
    XCTAssertGreaterThan(r3.retryAfter, 0, @"Retry-After should be positive");
    
    NSDictionary *headers = [self.limiter rateLimitHeadersForDid:did];
    XCTAssertEqualObjects(headers[@"X-RateLimit-Remaining"], @"0");
}

- (void)testCheckRateLimitForKey {
    NSString *key = @"custom:endpoint:/xrpc/app.bsky.feed.getTimeline";
    RateLimitResult *r1 = [self.limiter checkRateLimitForKey:key limit:5 windowSeconds:60];
    XCTAssertTrue(r1.allowed);
    XCTAssertEqual(r1.limit, 5);
    XCTAssertEqual(r1.remaining, 4);
}

- (void)testGetTopLimitedIdentifiers {
    [self.limiter checkRateLimitForDid:@"did:test:top1"];
    [self.limiter checkRateLimitForDid:@"did:test:top1"];
    [self.limiter checkRateLimitForDid:@"did:test:top2"];
    
    NSArray<NSDictionary *> *top = [self.limiter getTopLimitedIdentifiers:10];
    XCTAssertGreaterThanOrEqual(top.count, 2, @"Should return at least 2 tracked identifiers");
    BOOL foundTop1 = NO;
    for (NSDictionary *entry in top) {
        if ([entry[@"identifier"] isEqualToString:@"did:test:top1"]) {
            foundTop1 = YES;
            XCTAssertEqual([entry[@"requestCount"] integerValue], 2);
        }
    }
    XCTAssertTrue(foundTop1, @"Should find did:test:top1 in top limited identifiers");
}

- (void)testClearRateLimitForIdentifier {
    NSString *did = @"did:test:clear";
    self.limiter.didLimit = 3;
    [self.limiter checkRateLimitForDid:did];
    [self.limiter checkRateLimitForDid:did];
    
    RateLimitResult *beforeClear = [self.limiter checkRateLimitForDid:did];
    XCTAssertEqual(beforeClear.remaining, 0);
    
    NSInteger cleared = [self.limiter clearRateLimitForIdentifier:did type:@"0"]; // RateLimitTypeDID is 0
    XCTAssertGreaterThanOrEqual(cleared, 1, @"Should clear at least 1 row");
    
    RateLimitResult *afterClear = [self.limiter checkRateLimitForDid:did];
    XCTAssertTrue(afterClear.allowed);
    XCTAssertEqual(afterClear.remaining, 2, @"Remaining should be reset after clearing");
}

- (void)testClearBlobRateLimitForIdentifier {
    NSString *did = @"did:test:blobclear";
    self.limiter.blobLimit = 3;
    [self.limiter checkBlobUploadRateLimitForDid:did];
    
    NSInteger cleared = [self.limiter clearRateLimitForIdentifier:did type:@"blob"];
    XCTAssertGreaterThanOrEqual(cleared, 1, @"Should clear blob rate limit row");
}

@end

