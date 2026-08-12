// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/Analytics/PDSSequencerAnalyticsCollector.h"
#import "Database/Service/ServiceDatabases.h"

#import "Debug/GZLogger.h"
#import <sqlite3.h>

// Mock ATProtoSubscribeReposHandler for testing.
// The collector reads `handler.attachedConnections.count`, so the mock vends a
// set whose cardinality matches the configured connection count.
@interface MockSubscribeReposHandler : NSObject
@property (nonatomic, assign) NSUInteger attachedConnectionsCount;
@property (nonatomic, readonly) NSSet *attachedConnections;
@end

@implementation MockSubscribeReposHandler
- (NSSet *)attachedConnections {
    NSMutableSet *connections = [NSMutableSet set];
    for (NSUInteger i = 0; i < _attachedConnectionsCount; i++) {
        [connections addObject:@(i)];
    }
    return connections;
}
@end

// collectMetrics is private to the collector; tests drive it directly so a
// collection cycle is deterministic rather than waiting on the 5s timer.
@interface PDSSequencerAnalyticsCollector (Testing)
- (void)collectMetrics;
@end

@interface PDSSequencerAnalyticsTests : XCTestCase
@property (nonatomic, strong) PDSSequencerAnalyticsCollector *collector;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) MockSubscribeReposHandler *mockSubscribeHandler;
@property (nonatomic, copy) NSString *tempDirectory;
@property (nonatomic, assign) sqlite3 *testDatabase;
@end

@implementation PDSSequencerAnalyticsTests

- (void)setUp {
    [super setUp];

    // Create temp directory
    self.tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"SequencerAnalyticsTests_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Initialize service databases. PDSServiceDatabases derives its own file
    // layout from the base directory and runs the service migrations, which
    // create the sequencer_analytics table — so the schema is not set up here.
    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDirectory
                                                            serviceMaxSize:10
                                                           didCacheMaxSize:10
                                                          sequencerMaxSize:10];

    // Tests read and seed the same handle the collector writes through.
    // Owned by serviceDatabases — not closed here.
    self.testDatabase = (sqlite3 *)[self.serviceDatabases serviceDatabase];
    XCTAssertTrue(self.testDatabase != NULL, @"Service database handle should be available");

    // Create mock handler
    self.mockSubscribeHandler = [[MockSubscribeReposHandler alloc] init];
    self.mockSubscribeHandler.attachedConnectionsCount = 5;

    // Initialize collector
    self.collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:self.serviceDatabases
                                                                       subscribeHandler:self.mockSubscribeHandler];
}

- (void)tearDown {
    // Stop collecting
    [self.collector stopCollecting];

    // Close databases. self.testDatabase is owned by serviceDatabases, so it
    // must not be closed independently.
    self.testDatabase = NULL;
    [self.serviceDatabases closeAll];

    // Cleanup temp directory
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDirectory error:nil];

    [super tearDown];
}

#pragma mark - Collection Tests

- (void)testCollectorStartsAndStops {
    // Collector should not be running initially
    XCTAssertFalse(self.collector.isCollecting);

    // Start collection
    [self.collector startCollecting];
    XCTAssertTrue(self.collector.isCollecting);

    // Stop collection
    [self.collector stopCollecting];
    XCTAssertFalse(self.collector.isCollecting);
}

- (void)testCollectorRecordsMetricsToDatabase {
    [self.collector startCollecting];

    // The collection timer does not fire for 5s; drive one cycle directly so
    // the assertion below tests the recording path rather than the schedule.
    [self.collector collectMetrics];

    // Query database for records
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    sqlite3_stmt *stmt = NULL;
    NSString *sql = @"SELECT COUNT(*) FROM sequencer_analytics";

    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            XCTAssertGreaterThan(count, 0, @"Should have recorded analytics data");
        }
        sqlite3_finalize(stmt);
    }

    [self.collector stopCollecting];
}

- (void)testCurrentSnapshotReturnsMetrics {
    // Get current snapshot
    NSDictionary *snapshot = [self.collector currentSnapshot];

    XCTAssertNotNil(snapshot, @"Snapshot should not be nil");
    XCTAssertNotNil(snapshot[@"currentSeq"], @"Should contain currentSeq");
    XCTAssertNotNil(snapshot[@"subscriberCount"], @"Should contain subscriberCount");
    XCTAssertNotNil(snapshot[@"eventsPerSecond"], @"Should contain eventsPerSecond");
    XCTAssertNotNil(snapshot[@"healthStatus"], @"Should contain healthStatus");
    XCTAssertEqualObjects(snapshot[@"subscriberCount"],
                          @(self.mockSubscribeHandler.attachedConnectionsCount),
                          @"Subscriber count should come from the attached connections");
}

- (void)testHistoricalDataReturnsRecords {
    // Insert test data into database, using the collector's storage epoch.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    for (int i = 0; i < 3; i++) {
        NSString *sql = @"INSERT INTO sequencer_analytics "
            @"(timestamp, seq_number, events_per_second, subscriber_count, "
            @"backpressure_warnings, backpressure_critical, queue_overflows, created_at) "
            @"VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.testDatabase, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, (long)(now - (i * 3600)));
            sqlite3_bind_int64(stmt, 2, 1000 + i);
            sqlite3_bind_double(stmt, 3, 100.5 + i);
            sqlite3_bind_int(stmt, 4, 10 + i);
            sqlite3_bind_int(stmt, 5, i);
            sqlite3_bind_int(stmt, 6, 0);
            sqlite3_bind_int(stmt, 7, 0);
            sqlite3_bind_int64(stmt, 8, (long)now);

            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    }

    // Query historical data
    NSArray *history = [self.collector historicalDataSince:now - (24 * 3600) limit:10];

    XCTAssertNotNil(history, @"History should not be nil");
    XCTAssertEqual(history.count, 3, @"Should return 3 records");
}

- (void)testPruneOldRecords {
    // Insert test data - mix of old and new. The collector stores and prunes on
    // timeIntervalSinceReferenceDate, so seeded rows must use the same epoch.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval twoMonthsAgo = now - (60 * 24 * 3600);

    // Insert old record
    NSString *oldSql = @"INSERT INTO sequencer_analytics "
        @"(timestamp, seq_number, subscriber_count, created_at) "
        @"VALUES (?, ?, ?, ?)";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(self.testDatabase, oldSql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, (long)twoMonthsAgo);
        sqlite3_bind_int64(stmt, 2, 500);
        sqlite3_bind_int(stmt, 3, 5);
        sqlite3_bind_int64(stmt, 4, (long)twoMonthsAgo);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    // Insert recent record
    NSString *recentSql = @"INSERT INTO sequencer_analytics "
        @"(timestamp, seq_number, subscriber_count, created_at) "
        @"VALUES (?, ?, ?, ?)";
    if (sqlite3_prepare_v2(self.testDatabase, recentSql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, (long)now);
        sqlite3_bind_int64(stmt, 2, 1000);
        sqlite3_bind_int(stmt, 3, 10);
        sqlite3_bind_int64(stmt, 4, (long)now);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    // Prune records older than 30 days
    NSError *error = nil;
    BOOL success = [self.collector pruneOlderThan:30 error:&error];

    XCTAssertTrue(success, @"Prune should succeed");
    XCTAssertNil(error, @"Should not have errors");

    // Verify old record was deleted
    NSString *countSql = @"SELECT COUNT(*) FROM sequencer_analytics";
    if (sqlite3_prepare_v2(self.testDatabase, countSql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            XCTAssertEqual(count, 1, @"Should have deleted old record");
        }
        sqlite3_finalize(stmt);
    }
}

#pragma mark - Concurrency Tests

- (void)testConcurrentAccessToSnapshot {
    dispatch_queue_t queue = dispatch_queue_create("com.test.concurrent", DISPATCH_QUEUE_CONCURRENT);

    // Start collection
    [self.collector startCollecting];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Concurrent reads"];
    __block int completedReads = 0;

    for (int i = 0; i < 10; i++) {
        dispatch_async(queue, ^{
            NSDictionary *snapshot = [self.collector currentSnapshot];
            XCTAssertNotNil(snapshot);

            @synchronized(self) {
                completedReads++;
                if (completedReads == 10) {
                    [expectation fulfill];
                }
            }
        });
    }

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    [self.collector stopCollecting];
}

@end
