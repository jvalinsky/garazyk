// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayDownstreamHandler.h"
#import "Sync/Relay/RelayEventBuffer.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"
#import "Network/ATProtoSafeHTTPClient.h"

@interface RelayDownstreamHandler (RepoInventoryTesting)
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;
@end

@interface RelayInventoryHTTPClient : ATProtoSafeHTTPClient
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pages;
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *requests;
@end

@implementation RelayInventoryHTTPClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _pages = [NSMutableArray array];
        _requests = [NSMutableArray array];
    }
    return self;
}

- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                               options:(ATProtoSafeHTTPClientOptions *)options
                            completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    [self.requests addObject:request];
    NSDictionary *page = self.pages.count > 0 ? self.pages.firstObject : @{};
    if (self.pages.count > 0) {
        [self.pages removeObjectAtIndex:0];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:page options:0 error:nil];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                               statusCode:200
                                                              HTTPVersion:@"HTTP/1.1"
                                                             headerFields:@{}];
    completion(data, response, nil);
}

@end

@interface RelayDownstreamHandlerTests : XCTestCase

@end

@implementation RelayDownstreamHandlerTests

- (void)testInitialization {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:handler];
    
    XCTAssertNotNil(downstreamHandler, @"Handler should initialize");
}

- (void)testEventBufferProperty {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:handler];
    
    XCTAssertEqual(downstreamHandler.eventBuffer, buffer, @"Event buffer should be the same instance");
}

- (void)testSubscribeReposHandlerProperty {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:handler];
    
    XCTAssertEqual(downstreamHandler.subscribeReposHandler, handler, @"SubscribeReposHandler should be the same instance");
}

- (void)testMetricsProperty {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];
    RelayMetrics *metrics = [[RelayMetrics alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:handler];
    
    XCTAssertNil(downstreamHandler.metrics, @"Metrics should initially be nil");
    
    downstreamHandler.metrics = metrics;
    
    XCTAssertEqual(downstreamHandler.metrics, metrics, @"Metrics should be settable and retrievable");
}

- (void)testUpstreamManagerDelegateConformance {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:handler];
    
    // Should conform to RelayUpstreamManagerDelegate
    XCTAssertTrue([downstreamHandler conformsToProtocol:@protocol(RelayUpstreamManagerDelegate)],
                  @"Should conform to RelayUpstreamManagerDelegate");
}

- (void)testUpstreamManagerDidConnectToUpstream {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayMetrics *metrics = [[RelayMetrics alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    downstreamHandler.metrics = metrics;
    
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    
    // Should not crash when delegate method is called
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didConnectToUpstream:@"test.pds.com"],
                     @"Should handle connect notification without crash");
}

- (void)testUpstreamManagerDidDisconnectFromUpstream {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayMetrics *metrics = [[RelayMetrics alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    downstreamHandler.metrics = metrics;
    
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    
    NSError *testError = [NSError errorWithDomain:@"TestDomain" code:1 userInfo:nil];
    
    // Should not crash when delegate method is called
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didDisconnectFromUpstream:@"test.pds.com" error:testError],
                     @"Should handle disconnect notification without crash");
}

- (void)testUpstreamManagerDidReceiveCursor {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayMetrics *metrics = [[RelayMetrics alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    downstreamHandler.metrics = metrics;
    
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    
    // Should not crash when cursor is received
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didReceiveCursor:12345 fromUpstream:@"test.pds.com"],
                     @"Should handle cursor notification without crash");
}

- (void)testUpstreamManagerDidReceiveEventCommit {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayMetrics *metrics = [[RelayMetrics alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    downstreamHandler.metrics = metrics;
    
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    
    // Create a commit event
    FirehoseCommitEvent *commitEvent = [[FirehoseCommitEvent alloc] init];
    
    // Should not crash when event is received
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didReceiveEvent:commitEvent fromUpstream:@"test.pds.com"],
                     @"Should handle commit event without crash");
}

- (void)testCommitEventUpdatesRepoStateManager {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    RelayRepoStateManager *repoStateManager = [[RelayRepoStateManager alloc] init];
    downstreamHandler.repoStateManager = repoStateManager;

    FirehoseCommitEvent *commitEvent = [[FirehoseCommitEvent alloc] init];
    commitEvent.repo = @"did:plc:relay-state-test";
    commitEvent.commit = [CID sha256:[@"relay state test commit" dataUsingEncoding:NSUTF8StringEncoding]];
    commitEvent.rev = @"3mrelaystate";
    commitEvent.seq = 42;

    NSString *expectedRootCID = commitEvent.commit.stringValue;
    NSString *expectedRev = commitEvent.rev;
    int64_t expectedUpstreamSeq = commitEvent.seq;

    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    [downstreamHandler upstreamManager:manager
                       didReceiveEvent:commitEvent
                          fromUpstream:@"test.pds.com"];

    XCTestExpectation *stateUpdated = [self expectationWithDescription:@"commit state is recorded"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        XCTAssertEqualObjects([repoStateManager rootCIDForRepo:commitEvent.repo],
                              expectedRootCID);
        XCTAssertEqualObjects([repoStateManager revForRepo:commitEvent.repo], expectedRev);
        XCTAssertEqual([repoStateManager cursorForRepo:commitEvent.repo], expectedUpstreamSeq);
        XCTAssertEqual([repoStateManager statusForRepo:commitEvent.repo], RelayRepoStatusActive);
        [stateUpdated fulfill];
    });
    [self waitForExpectations:@[stateUpdated] timeout:1.0];
}

- (void)testUpstreamConnectionBootstrapsPaginatedRepoInventory {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    RelayRepoStateManager *repoStateManager = [[RelayRepoStateManager alloc] init];
    downstreamHandler.repoStateManager = repoStateManager;

    RelayInventoryHTTPClient *client = [[RelayInventoryHTTPClient alloc] init];
    [client.pages addObject:@{
        @"cursor": @"next::did:plc:two",
        @"repos": @[
            @{@"did": @"did:plc:one", @"head": @"bafyreone", @"rev": @"3mone", @"active": @YES}
        ]
    }];
    [client.pages addObject:@{
        @"repos": @[
            @{@"did": @"did:plc:two", @"head": @"bafryetwo", @"rev": @"3mtwo", @"active": @NO}
        ]
    }];
    downstreamHandler.safeHTTPClient = client;

    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[]];
    [downstreamHandler upstreamManager:manager didConnectToUpstream:@"https://inventory.test"];

    XCTestExpectation *bootstrapCompleted = [self expectationWithDescription:@"inventory bootstrap completes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        XCTAssertEqual(client.requests.count, 2);
        XCTAssertEqualObjects(client.requests[0].URL.absoluteString,
                              @"https://inventory.test/xrpc/com.atproto.sync.listRepos?limit=1000");
        NSURLComponents *secondRequestComponents =
            [NSURLComponents componentsWithURL:client.requests[1].URL resolvingAgainstBaseURL:NO];
        XCTAssertEqualObjects(secondRequestComponents.queryItems[1].value,
                              @"next::did:plc:two");
        XCTAssertEqualObjects([repoStateManager rootCIDForRepo:@"did:plc:one"], @"bafyreone");
        XCTAssertEqualObjects([repoStateManager revForRepo:@"did:plc:one"], @"3mone");
        XCTAssertEqual([repoStateManager statusForRepo:@"did:plc:one"], RelayRepoStatusActive);
        XCTAssertEqualObjects([repoStateManager rootCIDForRepo:@"did:plc:two"], @"bafryetwo");
        XCTAssertEqual([repoStateManager statusForRepo:@"did:plc:two"], RelayRepoStatusDesynchronized);
        [bootstrapCompleted fulfill];
    });
    [self waitForExpectations:@[bootstrapCompleted] timeout:1.0];
}

- (void)testUpstreamManagerDidReceiveEventIdentity {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayMetrics *metrics = [[RelayMetrics alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    downstreamHandler.metrics = metrics;
    
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    
    // Create an identity event
    FirehoseIdentityEvent *identityEvent = [[FirehoseIdentityEvent alloc] init];
    
    // Should not crash when event is received
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didReceiveEvent:identityEvent fromUpstream:@"test.pds.com"],
                     @"Should handle identity event without crash");
}

- (void)testUpstreamManagerDidReceiveEventAccount {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayMetrics *metrics = [[RelayMetrics alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    downstreamHandler.metrics = metrics;
    
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    
    // Create an account event
    FirehoseAccountEvent *accountEvent = [[FirehoseAccountEvent alloc] init];
    
    // Should not crash when event is received
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didReceiveEvent:accountEvent fromUpstream:@"test.pds.com"],
                     @"Should handle account event without crash");
}

- (void)testUpstreamManagerDidReceiveEventError {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayMetrics *metrics = [[RelayMetrics alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    downstreamHandler.metrics = metrics;
    
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    
    // Create an error event
    FirehoseErrorEvent *errorEvent = [[FirehoseErrorEvent alloc] init];
    
    // Should not crash when event is received
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didReceiveEvent:errorEvent fromUpstream:@"test.pds.com"],
                     @"Should handle error event without crash");
}

- (void)testActiveDownstreamCountInitial {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    
    // Initially no downstream connections
    NSUInteger count = [downstreamHandler activeDownstreamCount];
    XCTAssertEqual(count, 0, @"Should have zero downstream connections initially");
}

- (void)testHandlesNilMetrics {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    // metrics is nil
    
    RelayUpstreamManager *manager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
    
    // Should not crash when metrics is nil
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didConnectToUpstream:@"test.pds.com"],
                     @"Should handle connect with nil metrics");
    XCTAssertNoThrow([downstreamHandler upstreamManager:manager didReceiveCursor:100 fromUpstream:@"test.pds.com"],
                     @"Should handle cursor with nil metrics");
}

#pragma mark - Chain Verification

- (void)testVerifyChainFirstCommitAccepted {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    RelayRepoStateManager *repoStateManager = [[RelayRepoStateManager alloc] init];
    downstreamHandler.repoStateManager = repoStateManager;

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:newrepo";
    event.commit = [CID sha256:[@"commit1" dataUsingEncoding:NSUTF8StringEncoding]];
    event.rev = @"3m1";
    event.seq = 1;

    XCTAssertTrue([downstreamHandler verifyChainForCommitEvent:event],
                  @"First commit for unknown repo should be accepted");
}

- (void)testVerifyChainValidContinuation {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    RelayRepoStateManager *repoStateManager = [[RelayRepoStateManager alloc] init];
    downstreamHandler.repoStateManager = repoStateManager;

    CID *root1 = [CID sha256:[@"root1" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *root2 = [CID sha256:[@"root2" dataUsingEncoding:NSUTF8StringEncoding]];

    [repoStateManager handleCommitForRepo:@"did:plc:test" root:root1.stringValue rev:@"1" seq:1];

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:test";
    event.commit = root2;
    event.rev = @"2";
    event.seq = 2;
    event.prevData = root1;

    XCTAssertTrue([downstreamHandler verifyChainForCommitEvent:event],
                  @"Commit with prevData matching stored root should be accepted");
}

- (void)testVerifyChainBreakDetected {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    RelayRepoStateManager *repoStateManager = [[RelayRepoStateManager alloc] init];
    downstreamHandler.repoStateManager = repoStateManager;

    CID *root1 = [CID sha256:[@"root1" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *wrongPrev = [CID sha256:[@"wrongprev" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *root2 = [CID sha256:[@"root2" dataUsingEncoding:NSUTF8StringEncoding]];

    [repoStateManager handleCommitForRepo:@"did:plc:test" root:root1.stringValue rev:@"1" seq:1];

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:test";
    event.commit = root2;
    event.rev = @"2";
    event.seq = 2;
    event.prevData = wrongPrev;

    XCTAssertFalse([downstreamHandler verifyChainForCommitEvent:event],
                   @"Commit with mismatched prevData should be rejected");

    XCTAssertEqual([repoStateManager statusForRepo:@"did:plc:test"], RelayRepoStatusDesynchronized,
                   @"Repo should be marked desynchronized after chain break");
}

- (void)testVerifyChainNoPrevDataAcceptedWithWarning {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    RelayRepoStateManager *repoStateManager = [[RelayRepoStateManager alloc] init];
    downstreamHandler.repoStateManager = repoStateManager;

    CID *root1 = [CID sha256:[@"root1" dataUsingEncoding:NSUTF8StringEncoding]];
    [repoStateManager handleCommitForRepo:@"did:plc:test" root:root1.stringValue rev:@"1" seq:1];

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:test";
    event.commit = [CID sha256:[@"root2" dataUsingEncoding:NSUTF8StringEncoding]];
    event.rev = @"2";
    event.seq = 2;
    event.prevData = nil;

    XCTAssertTrue([downstreamHandler verifyChainForCommitEvent:event],
                  @"Commit with nil prevData for known repo should be accepted with warning");
}

- (void)testVerifyChainNoStateManagerAlwaysAccepted {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    SubscribeReposHandler *subHandler = [[SubscribeReposHandler alloc] init];
    RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
        initWithEventBuffer:buffer
        subscribeReposHandler:subHandler];
    // repoStateManager is nil

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:test";
    event.commit = [CID sha256:[@"root" dataUsingEncoding:NSUTF8StringEncoding]];
    event.rev = @"1";
    event.seq = 1;

    XCTAssertTrue([downstreamHandler verifyChainForCommitEvent:event],
                  @"Should accept when no state manager is configured");
}

@end
