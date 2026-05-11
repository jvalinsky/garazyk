// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// RecordCacheTests.m
// Basic tests for PDSRecordCache

#import <Foundation/Foundation.h>
#import "Database/Cache/PDSRecordCache.h"

@interface RecordCacheTest : NSObject
- (BOOL)runAllTests;
- (BOOL)testCacheCreation;
- (BOOL)testSetAndGet;
- (BOOL)testLRUEviction;
- (BOOL)testTTLExpiration;
- (BOOL)testInvalidateDID;
- (BOOL)testStatistics;
- (void)logPass:(NSString *)testName;
- (void)logFail:(NSString *)testName message:(NSString *)message;
@end

@implementation RecordCacheTest {
    NSInteger passCount;
    NSInteger failCount;
}

- (instancetype)init {
    if ((self = [super init])) {
        passCount = 0;
        failCount = 0;
    }
    return self;
}

- (BOOL)runAllTests {
    NSLog(@"=== Record Cache Tests ===\n");

    @autoreleasepool {
        if (![self testCacheCreation]) return NO;
    }

    @autoreleasepool {
        if (![self testSetAndGet]) return NO;
    }

    @autoreleasepool {
        if (![self testLRUEviction]) return NO;
    }

    @autoreleasepool {
        if (![self testTTLExpiration]) return NO;
    }

    @autoreleasepool {
        if (![self testInvalidateDID]) return NO;
    }

    @autoreleasepool {
        if (![self testStatistics]) return NO;
    }

    NSLog(@"\n=== Test Results ===");
    NSLog(@"Passed: %ld", (long)passCount);
    NSLog(@"Failed: %ld", (long)failCount);
    NSLog(@"%@", failCount == 0 ? @"✓ ALL TESTS PASSED" : @"✗ SOME TESTS FAILED");

    return failCount == 0;
}

- (BOOL)testCacheCreation {
    NSString *testName = @"testCacheCreation";
    NSLog(@"\nRunning %@...", testName);

    PDSRecordCache *cache = [[PDSRecordCache alloc] initWithMaxEntries:100];

    if (!cache) {
        [self logFail:testName message:@"Failed to create cache"];
        return NO;
    }

    if (cache.maxEntries != 100) {
        [self logFail:testName message:@"Max entries should be 100"];
        return NO;
    }

    if ([cache currentEntryCount] != 0) {
        [self logFail:testName message:@"Should start with 0 entries"];
        return NO;
    }

    if (!cache.enabled) {
        [self logFail:testName message:@"Should be enabled by default"];
        return NO;
    }

    [self logPass:testName];
    return YES;
}

- (BOOL)testSetAndGet {
    NSString *testName = @"testSetAndGet";
    NSLog(@"\nRunning %@...", testName);

    PDSRecordCache *cache = [[PDSRecordCache alloc] initWithMaxEntries:100];

    NSString *testURI = @"at://did:plc:test/app.bsky.feed.post/123";
    NSDictionary *testRecord = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello world",
        @"createdAt": @"2026-04-17T00:00:00Z"
    };

    // Set record
    [cache setRecord:testRecord forURI:testURI];

    if ([cache currentEntryCount] != 1) {
        [self logFail:testName message:@"Should have 1 entry after set"];
        return NO;
    }

    // Get record (should be a miss since we didn't call get first)
    NSDictionary *retrieved = [cache getRecordWithURI:testURI];
    if (!retrieved) {
        [self logFail:testName message:@"Should retrieve cached record"];
        return NO;
    }

    if (![retrieved isEqualToDictionary:testRecord]) {
        [self logFail:testName message:@"Retrieved record should match original"];
        return NO;
    }

    // Check hit count incremented
    if ([cache hitCount] != 1) {
        [self logFail:testName message:@"Should have 1 hit"];
        return NO;
    }

    [self logPass:testName];
    return YES;
}

- (BOOL)testLRUEviction {
    NSString *testName = @"testLRUEviction";
    NSLog(@"\nRunning %@...", testName);

    // Small cache to test eviction
    PDSRecordCache *cache = [[PDSRecordCache alloc] initWithMaxEntries:3];

    NSDictionary *record1 = @{@"$type": @"post", @"text": @"1"};
    NSDictionary *record2 = @{@"$type": @"post", @"text": @"2"};
    NSDictionary *record3 = @{@"$type": @"post", @"text": @"3"};
    NSDictionary *record4 = @{@"$type": @"post", @"text": @"4"};

    NSString *uri1 = @"at://did:plc:test/app.bsky.feed.post/1";
    NSString *uri2 = @"at://did:plc:test/app.bsky.feed.post/2";
    NSString *uri3 = @"at://did:plc:test/app.bsky.feed.post/3";
    NSString *uri4 = @"at://did:plc:test/app.bsky.feed.post/4";

    // Set 3 records (fills cache)
    [cache setRecord:record1 forURI:uri1];
    [cache setRecord:record2 forURI:uri2];
    [cache setRecord:record3 forURI:uri3];

    if ([cache currentEntryCount] != 3) {
        [self logFail:testName message:@"Should have 3 entries"];
        return NO;
    }

    // Add 4th - should evict oldest (uri1)
    [cache setRecord:record4 forURI:uri4];

    if ([cache currentEntryCount] != 3) {
        [self logFail:testName message:@"Should still have 3 entries after eviction"];
        return NO;
    }

    NSUInteger evictions = [cache evictionCount];
    if (evictions != 1) {
        [self logFail:testName message:[NSString stringWithFormat:@"Should have 1 eviction, got %lu", (unsigned long)evictions]];
        return NO;
    }

    // First URI should no longer be in cache
    NSDictionary *evicted = [cache getRecordWithURI:uri1];
    if (evicted) {
        [self logFail:testName message:@"Evicted record should not be retrievable"];
        return NO;
    }

    [self logPass:testName];
    return YES;
}

- (BOOL)testTTLExpiration {
    NSString *testName = @"testTTLExpiration";
    NSLog(@"\nRunning %@...", testName);

    // Cache with 0.5 second TTL for faster test
    PDSRecordCache *cache = [[PDSRecordCache alloc] initWithMaxEntries:100
                                                      maxMemoryBytes:0
                                                           defaultTTL:0.5];  // 0.5 second

    NSString *testURI = @"at://did:plc:test/app.bsky.feed.post/123";
    NSDictionary *testRecord = @{@"$type": @"post", @"text": @"test"};

    [cache setRecord:testRecord forURI:testURI];

    // Should be cached
    if ([cache currentEntryCount] != 1) {
        [self logFail:testName message:@"Should have 1 entry"];
        return NO;
    }

    // Get immediately - should be a hit
    NSDictionary *immediate = [cache getRecordWithURI:testURI];
    if (!immediate) {
        [self logFail:testName message:@"Should get record before TTL expires"];
        return NO;
    }

    // Wait for TTL to expire
    [NSThread sleepForTimeInterval:0.6];

    // After TTL, entry should be expired and removed on next get
    NSDictionary *expired = [cache getRecordWithURI:testURI];
    if (expired) {
        [self logFail:testName message:@"Should not get expired record"];
        return NO;
    }

    [self logPass:testName];
    return YES;
}

- (BOOL)testInvalidateDID {
    NSString *testName = @"testInvalidateDID";
    NSLog(@"\nRunning %@...", testName);

    PDSRecordCache *cache = [[PDSRecordCache alloc] initWithMaxEntries:100];

    // Create records for two different DIDs
    NSDictionary *record = @{@"$type": @"post", @"text": @"test"};
    NSString *did1 = @"did:plc:abc";
    NSString *did2 = @"did:plc:xyz";

    [cache setRecord:record forURI:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", did1]];
    [cache setRecord:record forURI:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/2", did1]];
    [cache setRecord:record forURI:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", did2]];

    if ([cache currentEntryCount] != 3) {
        [self logFail:testName message:@"Should have 3 entries"];
        return NO;
    }

    // Invalidate all for did1
    [cache invalidateDID:did1];

    if ([cache currentEntryCount] != 1) {
        [self logFail:testName message:@"Should have 1 entry after invalidation"];
        return NO;
    }

    // did2's record should still be there
    NSDictionary *remaining = [cache getRecordWithURI:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", did2]];
    if (!remaining) {
        [self logFail:testName message:@"did2's record should remain"];
        return NO;
    }

    [self logPass:testName];
    return YES;
}

- (BOOL)testStatistics {
    NSString *testName = @"testStatistics";
    NSLog(@"\nRunning %@...", testName);

    PDSRecordCache *cache = [[PDSRecordCache alloc] initWithMaxEntries:100];

    // Initial stats
    if ([cache hitCount] != 0 || [cache missCount] != 0) {
        [self logFail:testName message:@"Stats should start at 0"];
        return NO;
    }

    double initialRate = [cache hitRate];
    if (initialRate != 0.0) {
        [self logFail:testName message:@"Hit rate should be 0 with no accesses"];
        return NO;
    }

    // Add some entries
    NSDictionary *record = @{@"$type": @"post", @"text": @"test"};
    [cache setRecord:record forURI:@"at://did:plc:test/app.bsky.feed.post/1"];
    [cache setRecord:record forURI:@"at://did:plc:test/app.bsky.feed.post/2"];
    [cache setRecord:record forURI:@"at://did:plc:test/app.bsky.feed.post/3"];

    // Get one (hit)
    [cache getRecordWithURI:@"at://did:plc:test/app.bsky.feed.post/1"];

    // Try to get non-existent (miss)
    [cache getRecordWithURI:@"at://did:plc:test/app.bsky.feed.post/999"];

    if ([cache hitCount] != 1) {
        [self logFail:testName message:@"Should have 1 hit"];
        return NO;
    }

    if ([cache missCount] != 1) {
        [self logFail:testName message:@"Should have 1 miss"];
        return NO;
    }

    double rate = [cache hitRate];
    if (rate != 0.5) {
        [self logFail:testName message:[NSString stringWithFormat:@"Hit rate should be 0.5, got %.2f", rate]];
        return NO;
    }

    // Check memory usage
    NSUInteger memory = [cache currentMemoryUsage];
    if (memory == 0) {
        [self logFail:testName message:@"Memory usage should be > 0 with entries"];
        return NO;
    }

    // Reset stats
    [cache resetStatistics];
    if ([cache hitCount] != 0 || [cache missCount] != 0) {
        [self logFail:testName message:@"Stats should reset to 0"];
        return NO;
    }

    [self logPass:testName];
    return YES;
}

- (void)logPass:(NSString *)testName {
    passCount++;
    NSLog(@"  ✓ %@ passed", testName);
}

- (void)logFail:(NSString *)testName message:(NSString *)message {
    failCount++;
    NSLog(@"  ✗ %@ failed: %@", testName, message);
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        RecordCacheTest *test = [[RecordCacheTest alloc] init];
        BOOL success = [test runAllTests];
        return success ? 0 : 1;
    }
}
