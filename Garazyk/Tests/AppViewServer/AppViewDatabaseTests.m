/*!
 @file AppViewDatabaseTests.m

 @abstract Unit tests for AppViewDatabase — schema, checkpoint persistence,
 repo sync state machine, pending deltas, event log idempotency, and
 relevance set membership.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"

@interface AppViewDatabaseTests : XCTestCase
@property (nonatomic, strong) AppViewDatabase *db;
@end

@implementation AppViewDatabaseTests

- (void)setUp {
    [super setUp];
    NSError *err = nil;
    self.db = [[AppViewDatabase alloc] initInMemoryWithError:&err];
    XCTAssertNotNil(self.db, @"Failed to open in-memory AppViewDatabase: %@", err);
    XCTAssertTrue([self.db runMigrations:&err], @"Migrations failed: %@", err);
}

- (void)tearDown {
    [self.db close];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Checkpoint
// ---------------------------------------------------------------------------

- (void)testCheckpointRoundTrip {
    AppViewCheckpoint *cp = [[AppViewCheckpoint alloc]
        initWithRelayURL:@"wss://bsky.network" seq:12345];

    NSError *err = nil;
    XCTAssertTrue([self.db saveCheckpoint:cp error:&err], @"Save failed: %@", err);

    AppViewCheckpoint *loaded = [self.db loadCheckpointForRelayURL:@"wss://bsky.network" error:&err];
    XCTAssertNotNil(loaded);
    XCTAssertEqual(loaded.seq, 12345LL);
    XCTAssertEqualObjects(loaded.relayURL, @"wss://bsky.network");
}

- (void)testCheckpointUpsert {
    NSError *err = nil;
    AppViewCheckpoint *cp1 = [[AppViewCheckpoint alloc] initWithRelayURL:@"wss://test.relay" seq:100];
    AppViewCheckpoint *cp2 = [[AppViewCheckpoint alloc] initWithRelayURL:@"wss://test.relay" seq:200];

    XCTAssertTrue([self.db saveCheckpoint:cp1 error:&err]);
    XCTAssertTrue([self.db saveCheckpoint:cp2 error:&err]);

    AppViewCheckpoint *loaded = [self.db loadCheckpointForRelayURL:@"wss://test.relay" error:&err];
    XCTAssertEqual(loaded.seq, 200LL, @"Upsert should update to latest seq");
}

- (void)testCheckpointMissingReturnsNil {
    NSError *err = nil;
    AppViewCheckpoint *loaded = [self.db loadCheckpointForRelayURL:@"wss://nonexistent" error:&err];
    XCTAssertNil(loaded);
    XCTAssertNil(err);
}

// ---------------------------------------------------------------------------
// Repo Sync State Machine
// ---------------------------------------------------------------------------

- (void)testRepoSyncStateRoundTrip {
    AppViewRepoSyncState *state = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:test1"];
    state.status     = AppViewRepoSyncStatusPending;
    state.errorCount = 0;

    NSError *err = nil;
    XCTAssertTrue([self.db upsertRepoSyncState:state error:&err]);

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:test1" error:&err];
    XCTAssertNotNil(loaded);
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusPending);
    XCTAssertEqual(loaded.errorCount, 0);
}

- (void)testMarkReposAsProcessing {
    NSArray<NSString *> *dids = @[@"did:plc:a", @"did:plc:b", @"did:plc:c"];
    NSError *err = nil;

    for (NSString *did in dids) {
        AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:did];
        [self.db upsertRepoSyncState:s error:nil];
    }

    NSArray<NSString *> *transitioned = [self.db markReposAsProcessing:dids error:&err];
    XCTAssertNil(err);
    XCTAssertEqual(transitioned.count, 3u, @"All three should transition");

    // Second call — all are now processing, none should transition
    NSArray<NSString *> *second = [self.db markReposAsProcessing:dids error:&err];
    XCTAssertEqual(second.count, 0u, @"Already processing — no transitions");
}

- (void)testMarkRepoSynced {
    NSError *err = nil;
    AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:synced"];
    [self.db upsertRepoSyncState:s error:nil];

    XCTAssertTrue([self.db markRepoSynced:@"did:plc:synced" lastRev:@"abc123" error:&err]);

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:synced" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusSynced);
    XCTAssertEqualObjects(loaded.lastRev, @"abc123");
    XCTAssertEqual(loaded.errorCount, 0);
}

- (void)testMarkRepoDirty {
    NSError *err = nil;
    AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:dirty"];
    s.status = AppViewRepoSyncStatusSynced;
    [self.db upsertRepoSyncState:s error:nil];

    XCTAssertTrue([self.db markRepoDirty:@"did:plc:dirty" error:&err]);
    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:dirty" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusDirty);
}

- (void)testRecordBackfillError {
    NSError *err = nil;
    AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:errors"];
    [self.db upsertRepoSyncState:s error:nil];

    [self.db recordBackfillError:@"did:plc:errors" message:@"HTTP 503" error:nil];
    [self.db recordBackfillError:@"did:plc:errors" message:@"timeout" error:nil];

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:errors" error:&err];
    XCTAssertEqual(loaded.errorCount, 2);
    XCTAssertEqualObjects(loaded.lastError, @"timeout");
}

- (void)testLoadByStatusWithOrdering {
    NSError *err = nil;
    // Insert repos with different error counts
    for (NSInteger i = 0; i < 5; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:repo%ld", (long)i];
        AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:did];
        [self.db upsertRepoSyncState:s error:nil];
        for (NSInteger j = 0; j < i; j++) {
            [self.db recordBackfillError:did message:@"err" error:nil];
        }
    }

    NSArray *pending = [self.db loadRepoSyncStatesWithStatus:AppViewRepoSyncStatusPending
                                                       limit:10 error:&err];
    XCTAssertEqual(pending.count, 5u);
    // Ordered by error_count ASC
    XCTAssertEqual(((AppViewRepoSyncState *)pending[0]).errorCount, 0);
    XCTAssertEqual(((AppViewRepoSyncState *)pending[4]).errorCount, 4);
}

// ---------------------------------------------------------------------------
// Pending Deltas
// ---------------------------------------------------------------------------

- (void)testPendingDeltaEnqueueDequeue {
    NSError *err = nil;
    AppViewPendingDelta *d1 = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:x" seq:10 commitCID:@"cid1" rev:@"rev1"
        rawEnvelope:[NSData data]];
    AppViewPendingDelta *d2 = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:x" seq:20 commitCID:@"cid2" rev:@"rev2"
        rawEnvelope:[NSData data]];

    XCTAssertTrue([self.db enqueuePendingDelta:d1 error:&err]);
    XCTAssertTrue([self.db enqueuePendingDelta:d2 error:&err]);

    NSArray<AppViewPendingDelta *> *dequeued = [self.db dequeuePendingDeltasForDID:@"did:plc:x" error:&err];
    XCTAssertEqual(dequeued.count, 2u);
    XCTAssertEqual(dequeued[0].seq, 10LL, @"Should be ordered by seq ASC");
    XCTAssertEqual(dequeued[1].seq, 20LL);

    // After dequeue, count should be 0
    NSInteger count = [self.db countPendingDeltasForDID:@"did:plc:x" error:&err];
    XCTAssertEqual(count, 0);
}

- (void)testPendingDeltaIdempotency {
    AppViewPendingDelta *d = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:y" seq:5 commitCID:@"cid" rev:@"rev"
        rawEnvelope:[NSData data]];

    [self.db enqueuePendingDelta:d error:nil];
    [self.db enqueuePendingDelta:d error:nil]; // duplicate — should be ignored

    NSInteger count = [self.db countPendingDeltasForDID:@"did:plc:y" error:nil];
    XCTAssertEqual(count, 1, @"Duplicate (did, seq) should be silently ignored");
}

// ---------------------------------------------------------------------------
// Event Log Idempotency
// ---------------------------------------------------------------------------

- (void)testEventLogDeduplication {
    NSError *err = nil;
    NSData *envelope = [@"test" dataUsingEncoding:NSUTF8StringEncoding];

    BOOL ok1 = [self.db logEvent:100 did:@"did:plc:z" rev:@"rev1" cid:@"cid1"
                    rawEnvelope:envelope error:&err];
    XCTAssertTrue(ok1);

    // Same (did, rev, cid) — idempotent insert
    BOOL ok2 = [self.db logEvent:101 did:@"did:plc:z" rev:@"rev1" cid:@"cid1"
                    rawEnvelope:envelope error:&err];
    XCTAssertTrue(ok2, @"INSERT OR IGNORE should not fail");

    XCTAssertTrue([self.db hasEventWithDID:@"did:plc:z" rev:@"rev1" cid:@"cid1"]);
    XCTAssertFalse([self.db hasEventWithDID:@"did:plc:z" rev:@"rev999" cid:@"cid999"]);
}

// ---------------------------------------------------------------------------
// Relevance Set
// ---------------------------------------------------------------------------

- (void)testRelevancePermanentMembership {
    AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
        initWithDID:@"did:plc:seed" reason:AppViewRelevanceReasonSeed expiresAt:nil];

    NSError *err = nil;
    XCTAssertTrue([self.db upsertRelevanceMembership:m error:&err]);
    XCTAssertTrue([self.db isDIDRelevant:@"did:plc:seed"]);
    XCTAssertFalse([self.db isDIDRelevant:@"did:plc:unknown"]);
}

- (void)testRelevanceExpiredMembership {
    NSDate *pastDate = [NSDate dateWithTimeIntervalSinceNow:-3600]; // 1 hour ago
    AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
        initWithDID:@"did:plc:expired"
             reason:AppViewRelevanceReasonRecentInteraction
          expiresAt:pastDate];

    NSError *err = nil;
    [self.db upsertRelevanceMembership:m error:&err];

    // The membership is inserted but should be treated as expired
    // (isDIDRelevant relies on the DB cache which checks validity)
    // After pruning, it should be gone
    [self.db pruneExpiredRelevanceMemberships:&err];
    XCTAssertFalse([self.db isDIDRelevant:@"did:plc:expired"], @"Expired membership should be removed by prune");
}

- (void)testRelevancePruneCount {
    NSDate *past  = [NSDate dateWithTimeIntervalSinceNow:-7200];
    NSDate *future = [NSDate dateWithTimeIntervalSinceNow:7200];

    NSError *err = nil;
    for (NSInteger i = 0; i < 5; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:expired%ld", (long)i];
        AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
            initWithDID:did reason:AppViewRelevanceReasonFollowOfSeed expiresAt:past];
        [self.db upsertRelevanceMembership:m error:&err];
    }
    // One permanent entry that should survive
    AppViewRelevanceMembership *permanent = [[AppViewRelevanceMembership alloc]
        initWithDID:@"did:plc:permanent" reason:AppViewRelevanceReasonSeed expiresAt:nil];
    [self.db upsertRelevanceMembership:permanent error:&err];

    // One future-expiring entry
    AppViewRelevanceMembership *future_m = [[AppViewRelevanceMembership alloc]
        initWithDID:@"did:plc:future" reason:AppViewRelevanceReasonFollowOfSeed expiresAt:future];
    [self.db upsertRelevanceMembership:future_m error:&err];

    NSInteger pruned = [self.db pruneExpiredRelevanceMemberships:&err];
    XCTAssertEqual(pruned, 5, @"Exactly 5 expired entries should be removed");
    XCTAssertTrue([self.db isDIDRelevant:@"did:plc:permanent"]);
    XCTAssertTrue([self.db isDIDRelevant:@"did:plc:future"]);
}

// ---------------------------------------------------------------------------
// Dead Letter
// ---------------------------------------------------------------------------

- (void)testDeadLetterInsertion {
    NSError *err = nil;
    NSData *rawRecord = [@"{\"$type\":\"app.bsky.feed.post\"}" dataUsingEncoding:NSUTF8StringEncoding];

    BOOL ok = [self.db recordDeadLetterEvent:@"app.bsky.feed.post"
                                         seq:999
                                         did:@"did:plc:bad"
                                         rev:@"rev1"
                                         cid:@"cid1"
                                   rawRecord:rawRecord
                             validationError:@"Missing text field"
                                       error:&err];
    XCTAssertTrue(ok, @"Dead letter insert should succeed: %@", err);
}

@end
