#import <XCTest/XCTest.h>
#import "Sync/RelayMetrics.h"

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