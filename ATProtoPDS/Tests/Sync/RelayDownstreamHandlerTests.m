#import <XCTest/XCTest.h>
#import "Sync/RelayDownstreamHandler.h"
#import "Sync/RelayEventBuffer.h"
#import "Sync/SubscribeReposHandler.h"
#import "Sync/RelayMetrics.h"
#import "Sync/RelayUpstreamManager.h"
#import "Sync/Firehose.h"

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

@end
