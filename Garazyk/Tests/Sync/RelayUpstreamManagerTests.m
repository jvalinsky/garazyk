// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/ATProtoSafeHTTPClient.h"
#import "Sync/Relay/RelayUpstreamManager.h"

@interface ATProtoRelayUpstreamManager (ValidationTesting)
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoRelayClient *> *upstreamClients;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event;
@end

@interface RelayValidationHTTPClient : ATProtoSafeHTTPClient
@property (nonatomic, strong) NSURLRequest *capturedRequest;
@property (nonatomic, strong) ATProtoSafeHTTPClientOptions *capturedOptions;
@end

@implementation RelayValidationHTTPClient

- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                               options:(ATProtoSafeHTTPClientOptions *)options
                            completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    self.capturedRequest = request;
    self.capturedOptions = options;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                             statusCode:200
                                                            HTTPVersion:@"HTTP/1.1"
                                                           headerFields:@{}];
    completion([NSData data], response, nil);
}

@end

@interface RelayUpstreamManagerTests : XCTestCase

@end

@implementation RelayUpstreamManagerTests

- (void)testInitialization {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com", @"pds2.com"]];
    
    XCTAssertNotNil(manager);
    NSArray *allUpstreams = [manager allUpstreams];
    XCTAssertEqual(allUpstreams.count, 2);
    XCTAssertTrue([allUpstreams containsObject:@"pds1.com"]);
    XCTAssertTrue([allUpstreams containsObject:@"pds2.com"]);
}

- (void)testAddUpstream {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    XCTAssertEqual([manager allUpstreams].count, 1);
    
    [manager addUpstream:@"pds3.com"];
    
    XCTAssertEqual([manager allUpstreams].count, 2);
    XCTAssertTrue([[manager allUpstreams] containsObject:@"pds3.com"]);
}

- (void)testRemoveUpstream {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com", @"pds2.com"]];
    
    XCTAssertEqual([manager allUpstreams].count, 2);
    
    [manager removeUpstream:@"pds1.com"];
    
    XCTAssertEqual([manager allUpstreams].count, 1);
    XCTAssertFalse([[manager allUpstreams] containsObject:@"pds1.com"]);
    XCTAssertTrue([[manager allUpstreams] containsObject:@"pds2.com"]);
}

- (void)testRemoveAllUpstreams {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com", @"pds2.com"]];
    
    XCTAssertEqual([manager allUpstreams].count, 2);
    
    [manager removeAllUpstreams];
    
    XCTAssertEqual([manager allUpstreams].count, 0);
}

- (void)testActiveUpstreamsInitiallyEmpty {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    NSArray *active = [manager activeUpstreams];
    XCTAssertEqual(active.count, 0); // Not connected yet
}

- (void)testIsConnected {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    XCTAssertFalse([manager isConnected]); // No upstreams connected
}

- (void)testPauseResume {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    [manager pause];
    // Would test paused state here
    
    [manager resume];
    // Would test resumed state here
}

- (void)testDefaultReconnectSettings {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"pds1.com"]];
    
    XCTAssertEqual(manager.maxReconnectAttempts, 10);
    XCTAssertEqual(manager.baseReconnectInterval, 5.0);
    XCTAssertTrue(manager.autoReconnectEnabled);
}

- (void)testCrawlStateTransitionsAndRequestOrigin {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc]
        initWithInitialURLs:@[@"https://crawl.test/xrpc/com.atproto.sync.subscribeRepos"]];
    NSString *url = @"https://crawl.test/xrpc/com.atproto.sync.subscribeRepos";

    XCTAssertFalse([manager crawlWasRequestedForUpstream:url]);
    XCTAssertEqual([manager crawlStateForUpstream:url], RelayCrawlStateNotRequested);

    [manager markCrawlRequestedForUpstream:url];
    XCTAssertTrue([manager crawlWasRequestedForUpstream:url]);
    XCTAssertTrue([manager inventoryWasRequestedForUpstream:url]);
    XCTAssertNotNil([manager crawlRequestedAtForUpstream:url]);
    XCTAssertEqual([manager crawlStateForUpstream:url], RelayCrawlStateRequested);

    NSUInteger generation = [manager beginInventoryForUpstream:url];
    XCTAssertEqual([manager crawlStateForUpstream:url], RelayCrawlStateCrawling);
    XCTAssertEqual([manager crawlGenerationForUpstream:url], generation);

    [manager recordInventoryPageForUpstream:url generation:generation repoCount:3];
    [manager recordInventoryPageForUpstream:url generation:generation repoCount:2];
    XCTAssertEqual([manager crawlRepoCountForUpstream:url], (NSUInteger)5);

    [manager completeInventoryForUpstream:url generation:generation repoCount:5];
    XCTAssertEqual([manager crawlStateForUpstream:url], RelayCrawlStateComplete);
    XCTAssertNil([manager crawlErrorForUpstream:url]);

    [manager failInventoryForUpstream:url generation:generation error:@"inventory unavailable"];
    XCTAssertEqual([manager crawlStateForUpstream:url], RelayCrawlStateFailed);
    XCTAssertEqualObjects([manager crawlErrorForUpstream:url], @"inventory unavailable");
}

- (void)testTracksPerUpstreamEventActivityByKind {
    NSString *url = @"https://events.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc]
        initWithInitialURLs:@[url]];
    ATProtoRelayClient *client = manager.upstreamClients[url];

    [manager relayClient:client didReceiveCommitEvent:[[ATProtoFirehoseCommitEvent alloc] init]];
    [manager relayClient:client didReceiveCommitEvent:[[ATProtoFirehoseCommitEvent alloc] init]];
    [manager relayClient:client didReceiveIdentityEvent:[[ATProtoFirehoseIdentityEvent alloc] init]];

    XCTAssertEqual([manager eventCountForUpstream:url], (uint64_t)3);
    NSDictionary<NSString *, NSNumber *> *counts =
        [manager eventCountsByKindForUpstream:url];
    XCTAssertEqualObjects(counts[@"commit"], @2);
    XCTAssertEqualObjects(counts[@"identity"], @1);
    XCTAssertNotNil([manager lastEventAtForUpstream:url]);
}

- (void)testValidateHostUsesSafeHTTPClientWithBoundedPolicy {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[]];
    RelayValidationHTTPClient *client = [[RelayValidationHTTPClient alloc] init];
    manager.safeHTTPClient = client;

    XCTestExpectation *completed = [self expectationWithDescription:@"validation completed"];
    [manager validateHost:@"selfhosted.social" completion:^(BOOL reachable, NSError *error) {
        XCTAssertTrue(reachable);
        XCTAssertNil(error);
        [completed fulfill];
    }];
    [self waitForExpectations:@[completed] timeout:1.0];

    XCTAssertEqualObjects(client.capturedRequest.URL.absoluteString,
                          @"https://selfhosted.social/xrpc/com.atproto.server.describeServer");
    XCTAssertEqualObjects(client.capturedRequest.HTTPMethod, @"GET");
    XCTAssertEqualWithAccuracy(client.capturedOptions.timeout, 4.0, 0.01);
    XCTAssertEqual(client.capturedOptions.maxResponseBytes, 64 * 1024);
    XCTAssertFalse(client.capturedOptions.allowHTTP);
    XCTAssertFalse(client.capturedOptions.followRedirects);
}

- (void)testValidateLocalHostAllowsHTTPThroughSafeClient {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[]];
    RelayValidationHTTPClient *client = [[RelayValidationHTTPClient alloc] init];
    manager.safeHTTPClient = client;

    XCTestExpectation *completed = [self expectationWithDescription:@"local validation completed"];
    [manager validateHost:@"localhost:2583" completion:^(BOOL reachable, NSError *error) {
        XCTAssertTrue(reachable);
        XCTAssertNil(error);
        [completed fulfill];
    }];
    [self waitForExpectations:@[completed] timeout:1.0];

    XCTAssertEqualObjects(client.capturedRequest.URL.absoluteString,
                          @"http://localhost:2583/xrpc/com.atproto.server.describeServer");
    XCTAssertTrue(client.capturedOptions.allowHTTP);
}

@end
