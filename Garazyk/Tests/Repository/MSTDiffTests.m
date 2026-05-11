// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Repository/MSTWalker.h"
#import "Core/CID.h"

@interface MSTDiffTests : XCTestCase
@end

@implementation MSTDiffTests

- (CID *)testCID:(NSString *)suffix {
    NSData *data = [[NSString stringWithFormat:@"mst-diff-test-%@", suffix ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
    return [CID sha256:data];
}

- (CID *)defaultTestCID {
    return [self testCID:@""];
}

#pragma mark - Basic Diff Tests

- (void)testDiffNilOldTree {
    // When old tree is nil, all entries should be adds
    MST *newTree = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    
    [newTree put:@"com.example.record/aaa" valueCID:cid1];
    [newTree put:@"com.example.record/bbb" valueCID:cid1];
    [newTree put:@"com.example.record/ccc" valueCID:cid1];
    
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:nil];
    
    XCTAssertEqual(diff.count, 3, @"Should have 3 add operations");
    
    for (MSTDiffOperation *op in diff) {
        XCTAssertEqual(op.type, MSTDiffOperationTypeAdd, @"All operations should be adds");
        XCTAssertNotNil(op.currentCID, @"Add should have currentCID");
        XCTAssertNil(op.previousCID, @"Add should not have previousCID");
    }
}

- (void)testDiffNilNewTree {
    // When new tree is nil, all entries should be deletes
    MST *oldTree = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    
    [oldTree put:@"com.example.record/aaa" valueCID:cid1];
    [oldTree put:@"com.example.record/bbb" valueCID:cid1];
    [oldTree put:@"com.example.record/ccc" valueCID:cid1];
    
    MST *newTree = [[MST alloc] init];
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:oldTree];
    
    XCTAssertEqual(diff.count, 3, @"Should have 3 delete operations");
    
    for (MSTDiffOperation *op in diff) {
        XCTAssertEqual(op.type, MSTDiffOperationTypeDelete, @"All operations should be deletes");
        XCTAssertNotNil(op.previousCID, @"Delete should have previousCID");
        XCTAssertNil(op.currentCID, @"Delete should not have currentCID");
    }
}

- (void)testDiffIdenticalTrees {
    // Identical trees should have no diff
    MST *tree1 = [[MST alloc] init];
    MST *tree2 = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    
    [tree1 put:@"com.example.record/aaa" valueCID:cid1];
    [tree1 put:@"com.example.record/bbb" valueCID:cid1];
    [tree2 put:@"com.example.record/aaa" valueCID:cid1];
    [tree2 put:@"com.example.record/bbb" valueCID:cid1];
    
    NSArray<MSTDiffOperation *> *diff = [tree2 diffFrom:tree1];
    
    XCTAssertEqual(diff.count, 0, @"Identical trees should have empty diff");
}

- (void)testDiffAdditions {
    // Test adding entries
    MST *oldTree = [[MST alloc] init];
    MST *newTree = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    CID *cid2 = [self testCID:@"2"];
    
    [oldTree put:@"com.example.record/aaa" valueCID:cid1];
    
    [newTree put:@"com.example.record/aaa" valueCID:cid1];
    [newTree put:@"com.example.record/bbb" valueCID:cid2];
    [newTree put:@"com.example.record/ccc" valueCID:cid2];
    
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:oldTree];
    
    XCTAssertEqual(diff.count, 2, @"Should have 2 add operations");
    
    NSUInteger addCount = 0;
    for (MSTDiffOperation *op in diff) {
        if (op.type == MSTDiffOperationTypeAdd) {
            addCount++;
        }
    }
    XCTAssertEqual(addCount, 2, @"Should have exactly 2 adds");
}

- (void)testDiffDeletions {
    // Test deleting entries
    MST *oldTree = [[MST alloc] init];
    MST *newTree = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    CID *cid2 = [self testCID:@"2"];
    
    [oldTree put:@"com.example.record/aaa" valueCID:cid1];
    [oldTree put:@"com.example.record/bbb" valueCID:cid2];
    [oldTree put:@"com.example.record/ccc" valueCID:cid2];
    
    [newTree put:@"com.example.record/aaa" valueCID:cid1];
    
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:oldTree];
    
    XCTAssertEqual(diff.count, 2, @"Should have 2 delete operations");
    
    NSUInteger deleteCount = 0;
    for (MSTDiffOperation *op in diff) {
        if (op.type == MSTDiffOperationTypeDelete) {
            deleteCount++;
        }
    }
    XCTAssertEqual(deleteCount, 2, @"Should have exactly 2 deletes");
}

- (void)testDiffUpdates {
    // Test updating entries
    MST *oldTree = [[MST alloc] init];
    MST *newTree = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    CID *cid2 = [self testCID:@"2"];
    
    [oldTree put:@"com.example.record/aaa" valueCID:cid1];
    [oldTree put:@"com.example.record/bbb" valueCID:cid1];
    
    [newTree put:@"com.example.record/aaa" valueCID:cid2]; // Updated
    [newTree put:@"com.example.record/bbb" valueCID:cid1]; // Same
    
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:oldTree];
    
    XCTAssertEqual(diff.count, 1, @"Should have 1 update operation");
    
    MSTDiffOperation *op = diff.firstObject;
    XCTAssertEqual(op.type, MSTDiffOperationTypeUpdate, @"Should be an update");
    XCTAssertEqualObjects(op.key, @"com.example.record/aaa", @"Key should match");
    XCTAssertNotNil(op.previousCID, @"Update should have previousCID");
    XCTAssertNotNil(op.currentCID, @"Update should have currentCID");
}

- (void)testDiffMixedOperations {
    // Test mixed add/update/delete
    MST *oldTree = [[MST alloc] init];
    MST *newTree = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    CID *cid2 = [self testCID:@"2"];
    CID *cid3 = [self testCID:@"3"];
    
    // Old: aaa, bbb, ccc
    [oldTree put:@"com.example.record/aaa" valueCID:cid1];
    [oldTree put:@"com.example.record/bbb" valueCID:cid1];
    [oldTree put:@"com.example.record/ccc" valueCID:cid1];
    
    // New: aaa(updated), bbb(same), ddd(new)
    [newTree put:@"com.example.record/aaa" valueCID:cid2]; // Updated
    [newTree put:@"com.example.record/bbb" valueCID:cid1]; // Same
    [newTree put:@"com.example.record/ddd" valueCID:cid3]; // New
    
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:oldTree];
    
    // Expected: 1 update (aaa), 1 delete (ccc), 1 add (ddd)
    XCTAssertEqual(diff.count, 3, @"Should have 3 operations");
    
    NSUInteger addCount = 0, updateCount = 0, deleteCount = 0;
    for (MSTDiffOperation *op in diff) {
        switch (op.type) {
            case MSTDiffOperationTypeAdd: addCount++; break;
            case MSTDiffOperationTypeUpdate: updateCount++; break;
            case MSTDiffOperationTypeDelete: deleteCount++; break;
        }
    }
    
    XCTAssertEqual(addCount, 1, @"Should have 1 add");
    XCTAssertEqual(updateCount, 1, @"Should have 1 update");
    XCTAssertEqual(deleteCount, 1, @"Should have 1 delete");
}

#pragma mark - Walker Tests

- (void)testWalkerEmptyTree {
    // Empty tree walker should be done immediately
    MST *mst = [[MST alloc] init];
    MSTWalker *walker = [[MSTWalker alloc] initWithRootNode:mst.root];
    
    XCTAssertTrue(walker.status.isDone, @"Empty tree walker should be done");
}

- (void)testWalkerSingleEntry {
    // Single entry tree
    MST *mst = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    
    [mst put:@"com.example.record/aaa" valueCID:cid1];
    
    MSTWalker *walker = [[MSTWalker alloc] initWithRootNode:mst.root];
    
    XCTAssertFalse(walker.status.isDone, @"Should not be done initially");
    
    // Walk through the tree
    NSUInteger steps = 0;
    while (!walker.status.isDone && steps < 100) {
        [walker advance];
        steps++;
    }
    
    XCTAssertTrue(walker.status.isDone, @"Walker should finish");
    XCTAssertLessThan(steps, 100, @"Should not infinite loop");
}

- (void)testWalkerMultipleEntries {
    // Multiple entry tree
    MST *mst = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    
    [mst put:@"com.example.record/aaa" valueCID:cid1];
    [mst put:@"com.example.record/bbb" valueCID:cid1];
    [mst put:@"com.example.record/ccc" valueCID:cid1];
    [mst put:@"com.example.record/ddd" valueCID:cid1];
    [mst put:@"com.example.record/eee" valueCID:cid1];
    
    MSTWalker *walker = [[MSTWalker alloc] initWithRootNode:mst.root];
    
    NSMutableArray<NSString *> *visitedKeys = [NSMutableArray array];
    
    while (!walker.status.isDone) {
        MSTNodeEntry *entry = walker.status.currentEntry;
        if (entry != nil && !walker.status.isTreeNode) {
            [visitedKeys addObject:entry.fullKey];
        }
        [walker advance];
    }
    
    XCTAssertEqual(visitedKeys.count, 5, @"Should visit all 5 entries");
    
    // Verify sorted order
    for (NSUInteger i = 1; i < visitedKeys.count; i++) {
        XCTAssertLessThan([visitedKeys[i-1] compare:visitedKeys[i]], 0,
            @"Keys should be visited in sorted order");
    }
}

#pragma mark - Edge Cases

- (void)testDiffKeyOrdering {
    // Verify diff returns operations in key order
    MST *oldTree = [[MST alloc] init];
    MST *newTree = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    
    // Add entries in non-sorted order
    [newTree put:@"com.example.record/zzz" valueCID:cid1];
    [newTree put:@"com.example.record/aaa" valueCID:cid1];
    [newTree put:@"com.example.record/mmm" valueCID:cid1];
    
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:oldTree];
    
    // Verify sorted order
    for (NSUInteger i = 1; i < diff.count; i++) {
        XCTAssertLessThan([diff[i-1].key compare:diff[i].key], 0,
            @"Diff operations should be sorted by key");
    }
}

- (void)testDiffLargeTree {
    // Test with larger tree to ensure no infinite loops
    MST *oldTree = [[MST alloc] init];
    MST *newTree = [[MST alloc] init];
    CID *cid1 = [self defaultTestCID];
    CID *cid2 = [self testCID:@"2"];
    
    // Create 50 entries
    for (int i = 0; i < 50; i++) {
        NSString *key = [NSString stringWithFormat:@"com.example.record/key%03d", i];
        [oldTree put:key valueCID:cid1];
    }
    
    // Update some, delete some, add some
    for (int i = 0; i < 40; i++) {
        NSString *key = [NSString stringWithFormat:@"com.example.record/key%03d", i];
        [newTree put:key valueCID:cid1];
    }
    
    // Updates (different CID)
    for (int i = 0; i < 10; i++) {
        NSString *key = [NSString stringWithFormat:@"com.example.record/key%03d", i];
        [newTree put:key valueCID:cid2];
    }
    
    // New entries
    for (int i = 50; i < 60; i++) {
        NSString *key = [NSString stringWithFormat:@"com.example.record/key%03d", i];
        [newTree put:key valueCID:cid1];
    }
    
    NSArray<MSTDiffOperation *> *diff = [newTree diffFrom:oldTree];
    
    // Expected: 10 updates, 10 deletes (40-49), 10 adds (50-59)
    XCTAssertEqual(diff.count, 30, @"Should have 30 total operations");
}

@end
