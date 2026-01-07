#import <Foundation/Foundation.h>
#import "Network/RateLimiter.h"

int runRateLimiterTests(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"🧪 Running RateLimiter Tests");
        NSUInteger totalTests = 0;
        NSUInteger passedTests = 0;
        NSString *testDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ratelimit_test.db"];
        [[NSFileManager defaultManager] removeItemAtPath:testDbPath error:nil];

        RateLimiter *limiter = [[RateLimiter alloc] initWithDatabasePath:testDbPath];

        totalTests++;
        RateLimiter *singleton1 = [RateLimiter sharedLimiter];
        RateLimiter *singleton2 = [RateLimiter sharedLimiter];
        if (singleton1 == singleton2) {
            passedTests++;
            NSLog(@"✅ Singleton Test: PASSED");
        } else {
            NSLog(@"❌ Singleton Test: FAILED");
        }

        totalTests++;
        if (limiter.didLimit == 5000 && limiter.didWindowSeconds == 3600 &&
            limiter.ipLimit == 100 && limiter.ipWindowSeconds == 60 &&
            limiter.blobLimit == 50 && limiter.blobWindowSeconds == 3600) {
            passedTests++;
            NSLog(@"✅ Default Limits Test: PASSED");
        } else {
            NSLog(@"❌ Default Limits Test: FAILED");
        }

        totalTests++;
        RateLimitResult *result = [limiter checkRateLimitForDid:@"did:test:user1"];
        if (result.allowed && result.limit == 5000) {
            passedTests++;
            NSLog(@"✅ Rate Limit Allowed Test: PASSED");
        } else {
            NSLog(@"❌ Rate Limit Allowed Test: FAILED");
        }

        totalTests++;
        RateLimitResult *result1 = [limiter checkRateLimitForDid:@"did:test:user2"];
        RateLimitResult *result2 = [limiter checkRateLimitForDid:@"did:test:user2"];
        if (result1.allowed && result2.allowed && result2.remaining == result1.remaining - 1) {
            passedTests++;
            NSLog(@"✅ Rate Limit Decrements Remaining Test: PASSED");
        } else {
            NSLog(@"❌ Rate Limit Decrements Remaining Test: FAILED (remaining: %ld vs expected: %ld)",
                  (long)result2.remaining, (long)(result1.remaining - 1));
        }

        totalTests++;
        RateLimitResult *ipResult = [limiter checkRateLimitForIP:@"192.168.1.1"];
        if (ipResult.allowed && ipResult.limit == 100) {
            passedTests++;
            NSLog(@"✅ Rate Limit For IP Test: PASSED");
        } else {
            NSLog(@"❌ Rate Limit For IP Test: FAILED");
        }

        totalTests++;
        RateLimitResult *blobResult = [limiter checkBlobUploadRateLimitForDid:@"did:test:blobuser"];
        if (blobResult.allowed && blobResult.limit == 50) {
            passedTests++;
            NSLog(@"✅ Blob Upload Rate Limit Test: PASSED");
        } else {
            NSLog(@"❌ Blob Upload Rate Limit Test: FAILED");
        }

        totalTests++;
        NSDictionary *didHeaders = [limiter rateLimitHeadersForDid:@"did:test:headeruser"];
        if (didHeaders[@"X-RateLimit-Limit"] && didHeaders[@"X-RateLimit-Remaining"] && didHeaders[@"X-RateLimit-Reset"] &&
            [didHeaders[@"X-RateLimit-Limit"] isEqualToString:@"5000"]) {
            passedTests++;
            NSLog(@"✅ Rate Limit Headers For DID Test: PASSED");
        } else {
            NSLog(@"❌ Rate Limit Headers For DID Test: FAILED");
        }

        totalTests++;
        NSDictionary *ipHeaders = [limiter rateLimitHeadersForIP:@"10.0.0.1"];
        if (ipHeaders[@"X-RateLimit-Limit"] && [ipHeaders[@"X-RateLimit-Limit"] isEqualToString:@"100"]) {
            passedTests++;
            NSLog(@"✅ Rate Limit Headers For IP Test: PASSED");
        } else {
            NSLog(@"❌ Rate Limit Headers For IP Test: FAILED");
        }

        totalTests++;
        NSDictionary *blobHeaders = [limiter blobRateLimitHeadersForDid:@"did:test:blobheader"];
        if (blobHeaders[@"X-RateLimit-Limit"] && [blobHeaders[@"X-RateLimit-Limit"] isEqualToString:@"50"]) {
            passedTests++;
            NSLog(@"✅ Blob Rate Limit Headers Test: PASSED");
        } else {
            NSLog(@"❌ Blob Rate Limit Headers Test: FAILED");
        }

        totalTests++;
        RateLimitResult *nilDidResult = [limiter checkRateLimitForDid:nil];
        if (nilDidResult.allowed && nilDidResult.limit == 5000 && nilDidResult.remaining == 5000) {
            passedTests++;
            NSLog(@"✅ Nil DID Returns Allowed Test: PASSED");
        } else {
            NSLog(@"❌ Nil DID Returns Allowed Test: FAILED");
        }

        totalTests++;
        RateLimitResult *emptyDidResult = [limiter checkRateLimitForDid:@""];
        if (emptyDidResult.allowed) {
            passedTests++;
            NSLog(@"✅ Empty DID Returns Allowed Test: PASSED");
        } else {
            NSLog(@"❌ Empty DID Returns Allowed Test: FAILED");
        }

        totalTests++;
        RateLimitResult *nilIpResult = [limiter checkRateLimitForIP:nil];
        if (nilIpResult.allowed && nilIpResult.limit == 100) {
            passedTests++;
            NSLog(@"✅ Nil IP Returns Allowed Test: PASSED");
        } else {
            NSLog(@"❌ Nil IP Returns Allowed Test: FAILED");
        }

        totalTests++;
        NSString *did1 = @"did:test:user1";
        NSString *did2 = @"did:test:user2";
        [limiter checkRateLimitForDid:did1];
        [limiter checkRateLimitForDid:did1];
        RateLimitResult *result1_ind = [limiter checkRateLimitForDid:did1];
        RateLimitResult *result2_ind = [limiter checkRateLimitForDid:did2];
        if (result1_ind.remaining < result2_ind.remaining) {
            passedTests++;
            NSLog(@"✅ Different Identifiers Independent Test: PASSED");
        } else {
            NSLog(@"❌ Different Identifiers Independent Test: FAILED (did1: %ld, did2: %ld)",
                  (long)result1_ind.remaining, (long)result2_ind.remaining);
        }

        totalTests++;
        RateLimiter *typeLimiter = [[RateLimiter alloc] initWithDatabasePath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ratelimit_typedb.db"]];
        NSString *typeTestDid = [NSString stringWithFormat:@"did:test:typespecific:%lu", (unsigned long)totalTests];
        NSString *typeTestIp = [NSString stringWithFormat:@"ip:test:typespecific:%lu", (unsigned long)totalTests];
        [typeLimiter checkRateLimitForDid:typeTestDid];
        [typeLimiter checkRateLimitForIP:typeTestIp];
        RateLimitResult *didTypeResult = [typeLimiter checkRateLimitForDid:typeTestDid];
        RateLimitResult *ipTypeResult = [typeLimiter checkRateLimitForIP:typeTestIp];
        if (didTypeResult.limit == 5000 && ipTypeResult.limit == 100) {
            passedTests++;
            NSLog(@"✅ Different Types Independent Test: PASSED");
        } else {
            NSLog(@"❌ Different Types Independent Test: FAILED (did: %ld, ip: %ld)",
                  (long)didTypeResult.limit, (long)ipTypeResult.limit);
        }
        [[NSFileManager defaultManager] removeItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ratelimit_typedb.db"] error:nil];

        totalTests++;
        RateLimiter *customLimiter = [[RateLimiter alloc] initWithDatabasePath:testDbPath];
        customLimiter.didLimit = 100;
        customLimiter.ipLimit = 50;
        customLimiter.blobLimit = 25;
        NSDictionary *customDidHeaders = [customLimiter rateLimitHeadersForDid:@"did:test:custom"];
        NSDictionary *customIpHeaders = [customLimiter rateLimitHeadersForIP:@"1.2.3.4"];
        NSDictionary *customBlobHeaders = [customLimiter blobRateLimitHeadersForDid:@"did:test:blob"];
        if ([customDidHeaders[@"X-RateLimit-Limit"] isEqualToString:@"100"] &&
            [customIpHeaders[@"X-RateLimit-Limit"] isEqualToString:@"50"] &&
            [customBlobHeaders[@"X-RateLimit-Limit"] isEqualToString:@"25"]) {
            passedTests++;
            NSLog(@"✅ Custom Limits Test: PASSED");
        } else {
            NSLog(@"❌ Custom Limits Test: FAILED");
        }

        [[NSFileManager defaultManager] removeItemAtPath:testDbPath error:nil];

        NSLog(@"\n📊 RateLimiter Tests Complete: %lu/%lu passed", (unsigned long)passedTests, (unsigned long)totalTests);
        return passedTests == totalTests ? 0 : 1;
    }
}

int main(int argc, const char * argv[]) {
    return runRateLimiterTests(argc, argv);
}
