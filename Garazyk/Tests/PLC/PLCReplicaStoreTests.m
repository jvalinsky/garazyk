// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PLCReplicaStoreTests.m

 @brief Characterization tests for PLCReplicaStore (PLC replica sync-state + counts).

 @discussion PLCReplicaStore shipped with no tests. These pin down its current observable
 behaviour through the public interface — the sync-state get/set round-trips (backed by an
 upserting key/value table) and the operation / unique-DID counts over the inherited
 plc_operations table — as the prerequisite for a future QueryRunner migration (the store
 currently owns a hand-rolled transaction queue). Behaviour is captured as-is, including
 quirks: an unset integer cursor reads back as 0 (the header's "-1 on failure" is not what
 the code does), and the closed-database guard reports PLCPersistentStoreErrorDomain /
 ...DatabaseClosed while the header-declared PLCReplicaStoreErrorDomain is never used.
 */

#import <XCTest/XCTest.h>
#import "PLC/PLCReplicaStore.h"
#import "PLC/PLCOperation.h"

@interface PLCReplicaStoreTests : XCTestCase
@property (nonatomic, strong) PLCReplicaStore *store;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation PLCReplicaStoreTests

- (void)setUp {
    [super setUp];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"plc_replica_test_%@.db", [[NSUUID UUID] UUIDString]]];
    self.store = [[PLCReplicaStore alloc] initWithPath:self.dbPath];
    NSError *error = nil;
    XCTAssertTrue([self.store openWithError:&error], @"open replica store: %@", error);
}

- (void)tearDown {
    [self.store close];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.dbPath error:nil];
    [fm removeItemAtPath:[self.dbPath stringByAppendingString:@"-wal"] error:nil];
    [fm removeItemAtPath:[self.dbPath stringByAppendingString:@"-shm"] error:nil];
    self.store = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (void)appendOpForDID:(NSString *)did sig:(NSString *)sig prev:(nullable NSString *)prev {
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = sig;
    op.prev = prev;
    op.data = @{@"sig": sig};
    NSError *error = nil;
    XCTAssertTrue([self.store appendOperation:op nullifyCIDs:@[] error:&error], @"append %@: %@", sig, error);
}

#pragma mark - Sync cursor

- (void)testSyncCursorRoundTripAndUpsert {
    NSError *error = nil;
    XCTAssertTrue([self.store updateSyncCursor:42 error:&error], @"%@", error);
    XCTAssertEqual([self.store lastSyncCursorWithError:&error], 42);
    // ON CONFLICT(key) upsert: a second update overwrites in place.
    XCTAssertTrue([self.store updateSyncCursor:100 error:&error]);
    XCTAssertEqual([self.store lastSyncCursorWithError:&error], 100);
}

- (void)testLastSyncCursorDefaultsToZeroWhenUnset {
    // Quirk: the header documents "-1 on failure", but an unset cursor reads back as 0.
    NSError *error = nil;
    XCTAssertEqual([self.store lastSyncCursorWithError:&error], 0);
}

- (void)testLatestIngestedCursorRoundTripAndDefault {
    NSError *error = nil;
    XCTAssertEqual([self.store latestIngestedCursorWithError:&error], 0, @"unset defaults to 0");
    XCTAssertTrue([self.store updateLatestIngestedCursor:7 error:&error], @"%@", error);
    XCTAssertEqual([self.store latestIngestedCursorWithError:&error], 7);
}

#pragma mark - Timestamp

- (void)testLastSyncTimestampRoundTripToSecondPrecision {
    NSError *error = nil;
    XCTAssertNil([self.store lastSyncTimestampWithError:&error], @"unset defaults to nil");

    // Stored as integer seconds, so a whole-second instant round-trips exactly.
    NSDate *ts = [NSDate dateWithTimeIntervalSince1970:1700000000];
    XCTAssertTrue([self.store updateLastSyncTimestamp:ts error:&error], @"%@", error);
    NSDate *got = [self.store lastSyncTimestampWithError:&error];
    XCTAssertNotNil(got);
    XCTAssertEqualWithAccuracy([got timeIntervalSince1970], 1700000000.0, 0.5);
}

#pragma mark - String values

- (void)testUpstreamURLRoundTripAndUpsert {
    NSError *error = nil;
    XCTAssertNil([self.store upstreamURLWithError:&error], @"unset defaults to nil");
    XCTAssertTrue([self.store updateUpstreamURL:@"https://plc.directory" error:&error], @"%@", error);
    XCTAssertEqualObjects([self.store upstreamURLWithError:&error], @"https://plc.directory");
    XCTAssertTrue([self.store updateUpstreamURL:@"https://plc.example" error:&error]);
    XCTAssertEqualObjects([self.store upstreamURLWithError:&error], @"https://plc.example");
}

- (void)testSyncStateRoundTripAndDefault {
    NSError *error = nil;
    XCTAssertNil([self.store syncStateWithError:&error], @"unset defaults to nil");
    XCTAssertTrue([self.store updateSyncState:@"syncing" error:&error], @"%@", error);
    XCTAssertEqualObjects([self.store syncStateWithError:&error], @"syncing");
}

#pragma mark - Counts

- (void)testTotalOperationCountEmptyAndAfterAppends {
    NSError *error = nil;
    XCTAssertEqual([self.store totalOperationCountWithError:&error], 0u, @"empty: %@", error);

    [self appendOpForDID:@"did:plc:aaa" sig:@"a1" prev:nil];
    [self appendOpForDID:@"did:plc:aaa" sig:@"a2" prev:@"prev_a1"];
    [self appendOpForDID:@"did:plc:bbb" sig:@"b1" prev:nil];

    XCTAssertEqual([self.store totalOperationCountWithError:&error], 3u);
}

- (void)testUniqueDIDCountEmptyAndAfterAppends {
    NSError *error = nil;
    XCTAssertEqual([self.store uniqueDIDCountWithError:&error], 0u, @"empty: %@", error);

    [self appendOpForDID:@"did:plc:aaa" sig:@"a1" prev:nil];
    [self appendOpForDID:@"did:plc:aaa" sig:@"a2" prev:@"prev_a1"];  // same DID
    [self appendOpForDID:@"did:plc:bbb" sig:@"b1" prev:nil];         // distinct DID

    XCTAssertEqual([self.store uniqueDIDCountWithError:&error], 2u);
}

#pragma mark - Closed store

- (void)testUpdateOnClosedStoreReturnsDatabaseClosedError {
    [self.store close];

    NSError *error = nil;
    BOOL ok = [self.store updateSyncCursor:1 error:&error];
    XCTAssertFalse(ok);
    // The guard reports the *persistent* store's domain/code; PLCReplicaStore's own
    // PLCReplicaStoreErrorDomain (declared in its header) is unused by the implementation.
    XCTAssertEqualObjects(error.domain, PLCPersistentStoreErrorDomain);
    XCTAssertEqual(error.code, PLCPersistentStoreErrorDatabaseClosed);
}

@end
