// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/Analytics/PDSSequencerAnalyticsCollector.h"

@interface PDSSequencerAnalyticsCollectorTests : XCTestCase
@end

@implementation PDSSequencerAnalyticsCollectorTests

- (void)testInitWithNilDependenciesDoesNotCrash {
    PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                              subscribeHandler:nil];
    XCTAssertNotNil(collector);
    XCTAssertFalse(collector.isCollecting);
}

- (void)testStopCollectingIsSafeWhenNotCollecting {
    PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                              subscribeHandler:nil];
    [collector stopCollecting];
    XCTAssertFalse(collector.isCollecting);
}

- (void)testCurrentSnapshotReturnsNilWithoutDatabase {
    PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                              subscribeHandler:nil];
    NSDictionary *snapshot = [collector currentSnapshot];
    XCTAssertNil(snapshot);
}

- (void)testHistoricalDataReturnsNilWithoutDatabase {
    PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                              subscribeHandler:nil];
    NSArray *data = [collector historicalDataSince:0 limit:100];
    XCTAssertNil(data);
}

- (void)testHourlyDataReturnsNilWithoutDatabase {
    PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                              subscribeHandler:nil];
    NSArray *data = [collector hourlyDataForPastDays:7];
    XCTAssertNil(data);
}

- (void)testPruneFailsWithoutDatabase {
    PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                              subscribeHandler:nil];
    __autoreleasing NSError *error = nil;
    BOOL success = [collector pruneOlderThan:30 error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testStartAndStopCollectingToggleState {
    PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                              subscribeHandler:nil];
    [collector startCollecting];
    XCTAssertTrue(collector.isCollecting);
    [collector stopCollecting];
    XCTAssertFalse(collector.isCollecting);
}

- (void)testDoubleStartCollectingIsIdempotent {
    PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                              subscribeHandler:nil];
    [collector startCollecting];
    XCTAssertTrue(collector.isCollecting);
    [collector startCollecting];
    XCTAssertTrue(collector.isCollecting);
    [collector stopCollecting];
    XCTAssertFalse(collector.isCollecting);
}

- (void)testDeallocCallsStopCollecting {
    __weak PDSSequencerAnalyticsCollector *weakRef = nil;
    @autoreleasepool {
        PDSSequencerAnalyticsCollector *collector = [[PDSSequencerAnalyticsCollector alloc] initWithServiceDatabases:nil
                                                                                                  subscribeHandler:nil];
        [collector startCollecting];
        weakRef = collector;
    }
    XCTAssertNil(weakRef, @"Collector should be deallocated and stop collecting");
}

@end
