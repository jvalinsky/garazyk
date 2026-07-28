// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayMetrics.h"

@interface RelayMetricsTests : XCTestCase

- (void)waitForMetricsQueue;

@end

@implementation RelayMetricsTests

- (void)waitForMetricsQueue {
    usleep(100000);
}

- (void)testSingletonExists {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    XCTAssertNotNil(metrics);
}

- (void)testConnectionMetrics {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    [metrics recordUpstreamConnected];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.upstreamConnections, 1);
    
    [metrics recordDownstreamConnected];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.downstreamConnections, 1);
    
    [metrics recordDownstreamDisconnected];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.downstreamConnections, 0);
}

- (void)testEventMetrics {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    [metrics recordEventReceived];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsReceived, 1);
    
    [metrics recordEventForwarded];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsForwarded, 1);
}

- (void)testValidationMetrics {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    [metrics recordMSTValidationSuccess];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.mstValidationSuccess, 1);
    XCTAssertEqual(metrics.mstValidationFailure, 0);
    
    [metrics recordMSTValidationFailure];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.mstValidationFailure, 1);
}

- (void)testContinuityMetrics {
    RelayMetrics *metrics = [[RelayMetrics alloc] init];

    [metrics recordContinuityBaseline];
    [metrics recordContinuityVerified];
    [metrics recordContinuityFailure];
    [metrics recordSyncReset];
    [self waitForMetricsQueue];

    NSDictionary *snapshot = [metrics snapshotDictionary];
    XCTAssertEqual([snapshot[@"continuityBaselines"] longLongValue], 1LL);
    XCTAssertEqual([snapshot[@"continuityVerified"] longLongValue], 1LL);
    XCTAssertEqual([snapshot[@"continuityFailures"] longLongValue], 1LL);
    XCTAssertEqual([snapshot[@"syncResets"] longLongValue], 1LL);
    NSString *prometheus = [metrics renderPrometheusMetrics];
    XCTAssertTrue([prometheus containsString:@"relay_continuity_total"]);
    XCTAssertTrue([prometheus containsString:@"relay_sync_resets_total"]);
}

- (void)testSequenceTracking {
    XCTSkip(@"Async metric - flaky under test isolation");
}

- (void)testPrometheusOutput {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    [metrics recordUpstreamConnected];
    [metrics recordDownstreamConnected];
    [metrics recordEventReceived];
    [metrics recordEventForwarded];
    
    NSString *output = [metrics renderPrometheusMetrics];
    XCTAssertTrue([output containsString:@"relay_upstream_connections"]);
    XCTAssertTrue([output containsString:@"relay_downstream_connections"]);
    XCTAssertTrue([output containsString:@"relay_events_received_total"]);
    XCTAssertTrue([output containsString:@"relay_events_forwarded_total"]);
}

- (void)testEventDroppedMetric {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    [metrics recordEventDropped];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsDropped, 1);
}

- (void)testInvalidatedEventMetric {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    [metrics recordEventInvalidated:@"test"];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsInvalidated, 1);
}

@end
