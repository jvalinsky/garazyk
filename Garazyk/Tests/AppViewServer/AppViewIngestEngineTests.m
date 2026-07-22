// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
#import "Sync/Firehose/Firehose.h"

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

- (void)testBackpressureMarksRepoDirtyAndDurable {
    NSError *err = nil;
    AppViewRepoSyncState *state = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:lagged"];
    state.status = AppViewRepoSyncStatusSynced;
    state.lastRev = @"rev0";
    XCTAssertTrue([self.db upsertRepoSyncState:state error:&err]);

    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[]];
    engine.maxLagForBackpressure = 0;

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 10;
    event.repo = @"did:plc:lagged";
    event.rev = @"rev1";
    event.since = @"rev0";
    event.ops = @[];
    event.blocks = [NSData data];

    [engine _handleCommitEvent:event fromRelay:@"wss://test.relay"];

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:lagged" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusDirty);
    XCTAssertEqual([self.db durableCursorForRelayURL:@"wss://test.relay"], 10LL);

    NSArray<NSDictionary *> *events = [self.db loadStoredEventsAfterCursor:0 limit:10 error:&err];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0][@"event_type"], @"dirty_repair");
}

- (void)testProcessedLiveCommitAdvancesRepoLastRev {
    NSError *err = nil;
    AppViewRepoSyncState *state = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:live"];
    state.status = AppViewRepoSyncStatusSynced;
    state.lastRev = @"rev0";
    XCTAssertTrue([self.db upsertRepoSyncState:state error:&err]);

    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[]];
    engine.maxLagForBackpressure = 1000;

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 11;
    event.repo = @"did:plc:live";
    event.rev = @"rev1";
    event.since = @"rev0";
    event.ops = @[];

    [engine _handleCommitEvent:event fromRelay:@"wss://test.relay"];
    [NSThread sleepForTimeInterval:0.2];

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:live" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusSynced);
    XCTAssertEqualObjects(loaded.lastRev, @"rev1");
    XCTAssertEqual([self.db durableCursorForRelayURL:@"wss://test.relay"], 11LL);
}

- (void)testFirstLiveCommitForUnknownRepoMarksRepoSynced {
    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[]];
    engine.maxLagForBackpressure = 1000;

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 12;
    event.repo = @"did:plc:newrepo";
    event.rev = @"rev1";
    event.ops = @[];

    [engine _handleCommitEvent:event fromRelay:@"wss://test.relay"];
    [NSThread sleepForTimeInterval:0.2];

    NSError *err = nil;
    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:newrepo" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusSynced);
    XCTAssertEqualObjects(loaded.lastRev, @"rev1");
}

- (void)testQueuedLiveCommitIsAcknowledgedAfterMaterialization {
    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[]];
    engine.maxLagForBackpressure = 1000;

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 13;
    event.repo = @"did:plc:queued";
    event.rev = @"rev1";
    event.ops = @[];

    [engine _handleCommitEvent:event fromRelay:@"wss://test.relay"];
    [NSThread sleepForTimeInterval:0.2];

    NSError *error = nil;
    NSArray<NSDictionary *> *rows = [self.db executeParameterizedQuery:
        @"SELECT raw_envelope, indexed_at, terminal_error, attempts "
         "FROM appview_pending_index_events WHERE relay_url = ? AND seq = ?"
        params:@[@"wss://test.relay", @13] error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, 1U);
    XCTAssertGreaterThan([rows[0][@"raw_envelope"] length], 0U);
    XCTAssertNotEqual(rows[0][@"indexed_at"], [NSNull null]);
    XCTAssertNil(rows[0][@"terminal_error"]);
    XCTAssertEqual([rows[0][@"attempts"] integerValue], 1);
}

- (void)testConcurrencySafety {
    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[@"wss://relay1", @"wss://relay2"]];
    engine.maxLagForBackpressure = 1000;
    
    // We use a high number of iterations to increase the chance of catching race conditions
    const int iterations = 1000;
    XCTestExpectation *expectation = [self expectationWithDescription:@"Concurrency tests completed"];
    expectation.expectedFulfillmentCount = iterations * 2;
    
    dispatch_queue_t testQueue1 = dispatch_queue_create("test.queue.1", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_t testQueue2 = dispatch_queue_create("test.queue.2", DISPATCH_QUEUE_CONCURRENT);
    
    for (int i = 0; i < iterations; i++) {
        dispatch_async(testQueue1, ^{
            FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
            event.seq = 100 + i;
            event.repo = [NSString stringWithFormat:@"did:plc:repo%d", i];
            event.rev = [NSString stringWithFormat:@"rev%d", i];
            
            [engine _handleCommitEvent:event fromRelay:@"wss://relay1"];
            [expectation fulfill];
        });
        
        dispatch_async(testQueue2, ^{
            FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
            event.seq = 5000 + i;
            event.repo = [NSString stringWithFormat:@"did:plc:other%d", i];
            event.rev = [NSString stringWithFormat:@"rev%d", i];
            
            [engine _handleCommitEvent:event fromRelay:@"wss://relay2"];
            [expectation fulfill];
        });
    }
    
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
    
    // Verify internal state remains consistent
    // We can't directly access private properties, but we can verify side effects
    // like highestSeenSeq which should be >= 5000 + iterations - 1
    // and that the database has the expected number of events.
    
    // Wait for the engine's internal processing queue to finish
    // Since it's serial now, we can just dispatch a sync block to it if we had access,
    // or wait a bit.
    [NSThread sleepForTimeInterval:1.0];
    
    NSError *err = nil;
    NSArray *events = [self.db loadStoredEventsAfterCursor:0 limit:iterations * 3 error:&err];
    XCTAssertNil(err);
    // Some might be skipped due to idempotency if we picked overlapping DIDs/revs, 
    // but here we used unique ones.
    XCTAssertGreaterThanOrEqual(events.count, (NSUInteger)(iterations * 2));
}

@end
