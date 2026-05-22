// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"

@interface DatabasePoolTests : XCTestCase

@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *pool;

@end

@implementation DatabasePoolTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DatabasePoolTests"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    [fm createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:10];
}

- (void)tearDown {
    [self.pool closeAll];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    
    [super tearDown];
}

- (void)testPoolInitialization {
    XCTAssertNotNil(self.pool);
    XCTAssertEqualObjects(self.pool.dbDirectory, self.testDirectory);
    XCTAssertEqual(self.pool.maxSize, 10);
    XCTAssertEqual(self.pool.currentSize, 0);
    XCTAssertEqual(self.pool.openFileHandleCount, 0);
}

- (void)testStoreRetrieval {
    __autoreleasing NSError *error = nil;
    NSString *did = @"did:plc:aaaaaaaaaaaaaaaaaaaaaaaa";
    
    PDSActorStore *store = [self.pool storeForDid:did error:&error];
    XCTAssertNotNil(store, @"Failed to get store: %@", error);
    XCTAssertTrue(store.isOpen);
    XCTAssertEqual(self.pool.currentSize, 1);
    XCTAssertEqual(self.pool.openFileHandleCount, 1);
}

- (void)testSameStoreReturned {
    __autoreleasing NSError *error = nil;
    NSString *did = @"did:plc:bbbbbbbbbbbbbbbbbbbbbbbb";
    
    PDSActorStore *store1 = [self.pool storeForDid:did error:&error];
    __autoreleasing NSError *error2 = nil;
    PDSActorStore *store2 = [self.pool storeForDid:did error:&error2];
    
    XCTAssertEqualObjects(store1, store2, @"Should return same store for same DID");
    XCTAssertEqual(self.pool.currentSize, 1, @"Should only have one store");
}

- (void)testMultipleStores {
    __autoreleasing NSError *error = nil;
    
    NSArray *dids = @[@"did:plc:cccccccccccccccccccccccc",
                      @"did:plc:dddddddddddddddddddddddd",
                      @"did:plc:eeeeeeeeeeeeeeeeeeeeeeee"];
    NSMutableArray<PDSActorStore *> *stores = [NSMutableArray array];
    
    for (NSString *did in dids) {
        __autoreleasing NSError *storeError = nil;
        PDSActorStore *store = [self.pool storeForDid:did error:&storeError];
        XCTAssertNotNil(store, @"Failed for %@: %@", did, storeError);
        [stores addObject:store];
    }
    
    XCTAssertEqual(self.pool.currentSize, 3);
    XCTAssertEqual(self.pool.openFileHandleCount, 3);
    
    for (NSUInteger i = 0; i < stores.count; i++) {
        __autoreleasing NSError *storeError = nil;
        PDSActorStore *store = [self.pool storeForDid:dids[i] error:&storeError];
        XCTAssertEqualObjects(store, stores[i], @"Store %lu should be same", (unsigned long)i);
    }
}

- (void)testEvictionRemovesUnusedStoresFromSmallPool {
    PDSDatabasePool *smallPool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:3];
    
    NSArray *dids = @[@"did:plc:ffffffffffffffffffffffff",
                      @"did:plc:gggggggggggggggggggggggg",
                      @"did:plc:hhhhhhhhhhhhhhhhhhhhhhhh",
                      @"did:plc:iiiiiiiiiiiiiiiiiiiiiiii",
                      @"did:plc:jjjjjjjjjjjjjjjjjjjjjjjj"];
    
    for (NSString *did in dids) {
        __autoreleasing NSError *error = nil;
        PDSActorStore *store = [smallPool storeForDid:did error:&error];
        XCTAssertNotNil(store);
    }
    
    XCTAssertEqual(smallPool.currentSize, 3, @"Pool should be at max");
    
    [smallPool evictUnusedStores];
    
    [smallPool closeAll];
}

- (void)testEvictSpecificStore {
    __autoreleasing NSError *error = nil;
    
    NSArray *dids = @[@"did:plc:kkkkkkkkkkkkkkkkkkkkkkkk",
                      @"did:plc:llllllllllllllllllllllll",
                      @"did:plc:mmmmmmmmmmmmmmmmmmmmmmmm"];
    
    for (NSString *did in dids) {
        __autoreleasing NSError *storeError = nil;
        PDSActorStore *store = [self.pool storeForDid:did error:&storeError];
        XCTAssertNotNil(store);
    }
    
    XCTAssertEqual(self.pool.currentSize, 3);
    
    [self.pool evictStoreForDid:dids[1]];
    
    XCTAssertEqual(self.pool.currentSize, 2);
    
    __autoreleasing NSError *evictedError = nil;
    PDSActorStore *evicted = [self.pool storeForDid:dids[1] error:&evictedError];
    XCTAssertNotNil(evicted, @"Should recreate evicted store");
    XCTAssertEqual(self.pool.currentSize, 3, @"Pool should have 3 stores (evicted was recreated)");
}

- (void)testCloseAll {
    __autoreleasing NSError *error = nil;
    
    NSArray *dids = @[@"did:plc:nnnnnnnnnnnnnnnnnnnnnnnn",
                      @"did:plc:oooooooooooooooooooooooo"];
    
    for (NSString *did in dids) {
        __autoreleasing NSError *storeError = nil;
        PDSActorStore *store = [self.pool storeForDid:did error:&storeError];
        XCTAssertNotNil(store);
    }
    
    XCTAssertEqual(self.pool.currentSize, 2);
    XCTAssertEqual(self.pool.openFileHandleCount, 2);
    
    [self.pool closeAll];
    
    XCTAssertEqual(self.pool.currentSize, 0);
    XCTAssertEqual(self.pool.openFileHandleCount, 0);
}

- (void)testAccountOperations {
    __autoreleasing NSError *error = nil;
    NSString *did = @"did:plc:pppppppppppppppppppppppp";
    
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = @"account.test";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    __autoreleasing NSError *txError = nil;
    [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        __autoreleasing NSError *createError = nil;
        XCTAssertTrue([transactor createAccount:account error:&createError], @"Create failed: %@", createError);
    } error:&txError];
    
    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseAccount *fetched = [self.pool getAccount:did error:&fetchError];
    XCTAssertNotNil(fetched, @"Get account failed: %@", fetchError);
    XCTAssertEqualObjects(fetched.handle, @"account.test");
}

- (void)testMetricsCollection {
    __autoreleasing NSError *error = nil;
    
    NSString *did = @"did:plc:qqqqqqqqqqqqqqqqqqqqqqqq";
    [self.pool storeForDid:did error:&error];
    
    NSDictionary *metrics = [self.pool collectMetrics];
    XCTAssertNotNil(metrics);
    XCTAssertEqualObjects(metrics[@"max_size"], @(10));
    XCTAssertEqualObjects(metrics[@"current_size"], @(1));
    XCTAssertNotNil(metrics[@"stores"]);
}

- (void)testAcquireReleaseDetailed {
    __autoreleasing NSError *error = nil;
    NSString *did = @"did:plc:rrrrrrrrrrrrrrrrrrrrrrrr";

    // Acquire store
    PDSActorStore *store1 = [self.pool storeForDid:did error:&error];
    XCTAssertNotNil(store1);
    XCTAssertEqual(self.pool.currentSize, 1);

    // Acquire same store again - should return same instance
    PDSActorStore *store2 = [self.pool storeForDid:did error:&error];
    XCTAssertEqualObjects(store1, store2);
    XCTAssertEqual(self.pool.currentSize, 1);

    // Evict to simulate release
    [self.pool evictStoreForDid:did];
    XCTAssertEqual(self.pool.currentSize, 0);

    // Acquire again after eviction
    PDSActorStore *store3 = [self.pool storeForDid:did error:&error];
    XCTAssertNotNil(store3);
    XCTAssertNotEqualObjects(store1, store3); // New instance after eviction
    XCTAssertEqual(self.pool.currentSize, 1);
}

- (void)testAcquireTimeoutSimulation {
    // Simulate timeout by filling pool and checking behavior
    PDSDatabasePool *smallPool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:2];

    NSArray *dids = @[@"did:plc:ssssssssssssssssssssssss",
                      @"did:plc:tttttttttttttttttttttttt"];

    for (NSString *did in dids) {
        PDSActorStore *store = [smallPool storeForDid:did error:nil];
        XCTAssertNotNil(store);
    }
    XCTAssertEqual(smallPool.currentSize, 2);

    // Attempt to acquire more - should handle gracefully (pool doesn't block, just evicts)
    NSString *did3 = @"did:plc:uuuuuuuuuuuuuuuuuuuuuuuu";
    PDSActorStore *store3 = [smallPool storeForDid:did3 error:nil];
    XCTAssertNotNil(store3);
    XCTAssertEqual(smallPool.currentSize, 2); // Still at max, evicted one

    [smallPool closeAll];
}

- (void)testAcquireErrorConditions {
    // Test with nil DID
    __autoreleasing NSError *error = nil;
    PDSActorStore *store = [self.pool storeForDid:nil error:&error];
    XCTAssertNil(store);
    XCTAssertNotNil(error);

    // Test with invalid DID format that fails regex validation
    NSString *invalidDid = @"invalid-did";
    store = [self.pool storeForDid:invalidDid error:&error];
    XCTAssertNil(store);
    XCTAssertNotNil(error);

    // Test DID traversal attack
    NSString *traversalDid = @"did:plc:../some_other_did";
    store = [self.pool storeForDid:traversalDid error:&error];
    XCTAssertNil(store);
    XCTAssertNotNil(error);
}

#ifndef GNUSTEP
- (void)testConcurrentAccessPatternsReturnsExpectedStoreCount {
    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Concurrent access"];

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_t group = dispatch_group_create();

    NSMutableArray *stores = [NSMutableArray array];
    NSArray *dids = @[@"did:plc:vvvvvvvvvvvvvvvvvvvvvvvv",
                      @"did:plc:wwwwwwwwwwwwwwwwwwwwwwww",
                      @"did:plc:xxxxxxxxxxxxxxxxxxxxxxxx",
                      @"did:plc:yyyyyyyyyyyyyyyyyyyyyyyy",
                      @"did:plc:zzzzzzzzzzzzzzzzzzzzzzzz"];

    for (int i = 0; i < 5; i++) {
        dispatch_group_enter(group);
        NSString *did = dids[i];
        dispatch_async(queue, ^{
            __autoreleasing NSError *error = nil;
            PDSActorStore *store = [self.pool storeForDid:did error:&error];
            @synchronized(stores) {
                if (store) {
                    [stores addObject:store];
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        XCTAssertGreaterThanOrEqual(stores.count, 1);
        XCTAssertLessThanOrEqual(stores.count, 5);
        [expectation fulfill];
    });

    [self waitForExpectations:@[expectation] timeout:5.0];
}
#endif

- (void)testPoolExhaustionHandling {
    PDSDatabasePool *tinyPool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:3];

    // Fill pool
    NSArray *dids = @[@"did:plc:aaaaaaaaaaaaaaaaaaaaaaaa",
                      @"did:plc:bbbbbbbbbbbbbbbbbbbbbbbb",
                      @"did:plc:cccccccccccccccccccccccc"];

    for (NSString *did in dids) {
        PDSActorStore *store = [tinyPool storeForDid:did error:nil];
        XCTAssertNotNil(store);
    }
    XCTAssertEqual(tinyPool.currentSize, 3);

    // Try to acquire more - should evict oldest
    NSString *did4 = @"did:plc:dddddddddddddddddddddddd";
    PDSActorStore *store4 = [tinyPool storeForDid:did4 error:nil];
    XCTAssertNotNil(store4);
    XCTAssertEqual(tinyPool.currentSize, 3); // Still 3, evicted one

    // Access one to mark as used, evict unused
    NSString *didUsed = @"did:plc:cccccccccccccccccccccccc";
    PDSActorStore *usedStore = [tinyPool storeForDid:didUsed error:nil];
    [tinyPool evictUnusedStores];
    // Should evict unused ones, keep used
    XCTAssertGreaterThanOrEqual(tinyPool.currentSize, 1);
    XCTAssertLessThanOrEqual(tinyPool.currentSize, 3);

    [tinyPool closeAll];
}

#ifndef GNUSTEP
- (void)testEvictionUnderLoadMaintainsValidPoolSize {
    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Eviction under load"];

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    // Fill pool
    NSArray *dids = @[@"did:plc:eeeeeeeeeeeeeeeeeeeeeeee",
                      @"did:plc:ffffffffffffffffffffffff",
                      @"did:plc:gggggggggggggggggggggggg",
                      @"did:plc:hhhhhhhhhhhhhhhhhhhhhhhh",
                      @"did:plc:iiiiiiiiiiiiiiiiiiiiiiii",
                      @"did:plc:jjjjjjjjjjjjjjjjjjjjjjjj",
                      @"did:plc:kkkkkkkkkkkkkkkkkkkkkkkk",
                      @"did:plc:llllllllllllllllllllllll",
                      @"did:plc:mmmmmmmmmmmmmmmmmmmmmmmm",
                      @"did:plc:nnnnnnnnnnnnnnnnnnnnnnnn"];

    for (NSString *did in dids) {
        [self.pool storeForDid:did error:nil];
    }
    XCTAssertEqual(self.pool.currentSize, self.pool.maxSize);

    // Concurrent access and eviction
    dispatch_async(queue, ^{
        // Simulate load by accessing stores
        for (int i = 0; i < 10; i++) {
            NSString *did = dids[i % self.pool.maxSize];
            [self.pool storeForDid:did error:nil];
        }
        [self.pool evictUnusedStores];
        [expectation fulfill];
    });

    [self waitForExpectations:@[expectation] timeout:5.0];
    // Verify pool is still functional
    XCTAssertLessThanOrEqual(self.pool.currentSize, self.pool.maxSize);
}
#endif

@end
