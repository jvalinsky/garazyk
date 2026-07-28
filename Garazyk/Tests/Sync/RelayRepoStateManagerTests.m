// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import <sqlite3.h>
#import "Sync/Relay/RelayRepoStateManager.h"

@interface RelayRepoStateManagerTests : XCTestCase
@end

@implementation RelayRepoStateManagerTests

- (NSString *)tempDBPath {
    NSString *tmp = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmp
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return [tmp stringByAppendingPathComponent:@"relay_state.db"];
}

- (void)removeDBAt:(NSString *)path {
    [[NSFileManager defaultManager] removeItemAtPath:[path stringByDeletingLastPathComponent]
                                               error:NULL];
}

#pragma mark - In-memory tests

- (void)testDefaultInitializes {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    XCTAssertNotNil(manager);
}

- (void)testHandleCommitForRepo {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyrexxx" rev:@"3" seq:100];

    XCTAssertEqualObjects([manager rootCIDForRepo:@"did:plc:test"], @"bafyrexxx");
    XCTAssertEqualObjects([manager revForRepo:@"did:plc:test"], @"3");
    XCTAssertEqual([manager cursorForRepo:@"did:plc:test"], 100);
}

- (void)testGetNonExistentRepoState {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    XCTAssertNil([manager rootCIDForRepo:@"did:plc:nonexistent"]);
}

- (void)testHandleTombstone {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyrexxx" rev:@"3" seq:100];
    [manager handleTombstoneForRepo:@"did:plc:test"];

    XCTAssertEqual([manager statusForRepo:@"did:plc:test"], RelayRepoStatusTombstoned);
}

- (void)testRepoCount {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:a" root:@"bafyrea" rev:@"1" seq:1];
    [manager handleCommitForRepo:@"did:plc:b" root:@"bafyreb" rev:@"2" seq:2];

    XCTAssertEqual([manager repoCount], 2);
}

- (void)testAllRepos {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:a" root:@"bafyrea" rev:@"1" seq:1];
    [manager handleCommitForRepo:@"did:plc:b" root:@"bafyreb" rev:@"2" seq:2];

    NSArray *repos = [manager allRepos];
    XCTAssertEqual(repos.count, 2);
    XCTAssertEqualObjects(repos, (@[@"did:plc:a", @"did:plc:b"]));
}

- (void)testOlderCommitDoesNotRegressRepoState {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyre-new" rev:@"4" seq:101];
    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyre-old" rev:@"3" seq:100];

    XCTAssertEqualObjects([manager rootCIDForRepo:@"did:plc:test"], @"bafyre-new");
    XCTAssertEqualObjects([manager revForRepo:@"did:plc:test"], @"4");
    XCTAssertEqual([manager cursorForRepo:@"did:plc:test"], 101);
}

#pragma mark - Commit and data-root tracking

- (void)testCommitAndDataCIDsRemainDistinct {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test"
                       commitCID:@"bafyre-commit"
                         dataCID:@"bafyre-data"
                             rev:@"1"
                             seq:1];

    XCTAssertEqualObjects([manager commitCIDForRepo:@"did:plc:test"],
                          @"bafyre-commit");
    XCTAssertEqualObjects([manager rootCIDForRepo:@"did:plc:test"],
                          @"bafyre-commit");
    XCTAssertEqualObjects([manager dataCIDForRepo:@"did:plc:test"],
                          @"bafyre-data");
}

- (void)testAdvanceRepoComparesPrevDataWithStoredDataCID {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test"
                       commitCID:@"commit-1"
                         dataCID:@"data-1"
                             rev:@"1"
                             seq:1];

    RelayRepoAdvanceResult result =
        [manager advanceRepo:@"did:plc:test"
                       since:@"1"
                    prevData:@"data-1"
                   commitCID:@"commit-2"
                     dataCID:@"data-2"
                         rev:@"2"
                         seq:2];

    XCTAssertEqual(result, RelayRepoAdvanceResultAdvanced);
    XCTAssertEqualObjects([manager commitCIDForRepo:@"did:plc:test"], @"commit-2");
    XCTAssertEqualObjects([manager dataCIDForRepo:@"did:plc:test"], @"data-2");
}

- (void)testAdvanceRepoRejectsCommitCIDUsedAsPrevData {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test"
                       commitCID:@"commit-1"
                         dataCID:@"data-1"
                             rev:@"1"
                             seq:1];

    RelayRepoAdvanceResult result =
        [manager advanceRepo:@"did:plc:test"
                       since:@"1"
                    prevData:@"commit-1"
                   commitCID:@"commit-2"
                     dataCID:@"data-2"
                         rev:@"2"
                         seq:2];

    XCTAssertEqual(result, RelayRepoAdvanceResultPrevDataMismatch);
    XCTAssertEqualObjects([manager commitCIDForRepo:@"did:plc:test"], @"commit-1");
    XCTAssertEqualObjects([manager dataCIDForRepo:@"did:plc:test"], @"data-1");
    XCTAssertEqual([manager statusForRepo:@"did:plc:test"],
                   RelayRepoStatusDesynchronized);
}

#pragma mark - SQLite-backed persistence

- (void)testPersistenceRoundTrip {
    NSString *dbPath = [self tempDBPath];
    NSError *error = nil;

    RelayRepoStateManager *mgr = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                          error:&error];
    XCTAssertNotNil(mgr, @"initWithDataDir failed: %@", error);
    [mgr handleCommitForRepo:@"did:plc:alpha" root:@"bafyreA" rev:@"10" seq:100];
    [mgr handleCommitForRepo:@"did:plc:beta"  root:@"bafyreB" rev:@"20" seq:200];
    [mgr persistState];

    RelayRepoStateManager *mgr2 = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                           error:&error];
    XCTAssertNotNil(mgr2, @"initWithDataDir (reload) failed: %@", error);
    XCTAssertTrue([mgr2 loadState:&error], @"loadState failed: %@", error);

    XCTAssertEqual([mgr2 repoCount], 2);
    XCTAssertEqualObjects([mgr2 rootCIDForRepo:@"did:plc:alpha"], @"bafyreA");
    XCTAssertEqualObjects([mgr2 revForRepo:@"did:plc:alpha"], @"10");
    XCTAssertEqual([mgr2 cursorForRepo:@"did:plc:alpha"], 100);
    XCTAssertEqualObjects([mgr2 rootCIDForRepo:@"did:plc:beta"], @"bafyreB");
    XCTAssertEqualObjects([mgr2 revForRepo:@"did:plc:beta"], @"20");
    XCTAssertEqual([mgr2 cursorForRepo:@"did:plc:beta"], 200);

    [self removeDBAt:dbPath];
}

- (void)testPersistenceRoundTripIncludesDataCID {
    NSString *dbPath = [self tempDBPath];
    NSError *error = nil;

    RelayRepoStateManager *mgr = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                          error:&error];
    XCTAssertNotNil(mgr);
    [mgr handleCommitForRepo:@"did:plc:test"
                   commitCID:@"bafyre-commit"
                     dataCID:@"bafyre-data"
                         rev:@"2"
                         seq:2];
    [mgr persistState];

    RelayRepoStateManager *mgr2 = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                           error:&error];
    XCTAssertNotNil(mgr2);
    XCTAssertTrue([mgr2 loadState:&error]);

    XCTAssertEqualObjects([mgr2 dataCIDForRepo:@"did:plc:test"], @"bafyre-data");
    XCTAssertEqualObjects([mgr2 rootCIDForRepo:@"did:plc:test"], @"bafyre-commit");

    [self removeDBAt:dbPath];
}

- (void)testLegacySchemaMigrationDoesNotTrustPrevDataCID {
    NSString *dbPath = [self tempDBPath];
    sqlite3 *db = NULL;
    XCTAssertEqual(sqlite3_open(dbPath.fileSystemRepresentation, &db), SQLITE_OK);
    const char *legacySQL =
        "CREATE TABLE relay_repos ("
        "did TEXT PRIMARY KEY NOT NULL, root_cid TEXT, prev_data_cid TEXT, "
        "rev TEXT, seq INTEGER NOT NULL DEFAULT 0, "
        "status INTEGER NOT NULL DEFAULT 0, last_seen_at REAL NOT NULL);"
        "CREATE TABLE relay_meta (key TEXT PRIMARY KEY NOT NULL, value TEXT);"
        "INSERT INTO relay_repos "
        "(did, root_cid, prev_data_cid, rev, seq, status, last_seen_at) "
        "VALUES ('did:plc:legacy', 'commit-head', 'legacy-commit-head', "
        "'3mlegacy', 42, 0, 1.0);";
    XCTAssertEqual(sqlite3_exec(db, legacySQL, NULL, NULL, NULL), SQLITE_OK);
    sqlite3_close(db);

    NSError *error = nil;
    RelayRepoStateManager *manager =
        [[RelayRepoStateManager alloc] initWithDataDir:dbPath error:&error];
    XCTAssertNotNil(manager, @"Migration failed: %@", error);
    XCTAssertTrue([manager loadState:&error], @"Load failed: %@", error);
    XCTAssertEqualObjects([manager commitCIDForRepo:@"did:plc:legacy"],
                          @"commit-head");
    XCTAssertNil([manager dataCIDForRepo:@"did:plc:legacy"],
                 @"Legacy prev_data_cid stored commit CIDs and must not seed data roots");

    RelayRepoStateManager *reopened =
        [[RelayRepoStateManager alloc] initWithDataDir:dbPath error:&error];
    XCTAssertNotNil(reopened, @"Idempotent migration failed: %@", error);

    [self removeDBAt:dbPath];
}

- (void)testPersistenceRoundTripStatus {
    NSString *dbPath = [self tempDBPath];
    NSError *error = nil;

    RelayRepoStateManager *mgr = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                          error:&error];
    XCTAssertNotNil(mgr);
    [mgr handleCommitForRepo:@"did:plc:test" root:@"bafyre" rev:@"1" seq:1];
    [mgr handleAccountEventForRepo:@"did:plc:test" status:RelayRepoStatusThrottled];
    [mgr persistState];

    RelayRepoStateManager *mgr2 = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                           error:&error];
    XCTAssertNotNil(mgr2);
    XCTAssertTrue([mgr2 loadState:&error]);

    XCTAssertEqual([mgr2 statusForRepo:@"did:plc:test"], RelayRepoStatusThrottled);

    [self removeDBAt:dbPath];
}

- (void)testPersistStateNoopForInMemoryManager {
    RelayRepoStateManager *mgr = [[RelayRepoStateManager alloc] init];
    [mgr handleCommitForRepo:@"did:plc:test" root:@"bafyre" rev:@"1" seq:1];
    [mgr persistState];
    XCTAssertEqual([mgr repoCount], 1);
}

- (void)testLoadStateNoopForInMemoryManager {
    RelayRepoStateManager *mgr = [[RelayRepoStateManager alloc] init];
    [mgr handleCommitForRepo:@"did:plc:test" root:@"bafyre" rev:@"1" seq:1];
    NSError *error = nil;
    XCTAssertTrue([mgr loadState:&error]);
    XCTAssertEqual([mgr repoCount], 1);
}

- (void)testDeallocPersistsState {
    NSString *dbPath = [self tempDBPath];
    NSError *error = nil;

    @autoreleasepool {
        RelayRepoStateManager *mgr = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                              error:&error];
        [mgr handleCommitForRepo:@"did:plc:test" root:@"bafyre" rev:@"1" seq:1];

        // handleCommitForRepo: applies the write via dispatch_async on the
        // manager's serial state queue. Reading through any dispatch_sync
        // accessor (as below) is a FIFO barrier that guarantees the write
        // has completed before this scope exits and releases `mgr` --
        // without it, this test races: if the async write is still pending
        // when the autoreleasepool closes, the state queue (not this
        // thread) ends up dropping the last reference and running -dealloc
        // asynchronously, after this scope has already moved on to opening
        // the same database file in `mgr2` below.
        XCTAssertEqualObjects([mgr rootCIDForRepo:@"did:plc:test"], @"bafyre");
    }

    RelayRepoStateManager *mgr2 = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                           error:&error];
    XCTAssertNotNil(mgr2);
    XCTAssertTrue([mgr2 loadState:&error]);
    XCTAssertEqual([mgr2 repoCount], 1);
    XCTAssertEqualObjects([mgr2 rootCIDForRepo:@"did:plc:test"], @"bafyre");

    [self removeDBAt:dbPath];
}

@end
