// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "PLC/AdminUI/PLCAdminSnapshot.h"
#import "PLC/PLCMetrics.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCReplicaStore.h"
#import "PLC/PLCSyncClient.h"
#import "PLC/PLCSyncEngine.h"

@interface PLCSyncEngine (PLCAdminSnapshotTestAccess)
@property(nonatomic, assign, readwrite) PLCSyncState state;
@property(nonatomic, assign, readwrite) NSUInteger totalOperationsIngested;
@property(nonatomic, assign, readwrite) NSUInteger totalOperationsFailed;
@property(nonatomic, assign, readwrite) NSInteger currentCursor;
@property(nonatomic, strong, readwrite) NSDate *lastSyncDate;
@end

@interface PLCAdminBoundedMockStore : PLCMockStore
@property(nonatomic, assign) BOOL unboundedReadUsed;
@end

@implementation PLCAdminBoundedMockStore

- (NSArray<NSString *> *)getAllDIDsWithError:(NSError **)error {
    self.unboundedReadUsed = YES;
    return [super getAllDIDsWithError:error];
}

- (NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did
                              includeNullified:(BOOL)includeNullified
                                         error:(NSError **)error {
    self.unboundedReadUsed = YES;
    return [super getHistoryForDID:did includeNullified:includeNullified error:error];
}

@end

@interface PLCAdminSnapshotTests : XCTestCase
@end

@implementation PLCAdminSnapshotTests

- (void)testPrimaryEmptyStoreDoesNotInventReplicaFields {
    GZPLCAdminSnapshot *snapshot = [[GZPLCAdminSnapshot alloc] initWithStore:[[PLCMockStore alloc] init] syncEngine:nil];
    NSDictionary *value = [snapshot snapshot];
    XCTAssertEqualObjects(value[@"mode"], @"primary");
    XCTAssertEqualObjects(value[@"health"], @"ok");
    XCTAssertEqualObjects(value[@"didTotal"], @0);
    XCTAssertNil(value[@"replication"]);
}

- (void)testDirectoryLookupIsBoundedAndReportsOperationChain {
    PLCAdminBoundedMockStore *store = [[PLCAdminBoundedMockStore alloc] init];
    PLCOperation *operation = [[PLCOperation alloc] init];
    operation.did = @"did:plc:adminsnapshot";
    operation.sig = @"fixture";
    operation.data = @{@"type": @"create"};
    XCTAssertTrue([store appendOperation:operation nullifyCIDs:nil error:nil]);
    GZPLCAdminSnapshot *snapshot = [[GZPLCAdminSnapshot alloc] initWithStore:store syncEngine:nil];
    NSDictionary *entry = [snapshot directoryEntryForDID:operation.did];
    XCTAssertEqualObjects(entry[@"did"], operation.did);
    XCTAssertEqualObjects(entry[@"operationChainLength"], @1);
    XCTAssertNil(entry[@"error"]);
    XCTAssertFalse(store.unboundedReadUsed);
}

- (void)testPopulatedStoreReportsExactTotalsWithoutMaterializingTheDirectory {
    PLCAdminBoundedMockStore *store = [[PLCAdminBoundedMockStore alloc] init];
    for (NSString *did in @[ @"did:plc:one", @"did:plc:two" ]) {
        PLCOperation *operation = [[PLCOperation alloc] init];
        operation.did = did;
        operation.sig = @"fixture";
        operation.data = @{ @"type": @"create" };
        XCTAssertTrue([store appendOperation:operation nullifyCIDs:nil error:nil]);
    }
    GZPLCAdminSnapshot *snapshot = [[GZPLCAdminSnapshot alloc] initWithStore:store syncEngine:nil];
    NSDictionary *value = [snapshot snapshot];
    XCTAssertEqualObjects(value[@"didTotal"], @2);
    XCTAssertEqualObjects(value[@"operationTotal"], @2);
    XCTAssertFalse(store.unboundedReadUsed);
}

- (void)testMetricsSnapshotRemainsConsistentUnderConcurrentUpdates {
    PLCMetrics *metrics = [PLCMetrics sharedMetrics];
    int64_t before = metrics.totalRequests;
    dispatch_apply(128, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
        [metrics recordRequest];
        [metrics recordOperation:@"create"];
    });
    NSDictionary *snapshot = [metrics snapshot];
    XCTAssertGreaterThanOrEqual([snapshot[@"totalRequests"] longLongValue], before + 128);
    XCTAssertGreaterThanOrEqual([snapshot[@"operationCounts"][@"create"] longLongValue], 128);
}

- (void)testReplicaStatesAndCountersAreReported {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"plc-admin-%@.sqlite", NSUUID.UUID.UUIDString]];
    PLCReplicaStore *store = [[PLCReplicaStore alloc] initWithPath:path];
    XCTAssertTrue([store openWithError:nil]);
    PLCSyncEngine *sync = [[PLCSyncEngine alloc] initWithStore:store
                                                         client:[[PLCSyncClient alloc] initWithUpstreamURL:@"http://127.0.0.1:9"]
                                                        auditor:[[PLCAuditor alloc] initWithStore:store]];
    sync.currentCursor = 41;
    sync.totalOperationsIngested = 9;
    sync.totalOperationsFailed = 2;
    sync.lastSyncDate = [NSDate dateWithTimeIntervalSince1970:1];
    GZPLCAdminSnapshot *snapshot = [[GZPLCAdminSnapshot alloc] initWithStore:store syncEngine:sync];
    for (NSNumber *state in @[ @(PLCSyncStateIdle), @(PLCSyncStatePaused), @(PLCSyncStateLiveSyncing), @(PLCSyncStateError) ]) {
        sync.state = state.integerValue;
        NSDictionary *replication = [snapshot snapshot][@"replication"];
        XCTAssertNotNil(replication);
        XCTAssertEqualObjects(replication[@"cursor"], @41);
        XCTAssertEqualObjects(replication[@"ingested"], @9);
        XCTAssertEqualObjects(replication[@"failed"], @2);
    }
    XCTAssertEqualObjects([snapshot snapshot][@"replication"][@"state"], @"failed");
    [store close];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (void)testPrimaryMutationIsRecordedInBoundedAudit {
    GZPLCAdminSnapshot *snapshot = [[GZPLCAdminSnapshot alloc] initWithStore:[[PLCMockStore alloc] init] syncEngine:nil];
    NSError *error = nil;
    XCTAssertFalse([snapshot performReplicaAction:@"pause" error:&error]);
    XCTAssertNotNil(error);
    NSArray *auditEntries = [snapshot snapshot][@"adminAudit"];
    NSDictionary *audit = auditEntries.lastObject;
    XCTAssertEqualObjects(audit[@"action"], @"pause");
    XCTAssertEqualObjects(audit[@"succeeded"], @NO);
}

@end
