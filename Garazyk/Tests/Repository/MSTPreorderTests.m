// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Core/CID.h"

@interface MSTPreorderTests : XCTestCase
@end

@implementation MSTPreorderTests

#pragma mark - Setup / teardown

- (void)setUp {
    [super setUp];
    // Reset the class-level flag to the documented default so test ordering does
    // not leak state across the suite (global BOOLEAN).
    [MST setStreamableCARBlockOrderingEnabled:NO];
}

- (void)tearDown {
    [MST setStreamableCARBlockOrderingEnabled:NO];
    [super tearDown];
}

#pragma mark - Test data helpers

- (CID *)testCIDForKey:(NSString *)key {
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    return [CID sha256:data];
}

- (NSData *)testRecordDataForCID:(CID *)cid {
    // Deterministic record data distinct from any MST-node CBOR.
    NSMutableData *out = [NSMutableData data];
    uint8_t marker = 0xA1;
    [out appendBytes:&marker length:1];
    [out appendData:cid.bytes];
    return out;
}

- (NSString *)deterministicTIDForIndex:(int)index {
    static const char alphabet[] = "234567abcdefghijklmnopqrstuvwxyz";
    NSMutableString *tid = [NSMutableString stringWithCapacity:13];
    uint32_t val = (uint32_t)index * 2654435761u + 12345u;
    for (int i = 0; i < 13; i++) {
        [tid appendFormat:@"%c", alphabet[val % 32]];
        val = val * 1664525u + 1013904223u;
    }
    return tid;
}

- (MST *)buildMultiLevelTree {
    // Use a deterministic, force-multi-level seed by including keys with known
    // depths combined with deterministic TIDs. We add keys until the pre-order
    // traversal of MST nodes differs from BFS traversal, guaranteeing that the
    // resulting tree has multi-branch subtree depth and ensuring exact tree
    // shape reproducibility across every test run.
    MST *tree = [[MST alloc] init];

    NSArray<NSString *> *seedKeys = @[
        @"app.bsky.feed.post/3jzfcijpj2z2a",
        @"app.bsky.feed.post/3jzfcijpj2z2b",
        @"app.bsky.feed.post/3jzfcijpj2z2c",
        @"app.bsky.feed.post/3jzfcijpj2z2d",
        @"app.bsky.feed.post/3jzfcijpj2zek",
        @"app.bsky.feed.post/3jzfcijpj2zel",
        @"app.bsky.feed.post/3jzfcijpj2zep",
        @"post/aaa",
        @"post/bbb",
        @"post/ccc",
        @"post/ddd",
        @"test/key.005"
    ];
    for (NSString *key in seedKeys) {
        [tree put:key valueCID:[self testCIDForKey:key]];
    }

    NSMutableSet<NSString *> *seen = [NSMutableSet setWithArray:seedKeys];
    int idx = 0;
    while (seen.count < 300) {
        NSString *rkey = [self deterministicTIDForIndex:idx++];
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", rkey];
        if ([seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [tree put:key valueCID:[self testCIDForKey:key]];
        if (seen.count >= 20) {
            NSArray<NSString *> *preorder = [self capturePreorderMSTOnly:tree];
            NSArray<NSString *> *bfs = [self captureBFS:tree];
            if (![preorder isEqualToArray:bfs]) {
                break;
            }
        }
    }
    return tree;
}

#pragma mark - Feature flag behaviour

- (void)testDefaultFlagIsOff {
    // Arriving fresh into a test, the flag must be its documented default.
    XCTAssertFalse(MST.streamableCARBlockOrderingEnabled);
}

- (void)testFlagTogglePreservesState {
    [MST setStreamableCARBlockOrderingEnabled:YES];
    XCTAssertTrue(MST.streamableCARBlockOrderingEnabled);
    [MST setStreamableCARBlockOrderingEnabled:NO];
    XCTAssertFalse(MST.streamableCARBlockOrderingEnabled);
}

- (void)testRefusesWhenFlagOff {
    MST *tree = [self buildMultiLevelTree];
    NSError *err = nil;
    __block NSUInteger emitted = 0;
    BOOL ok = [tree enumerateStreamableCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **e) {
        emitted++;
        return YES;
    } recordProvider:^NSData *(CID *cid) {
        return [self testRecordDataForCID:cid];
    } error:&err];
    XCTAssertFalse(ok, @"Pre-order walker must refuse when the flag is off");
    XCTAssertNotNil(err, @"Refusal must surface an error");
    XCTAssertEqualObjects(err.domain, @"com.atproto.mst");
    XCTAssertEqual(err.code, 100);
    XCTAssertEqual(emitted, (NSUInteger)0, @"Refused walk must not emit any blocks");
}

#pragma mark - Structural invariants

- (void)testPreorderEmitsRootFirst {
    [MST setStreamableCARBlockOrderingEnabled:YES];
    MST *tree = [self buildMultiLevelTree];
    NSArray<NSString *> *order = [self capturePreorderStream:tree];
    XCTAssertGreaterThan(order.count, (NSUInteger)0);
    XCTAssertEqualObjects(order.firstObject, tree.rootCID.stringValue,
                          @"Pre-order must start at the root MST node");
}

- (void)testPreorderHasNoDuplicatesIncludingRecords {
    [MST setStreamableCARBlockOrderingEnabled:YES];
    MST *tree = [self buildMultiLevelTree];
    NSArray<NSString *> *order = [self capturePreorderStream:tree];
    NSCountedSet<NSString *> *uniq = [NSCountedSet setWithArray:order];
    XCTAssertEqual(order.count, uniq.count,
                   @"Pre-order must not emit any block (node or record) twice");
}

- (void)testPreorderMSTSubsetEqualsBFSSubset {
    [MST setStreamableCARBlockOrderingEnabled:YES];
    MST *tree = [self buildMultiLevelTree];
    NSSet<NSString *> *mstNodeSet = [self mstNodeCIDSetForTree:tree];

    NSArray<NSString *> *preorderMST = [self capturePreorderMSTOnly:tree];
    NSArray<NSString *> *bfsOrder = [self captureBFS:tree];

    XCTAssertEqualObjects([NSSet setWithArray:preorderMST], mstNodeSet,
                          @"MST-node-only pre-order must cover exactly the MST node set");
    XCTAssertEqualObjects([NSSet setWithArray:preorderMST], [NSSet setWithArray:bfsOrder],
                          @"MST-node-only pre-order and BFS must yield the same set of MST node CIDs");
    XCTAssertEqual(preorderMST.count, bfsOrder.count,
                   @"Without records, both walks emit the same number of MST node blocks");
}

- (void)testPreorderMSTOrderDiffersFromBFSForMultiLevelTree {
    [MST setStreamableCARBlockOrderingEnabled:YES];
    MST *tree = [self buildMultiLevelTree];
    NSSet<NSString *> *mstNodeSet = [self mstNodeCIDSetForTree:tree];
    if (mstNodeSet.count < 2) {
        // Skip explicitly so the bail-out is visible in test summary output
        // rather than silently passing an unobservable regression.
        XCTSkip(@"Test tree has only one MST node; cannot compare pre-order vs BFS ordering.");
    }
    NSArray<NSString *> *preorderMST = [self capturePreorderMSTOnly:tree];
    NSArray<NSString *> *bfsOrder = [self captureBFS:tree];
    XCTAssertNotEqualObjects(preorderMST, bfsOrder,
        @"Pre-order must produce a different MST-node sequence than BFS for multi-level trees");
}

- (void)testPreorderEmptyTreeEmitsSameBlockAsBFS {
    [MST setStreamableCARBlockOrderingEnabled:YES];
    MST *tree = [[MST alloc] init];
    NSArray<NSString *> *preorder = [self capturePreorderStream:tree];
    NSArray<NSString *> *bfs = [self captureBFS:tree];
    // An empty repo still has a singleton empty-MST node with a defined CID,
    // and emitting that block is spec-correct: consumers need it together with
    // the commit block to verify the empty-repo state. Both walkers emit
    // exactly one block (the same empty-MST node) for an empty tree.
    XCTAssertEqual(preorder.count, (NSUInteger)1,
                   @"Empty tree must emit exactly the empty-MST node block under pre-order ordering");
    XCTAssertEqualObjects(preorder, bfs,
                          @"Pre-order and BFS must emit the same empty-MST node block for an empty tree");
}

- (void)testPreorderNilRecordProviderSkipsRecords {
    [MST setStreamableCARBlockOrderingEnabled:YES];
    MST *tree = [self buildMultiLevelTree];
    NSArray<NSString *> *orderNoRecords = [self capturePreorderMSTOnly:tree];
    NSArray<NSString *> *bfsOrder = [self captureBFS:tree];
    XCTAssertEqualObjects([NSSet setWithArray:orderNoRecords],
                          [NSSet setWithArray:bfsOrder],
                          @"Nil record provider must drop records; MST-node set must match BFS");
    XCTAssertEqual(orderNoRecords.count, bfsOrder.count,
                   @"Without records, preorder MST-node block count equals BFS block count");
}

#pragma mark - Fixture capture

- (void)testEmitsPreorderFixture {
    [MST setStreamableCARBlockOrderingEnabled:YES];
    MST *tree = [self buildMultiLevelTree];
    NSArray<NSString *> *preorder = [self capturePreorderStream:tree];
    NSArray<NSString *> *bfsOrder = [self captureBFS:tree];
    NSSet<NSString *> *mstNodeSet = [self mstNodeCIDSetForTree:tree];

    NSMutableArray<NSString *> *preorderMST = [NSMutableArray array];
    NSMutableArray<NSString *> *preorderRecords = [NSMutableArray array];
    for (NSString *cid in preorder) {
        if ([mstNodeSet containsObject:cid]) {
            [preorderMST addObject:cid];
        } else {
            [preorderRecords addObject:cid];
        }
    }

    NSData *jPreorder      = [NSJSONSerialization dataWithJSONObject:preorder options:0 error:nil];
    NSData *jPreorderMST   = [NSJSONSerialization dataWithJSONObject:preorderMST options:0 error:nil];
    NSData *jPreorderRecs  = [NSJSONSerialization dataWithJSONObject:preorderRecords options:0 error:nil];
    NSData *jBFS           = [NSJSONSerialization dataWithJSONObject:bfsOrder options:0 error:nil];

    NSLog(@"[MSTPreorderTests] === Sync 1.1 Streamable CAR Block Ordering fixture ===");
    NSLog(@"[MSTPreorderTests] rootCID: %@", tree.rootCID.stringValue);
    NSLog(@"[MSTPreorderTests] preorder total  (%lu): %@",
          (unsigned long)preorder.count,
          [[NSString alloc] initWithData:jPreorder encoding:NSUTF8StringEncoding]);
    NSLog(@"[MSTPreorderTests] preorder MST   (%lu): %@",
          (unsigned long)preorderMST.count,
          [[NSString alloc] initWithData:jPreorderMST encoding:NSUTF8StringEncoding]);
    NSLog(@"[MSTPreorderTests] preorder records(%lu): %@",
          (unsigned long)preorderRecords.count,
          [[NSString alloc] initWithData:jPreorderRecs encoding:NSUTF8StringEncoding]);
    NSLog(@"[MSTPreorderTests] BFS for compare (%lu): %@",
          (unsigned long)bfsOrder.count,
          [[NSString alloc] initWithData:jBFS encoding:NSUTF8StringEncoding]);
    NSLog(@"[MSTPreorderTests] =================================================");

    // Re-pin the invariant assertions here so a failure shows the fixture
    // context in the log stream above even when collapsed by the test runner.
    XCTAssertEqualObjects(preorder.firstObject, tree.rootCID.stringValue);
    XCTAssertGreaterThan(preorderMST.count, (NSUInteger)0,
                         @"Fixture must include at least the root MST node block");
    XCTAssertGreaterThan(preorderRecords.count, (NSUInteger)0,
                         @"Fixture must include at least one record block to be a useful pre-order example");
    XCTAssertEqual(preorder.count, preorderMST.count + preorderRecords.count,
                   @"Pre-order total must equal MST-node count + record count");
}

#pragma mark - Walk helpers

- (NSArray<NSString *> *)capturePreorderStream:(MST *)tree {
    __block NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSError *err = nil;
    BOOL ok = [tree enumerateStreamableCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **error) {
        (void)error;
        [order addObject:cid.stringValue];
        return YES;
    } recordProvider:^NSData *(CID *cid) {
        return [self testRecordDataForCID:cid];
    } error:&err];
    XCTAssertTrue(ok, @"Pre-order walk must succeed when flag is enabled: %@", err);
    return order;
}

- (NSArray<NSString *> *)capturePreorderMSTOnly:(MST *)tree {
    __block NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSError *err = nil;
    BOOL ok = [tree enumerateStreamableCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **error) {
        (void)error;
        [order addObject:cid.stringValue];
        return YES;
    } recordProvider:nil error:&err];
    XCTAssertTrue(ok, @"Pre-order walk (records disabled) must succeed: %@", err);
    return order;
}

- (NSArray<NSString *> *)captureBFS:(MST *)tree {
    __block NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSError *err = nil;
    BOOL ok = [tree enumerateNodeCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **error) {
        (void)error;
        [order addObject:cid.stringValue];
        return YES;
    } error:&err];
    XCTAssertTrue(ok, @"Existing BFS walk must succeed: %@", err);
    return order;
}

- (NSSet<NSString *> *)mstNodeCIDSetForTree:(MST *)tree {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    [tree enumerateNodeCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **error) {
        (void)error;
        [set addObject:cid.stringValue];
        return YES;
    } error:nil];
    return set;
}

@end
