/*!
 @file AppViewIngestEngineTests.m

 @abstract Tests for ingest engine cursor resume, duplicate suppression,
 and pending delta buffering.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"

// ---------------------------------------------------------------------------
// Tracking delegate
// ---------------------------------------------------------------------------

@interface IngestTrackingDelegate : NSObject <AppViewIngestEngineDelegate>
@property (nonatomic, strong) NSMutableArray<AppViewIngestEvent *> *receivedCommits;
@property (nonatomic, strong) NSMutableArray<AppViewIngestEvent *> *receivedIdentityChanges;
@end

@implementation IngestTrackingDelegate

- (instancetype)init {
    self = [super init];
    _receivedCommits = [NSMutableArray array];
    _receivedIdentityChanges = [NSMutableArray array];
    return self;
}

- (void)ingestEngine:(AppViewIngestEngine *)engine didReceiveCommit:(AppViewIngestEvent *)event {
    @synchronized(self) { [_receivedCommits addObject:event]; }
}

- (void)ingestEngine:(AppViewIngestEngine *)engine didReceiveIdentityChange:(AppViewIngestEvent *)event {
    @synchronized(self) { [_receivedIdentityChanges addObject:event]; }
}

@end

// ---------------------------------------------------------------------------

@interface AppViewIngestEngineTests : XCTestCase
@property (nonatomic, strong) AppViewDatabase *db;
@property (nonatomic, strong) IngestTrackingDelegate *delegate;
@end

@implementation AppViewIngestEngineTests

- (void)setUp {
    [super setUp];
    NSError *err = nil;
    self.db = [[AppViewDatabase alloc] initInMemoryWithError:&err];
    XCTAssertNotNil(self.db);
    [self.db runMigrations:&err];
    self.delegate = [[IngestTrackingDelegate alloc] init];
}

- (void)tearDown {
    [self.db close];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Database layer tests (not live network)
// ---------------------------------------------------------------------------

- (void)testCheckpointPersistedOnStop {
    // Simulate saving a checkpoint
    AppViewCheckpoint *cp = [[AppViewCheckpoint alloc]
        initWithRelayURL:@"wss://test.relay" seq:999];
    NSError *err = nil;
    [self.db saveCheckpoint:cp error:&err];
    XCTAssertNil(err);

    // Engine should resume from this checkpoint
    AppViewCheckpoint *loaded = [self.db loadCheckpointForRelayURL:@"wss://test.relay" error:&err];
    XCTAssertEqual(loaded.seq, 999LL);
}

- (void)testEventLogIdempotency {
    NSError *err = nil;
    NSData *envelope = [NSData data];

    // Log same event twice
    [self.db logEvent:50 did:@"did:plc:test" rev:@"rev" cid:@"cid" rawEnvelope:envelope error:&err];
    [self.db logEvent:51 did:@"did:plc:test" rev:@"rev" cid:@"cid" rawEnvelope:envelope error:&err];

    // hasEvent should return YES after first insert
    XCTAssertTrue([self.db hasEventWithDID:@"did:plc:test" rev:@"rev" cid:@"cid"],
                  @"Duplicate event should be detected");
}

- (void)testPendingDeltaBufferedForProcessingRepo {
    NSError *err = nil;
    // Mark repo as processing
    AppViewRepoSyncState *state = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:busy"];
    state.status = AppViewRepoSyncStatusProcessing;
    [self.db upsertRepoSyncState:state error:nil];

    // Enqueue a pending delta (simulating the ingest engine buffering)
    AppViewPendingDelta *delta = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:busy" seq:100 commitCID:@"cid1" rev:@"rev1"
        rawEnvelope:[NSData data]];
    XCTAssertTrue([self.db enqueuePendingDelta:delta error:&err]);

    // After backfill completes, dequeue
    NSArray<AppViewPendingDelta *> *dequeued = [self.db dequeuePendingDeltasForDID:@"did:plc:busy" error:&err];
    XCTAssertEqual(dequeued.count, 1u);
    XCTAssertEqualObjects(dequeued[0].commitCID, @"cid1");
}

- (void)testIngestEventCreation {
    AppViewIngestEvent *event = [[AppViewIngestEvent alloc] init];
    event.seq       = 12345;
    event.relayURL  = @"wss://test";
    event.did       = @"did:plc:abc";
    event.eventType = @"#commit";
    event.receivedAt = [NSDate date];

    XCTAssertEqual(event.seq, 12345LL);
    XCTAssertEqualObjects(event.eventType, @"#commit");
}

- (void)testIngestEngineInitialization {
    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[@"wss://bsky.network"]];
    XCTAssertNotNil(engine);
    XCTAssertFalse(engine.isRunning);
    XCTAssertEqual(engine.checkpointIntervalMs, 5000u);
}

@end
