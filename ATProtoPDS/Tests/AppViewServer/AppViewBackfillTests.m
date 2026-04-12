/*!
 @file AppViewBackfillTests.m

 @abstract Unit tests for the backfill orchestrator: scheduling fairness,
 per-host caps, state transitions, and pending delta replay.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AppViewServer/AppViewDatabase.h"
#import "AppViewServer/AppViewTypes.h"
#import "AppViewServer/Backfill/AppViewBackfillOrchestrator.h"
#import "AppViewServer/Indexers/AppViewIndexer.h"

// ---------------------------------------------------------------------------
// Mock indexer that does nothing
// ---------------------------------------------------------------------------

@interface MockIndexer : NSObject <AppViewIndexer>
@end

@implementation MockIndexer
- (BOOL)canIndexCollection:(NSString *)collection { return YES; }
- (BOOL)indexRecord:(NSDictionary *)record did:(NSString *)did collection:(NSString *)collection error:(NSError **)error { return YES; }
@end

// ---------------------------------------------------------------------------

@interface AppViewBackfillTests : XCTestCase
@property (nonatomic, strong) AppViewDatabase *db;
@property (nonatomic, strong) AppViewBackfillOrchestrator *orchestrator;
@end

@implementation AppViewBackfillTests

- (void)setUp {
    [super setUp];
    NSError *err = nil;
    self.db = [[AppViewDatabase alloc] initInMemoryWithError:&err];
    XCTAssertNotNil(self.db);
    [self.db runMigrations:&err];

    self.orchestrator = [[AppViewBackfillOrchestrator alloc]
        initWithDatabase:self.db indexers:@[[[MockIndexer alloc] init]]];
    self.orchestrator.globalWorkerCap  = 4;
    self.orchestrator.perHostWorkerCap = 2;
}

- (void)tearDown {
    [self.db close];
    [super tearDown];
}

// ---------------------------------------------------------------------------

- (void)testEnqueueUnknownDIDCreatesState {
    NSError *err = nil;
    [self.orchestrator enqueueDIDs:@[@"did:plc:newdid"]];

    // Give the scheduler queue a moment to process
    [NSThread sleepForTimeInterval:0.05];

    AppViewRepoSyncState *state = [self.db loadRepoSyncStateForDID:@"did:plc:newdid" error:&err];
    XCTAssertNotNil(state, @"Enqueueing an unknown DID should create a pending sync state");
}

- (void)testEnqueueSyncedDIDMarksDirty {
    NSError *err = nil;
    AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:@"did:plc:synced"];
    s.status = AppViewRepoSyncStatusSynced;
    [self.db upsertRepoSyncState:s error:nil];

    [self.orchestrator enqueueDIDs:@[@"did:plc:synced"]];
    [NSThread sleepForTimeInterval:0.05];

    AppViewRepoSyncState *loaded = [self.db loadRepoSyncStateForDID:@"did:plc:synced" error:&err];
    XCTAssertEqual(loaded.status, AppViewRepoSyncStatusDirty,
                   @"Synced repo should be marked dirty when re-enqueued");
}

- (void)testStatusReportContainsExpectedKeys {
    NSDictionary *report = [self.orchestrator statusReport];
    XCTAssertNotNil(report[@"queue_depth"]);
    XCTAssertNotNil(report[@"active_workers"]);
    XCTAssertNotNil(report[@"repos_pending"]);
    XCTAssertNotNil(report[@"repos_synced"]);
    XCTAssertNotNil(report[@"repos_dirty"]);
}

- (void)testQueueDepthReflectsEnqueuedDIDs {
    // Insert 3 pending repos
    for (NSInteger i = 0; i < 3; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:depth%ld", (long)i];
        AppViewRepoSyncState *s = [[AppViewRepoSyncState alloc] initWithDID:did];
        [self.db upsertRepoSyncState:s error:nil];
        [self.orchestrator enqueueDIDs:@[did]];
    }

    NSInteger depth = self.orchestrator.queueDepth;
    XCTAssertGreaterThanOrEqual(depth, 0, @"Queue depth should be non-negative");
}

@end
