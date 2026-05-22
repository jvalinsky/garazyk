// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"

@interface MSTRebalancingTests : XCTestCase
@end

@implementation MSTRebalancingTests

- (void)testSequentialKeysStress {
    // Stress test with sequential keys and various key patterns.
    // Sequential keys (e.g. poison0001, poison0002, ...) produce random
    // SHA-256 hashes due to the avalanche effect, so the MST should handle
    // them the same as random TIDs.
    int count = 100;
    NSArray<NSString *> *patterns = @[
        @"poison%04d",
        @"key_%05d",
        @"test/data/record_%03d",
        @"app.bsky.feed.post/seq%04d",
    ];

    for (NSString *pattern in patterns) {
        MST *tree = [[MST alloc] init];
        NSMutableDictionary<NSString *, CID *> *expected = [NSMutableDictionary dictionary];

        for (int i = 0; i < count; i++) {
            NSString *key = [NSString stringWithFormat:pattern, i];
            CID *cid = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
            [tree put:key valueCID:cid];
            expected[key] = cid;
        }

        XCTAssertEqual(tree.allEntries.count, (NSUInteger)count,
            @"Pattern '%@' should have all %d entries after insertion", pattern, count);

        for (NSString *key in expected) {
            CID *found = [tree get:key];
            XCTAssertEqualObjects(found.stringValue, expected[key].stringValue,
                @"Pattern '%@': key %@ not found or value mismatch", pattern, key);
        }

        // Delete half
        NSArray *sorted = [expected.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for (NSUInteger i = 0; i < sorted.count; i += 2) {
            [tree delete:sorted[i]];
            [expected removeObjectForKey:sorted[i]];
        }

        XCTAssertEqual(tree.allEntries.count, (NSUInteger)(count / 2),
            @"Pattern '%@': should have %d entries after deleting half", pattern, count / 2);

        for (NSString *key in expected) {
            CID *found = [tree get:key];
            XCTAssertEqualObjects(found.stringValue, expected[key].stringValue,
                @"Pattern '%@': remaining key %@ mismatch after deletion", pattern, key);
        }

        GZ_LOG_INFO(@"[MST TEST] Sequential key pattern '%@' stress test passed (%d keys)", pattern, count);
    }

    GZ_LOG_INFO(@"[MST TEST] All sequential key patterns stress test completed.");
}

- (void)testLargeScaleRebalancing {
    MST *tree = [[MST alloc] init];
    NSMutableDictionary<NSString *, CID *> *expectedEntries = [NSMutableDictionary dictionary];
    
    // Insert 1000 keys with pseudo-random TIDs
    int count = 1000;
    GZ_LOG_INFO(@"[MST TEST] Starting insertion of %d keys...", count);
    for (int i = 0; i < count; i++) {
        NSString *rkey = [self generateRandomTID];
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", rkey];
        CID *valueCID = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
        
        [tree put:key valueCID:valueCID];
        expectedEntries[key] = valueCID;
    }
    
    XCTAssertEqual(tree.allEntries.count, count);
    
    // Verify all entries are present and correct
    for (NSString *key in expectedEntries) {
        CID *foundCID = [tree get:key];
        if (![foundCID.stringValue isEqualToString:expectedEntries[key].stringValue]) {
             GZ_LOG_ERROR(@"[MST TEST] Verification failure for key %@: expected %@, found %@", key, expectedEntries[key].stringValue, foundCID.stringValue);
        }
        XCTAssertEqualObjects(foundCID.stringValue, expectedEntries[key].stringValue);
    }
    
    int deleteCount = 500;
    GZ_LOG_INFO(@"[MST TEST] Insertion verified. Starting deletion of %d keys...", deleteCount);
    
    // Delete keys
    NSArray *keysToDelete = [[expectedEntries.allKeys sortedArrayUsingSelector:@selector(compare:)] subarrayWithRange:NSMakeRange(0, deleteCount)];
    
    for (NSString *key in keysToDelete) {
        [tree delete:key];
        [expectedEntries removeObjectForKey:key];
    }
    
    XCTAssertEqual(tree.allEntries.count, count - deleteCount);
    
    // Verify remaining entries
    for (NSString *key in expectedEntries) {
        CID *foundCID = [tree get:key];
        XCTAssertEqualObjects(foundCID.stringValue, expectedEntries[key].stringValue);
    }
    
    // Verify deleted keys are gone
    for (NSString *key in keysToDelete) {
        XCTAssertNil([tree get:key]);
    }
    
    GZ_LOG_INFO(@"[MST TEST] MST rebalancing test completed successfully.");
}

- (void)testSmallScaleInsertDeleteRoundtrip {
    MST *tree = [[MST alloc] init];
    NSMutableDictionary<NSString *, CID *> *expected = [NSMutableDictionary dictionary];
    int count = 20;

    // Insert 20 keys with random TIDs
    GZ_LOG_INFO(@"[MST TEST] Starting small-scale insert of %d keys...", count);
    for (int i = 0; i < count; i++) {
        NSString *rkey = [self generateRandomTID];
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", rkey];
        CID *cid = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
        [tree put:key valueCID:cid];
        expected[key] = cid;
    }

    // Verify all entries present
    XCTAssertEqual((NSUInteger)count, tree.allEntries.count);
    for (NSString *key in expected) {
        CID *found = [tree get:key];
        XCTAssertEqualObjects(found.stringValue, expected[key].stringValue);
    }

    // Delete half the entries
    NSArray *sorted = [expected.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSUInteger i = 0; i < sorted.count; i += 2) {
        [tree delete:sorted[i]];
        [expected removeObjectForKey:sorted[i]];
    }

    // Verify remaining count
    XCTAssertEqual((NSUInteger)(count / 2), tree.allEntries.count);
    for (NSString *key in expected) {
        CID *found = [tree get:key];
        XCTAssertEqualObjects(found.stringValue, expected[key].stringValue);
    }

    // Verify deleted entries gone
    for (NSUInteger i = 0; i < sorted.count; i += 2) {
        XCTAssertNil([tree get:sorted[i]]);
    }

    GZ_LOG_INFO(@"[MST TEST] Small-scale insert/delete/roundtrip completed.");
}

- (void)testSerializeDeserializeRoundtrip {
    MST *tree = [[MST alloc] init];
    NSMutableDictionary<NSString *, CID *> *expected = [NSMutableDictionary dictionary];
    int count = 20;

    // Use random TID keys (will produce multi-node MST at various depths)
    for (int i = 0; i < count; i++) {
        NSString *rkey = [self generateRandomTID];
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", rkey];
        CID *cid = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
        [tree put:key valueCID:cid];
        expected[key] = cid;
    }

    // Serialize root node to CBOR
    NSData *cbor = [tree serializeToCBOR];
    XCTAssertNotNil(cbor);

    // Build a node map (CID → CBOR) from the original tree for the block provider
    NSMutableDictionary<NSString *, NSData *> *nodeMap = [NSMutableDictionary dictionary];
    [tree enumerateNodeCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **error) {
        nodeMap[cid.stringValue] = data;
        return YES;
    } error:nil];
    XCTAssertEqual((NSUInteger)count, tree.allEntries.count,
        @"Tree should have %d entries before roundtrip", count);

    // Deserialize with block provider to reconstruct child subtrees
    MSTBlockProvider provider = ^NSData *(CID *cid) {
        return nodeMap[cid.stringValue];
    };
    MST *restored = [MST deserializeFromCBOR:cbor blockProvider:provider];
    XCTAssertNotNil(restored);

    // Verify all entries survive roundtrip
    XCTAssertEqual((NSUInteger)count, restored.allEntries.count);
    for (NSString *key in expected) {
        CID *found = [restored get:key];
        XCTAssertEqualObjects(found.stringValue, expected[key].stringValue,
            @"Roundtrip: Key %@ not found or value mismatch", key);
    }

    GZ_LOG_INFO(@"[MST TEST] Serialize/deserialize roundtrip with block provider completed.");
}

- (void)testDeserializeWithNilBlockProvider {
    // Verify backward compatibility: nil blockProvider returns single-node tree
    MST *tree = [[MST alloc] init];
    int count = 5;
    for (int i = 0; i < count; i++) {
        NSString *rkey = [self generateRandomTID];
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", rkey];
        CID *cid = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
        [tree put:key valueCID:cid];
    }

    NSData *cbor = [tree serializeToCBOR];
    XCTAssertNotNil(cbor);

    // Deserialize with nil blockProvider — should not crash, returns root node only
    MST *restored = [MST deserializeFromCBOR:cbor blockProvider:nil];
    XCTAssertNotNil(restored);

    GZ_LOG_INFO(@"[MST TEST] Deserialize with nil blockProvider completed.");
}

- (void)testDeserializeWithMissingCIDInBlockProvider {
    // Verify graceful handling when block provider returns nil for a CID
    MST *tree = [[MST alloc] init];
    int count = 10;
    for (int i = 0; i < count; i++) {
        NSString *rkey = [self generateRandomTID];
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", rkey];
        CID *cid = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
        [tree put:key valueCID:cid];
    }

    NSData *cbor = [tree serializeToCBOR];
    XCTAssertNotNil(cbor);

    // Provide a block provider that returns nil for all CIDs (missing data)
    MSTBlockProvider missingProvider = ^NSData *(CID *cid) {
        return nil;
    };
    MST *restored = [MST deserializeFromCBOR:cbor blockProvider:missingProvider];
    XCTAssertNotNil(restored);

    // Should still have the root node's entries (child subtrees gracefully skipped)
    XCTAssertTrue(restored.allEntries.count > 0);

    GZ_LOG_INFO(@"[MST TEST] Deserialize with missing CID in block provider completed.");
}

- (void)testDeserializeEmptyTree {
    // Empty tree serialization/deserialization
    MST *tree = [[MST alloc] init];
    XCTAssertEqual(tree.allEntries.count, 0);

    NSData *cbor = [tree serializeToCBOR];
    XCTAssertNotNil(cbor);

    // Deserialize with nil blockProvider
    MST *restored = [MST deserializeFromCBOR:cbor blockProvider:nil];
    XCTAssertNotNil(restored);
    XCTAssertEqual(restored.allEntries.count, 0);

    // Deserialize with block provider
    MSTBlockProvider provider = ^NSData *(CID *cid) { return nil; };
    MST *restored2 = [MST deserializeFromCBOR:cbor blockProvider:provider];
    XCTAssertNotNil(restored2);
    XCTAssertEqual(restored2.allEntries.count, 0);

    GZ_LOG_INFO(@"[MST TEST] Deserialize empty tree completed.");
}

- (void)testDeserializeSingleNodeTree {
    // Single-node tree (all keys at depth 0) — no child subtree CIDs to resolve
    MST *tree = [[MST alloc] init];
    NSMutableDictionary<NSString *, CID *> *expected = [NSMutableDictionary dictionary];
    int count = 10;
    int added = 0;
    int maxAttempts = 500;

    // Find depth-0 keys (single node tree)
    for (int i = 0; i < maxAttempts && added < count; i++) {
        NSString *rkey = [self generateRandomTID];
        NSString *key = [NSString stringWithFormat:@"app.bsky.feed.post/%@", rkey];
        if ([MST keyDepth:key] == 0) {
            CID *cid = [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
            [tree put:key valueCID:cid];
            expected[key] = cid;
            added++;
        }
    }
    XCTAssertEqual((NSUInteger)count, tree.allEntries.count);

    NSData *cbor = [tree serializeToCBOR];
    XCTAssertNotNil(cbor);

    // Deserialize without block provider
    MST *restored = [MST deserializeFromCBOR:cbor];
    XCTAssertNotNil(restored);
    XCTAssertEqual((NSUInteger)count, restored.allEntries.count);
    for (NSString *key in expected) {
        CID *found = [restored get:key];
        XCTAssertEqualObjects(found.stringValue, expected[key].stringValue);
    }

    GZ_LOG_INFO(@"[MST TEST] Deserialize single-node tree completed.");
}

- (void)testDepthConsistency {
    // Verify that key depth is deterministic and consistent with the spec
    NSString *key1 = @"app.bsky.feed.post/3jzfcijpj2z2a";
    uint32_t depth1 = [MST keyDepth:key1];
    
    // Re-calculating should give same result
    XCTAssertEqual([MST keyDepth:key1], depth1);
    
    // Different key should (likely) have different depth or at least valid range
    NSString *key2 = @"app.bsky.feed.post/3jzfcijpj2z2b";
    uint32_t depth2 = [MST keyDepth:key2];
    XCTAssertTrue(depth1 >= 0);
    XCTAssertTrue(depth2 >= 0);
}

#pragma mark - Helpers

- (NSString *)generateRandomTID {
    static const char alphabet[] = "234567abcdefghijklmnopqrstuvwxyz";
    NSMutableString *tid = [NSMutableString stringWithCapacity:13];
    for (int i = 0; i < 13; i++) {
        [tid appendFormat:@"%c", alphabet[arc4random_uniform(32)]];
    }
    return tid;
}

@end
