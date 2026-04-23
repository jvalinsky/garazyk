
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

@end
