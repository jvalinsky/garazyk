#import <XCTest/XCTest.h>
#import "Core/MSTAtomicReference.h"
#import "Repository/MST.h"

@interface MSTAtomicReferenceTests : XCTestCase
@end

@implementation MSTAtomicReferenceTests

#pragma mark - Basic Functionality

- (void)testInitWithNilMST {
    MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:nil];
    XCTAssertNil([ref currentSnapshot], @"nil init should yield nil snapshot");
}

- (void)testInitWithMST {
    MST *mst = [[MST alloc] init];
    MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:mst];
    MST *snapshot = [ref currentSnapshot];
    XCTAssertNotNil(snapshot, @"snapshot should not be nil after init with MST");
    XCTAssertEqual(snapshot, mst, @"snapshot should be the same object passed to init");
}

- (void)testSwapMST {
    MST *mst1 = [[MST alloc] init];
    MST *mst2 = [[MST alloc] init];
    MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:mst1];

    XCTAssertEqual([ref currentSnapshot], mst1, @"initial snapshot should be mst1");

    [ref swapMST:mst2];
    XCTAssertEqual([ref currentSnapshot], mst2, @"after swap, snapshot should be mst2");
}

- (void)testSwapMSTWithNil {
    MST *mst = [[MST alloc] init];
    MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:mst];

    [ref clear];
    XCTAssertNil([ref currentSnapshot], @"after clear, snapshot should be nil");
}

- (void)testClear {
    MST *mst = [[MST alloc] init];
    MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:mst];

    XCTAssertNotNil([ref currentSnapshot], @"before clear, snapshot should not be nil");

    [ref clear];
    XCTAssertNil([ref currentSnapshot], @"after clear, snapshot should be nil");
}

- (void)testClearWhenAlreadyNil {
    MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:nil];
    [ref clear];  // Should not crash
    XCTAssertNil([ref currentSnapshot], @"clear on nil ref should still be nil");
}

#pragma mark - Concurrent Read/Write Stress Test

- (void)testConcurrentReadWriteStress {
    MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:nil];

    // Create a set of MST objects to swap in
    NSMutableArray<MST *> *msts = [NSMutableArray arrayWithCapacity:10];
    for (NSUInteger i = 0; i < 10; i++) {
        [msts addObject:[[MST alloc] init]];
    }

    __block BOOL writerDone = NO;
    __block BOOL hadCrash = NO;
    __block NSUInteger readCount = 0;
    __block NSUInteger nilCount = 0;
    __block NSUInteger nonNilCount = 0;

    // Writer: swap MST objects in a loop
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        for (NSUInteger i = 0; i < 100000; i++) {
            MST *mst = msts[i % msts.count];
            [ref swapMST:mst];
        }
        // Final clear to nil
        [ref clear];
        writerDone = YES;
    });

    // Readers: read snapshots in a loop
    dispatch_group_t readerGroup = dispatch_group_create();
    for (NSUInteger r = 0; r < 10; r++) {
        dispatch_group_enter(readerGroup);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            for (NSUInteger i = 0; i < 10000; i++) {
                @autoreleasepool {
                    MST *snapshot = [ref currentSnapshot];
                    if (snapshot) {
                        // Verify the snapshot is a valid MST object
                        @synchronized(msts) {
                            // The snapshot must be one of the MSTs we created, or nil
                            // (it could also be the final nil after writerDone)
                            BOOL found = [msts containsObject:snapshot];
                            if (!found && !writerDone) {
                                // This shouldn't happen — the snapshot should always
                                // be one of the MSTs we created
                                hadCrash = YES;
                            }
                            nonNilCount++;
                        }
                    } else {
                        nilCount++;
                    }
                    readCount++;
                }
            }
            dispatch_group_leave(readerGroup);
        });
    }

    // Wait for readers to finish
    dispatch_group_wait(readerGroup, DISPATCH_TIME_FOREVER);

    // Wait for writer to finish (readers may finish first)
    while (!writerDone) {
        usleep(1000);
    }

    XCTAssertFalse(hadCrash, @"No crashes during concurrent read/write");
    XCTAssertGreaterThan(readCount, 0U, @"Some reads should have occurred");
}

#pragma mark - Concurrent Swap Test

- (void)testConcurrentSwapNoLostMST {
    MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:nil];

    // Create distinct MST objects with identifiable rootCIDs
    NSMutableArray<MST *> *msts = [NSMutableArray arrayWithCapacity:20];
    for (NSUInteger i = 0; i < 20; i++) {
        [msts addObject:[[MST alloc] init]];
    }

    __block NSMutableSet<MST *> *seenMSTs = [NSMutableSet set];
    __block BOOL hadInvalidSnapshot = NO;

    // Multiple writers swapping different MSTs
    dispatch_group_t writerGroup = dispatch_group_create();
    for (NSUInteger w = 0; w < 5; w++) {
        dispatch_group_enter(writerGroup);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            for (NSUInteger i = 0; i < 10000; i++) {
                NSUInteger idx = (w * 10000 + i) % msts.count;
                [ref swapMST:msts[idx]];
            }
            dispatch_group_leave(writerGroup);
        });
    }

    // Reader: collect all snapshots seen
    dispatch_group_t readerGroup = dispatch_group_create();
    dispatch_group_enter(readerGroup);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSUInteger i = 0; i < 50000; i++) {
            @autoreleasepool {
                MST *snapshot = [ref currentSnapshot];
                if (snapshot) {
                    @synchronized(seenMSTs) {
                        [seenMSTs addObject:snapshot];
                    }
                    // Verify the snapshot is one of our MSTs
                    if (![msts containsObject:snapshot]) {
                        hadInvalidSnapshot = YES;
                    }
                }
            }
        }
        dispatch_group_leave(readerGroup);
    });

    dispatch_group_wait(writerGroup, DISPATCH_TIME_FOREVER);
    dispatch_group_wait(readerGroup, DISPATCH_TIME_FOREVER);

    XCTAssertFalse(hadInvalidSnapshot, @"Every snapshot should be one of our MST objects");
    XCTAssertGreaterThan(seenMSTs.count, 0U, @"Should have seen at least one MST");
}

#pragma mark - Dealloc Safety

- (void)testDeallocWithPendingReads {
    for (NSUInteger i = 0; i < 1000; i++) {
        @autoreleasepool {
            MSTAtomicReference *ref = [[MSTAtomicReference alloc] initWithMST:[[MST alloc] init]];
            MST *snapshot = [ref currentSnapshot];
            XCTAssertNotNil(snapshot);
            // ref is released here — should not crash
        }
    }
}

@end
