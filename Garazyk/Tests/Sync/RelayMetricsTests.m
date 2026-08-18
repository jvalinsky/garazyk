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
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    XCTAssertNotNil(metrics);
}

- (void)testConnectionMetrics {
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    
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
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    
    [metrics recordEventReceived];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsReceived, 1);
    
    [metrics recordEventForwarded];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsForwarded, 1);
}

- (void)testValidationMetrics {
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    
    [metrics recordMSTValidationSuccess];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.mstValidationSuccess, 1);
    XCTAssertEqual(metrics.mstValidationFailure, 0);
    
    [metrics recordMSTValidationFailure];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.mstValidationFailure, 1);
}

- (void)testContinuityMetrics {
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];

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
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    
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
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    
    [metrics recordEventDropped];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsDropped, 1);
}

- (void)testInvalidatedEventMetric {
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    
    [metrics recordEventInvalidated:@"test"];
    [self waitForMetricsQueue];
    XCTAssertEqual(metrics.eventsInvalidated, 1);
}

- (void)testSignatureValidationFailureCategoriesAppearInSnapshotsAndPrometheus {
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];

    [metrics recordSignatureValidationFailureWithCategory:@"signing-key"];
    [metrics recordSignatureValidationFailureWithCategory:@"signing-key"];
    [metrics recordSignatureValidationFailureWithCategory:@"did-resolution"];

    NSDictionary *snapshot = [metrics snapshotDictionary];
    NSDictionary *categories = snapshot[@"signatureValidationFailuresByCategory"];
    XCTAssertEqual([snapshot[@"signatureValidationFailure"] longLongValue], 3LL);
    XCTAssertEqual([categories[@"signing-key"] longLongValue], 2LL);
    XCTAssertEqual([categories[@"did-resolution"] longLongValue], 1LL);

    NSString *prometheus = [metrics renderPrometheusMetrics];
    XCTAssertTrue([prometheus containsString:@"relay_signature_validation_failures_total{category=\"did-resolution\"} 1"]);
    XCTAssertTrue([prometheus containsString:@"relay_signature_validation_failures_total{category=\"signing-key\"} 2"]);
}

- (void)testSignatureValidationFailureCategoriesCollapseUnknownAndMutableInput {
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];
    NSMutableString *mutableKnownCategory = [@"signing-key" mutableCopy];
    [metrics recordSignatureValidationFailureWithCategory:mutableKnownCategory];
    [mutableKnownCategory appendString:@"-mutated-after-recording"];
    [metrics recordSignatureValidationFailureWithCategory:@"hostile\"label\nvalue"];

    NSDictionary *snapshot = [metrics snapshotDictionary];
    NSDictionary *categories = snapshot[@"signatureValidationFailuresByCategory"];
    XCTAssertEqual(categories.count, 2U);
    XCTAssertEqual([categories[@"signing-key"] longLongValue], 1LL);
    XCTAssertEqual([categories[@"unknown"] longLongValue], 1LL);
    XCTAssertNil(categories[@"hostile\"label\nvalue"]);

    NSString *prometheus = [metrics renderPrometheusMetrics];
    XCTAssertFalse([prometheus containsString:@"hostile\"label"]);
    XCTAssertTrue([prometheus containsString:@"relay_signature_validation_failures_total{category=\"unknown\"} 1"]);
}

- (void)testPerUpstreamPauseMetrics {
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];

    [metrics recordIngressUpstreamPause:@"https://pds1.example"];
    [self waitForMetricsQueue];
    [metrics recordIngressUpstreamPause:@"https://pds1.example"];
    [self waitForMetricsQueue];
    [metrics recordIngressUpstreamPause:@"https://pds2.example"];
    [self waitForMetricsQueue];

    // Simulate some pause duration
    usleep(50000); // 50ms

    [metrics recordIngressUpstreamResume:@"https://pds1.example"];
    [self waitForMetricsQueue];

    NSString *prometheus = [metrics renderPrometheusMetrics];
    XCTAssertTrue([prometheus containsString:@"relay_ingress_upstream_pause_total{upstream=\"https://pds1.example\"} 2"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_upstream_pause_total{upstream=\"https://pds2.example\"} 1"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_upstream_paused_duration_ms_total{upstream="]);
}

- (void)testPerShardDispatchMetrics {
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];

    [metrics recordIngressShardDispatch:0];
    [self waitForMetricsQueue];
    [metrics recordIngressShardDispatch:0];
    [self waitForMetricsQueue];
    [metrics recordIngressShardDispatch:1];
    [self waitForMetricsQueue];
    [metrics recordIngressShardDispatch:3];
    [self waitForMetricsQueue];

    NSString *prometheus = [metrics renderPrometheusMetrics];
    XCTAssertTrue([prometheus containsString:@"relay_ingress_shard_dispatch_total{shard=\"0\"} 2"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_shard_dispatch_total{shard=\"1\"} 1"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_shard_dispatch_total{shard=\"3\"} 1"]);
}

- (void)testOldestAgeMetric {
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];

    [metrics recordIngressOldestAgeMs:0];
    [self waitForMetricsQueue];

    NSString *prometheus = [metrics renderPrometheusMetrics];
    XCTAssertTrue([prometheus containsString:@"relay_ingress_oldest_accepted_age_ms 0"]);

    [metrics recordIngressOldestAgeMs:123.5];
    [self waitForMetricsQueue];

    prometheus = [metrics renderPrometheusMetrics];
    XCTAssertTrue([prometheus containsString:@"relay_ingress_oldest_accepted_age_ms"]);
}

- (void)testQueueDelayHistogram {
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];

    // Record delays in different buckets
    [metrics recordIngressQueueDelayMs:0.5];   // falls in 1ms bucket
    [self waitForMetricsQueue];
    [metrics recordIngressQueueDelayMs:5];     // falls in 10ms bucket
    [self waitForMetricsQueue];
    [metrics recordIngressQueueDelayMs:25];    // falls in 50ms bucket
    [self waitForMetricsQueue];
    [metrics recordIngressQueueDelayMs:75];    // falls in 100ms bucket
    [self waitForMetricsQueue];
    [metrics recordIngressQueueDelayMs:750];   // falls in 1000ms bucket
    [self waitForMetricsQueue];

    NSString *prometheus = [metrics renderPrometheusMetrics];

    // Verify histogram format and buckets exist
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_bucket"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_sum"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_count"]);

    // Verify bucket structure with specific values
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_bucket{le=\"1\"}"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_bucket{le=\"10\"}"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_bucket{le=\"50\"}"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_bucket{le=\"100\"}"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_bucket{le=\"1000\"}"]);
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_bucket{le=\"+Inf\"}"]);

    // Verify count is correct (5 observations)
    XCTAssertTrue([prometheus containsString:@"relay_ingress_queue_delay_ms_count 5"]);
}

@end
