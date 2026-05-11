// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Auth/PDSReplayCache.h"

@interface PDSReplayCacheTests : XCTestCase
@property (nonatomic, copy) NSString *tempDir;
@end

@implementation PDSReplayCacheTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:uuid];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)tearDown {
    if (self.tempDir) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    }
    [super tearDown];
}

- (void)testReplayCachePersistsAcrossInstances {
    NSString *dbPath = [self.tempDir stringByAppendingPathComponent:@"replay.db"];
    NSDate *futureExpiry = [NSDate dateWithTimeIntervalSinceNow:3600];

    // Initial instance: add a JTI
    PDSReplayCache *cache1 = [[PDSReplayCache alloc] initWithDatabasePath:dbPath];
    XCTAssertNotNil(cache1);
    BOOL added = [cache1 checkAndAddJTI:@"jti-persist-test" expiration:futureExpiry];
    XCTAssertTrue(added, @"First add should succeed");

    // Duplicate add on same instance should fail (replay)
    BOOL replay = [cache1 checkAndAddJTI:@"jti-persist-test" expiration:futureExpiry];
    XCTAssertFalse(replay, @"Replay should be detected on same instance");

    // Destroy initial instance (must invalidate timer to break retain cycle)
    [cache1 invalidate];
    cache1 = nil;

    // New instance with same path: JTI should be rejected (persisted)
    PDSReplayCache *cache2 = [[PDSReplayCache alloc] initWithDatabasePath:dbPath];
    XCTAssertNotNil(cache2);
    BOOL replayAfterReopen = [cache2 checkAndAddJTI:@"jti-persist-test" expiration:futureExpiry];
    XCTAssertFalse(replayAfterReopen, @"Replay should be detected after reopening database");
    [cache2 invalidate];
}

- (void)testExpiredJTICanBeReused {
    NSString *dbPath = [self.tempDir stringByAppendingPathComponent:@"replay_expiry.db"];
    PDSReplayCache *cache = [[PDSReplayCache alloc] initWithDatabasePath:dbPath];
    XCTAssertNotNil(cache);

    // Add JTI with past expiration
    NSDate *pastExpiry = [NSDate dateWithTimeIntervalSinceNow:-60];
    BOOL added = [cache checkAndAddJTI:@"jti-expiry-test" expiration:pastExpiry];
    XCTAssertTrue(added, @"First add should succeed");

    // Re-add with future expiration — should succeed because old entry is expired
    NSDate *futureExpiry = [NSDate dateWithTimeIntervalSinceNow:3600];
    BOOL reused = [cache checkAndAddJTI:@"jti-expiry-test" expiration:futureExpiry];
    XCTAssertTrue(reused, @"Expired JTI should be reusable");

    // Now it should be rejected (non-expired)
    BOOL replay = [cache checkAndAddJTI:@"jti-expiry-test" expiration:futureExpiry];
    XCTAssertFalse(replay, @"Non-expired JTI should be rejected");
    [cache invalidate];
}

- (void)testCleanupRemovesExpiredEntries {
    NSString *dbPath = [self.tempDir stringByAppendingPathComponent:@"replay_cleanup.db"];
    PDSReplayCache *cache = [[PDSReplayCache alloc] initWithDatabasePath:dbPath];
    XCTAssertNotNil(cache);

    // Add entry with past expiration
    NSDate *pastExpiry = [NSDate dateWithTimeIntervalSinceNow:-60];
    [cache checkAndAddJTI:@"jti-cleanup-test" expiration:pastExpiry];

    // Run cleanup
    [cache cleanup];

    // After cleanup, the expired entry should be gone and a new add should succeed
    NSDate *futureExpiry = [NSDate dateWithTimeIntervalSinceNow:3600];
    BOOL added = [cache checkAndAddJTI:@"jti-cleanup-test" expiration:futureExpiry];
    XCTAssertTrue(added, @"After cleanup, expired JTI should be re-addable");
    [cache invalidate];
}

- (void)testInMemoryCache {
    // nil path => in-memory
    PDSReplayCache *cache = [[PDSReplayCache alloc] initWithDatabasePath:nil];
    XCTAssertNotNil(cache);

    NSDate *futureExpiry = [NSDate dateWithTimeIntervalSinceNow:3600];
    BOOL added = [cache checkAndAddJTI:@"jti-memory-test" expiration:futureExpiry];
    XCTAssertTrue(added);

    BOOL replay = [cache checkAndAddJTI:@"jti-memory-test" expiration:futureExpiry];
    XCTAssertFalse(replay);
    [cache invalidate];
}

- (void)testConcurrentCheckAndAddRejectsDuplicateJTI {
    // Two threads simultaneously validate the same JTI.
    // Only one should succeed; the other should be rejected as a replay.
    PDSReplayCache *cache = [[PDSReplayCache alloc] initWithDatabasePath:nil];
    XCTAssertNotNil(cache);

    NSDate *futureExpiry = [NSDate dateWithTimeIntervalSinceNow:3600];
    NSString *sharedJTI = @"jti-concurrent-test";

    __block BOOL result1 = NO;
    __block BOOL result2 = NO;
    __block XCTestExpectation *exp1 = [self expectationWithDescription:@"thread1"];
    __block XCTestExpectation *exp2 = [self expectationWithDescription:@"thread2"];

    dispatch_queue_t queue = dispatch_queue_create("concurrent-jti-test", DISPATCH_QUEUE_CONCURRENT);

    dispatch_async(queue, ^{
        result1 = [cache checkAndAddJTI:sharedJTI expiration:futureExpiry];
        [exp1 fulfill];
    });

    dispatch_async(queue, ^{
        result2 = [cache checkAndAddJTI:sharedJTI expiration:futureExpiry];
        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // Exactly one should succeed and one should fail (replay detected)
    // With BEGIN IMMEDIATE, the second thread will block until the first
    // commits, then see the row and return NO.
    XCTAssertNotEqual(result1, result2,
        @"Exactly one concurrent checkAndAdd should succeed for the same JTI. "
        @"Got result1=%d, result2=%d", result1, result2);

    [cache invalidate];
}

- (void)testNilJTIReturnsNO {
    PDSReplayCache *cache = [[PDSReplayCache alloc] initWithDatabasePath:nil];
    XCTAssertNotNil(cache);

    NSDate *futureExpiry = [NSDate dateWithTimeIntervalSinceNow:3600];
    BOOL result = [cache checkAndAddJTI:nil expiration:futureExpiry];
    XCTAssertFalse(result, @"nil JTI should return NO");

    [cache invalidate];
}

- (void)testNilExpirationReturnsNO {
    PDSReplayCache *cache = [[PDSReplayCache alloc] initWithDatabasePath:nil];
    XCTAssertNotNil(cache);

    BOOL result = [cache checkAndAddJTI:@"jti-nil-expiry" expiration:nil];
    XCTAssertFalse(result, @"nil expiration should return NO");

    [cache invalidate];
}

@end
