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

#pragma mark - prevDataCID tracking

- (void)testPrevDataCIDTrackedOnCommit {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyre-first" rev:@"1" seq:1];
    XCTAssertNil([manager prevDataCIDForRepo:@"did:plc:test"]);

    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyre-second" rev:@"2" seq:2];
    XCTAssertEqualObjects([manager prevDataCIDForRepo:@"did:plc:test"], @"bafyre-first");

    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyre-third" rev:@"3" seq:3];
    XCTAssertEqualObjects([manager prevDataCIDForRepo:@"did:plc:test"], @"bafyre-second");
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

- (void)testPersistenceRoundTripIncludesPrevDataCID {
    NSString *dbPath = [self tempDBPath];
    NSError *error = nil;

    RelayRepoStateManager *mgr = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                          error:&error];
    XCTAssertNotNil(mgr);
    [mgr handleCommitForRepo:@"did:plc:test" root:@"bafyre-v1" rev:@"1" seq:1];
    [mgr handleCommitForRepo:@"did:plc:test" root:@"bafyre-v2" rev:@"2" seq:2];
    [mgr persistState];

    RelayRepoStateManager *mgr2 = [[RelayRepoStateManager alloc] initWithDataDir:dbPath
                                                                           error:&error];
    XCTAssertNotNil(mgr2);
    XCTAssertTrue([mgr2 loadState:&error]);

    XCTAssertEqualObjects([mgr2 prevDataCIDForRepo:@"did:plc:test"], @"bafyre-v1");
    XCTAssertEqualObjects([mgr2 rootCIDForRepo:@"did:plc:test"], @"bafyre-v2");

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
