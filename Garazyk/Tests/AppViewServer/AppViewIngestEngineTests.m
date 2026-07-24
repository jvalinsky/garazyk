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
#import "Sync/Relay/EventFormatter.h"

// ---------------------------------------------------------------------------
// Tracking delegate
// ---------------------------------------------------------------------------

@interface IngestTrackingDelegate : NSObject <AppViewIngestEngineDelegate>
@property (nonatomic, strong) NSMutableArray<AppViewIngestEvent *> *receivedCommits;
@property (nonatomic, strong) NSMutableArray<AppViewIngestEvent *> *receivedIdentityChanges;
@property (nonatomic, strong) NSMutableArray<AppViewIngestEvent *> *receivedAccountEvents;
@end

@implementation IngestTrackingDelegate

- (instancetype)init {
    self = [super init];
    _receivedCommits = [NSMutableArray array];
    _receivedIdentityChanges = [NSMutableArray array];
    _receivedAccountEvents = [NSMutableArray array];
    return self;
}

- (void)ingestEngine:(AppViewIngestEngine *)engine didReceiveCommit:(AppViewIngestEvent *)event {
    @synchronized(self) { [_receivedCommits addObject:event]; }
}

- (void)ingestEngine:(AppViewIngestEngine *)engine didReceiveIdentityChange:(AppViewIngestEvent *)event {
    @synchronized(self) { [_receivedIdentityChanges addObject:event]; }
}

- (void)ingestEngine:(AppViewIngestEngine *)engine didReceiveAccountEvent:(AppViewIngestEvent *)event {
    @synchronized(self) { [_receivedAccountEvents addObject:event]; }
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

- (void)testQueueWatermarkAppliesBackpressureBeforeAcceptingAnotherEvent {
    NSError *error = nil;
    XCTAssertTrue([self.db enqueueIndexEventForRelayURL:@"wss://test.relay" seq:9 eventType:@"#commit"
                                                    did:@"did:plc:queued" rev:@"rev0" cid:nil
                                            rawEnvelope:[NSData data] error:&error]);
    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc] initWithDatabase:self.db relayURLs:@[]];
    engine.maxLagForBackpressure = INT64_MAX;
    engine.indexQueueHighWatermarkEvents = 1;

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 10;
    event.repo = @"did:plc:over-limit";
    event.rev = @"rev1";
    event.ops = @[];
    [engine _handleCommitEvent:event fromRelay:@"wss://test.relay"];

    NSDictionary<NSString *, NSNumber *> *metrics = [self.db pendingIndexQueueMetricsForRelayURL:@"wss://test.relay" error:&error];
    XCTAssertEqual([metrics[@"event_count"] integerValue], 1);
    NSArray<NSDictionary *> *events = [self.db loadStoredEventsAfterCursor:0 limit:10 error:&error];
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
    [engine waitForIndexQueueDrainForTesting];

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
    [engine waitForIndexQueueDrainForTesting];

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
    [engine waitForIndexQueueDrainForTesting];

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

- (void)testStartRecoversQueuedCommitBeforeRelayConsumption {
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 14;
    event.repo = @"did:plc:recovered";
    event.rev = @"rev1";
    event.ops = @[];

    NSError *error = nil;
    NSData *envelope = [[[EventFormatter alloc] init] encodeCommitEvent:event error:&error];
    XCTAssertNotNil(envelope, @"%@", error);
    XCTAssertTrue([self.db enqueueIndexEventForRelayURL:@"wss://test.relay" seq:event.seq eventType:@"live_commit"
                                                    did:event.repo rev:event.rev cid:nil rawEnvelope:envelope error:&error], @"%@", error);

    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc] initWithDatabase:self.db relayURLs:@[]];
    [engine start];
    [engine waitForIndexQueueDrainForTesting];
    [engine stop];

    AppViewRepoSyncState *state = [self.db loadRepoSyncStateForDID:event.repo error:&error];
    XCTAssertEqual(state.status, AppViewRepoSyncStatusSynced);
    XCTAssertEqualObjects(state.lastRev, @"rev1");
    NSArray<NSDictionary *> *rows = [self.db executeParameterizedQuery:
        @"SELECT indexed_at FROM appview_pending_index_events WHERE relay_url = ? AND seq = ?"
        params:@[@"wss://test.relay", @14] error:&error];
    XCTAssertNotNil(rows[0][@"indexed_at"]);
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
    
    // Wait for the engine's internal processing queue to finish.
    [engine waitForIndexQueueDrainForTesting];
    
    NSError *err = nil;
    NSArray *events = [self.db loadStoredEventsAfterCursor:0 limit:iterations * 3 error:&err];
    XCTAssertNil(err);
    // Some might be skipped due to idempotency if we picked overlapping DIDs/revs, 
    // but here we used unique ones.
    XCTAssertGreaterThanOrEqual(events.count, (NSUInteger)(iterations * 2));
}

// ---------------------------------------------------------------------------
// Takedown Enforcement
// ---------------------------------------------------------------------------

- (void)testTakedownEventPurgesRecordsAndBlocks {
    NSError *err = nil;
    NSString *did = @"did:plc:takendown";

    // Seed records for the DID
    XCTAssertTrue([self.db saveRecordWithURI:@"at://did:plc:takendown/app.bsky.feed.post/one"
                                        did:did collection:@"app.bsky.feed.post" rkey:@"one"
                                        cid:@"cid1" handle:nil
                                      value:@"{\"text\":\"hello\"}" subjectDid:nil error:&err]);
    XCTAssertTrue([self.db saveRecordWithURI:@"at://did:plc:takendown/app.bsky.feed.post/two"
                                        did:did collection:@"app.bsky.feed.post" rkey:@"two"
                                        cid:@"cid2" handle:nil
                                      value:@"{\"text\":\"world\"}" subjectDid:nil error:&err]);
    XCTAssertEqual([self.db getTotalRecordsCountForCollection:@"app.bsky.feed.post" error:&err], 2);

    // Seed a block
    NSData *blockCid = [@"block-cid" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *blockData = [@"block-data" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([self.db saveBlockWithCid:blockCid repoDid:did blockData:blockData
                               contentType:@"application/cbor" error:&err]);
    XCTAssertEqual([self.db getTotalBlocksCountWithError:&err], 1);

    // Seed search_actors
    [self.db executeParameterizedUpdate:@"INSERT INTO search_actors(did, display_name, handle, description) VALUES (?, ?, ?, ?)"
                                 params:@[did, @"Test", @"test.bsky.social", @"desc"] error:nil];

    // Simulate a takedown account event
    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[@"wss://test.relay"]];
    engine.delegate = self.delegate;

    FirehoseAccountEvent *takedown = [[FirehoseAccountEvent alloc] init];
    takedown.seq = 50;
    takedown.did = did;
    takedown.active = NO;
    takedown.status = @"takendown";
    takedown.time = @"2026-07-23T00:00:00Z";

    [engine _handleAccountEvent:takedown fromRelay:@"wss://test.relay"];

    // Records and blocks should be purged
    XCTAssertEqual([self.db getTotalRecordsCountForCollection:@"app.bsky.feed.post" error:&err], 0);
    XCTAssertEqual([self.db getTotalBlocksCountWithError:&err], 0);

    // Search actors should be purged
    NSArray *actors = [self.db executeParameterizedQuery:@"SELECT * FROM search_actors WHERE did = ?"
                                                  params:@[did] error:&err];
    XCTAssertEqual(actors.count, 0u);

    // Repo sync state should be tombstoned
    AppViewRepoSyncState *state = [self.db loadRepoSyncStateForDID:did error:&err];
    XCTAssertEqual(state.status, AppViewRepoSyncStatusDirty);
    XCTAssertEqualObjects(state.lastError, @"takendown");

    // Delegate should have received the account event
    XCTAssertEqual(self.delegate.receivedAccountEvents.count, 1u);
    XCTAssertEqualObjects(self.delegate.receivedAccountEvents[0].did, did);
    XCTAssertEqualObjects(self.delegate.receivedAccountEvents[0].eventType, @"#account");

    // Cursor should be advanced
    XCTAssertEqual([self.db durableCursorForRelayURL:@"wss://test.relay"], 50LL);
}

- (void)testReinstatementEventDoesNotPurge {
    NSError *err = nil;
    NSString *did = @"did:plc:reinstated";

    // Seed a record
    XCTAssertTrue([self.db saveRecordWithURI:@"at://did:plc:reinstated/app.bsky.feed.post/one"
                                        did:did collection:@"app.bsky.feed.post" rkey:@"one"
                                        cid:@"cid1" handle:nil
                                      value:@"{\"text\":\"hello\"}" subjectDid:nil error:&err]);
    XCTAssertEqual([self.db getTotalRecordsCountForCollection:@"app.bsky.feed.post" error:&err], 1);

    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[]];
    engine.delegate = self.delegate;

    FirehoseAccountEvent *reinstatement = [[FirehoseAccountEvent alloc] init];
    reinstatement.seq = 60;
    reinstatement.did = did;
    reinstatement.active = YES;
    reinstatement.status = nil;
    reinstatement.time = @"2026-07-23T00:00:00Z";

    [engine _handleAccountEvent:reinstatement fromRelay:@"wss://test.relay"];

    // Record must survive — reinstatement does not purge
    XCTAssertEqual([self.db getTotalRecordsCountForCollection:@"app.bsky.feed.post" error:&err], 1);
}

- (void)testNonTakedownAccountEventDoesNotPurge {
    NSError *err = nil;
    NSString *did = @"did:plc:suspended";

    // Seed a record
    XCTAssertTrue([self.db saveRecordWithURI:@"at://did:plc:suspended/app.bsky.feed.post/one"
                                        did:did collection:@"app.bsky.feed.post" rkey:@"one"
                                        cid:@"cid1" handle:nil
                                      value:@"{}" subjectDid:nil error:&err]);

    AppViewIngestEngine *engine = [[AppViewIngestEngine alloc]
        initWithDatabase:self.db relayURLs:@[]];

    FirehoseAccountEvent *suspended = [[FirehoseAccountEvent alloc] init];
    suspended.seq = 70;
    suspended.did = did;
    suspended.active = NO;
    suspended.status = @"suspended";  // not "takendown"
    suspended.time = @"2026-07-23T00:00:00Z";

    [engine _handleAccountEvent:suspended fromRelay:@"wss://test.relay"];

    // Only takendown triggers purge; suspended does not
    XCTAssertEqual([self.db getTotalRecordsCountForCollection:@"app.bsky.feed.post" error:&err], 1);
}

@end
