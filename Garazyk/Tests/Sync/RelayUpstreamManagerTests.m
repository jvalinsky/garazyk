#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayUpstreamManager.h"

@interface RelayUpstreamManagerTests : XCTestCase

@end

@implementation RelayUpstreamManagerTests

- (void)testInitialization {
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com", @"pds2.com"]];
    
    XCTAssertNotNil(manager);
    NSArray *allUpstreams = [manager allUpstreams];
    XCTAssertEqual(allUpstreams.count, 2);
    XCTAssertTrue([allUpstreams containsObject:@"pds1.com"]);
    XCTAssertTrue([allUpstreams containsObject:@"pds2.com"]);
}

- (void)testAddUpstream {
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    XCTAssertEqual([manager allUpstreams].count, 1);
    
    [manager addUpstream:@"pds3.com"];
    
    XCTAssertEqual([manager allUpstreams].count, 2);
    XCTAssertTrue([[manager allUpstreams] containsObject:@"pds3.com"]);
}

- (void)testRemoveUpstream {
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com", @"pds2.com"]];
    
    XCTAssertEqual([manager allUpstreams].count, 2);
    
    [manager removeUpstream:@"pds1.com"];
    
    XCTAssertEqual([manager allUpstreams].count, 1);
    XCTAssertFalse([[manager allUpstreams] containsObject:@"pds1.com"]);
    XCTAssertTrue([[manager allUpstreams] containsObject:@"pds2.com"]);
}

- (void)testRemoveAllUpstreams {
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com", @"pds2.com"]];
    
    XCTAssertEqual([manager allUpstreams].count, 2);
    
    [manager removeAllUpstreams];
    
    XCTAssertEqual([manager allUpstreams].count, 0);
}

- (void)testActiveUpstreamsInitiallyEmpty {
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    NSArray *active = [manager activeUpstreams];
    XCTAssertEqual(active.count, 0); // Not connected yet
}

- (void)testIsConnected {
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    XCTAssertFalse([manager isConnected]); // No upstreams connected
}

- (void)testPauseResume {
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    [manager pause];
    // Would test paused state here
    
    [manager resume];
    // Would test resumed state here
}

- (void)testDefaultReconnectSettings {
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    XCTAssertEqual(manager.maxReconnectAttempts, 10);
    XCTAssertEqual(manager.baseReconnectInterval, 5.0);
    XCTAssertTrue(manager.autoReconnectEnabled);
}

@end