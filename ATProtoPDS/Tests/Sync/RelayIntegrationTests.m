#import <XCTest/XCTest.h>
#import "Sync/RelayConfiguration.h"
#import "Sync/RelayUpstreamManager.h"
#import "Sync/RelayMetrics.h"
#import "Sync/RelayEventValidator.h"
#import "Sync/RelayEventFilter.h"
#import "Sync/RelayEventBuffer.h"
#import "Sync/RelayRepoStateManager.h"

@interface RelayIntegrationTests : XCTestCase
@end

@implementation RelayIntegrationTests

- (void)testFullRelayPipeline {
    NSArray *upstreamURLs = @[@"pds1.example.com", @"pds2.example.com"];
    RelayConfiguration *config = [[RelayConfiguration alloc] initWithUpstreamURLs:upstreamURLs
                                                                      downstreamPort:2584
                                                                       retentionHours:72
                                                                     validationMode:RelayValidationModeLogOnly];
    
    XCTAssertEqual(config.downstreamPort, 2584);
    XCTAssertEqual(config.retentionHours, 72);
    XCTAssertEqual(config.upstreamURLs.count, 2);
}

- (void)testUpstreamManagerWithMultipleURLs {
    NSArray *urls = @[@"pds1.example.com", @"pds2.example.com", @"pds3.example.com"];
    RelayUpstreamManager *mgr = [[RelayUpstreamManager alloc] initWithInitialURLs:urls];
    
    XCTAssertEqual([mgr allUpstreams].count, 3);
    
    [mgr removeUpstream:@"pds2.example.com"];
    XCTAssertEqual([mgr allUpstreams].count, 2);
}

- (void)testMetricsRecording {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    [metrics recordEventReceived];
    [metrics recordEventValidated];
    [metrics recordEventForwarded];
    
    XCTAssertGreaterThan(metrics.eventsReceived, 0);
    XCTAssertGreaterThan(metrics.eventsValidated, 0);
    XCTAssertGreaterThan(metrics.eventsForwarded, 0);
}

- (void)testEventValidatorModes {
    RelayValidationMode lenient = RelayValidationModeLenient;
    RelayValidationMode strict = RelayValidationModeStrict;
    RelayValidationMode logOnly = RelayValidationModeLogOnly;
    
    XCTAssertEqual(lenient, RelayValidationModeLenient);
    XCTAssertEqual(strict, RelayValidationModeStrict);
    XCTAssertEqual(logOnly, RelayValidationModeLogOnly);
}

- (void)testEventFilterCombinations {
    RelayEventFilter *filter = [[RelayEventFilter alloc] initWithAllowedCollections:@[@"app.bsky.feed.post"]
                                                                   allowedRepos:nil
                                                                   blockedActors:nil];
    
    XCTAssertTrue([filter shouldForwardCollection:@"app.bsky.feed.post"]);
    XCTAssertFalse([filter shouldForwardCollection:@"app.bsky.actor.profile"]);
}

- (void)testEventBufferWithRetention {
    RelayEventBuffer *buffer = [[RelayEventBuffer alloc] initWithRetentionHours:24 maxEvents:1000];
    
    XCTAssertEqual(buffer.retentionSeconds, 86400);
    XCTAssertEqual(buffer.maxEvents, 1000);
}

- (void)testRepoStateManagerWorkflow {
    RelayRepoStateManager *mgr = [[RelayRepoStateManager alloc] init];
    
    [mgr handleCommitForRepo:@"did:plc:abc" root:@"bafyre1" rev:@"1" seq:1];
    [mgr handleCommitForRepo:@"did:plc:abc" root:@"bafyre2" rev:@"2" seq:2];
    [mgr handleCommitForRepo:@"did:plc:def" root:@"bafyre3" rev:@"1" seq:3];
    
    XCTAssertEqual([mgr repoCount], 2);
    XCTAssertEqualObjects([mgr revForRepo:@"did:plc:abc"], @"2");
    XCTAssertEqualObjects([mgr rootCIDForRepo:@"did:plc:def"], @"bafyre3");
    
    [mgr handleTombstoneForRepo:@"did:plc:def"];
    XCTAssertEqual([mgr statusForRepo:@"did:plc:def"], RelayRepoStatusTombstoned);
}

- (void)testMetricsPrometheusOutput {
    RelayMetrics *metrics = [RelayMetrics sharedMetrics];
    
    [metrics recordUpstreamConnected];
    [metrics recordEventReceived];
    [metrics recordEventForwarded];
    
    NSString *output = [metrics renderPrometheusMetrics];
    XCTAssertTrue([output containsString:@"relay_upstream_connections"]);
    XCTAssertTrue([output containsString:@"relay_events_received"]);
}

@end
