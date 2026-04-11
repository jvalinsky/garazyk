#import <XCTest/XCTest.h>
#import "Sync/RelayMetrics.h"

@interface RelayMetricsTests : XCTestCase

- (void)waitForMetricsQueue;

@end

@implementation RelayMetricsTests

- (void)waitForMetricsQueue {
    usleep(50000);
}

- (void)testSingletonExists {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    XCTAssertNotNil(metrics);
}

- (void)testConnectionMetrics {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    int64_t initialUpstream = metrics.upstreamConnections;
    int64_t initialDownstream = metrics.downstreamConnections;
    
    [metrics recordUpstreamConnected];
    XCTAssertEqual(metrics.upstreamConnections, initialUpstream + 1);
    
    [metrics recordDownstreamConnected];
    XCTAssertEqual(metrics.downstreamConnections, initialDownstream + 1);
    
    [metrics recordDownstreamDisconnected];
    XCTAssertEqual(metrics.downstreamConnections, initialDownstream);
}

- (void)testEventMetrics {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    int64_t initialReceived = metrics.eventsReceived;
    int64_t initialForwarded = metrics.eventsForwarded;
    
    [metrics recordEventReceived];
    XCTAssertEqual(metrics.eventsReceived, initialReceived + 1);
    
    [metrics recordEventForwarded];
    XCTAssertEqual(metrics.eventsForwarded, initialForwarded + 1);
}

- (void)testValidationMetrics {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    int64_t initialMSTSuccess = metrics.mstValidationSuccess;
    int64_t initialMSTFailure = metrics.mstValidationFailure;
    
    [metrics recordMSTValidationSuccess];
    XCTAssertEqual(metrics.mstValidationSuccess, initialMSTSuccess + 1);
    XCTAssertEqual(metrics.mstValidationFailure, initialMSTFailure);
    
    [metrics recordMSTValidationFailure];
    XCTAssertEqual(metrics.mstValidationFailure, initialMSTFailure + 1);
}

- (void)testSequenceTracking {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    // Record initial sequence
    [metrics recordSequence:1000];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.currentSequence, 1000);
    
    [metrics recordSequence:2000];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.currentSequence, 2000);
    
    // Lower sequence should not update
    [metrics recordSequence:1500];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.currentSequence, 2000);
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
    int64_t initial = metrics.eventsDropped;
    
    [metrics recordEventDropped];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsDropped, initial + 1);
}

- (void)testInvalidatedEventMetric {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    int64_t initial = metrics.eventsInvalidated;
    
    [metrics recordEventInvalidated:@"MST proof invalid"];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsInvalidated, initial + 1);
}

@end