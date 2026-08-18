// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/ATProtoSafeHTTPClient.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Sync/Relay/RelayIngressConfiguration.h"
#import "Sync/Relay/RelayMetrics.h"

@interface ATProtoRelayUpstreamManager (ValidationTesting)
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoRelayClient *> *upstreamClients;
@property (nonatomic, strong) NSMutableSet<NSString *> *backpressurePausedUpstreams;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *clientIngressGenerations;
@property (nonatomic, assign) NSUInteger ingressGeneration;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event;
- (void)relayClientDidConnect:(ATProtoRelayClient *)client;
- (void)relayClient:(ATProtoRelayClient *)client didDisconnectWithError:(nullable NSError *)error;
- (void)performSynchronouslyOnManagerQueue:(dispatch_block_t)block;
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

#pragma mark - ADR 0039: ingress gate wiring

- (ATProtoRelayIngressConfiguration *)boundedIngressTestConfiguration {
    NSError *configError = nil;
    ATProtoRelayIngressConfiguration *configuration =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:10
                                                              maxByteCount:1024 * 1024
                                                        lowEventWatermark:5
                                                         lowByteWatermark:512 * 1024
                                                        highEventWatermark:8
                                                          highByteWatermark:768 * 1024
                                                                shardCount:1
                                                     boundedIngressEnabled:YES
                                                                     error:&configError];
    XCTAssertNotNil(configuration);
    XCTAssertNil(configError);
    return configuration;
}

- (void)testConfigureBoundedIngressInstallsIngressGateOnExistingClients {
    NSString *url = @"https://gate.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[url]];
    ATProtoRelayClient *client = manager.upstreamClients[url];
    XCTAssertNil(client.ingressGate);

    [manager configureBoundedIngressWithConfiguration:[self boundedIngressTestConfiguration]
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        completion(RelayIngressReleaseReasonProcessed);
    }];

    XCTAssertNotNil(client.ingressGate);
    XCTAssertTrue(client.reconnectUsesProcessedCursor);
}

- (void)testAddUpstreamAfterBoundedIngressInstallsIngressGateOnNewClient {
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[]];

    [manager configureBoundedIngressWithConfiguration:[self boundedIngressTestConfiguration]
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        completion(RelayIngressReleaseReasonProcessed);
    }];

    NSString *lateURL = @"https://late.test/xrpc/com.atproto.sync.subscribeRepos";
    [manager addUpstream:lateURL];
    // addUpstream: dispatches onto the manager's private serial queue.
    // allUpstreams round-trips through the same queue, so by the time it
    // returns the addUpstream: block above is guaranteed to have run.
    XCTAssertTrue([[manager allUpstreams] containsObject:lateURL]);

    ATProtoRelayClient *client = manager.upstreamClients[lateURL];
    XCTAssertNotNil(client);
    XCTAssertNotNil(client.ingressGate);
    XCTAssertTrue(client.reconnectUsesProcessedCursor);
}

// ADR 0039, section 1: the gate block is the sole point of admission for
// Commit/Identity/Account/Sync events. Once ATProtoFirehose's ingressGate
// has admitted an event, the same event arriving through the ordinary
// RelayClientDelegate chain (as ATProtoFirehose still delivers it for an
// admitted frame) must not be submitted to the ingress pipeline again --
// that would double-admit and double-process it.
- (void)testIngressGateAdmissionIsNotDoubleSubmittedByDelegateChain {
    NSString *url = @"https://dedupe.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[url]];
    ATProtoRelayClient *client = manager.upstreamClients[url];

    __block NSUInteger processedCount = 0;
    XCTestExpectation *processedOnce = [self expectationWithDescription:@"processed once"];
    [manager configureBoundedIngressWithConfiguration:[self boundedIngressTestConfiguration]
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        processedCount++;
        [processedOnce fulfill];
        completion(RelayIngressReleaseReasonProcessed);
    }];

    XCTAssertNotNil(client.ingressGate);

    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:dedupe";
    event.seq = 42;
    event.wireFrameLength = 128;

    // Simulate the read-thread gate call ATProtoFirehose makes before
    // delivery (ADR 0039, section 1).
    BOOL admitted = client.ingressGate(event, FirehoseEventKindCommit);
    XCTAssertTrue(admitted);
    [self waitForExpectations:@[processedOnce] timeout:1.0];

    // Simulate ATProtoFirehose still delivering the (now-admitted) event
    // through the ordinary delegate chain.
    [manager relayClient:client didReceiveCommitEvent:event];

    // Give an accidental second submission time to land before asserting
    // it did not happen.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertEqual(processedCount, (NSUInteger)1);
}

#pragma mark - F6: upstreamClients / ingressPipeline queue confinement

- (ATProtoRelayIngressConfiguration *)churnStressIngressConfiguration {
    NSError *configError = nil;
    ATProtoRelayIngressConfiguration *configuration =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:1024
                                                              maxByteCount:16 * 1024 * 1024
                                                        lowEventWatermark:256
                                                         lowByteWatermark:4 * 1024 * 1024
                                                        highEventWatermark:768
                                                          highByteWatermark:8 * 1024 * 1024
                                                                shardCount:4
                                                     boundedIngressEnabled:YES
                                                                     error:&configError];
    XCTAssertNotNil(configuration);
    XCTAssertNil(configError);
    return configuration;
}

// Regression test for F6: the ingress-completion block RelayUpstreamManager
// builds in -configureBoundedIngressWithConfiguration:... used to read
// upstreamClients[upstreamURL] directly from whatever queue
// RelayIngressPipeline invoked it on (a shard queue), racing with
// addUpstream:/removeUpstream: mutating the very same NSMutableDictionary
// on _managerQueue. Drives a burst of gate-admitted events (each of which
// completes on a shard queue and reads upstreamClients to acknowledge the
// processed sequence) concurrently with repeated removeUpstream:/
// addUpstream: churn on a second upstream, and asserts nothing crashes and
// every admitted event is still processed exactly once.
- (void)testConcurrentUpstreamChurnDuringIngressAcknowledgement {
    NSString *gatedURL = @"https://churn-gate.test/xrpc/com.atproto.sync.subscribeRepos";
    NSString *churnURL = @"https://churn-other.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager =
        [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[gatedURL, churnURL]];
    ATProtoRelayClient *gatedClient = manager.upstreamClients[gatedURL];

    const NSUInteger eventCount = 200;
    dispatch_queue_t countingQueue = dispatch_queue_create("com.atproto.test.relay.churn.count", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger processedCount = 0;

    [manager configureBoundedIngressWithConfiguration:[self churnStressIngressConfiguration]
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        dispatch_sync(countingQueue, ^{
            processedCount++;
        });
        completion(RelayIngressReleaseReasonProcessed);
    }];
    XCTAssertNotNil(gatedClient.ingressGate);

    dispatch_queue_t workerQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_t group = dispatch_group_create();

    // Fan out concurrent admit calls through the gate. Each admission's
    // completion (invoked asynchronously on a RelayIngressPipeline shard
    // queue) reads manager.upstreamClients[gatedURL] to call
    // -acknowledgeProcessedSequence: on gatedClient.
    dispatch_group_async(group, workerQueue, ^{
        dispatch_apply(eventCount, workerQueue, ^(size_t idx) {
            ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
            event.repo = [NSString stringWithFormat:@"did:plc:churn-%zu", (size_t)idx];
            event.seq = (int64_t)idx + 1;
            event.wireFrameLength = 32;
            (void)gatedClient.ingressGate(event, FirehoseEventKindCommit);
        });
    });

    // Concurrently churn a *different* upstream's client in and out of the
    // same upstreamClients dictionary on _managerQueue while the above is
    // in flight.
    dispatch_group_async(group, workerQueue, ^{
        for (NSUInteger i = 0; i < 100; i++) {
            [manager removeUpstream:churnURL];
            [manager addUpstream:churnURL];
        }
    });

    XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC))), 0l);

    // Admission is synchronous but processing/acknowledgement happens
    // asynchronously on the pipeline's shard queues; poll briefly for the
    // last stragglers to finish.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    __block NSUInteger snapshot = 0;
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        dispatch_sync(countingQueue, ^{
            snapshot = processedCount;
        });
        if (snapshot == eventCount) {
            break;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }

    XCTAssertEqual(snapshot, eventCount);
    XCTAssertTrue([[manager allUpstreams] containsObject:churnURL]);
    XCTAssertNotNil(manager.upstreamClients[churnURL]);
}

#pragma mark - F5: resume bookkeeping on generation mismatch

// Regression test for F5: -ingressPipelineDidRequestResume: used to `continue`
// on a generation mismatch *before* removing the url from
// backpressurePausedUpstreams, permanently stranding it there --
// -ingressPipelineDidRequestPause: refuses to re-track a url already present
// in that set, so a still-connected client could never be paused or resumed
// again. The fix separates the two: bookkeeping (removeObject:) clears
// unconditionally, only the resumeReading/metrics call is gated on the
// generation still matching current.
- (void)testResumeClearsPauseBookkeepingButSkipsStaleGenerationClient {
    NSString *url = @"https://stale-resume.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[url]];
    ATProtoRelayClient *client = manager.upstreamClients[url];

    // Simulate a connected, paused upstream recorded at generation 0. The
    // real socket state (isConnected/isReadingPaused) is exercised via the
    // client's own KVC-settable ivar and public pauseReading, exactly as
    // -ingressPipelineDidRequestPause: would have left it; the firehose is
    // nil here, which pauseReading tolerates (nil-messaging no-op).
    [client setValue:@YES forKey:@"isConnected"];
    [client pauseReading];
    XCTAssertTrue(client.isReadingPaused);

    [manager performSynchronouslyOnManagerQueue:^{
        [manager.backpressurePausedUpstreams addObject:url];
        manager.clientIngressGenerations[url] = @0;
    }];

    // Bump the generation past what this client was paused under, exactly as
    // -connectAll/-disconnectAll do on a reconfigure.
    [manager performSynchronouslyOnManagerQueue:^{
        manager.ingressGeneration = 1;
    }];

    id<RelayIngressBackpressureDelegate> delegate = (id<RelayIngressBackpressureDelegate>)manager;
    [delegate ingressPipelineDidRequestResume:nil];

    // Round-trip through the manager's serial queue so the async resume
    // handler above is guaranteed to have run before we assert.
    [manager performSynchronouslyOnManagerQueue:^{}];

    // Bookkeeping cleared even though the generation was stale...
    XCTAssertFalse([manager.backpressurePausedUpstreams containsObject:url]);
    // ...but the stale client's socket was left untouched -- resumeReading
    // must not have been called.
    XCTAssertTrue(client.isReadingPaused);

    // Now pause again at the *current* generation and confirm a second
    // resume call resumes it normally -- proving the fix separates "clear
    // stale bookkeeping" from "touch a live, current-generation socket"
    // rather than just silently dropping pause tracking altogether.
    [manager performSynchronouslyOnManagerQueue:^{
        [manager.backpressurePausedUpstreams addObject:url];
        manager.clientIngressGenerations[url] = @(manager.ingressGeneration);
    }];

    [delegate ingressPipelineDidRequestResume:nil];
    [manager performSynchronouslyOnManagerQueue:^{}];

    XCTAssertFalse([manager.backpressurePausedUpstreams containsObject:url]);
    XCTAssertFalse(client.isReadingPaused);
}

#pragma mark - F11 / R11: selective (top-1) pause on high watermark

// Regression test for F11: -ingressPipelineDidRequestPause: used to pause
// every connected upstream unconditionally. It now queries
// ingressPipeline.inFlightByteCountByUpstream and pauses only the single
// connected, not-already-paused upstream currently holding the most
// in-flight backlog bytes. This admits events through the real ingress
// gate/pipeline (rather than faking the byte counts) with a processBlock
// that never calls its completion, so every admitted event stays
// "in flight" -- exactly the state -inFlightByteCountByUpstream reports on
// -- for the duration of the assertions below.
- (void)testPauseSelectsOnlyLargestInFlightContributor {
    NSString *smallURL = @"https://fair-small.test/xrpc/com.atproto.sync.subscribeRepos";
    NSString *bigURL = @"https://fair-big.test/xrpc/com.atproto.sync.subscribeRepos";
    NSString *idleURL = @"https://fair-idle.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc]
        initWithInitialURLs:@[smallURL, bigURL, idleURL]];
    ATProtoRelayClient *smallClient = manager.upstreamClients[smallURL];
    ATProtoRelayClient *bigClient = manager.upstreamClients[bigURL];
    ATProtoRelayClient *idleClient = manager.upstreamClients[idleURL];

    for (ATProtoRelayClient *client in @[smallClient, bigClient, idleClient]) {
        [client setValue:@YES forKey:@"isConnected"];
    }
    [manager relayClientDidConnect:smallClient];
    [manager relayClientDidConnect:bigClient];
    [manager relayClientDidConnect:idleClient];
    // Round-trip through the manager's serial queue so the async
    // connect-bookkeeping above (connectedUpstreams, clientIngressGenerations)
    // is guaranteed to have landed before the gate calls below.
    [manager performSynchronouslyOnManagerQueue:^{}];

    // A processBlock that never calls its completion: admitted events stay
    // in-flight (admitted, not released) for the rest of the test.
    [manager configureBoundedIngressWithConfiguration:[self churnStressIngressConfiguration]
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        (void)event;
        (void)upstreamURL;
        (void)sequence;
        (void)completion;
    }];

    ATProtoFirehoseCommitEvent *smallEvent = [[ATProtoFirehoseCommitEvent alloc] init];
    smallEvent.repo = @"did:plc:fair-small";
    smallEvent.seq = 1;
    smallEvent.wireFrameLength = 100;
    XCTAssertTrue(smallClient.ingressGate(smallEvent, FirehoseEventKindCommit));

    ATProtoFirehoseCommitEvent *bigEvent = [[ATProtoFirehoseCommitEvent alloc] init];
    bigEvent.repo = @"did:plc:fair-big";
    bigEvent.seq = 1;
    bigEvent.wireFrameLength = 10000;
    XCTAssertTrue(bigClient.ingressGate(bigEvent, FirehoseEventKindCommit));
    // idleURL never admits any event, so it has no in-flight bytes at all.

    id<RelayIngressBackpressureDelegate> delegate = (id<RelayIngressBackpressureDelegate>)manager;
    [delegate ingressPipelineDidRequestPause:manager.ingressPipeline];
    [manager performSynchronouslyOnManagerQueue:^{}];

    XCTAssertTrue([manager.backpressurePausedUpstreams containsObject:bigURL]);
    XCTAssertFalse([manager.backpressurePausedUpstreams containsObject:smallURL]);
    XCTAssertFalse([manager.backpressurePausedUpstreams containsObject:idleURL]);
    XCTAssertTrue(bigClient.isReadingPaused);
    XCTAssertFalse(smallClient.isReadingPaused);
    XCTAssertFalse(idleClient.isReadingPaused);
}

// Regression/coverage for the fallback path: a watermark trip must never be
// left with zero backpressure applied. When inFlightByteCountByUpstream has
// nothing to report (no upstream has admitted an in-flight event yet -- e.g.
// bounded ingress was configured but the trip raced ahead of any admission),
// -ingressPipelineDidRequestPause: must fall back to pausing every connected
// upstream, exactly as it did before the F11 fix.
- (void)testPauseFallsBackToPausingEveryoneWhenNoInFlightBytesReported {
    NSString *firstURL = @"https://fallback-a.test/xrpc/com.atproto.sync.subscribeRepos";
    NSString *secondURL = @"https://fallback-b.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc]
        initWithInitialURLs:@[firstURL, secondURL]];
    ATProtoRelayClient *firstClient = manager.upstreamClients[firstURL];
    ATProtoRelayClient *secondClient = manager.upstreamClients[secondURL];

    for (ATProtoRelayClient *client in @[firstClient, secondClient]) {
        [client setValue:@YES forKey:@"isConnected"];
    }
    [manager relayClientDidConnect:firstClient];
    [manager relayClientDidConnect:secondClient];
    [manager performSynchronouslyOnManagerQueue:^{}];

    [manager configureBoundedIngressWithConfiguration:[self boundedIngressTestConfiguration]
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        completion(RelayIngressReleaseReasonProcessed);
    }];

    // No events were ever admitted for either upstream, so
    // inFlightByteCountByUpstream is empty and there is no largest
    // contributor to select.
    id<RelayIngressBackpressureDelegate> delegate = (id<RelayIngressBackpressureDelegate>)manager;
    [delegate ingressPipelineDidRequestPause:manager.ingressPipeline];
    [manager performSynchronouslyOnManagerQueue:^{}];

    XCTAssertTrue([manager.backpressurePausedUpstreams containsObject:firstURL]);
    XCTAssertTrue([manager.backpressurePausedUpstreams containsObject:secondURL]);
    XCTAssertTrue(firstClient.isReadingPaused);
    XCTAssertTrue(secondClient.isReadingPaused);
}

#pragma mark - Stress cases 1/2/4/6: shared helpers

// Computes the real encoded byte cost RelayIngressPipeline will account for
// an ATProtoFirehoseIdentityEvent of the given wire length, via the same
// public class method the real ingress gate uses
// (+encodedByteLengthForEvent:), rather than hardcoding the internal
// decoded-cost multiplier (F13/R12) in this test file. Keeps configuration
// math below correct even if that multiplier changes.
- (uint64_t)identityEventEncodedBytesForWireFrameLength:(NSUInteger)wireFrameLength {
    ATProtoFirehoseIdentityEvent *probe = [ATProtoFirehoseIdentityEvent eventWithDid:@"did:plc:probe"];
    probe.wireFrameLength = wireFrameLength;
    return [ATProtoRelayIngressPipeline encodedByteLengthForEvent:probe];
}

// Small, single-shard configuration shared by the stress case 1 and case 6
// tests below: shardCount:1 makes "every worker" trivially and
// deterministically the one worker that exists, and the exact byte
// thresholds are derived from the real per-event encoded cost so they stay
// correct regardless of the decoded-cost multiplier's value.
- (ATProtoRelayIngressConfiguration *)singleShardSmallIngressConfiguration {
    uint64_t perEventBytes = [self identityEventEncodedBytesForWireFrameLength:8];
    NSError *configError = nil;
    ATProtoRelayIngressConfiguration *configuration =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:6
                                                              maxByteCount:perEventBytes * 6
                                                        lowEventWatermark:1
                                                         lowByteWatermark:perEventBytes
                                                        highEventWatermark:3
                                                          highByteWatermark:perEventBytes * 3
                                                                shardCount:1
                                                     boundedIngressEnabled:YES
                                                                     error:&configError];
    XCTAssertNotNil(configuration);
    XCTAssertNil(configError);
    return configuration;
}

#pragma mark - Stress case 1: resolver blocks all workers past the high watermark

// Stress case 1 (phase prompt): a stalled resolver blocking every shard's
// worker for longer than the high-watermark interval must not allow the
// byte/event bound to be exceeded, must propagate pause to the real
// upstream socket through the real RelayIngressBackpressureDelegate wiring
// (not a mock delegate), and must drain cleanly to zero outstanding
// accounting once the resolver unblocks. This is the core promise of the
// whole Phase 38 remediation, so this test drives the real
// ATProtoRelayUpstreamManager + ATProtoRelayIngressPipeline wired together
// via -configureBoundedIngressWithConfiguration:..., calling
// client.ingressGate directly the same way testIngressGateAdmissionIsNot...
// and testPauseSelectsOnlyLargestInFlightContributor above do to simulate
// the WebSocket read thread, rather than isolated unit fakes.
- (void)testResolverStallBlocksAllWorkersWithoutExceedingByteBound {
    NSString *url = @"https://stalled-resolver.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[url]];
    ATProtoRelayClient *client = manager.upstreamClients[url];
    [client setValue:@YES forKey:@"isConnected"];
    [manager relayClientDidConnect:client];
    [manager performSynchronouslyOnManagerQueue:^{}];

    ATProtoRelayIngressConfiguration *config = [self singleShardSmallIngressConfiguration];
    dispatch_semaphore_t resolverGate = dispatch_semaphore_create(0);
    dispatch_queue_t countingQueue =
        dispatch_queue_create("com.atproto.test.relay.resolverstall.count", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger processedCount = 0;

    [manager configureBoundedIngressWithConfiguration:config
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        (void)event;
        (void)upstreamURL;
        (void)sequence;
        // Every worker that reaches this block blocks here -- simulating a
        // stalled resolver -- until the test releases resolverGate below.
        dispatch_semaphore_wait(resolverGate, DISPATCH_TIME_FOREVER);
        dispatch_sync(countingQueue, ^{ processedCount++; });
        completion(RelayIngressReleaseReasonProcessed);
    }];
    XCTAssertNotNil(client.ingressGate);

    // Submit more events than maxEventCount so the hard cap is exercised
    // while the single shard's worker stays blocked on resolverGate. The
    // first event dispatches into the (now-stuck) worker; every later event
    // sits admitted-but-queued until the cap is hit, then gets rejected.
    NSUInteger submitted = 0;
    NSUInteger rejected = 0;
    for (NSUInteger index = 0; index < config.maxEventCount + 4; index++) {
        ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:
            [NSString stringWithFormat:@"did:plc:resolver-stall-%lu", (unsigned long)index]];
        event.seq = (int64_t)index + 1;
        event.wireFrameLength = 8;
        BOOL admitted = client.ingressGate(event, FirehoseEventKindIdentity);
        if (admitted) {
            submitted++;
        } else {
            rejected++;
        }
        // The admitted backlog must never exceed the hard cap, even while
        // every worker is stuck and nothing is draining.
        XCTAssertLessThanOrEqual(manager.ingressPipeline.admission.currentEventCount, config.maxEventCount);
        XCTAssertLessThanOrEqual(manager.ingressPipeline.admission.currentByteCount, config.maxByteCount);
    }
    XCTAssertEqual(submitted, config.maxEventCount);
    XCTAssertGreaterThan(rejected, (NSUInteger)0,
                          @"hard cap must reject once the backlog fills while every worker is stuck");

    // The real high-watermark -> onHighWatermark -> backpressureDelegate ->
    // -ingressPipelineDidRequestPause: -> client.pauseReading chain must
    // have paused the real socket by now.
    NSDate *pauseDeadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
    while (!client.isReadingPaused && [[NSDate date] compare:pauseDeadline] == NSOrderedAscending) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTAssertTrue(client.isReadingPaused);
    XCTAssertTrue([manager.backpressurePausedUpstreams containsObject:url]);

    // Release the stalled resolver: every queued worker item can now run.
    for (NSUInteger index = 0; index < submitted; index++) {
        dispatch_semaphore_signal(resolverGate);
    }

    NSDate *drainDeadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while ([[NSDate date] compare:drainDeadline] == NSOrderedAscending) {
        if (manager.ingressPipeline.admission.currentEventCount == 0 &&
            manager.ingressPipeline.admission.currentByteCount == 0) {
            break;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    XCTAssertEqual(manager.ingressPipeline.admission.currentEventCount, (NSUInteger)0);
    XCTAssertEqual(manager.ingressPipeline.admission.currentByteCount, (uint64_t)0);

    __block NSUInteger finalProcessed = 0;
    dispatch_sync(countingQueue, ^{ finalProcessed = processedCount; });
    XCTAssertEqual(finalProcessed, submitted);
}

#pragma mark - Stress case 2: flooding upstream vs. small-event upstreams

- (ATProtoRelayIngressConfiguration *)floodVsSmallIngressConfiguration {
    ATProtoFirehoseCommitEvent *floodProbe = [[ATProtoFirehoseCommitEvent alloc] init];
    floodProbe.wireFrameLength = 10000;
    uint64_t floodEventBytes = [ATProtoRelayIngressPipeline encodedByteLengthForEvent:floodProbe];

    ATProtoFirehoseCommitEvent *smallProbe = [[ATProtoFirehoseCommitEvent alloc] init];
    smallProbe.wireFrameLength = 50;
    uint64_t smallEventBytes = [ATProtoRelayIngressPipeline encodedByteLengthForEvent:smallProbe];

    // Enough headroom for a handful of flood events plus a full run of
    // small ones; high watermark trips after ~4 flood events, well below
    // the hard cap, giving the pause signal real headroom to act (F3).
    uint64_t maxBytes = floodEventBytes * 6 + smallEventBytes * 60;
    uint64_t highBytes = floodEventBytes * 4;
    uint64_t lowBytes = floodEventBytes;
    NSError *configError = nil;
    ATProtoRelayIngressConfiguration *configuration =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:200
                                                              maxByteCount:maxBytes
                                                        lowEventWatermark:5
                                                         lowByteWatermark:lowBytes
                                                        highEventWatermark:150
                                                          highByteWatermark:highBytes
                                                                shardCount:4
                                                     boundedIngressEnabled:YES
                                                                     error:&configError];
    XCTAssertNotNil(configuration);
    XCTAssertNil(configError);
    return configuration;
}

// Stress case 2 (phase prompt): one upstream floods maximum-sized legal
// events while two others send a steady stream of small events, all
// concurrently, through the real gate/pipeline/manager (not isolated unit
// fakes). Proves three things simultaneously: the admitted backlog never
// exceeds the configured hard caps even while the flood is running
// (admission tracks peakEventCount/peakByteCount independently of this
// test's own timing, so asserting against those after the fact is
// equivalent to having sampled the caps continuously throughout); the small
// upstreams are not starved by the flood (each gets its full attempted run
// admitted and processed, not throttled to near zero); and the whole
// pipeline drains to zero outstanding accounting once every worker
// finishes.
- (void)testFloodingUpstreamDoesNotStarveSmallUpstreamsOrExceedBounds {
    NSString *floodURL = @"https://flood-big.test/xrpc/com.atproto.sync.subscribeRepos";
    NSString *smallURLA = @"https://flood-small-a.test/xrpc/com.atproto.sync.subscribeRepos";
    NSString *smallURLB = @"https://flood-small-b.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc]
        initWithInitialURLs:@[floodURL, smallURLA, smallURLB]];
    ATProtoRelayClient *floodClient = manager.upstreamClients[floodURL];
    ATProtoRelayClient *smallClientA = manager.upstreamClients[smallURLA];
    ATProtoRelayClient *smallClientB = manager.upstreamClients[smallURLB];

    for (ATProtoRelayClient *client in @[floodClient, smallClientA, smallClientB]) {
        [client setValue:@YES forKey:@"isConnected"];
    }
    [manager relayClientDidConnect:floodClient];
    [manager relayClientDidConnect:smallClientA];
    [manager relayClientDidConnect:smallClientB];
    [manager performSynchronouslyOnManagerQueue:^{}];

    ATProtoRelayIngressConfiguration *config = [self floodVsSmallIngressConfiguration];
    dispatch_queue_t countingQueue = dispatch_queue_create("com.atproto.test.relay.flood.count", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger totalProcessed = 0;

    [manager configureBoundedIngressWithConfiguration:config
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        (void)event;
        (void)upstreamURL;
        (void)sequence;
        // A small, realistic processing cost so admission genuinely
        // outpaces draining and the caps get exercised, rather than every
        // event completing instantly with no backlog ever forming.
        usleep(1500);
        dispatch_sync(countingQueue, ^{ totalProcessed++; });
        completion(RelayIngressReleaseReasonProcessed);
    }];

    const NSUInteger floodTarget = 24;
    const NSUInteger smallTargetEach = 60;
    const NSUInteger floodAttemptCap = floodTarget * 40;
    const NSUInteger smallAttemptCap = smallTargetEach * 40;

    __block NSUInteger floodAdmitted = 0;
    __block NSUInteger smallAdmittedA = 0;
    __block NSUInteger smallAdmittedB = 0;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t workerQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    dispatch_group_async(group, workerQueue, ^{
        NSUInteger admitted = 0;
        NSUInteger attempts = 0;
        // A paused upstream's real read loop simply would not deliver more
        // frames; mirror that here instead of hammering ingressGate while
        // paused, which a live socket could never actually do.
        while (admitted < floodTarget && attempts < floodAttemptCap) {
            attempts++;
            if (floodClient.isReadingPaused) {
                usleep(500);
                continue;
            }
            ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
            event.repo = [NSString stringWithFormat:@"did:plc:flood-%lu", (unsigned long)admitted];
            event.seq = (int64_t)admitted + 1;
            event.wireFrameLength = 10000;
            if (floodClient.ingressGate(event, FirehoseEventKindCommit)) {
                admitted++;
            }
        }
        floodAdmitted = admitted;
    });

    dispatch_group_async(group, workerQueue, ^{
        NSUInteger admitted = 0;
        NSUInteger attempts = 0;
        while (admitted < smallTargetEach && attempts < smallAttemptCap) {
            attempts++;
            if (smallClientA.isReadingPaused) {
                usleep(500);
                continue;
            }
            ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
            event.repo = [NSString stringWithFormat:@"did:plc:small-a-%lu", (unsigned long)admitted];
            event.seq = (int64_t)admitted + 1;
            event.wireFrameLength = 50;
            if (smallClientA.ingressGate(event, FirehoseEventKindCommit)) {
                admitted++;
            }
        }
        smallAdmittedA = admitted;
    });

    dispatch_group_async(group, workerQueue, ^{
        NSUInteger admitted = 0;
        NSUInteger attempts = 0;
        while (admitted < smallTargetEach && attempts < smallAttemptCap) {
            attempts++;
            if (smallClientB.isReadingPaused) {
                usleep(500);
                continue;
            }
            ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
            event.repo = [NSString stringWithFormat:@"did:plc:small-b-%lu", (unsigned long)admitted];
            event.seq = (int64_t)admitted + 1;
            event.wireFrameLength = 50;
            if (smallClientB.ingressGate(event, FirehoseEventKindCommit)) {
                admitted++;
            }
        }
        smallAdmittedB = admitted;
    });

    XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))), 0l);

    // The admitted backlog never exceeded the configured hard caps at any
    // point during the flood.
    XCTAssertLessThanOrEqual(manager.ingressPipeline.admission.peakEventCount, config.maxEventCount);
    XCTAssertLessThanOrEqual(manager.ingressPipeline.admission.peakByteCount, config.maxByteCount);

    // Both small upstreams got their full attempted run through rather than
    // being starved out by the flood.
    XCTAssertEqual(smallAdmittedA, smallTargetEach);
    XCTAssertEqual(smallAdmittedB, smallTargetEach);
    XCTAssertGreaterThan(floodAdmitted, (NSUInteger)0);

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        if (manager.ingressPipeline.admission.currentEventCount == 0 &&
            manager.ingressPipeline.admission.currentByteCount == 0) {
            break;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    XCTAssertEqual(manager.ingressPipeline.admission.currentEventCount, (NSUInteger)0);
    XCTAssertEqual(manager.ingressPipeline.admission.currentByteCount, (uint64_t)0);

    __block NSUInteger finalProcessed = 0;
    dispatch_sync(countingQueue, ^{ finalProcessed = totalProcessed; });
    XCTAssertEqual(finalProcessed, floodAdmitted + smallAdmittedA + smallAdmittedB);
}

#pragma mark - Stress case 4: disconnect while paused

// Stress case 4 (phase prompt), literal reading: the upstream must actually
// be in a *paused* (backpressure-engaged) state at the moment of disconnect.
// testNoteUpstreamDisconnectedReleasesInFlightTokensPromptly in
// RelayIngressAdmissionTests.m (F10) proves the pipeline-level release-on-
// disconnect mechanism against a plain connected-and-in-flight upstream, but
// never establishes pause first, so it does not exercise the interaction
// with -ingressPipelineDidRequestPause:'s backpressurePausedUpstreams
// bookkeeping (F5/F11) that only a genuinely paused upstream has. This test
// drives the real pause path first (top-1 selective pause, same as
// testPauseSelectsOnlyLargestInFlightContributor), then disconnects that
// same upstream, and asserts both that in-flight tokens still release
// promptly *and* that the pause bookkeeping does not leak a stale entry for
// the now-gone upstream.
- (void)testDisconnectWhilePausedReleasesInFlightTokensAndClearsPauseBookkeeping {
    NSString *url = @"https://disconnect-paused.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[url]];
    ATProtoRelayClient *client = manager.upstreamClients[url];
    [client setValue:@YES forKey:@"isConnected"];
    [manager relayClientDidConnect:client];
    [manager performSynchronouslyOnManagerQueue:^{}];

    dispatch_semaphore_t started = dispatch_semaphore_create(0);
    dispatch_semaphore_t allowFinish = dispatch_semaphore_create(0);
    [manager configureBoundedIngressWithConfiguration:[self boundedIngressTestConfiguration]
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        (void)event;
        (void)upstreamURL;
        (void)sequence;
        dispatch_semaphore_signal(started);
        dispatch_semaphore_wait(allowFinish, DISPATCH_TIME_FOREVER);
        completion(RelayIngressReleaseReasonProcessed);
    }];
    XCTAssertNotNil(client.ingressGate);

    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:disconnect-paused";
    event.seq = 1;
    event.wireFrameLength = 64;
    XCTAssertTrue(client.ingressGate(event, FirehoseEventKindCommit));
    XCTAssertEqual(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);
    XCTAssertGreaterThan(manager.ingressPipeline.admission.currentByteCount, (uint64_t)0);

    // Drive the upstream into backpressure-paused state via the real pause
    // path, exactly as a high-watermark trip would (this is the single
    // connected upstream, so top-1 selection pauses it directly).
    id<RelayIngressBackpressureDelegate> delegate = (id<RelayIngressBackpressureDelegate>)manager;
    [delegate ingressPipelineDidRequestPause:manager.ingressPipeline];
    [manager performSynchronouslyOnManagerQueue:^{}];
    XCTAssertTrue([manager.backpressurePausedUpstreams containsObject:url]);
    XCTAssertTrue(client.isReadingPaused);

    // Now disconnect the still-paused upstream (e.g. the socket dropped
    // while backpressure was already engaged).
    [manager relayClient:client didDisconnectWithError:nil];
    [manager performSynchronouslyOnManagerQueue:^{}];

    // Pause bookkeeping must not leak a stale entry for the now-gone
    // upstream.
    XCTAssertFalse([manager.backpressurePausedUpstreams containsObject:url]);

    // In-flight tokens must still release promptly -- before the blocked
    // process block below is ever unblocked.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (manager.ingressPipeline.admission.currentByteCount != 0 &&
           [[NSDate date] compare:deadline] == NSOrderedAscending) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTAssertEqual(manager.ingressPipeline.admission.currentEventCount, (NSUInteger)0);
    XCTAssertEqual(manager.ingressPipeline.admission.currentByteCount, (uint64_t)0);

    // Release the gate so the shard queue's own (now-redundant) release
    // call runs; it must double-release harmlessly, matching F10's
    // regression test.
    dispatch_semaphore_signal(allowFinish);
    [manager.ingressPipeline waitForDrainForTesting];
    XCTAssertEqual(manager.ingressPipeline.admission.currentEventCount, (NSUInteger)0);
    XCTAssertEqual(manager.ingressPipeline.admission.currentByteCount, (uint64_t)0);
}

#pragma mark - Stress case 6: reconnect generation change races a scheduled resume

// Stress case 6 (phase prompt), literal reading: "reconnect generation
// changes before a *scheduled* resume callback" -- a timing race, not a
// pre-arranged static mismatch. testResumeClearsPauseBookkeepingButSkips...
// above (F5) proves the generation-mismatch *logic* by setting up the
// mismatch synchronously and calling -ingressPipelineDidRequestResume:
// directly; it never drives a genuine onLowWatermark-triggered async resume
// dispatch. This test does: it crosses the high watermark for real (pausing
// the upstream through the real wiring, as in stress case 1 above), then
// releases enough admitted tokens to cross the low watermark for real --
// firing admission.onLowWatermark -> the pipeline's closure ->
// -ingressPipelineDidRequestResume:, which itself does a further
// dispatch_async onto _managerQueue -- and bumps ingressGeneration in the
// narrow window before that dispatched callback actually runs.
//
// Ordering is not synchronized with a lock; it relies on a hop-count
// asymmetry that is reliable in practice: the generation bump below is a
// single direct dispatch onto _managerQueue issued synchronously on the
// test thread, whereas the real resume dispatch must first cross the
// blocked shard's semaphore wakeup, then admission's own serial queue
// (dispatch_sync from the shard queue), then a dedicated watermark-handler
// queue, before it can even attempt to enqueue onto _managerQueue -- four
// or five hops and at least one kernel thread wakeup behind the single hop
// the bump takes. This mirrors the "give an accidental double-submission
// time to land" polling idiom already used in
// testIngressGateAdmissionIsNotDoubleSubmittedByDelegateChain above, just
// applied to winning a head start rather than observing an absence.
- (void)testResumeGenerationChangeRacesScheduledAsyncResumeCallback {
    NSString *url = @"https://race-resume.test/xrpc/com.atproto.sync.subscribeRepos";
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[url]];
    ATProtoRelayClient *client = manager.upstreamClients[url];
    [client setValue:@YES forKey:@"isConnected"];
    [manager relayClientDidConnect:client];
    [manager performSynchronouslyOnManagerQueue:^{}];

    ATProtoRelayIngressConfiguration *config = [self singleShardSmallIngressConfiguration];
    dispatch_semaphore_t processGate = dispatch_semaphore_create(0);
    [manager configureBoundedIngressWithConfiguration:config
                                               metrics:[ATProtoRelayMetrics sharedMetrics]
                                          processBlock:^(id event, NSString *upstreamURL, int64_t sequence, RelayIngressProcessCompletion completion) {
        (void)event;
        (void)upstreamURL;
        (void)sequence;
        dispatch_semaphore_wait(processGate, DISPATCH_TIME_FOREVER);
        completion(RelayIngressReleaseReasonProcessed);
    }];
    XCTAssertNotNil(client.ingressGate);

    // Cross the high watermark for real, pausing the upstream through the
    // genuine backpressure wiring (not a manual delegate call).
    for (NSUInteger index = 0; index < config.highEventWatermark; index++) {
        ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:
            [NSString stringWithFormat:@"did:plc:race-resume-%lu", (unsigned long)index]];
        event.seq = (int64_t)index + 1;
        event.wireFrameLength = 8;
        XCTAssertTrue(client.ingressGate(event, FirehoseEventKindIdentity));
    }

    NSDate *pauseDeadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (!client.isReadingPaused && [[NSDate date] compare:pauseDeadline] == NSOrderedAscending) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTAssertTrue(client.isReadingPaused);
    __block NSNumber *pausedGeneration = nil;
    [manager performSynchronouslyOnManagerQueue:^{
        XCTAssertTrue([manager.backpressurePausedUpstreams containsObject:url]);
        pausedGeneration = manager.clientIngressGenerations[url];
    }];
    XCTAssertEqualObjects(pausedGeneration, @0);

    // Trigger the real low-watermark crossing: releasing every admitted
    // token drops accounted count/bytes to 0, well under both low
    // watermarks, firing admission.onLowWatermark for real.
    for (NSUInteger index = 0; index < config.highEventWatermark; index++) {
        dispatch_semaphore_signal(processGate);
    }

    // Immediately race the generation bump against the resume dispatch that
    // chain is about to (asynchronously, several hops later) issue. See the
    // hop-count argument in the comment above.
    [manager performSynchronouslyOnManagerQueue:^{
        manager.ingressGeneration = 1;
    }];

    // Poll for the resume handler (now guaranteed to run behind the bump)
    // to finish clearing pause bookkeeping.
    NSDate *resumeDeadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
    __block BOOL stillPaused = YES;
    while ([[NSDate date] compare:resumeDeadline] == NSOrderedAscending) {
        __block BOOL contains = NO;
        [manager performSynchronouslyOnManagerQueue:^{
            contains = [manager.backpressurePausedUpstreams containsObject:url];
        }];
        stillPaused = contains;
        if (!stillPaused) {
            break;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }

    // Bookkeeping cleared unconditionally, exactly as in the synchronous F5
    // regression test above...
    XCTAssertFalse(stillPaused);
    // ...but because the generation changed out from under the
    // already-in-flight resume dispatch, the stale client's socket must be
    // left untouched: still paused, -resumeReading never called.
    XCTAssertTrue(client.isReadingPaused);

    [manager.ingressPipeline waitForDrainForTesting];
    XCTAssertEqual(manager.ingressPipeline.admission.currentEventCount, (NSUInteger)0);
    XCTAssertEqual(manager.ingressPipeline.admission.currentByteCount, (uint64_t)0);
}

@end
