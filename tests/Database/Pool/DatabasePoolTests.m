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
    NSString *did = @"did:plc:test123";
    NSError *error = nil;
    
    PDSActorStore *store = [self.pool storeForDid:did error:&error];
    XCTAssertNotNil(store, @"Failed to get store: %@", error);
    XCTAssertTrue(store.isOpen);
    XCTAssertEqual(self.pool.currentSize, 1);
    XCTAssertEqual(self.pool.openFileHandleCount, 1);
}

- (void)testSameStoreReturned {
    NSString *did = @"did:plc:test456";
    NSError *error = nil;
    
    PDSActorStore *store1 = [self.pool storeForDid:did error:&error];
    PDSActorStore *store2 = [self.pool storeForDid:did error:&error];
    
    XCTAssertEqualObjects(store1, store2, @"Should return same store for same DID");
    XCTAssertEqual(self.pool.currentSize, 1, @"Should only have one store");
}

- (void)testMultipleStores {
    NSError *error = nil;
    
    NSArray *dids = @[@"did:plc:aaa", @"did:plc:bbb", @"did:plc:ccc"];
    NSMutableArray<PDSActorStore *> *stores = [NSMutableArray array];
    
    for (NSString *did in dids) {
        PDSActorStore *store = [self.pool storeForDid:did error:&error];
        XCTAssertNotNil(store, @"Failed for %@: %@", did, error);
        [stores addObject:store];
    }
    
    XCTAssertEqual(self.pool.currentSize, 3);
    XCTAssertEqual(self.pool.openFileHandleCount, 3);
    
    for (NSUInteger i = 0; i < stores.count; i++) {
        PDSActorStore *store = [self.pool storeForDid:dids[i] error:&error];
        XCTAssertEqualObjects(store, stores[i], @"Store %lu should be same", (unsigned long)i);
    }
}

- (void)testEviction {
    PDSDatabasePool *smallPool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:3];
    
    NSError *error = nil;
    
    for (int i = 0; i < 5; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:evict%d", i];
        PDSActorStore *store = [smallPool storeForDid:did error:&error];
        XCTAssertNotNil(store);
    }
    
    XCTAssertEqual(smallPool.currentSize, 3, @"Pool should be at max");
    
    [smallPool evictUnusedStores];
    
    [smallPool closeAll];
}

- (void)testEvictSpecificStore {
    NSError *error = nil;
    
    NSArray *dids = @[@"did:plc:evict1", @"did:plc:evict2", @"did:plc:evict3"];
    
    for (NSString *did in dids) {
        PDSActorStore *store = [self.pool storeForDid:did error:&error];
        XCTAssertNotNil(store);
    }
    
    XCTAssertEqual(self.pool.currentSize, 3);
    
    [self.pool evictStoreForDid:dids[1]];
    
    XCTAssertEqual(self.pool.currentSize, 2);
    
    PDSActorStore *evicted = [self.pool storeForDid:dids[1] error:&error];
    XCTAssertNotNil(evicted, @"Should recreate evicted store");
    XCTAssertEqual(self.pool.currentSize, 2, @"Pool should have 2 stores (evicted was recreated)");
}

- (void)testCloseAll {
    NSError *error = nil;
    
    NSArray *dids = @[@"did:plc:close1", @"did:plc:close2"];
    
    for (NSString *did in dids) {
        PDSActorStore *store = [self.pool storeForDid:did error:&error];
        XCTAssertNotNil(store);
    }
    
    XCTAssertEqual(self.pool.currentSize, 2);
    XCTAssertEqual(self.pool.openFileHandleCount, 2);
    
    [self.pool closeAll];
    
    XCTAssertEqual(self.pool.currentSize, 0);
    XCTAssertEqual(self.pool.openFileHandleCount, 0);
}

- (void)testAccountOperations {
    NSError *error = nil;
    NSString *did = @"did:plc:accounttest";
    
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = @"account.test";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        XCTAssertTrue([transactor createAccount:account error:&error], @"Create failed: %@", error);
    } error:&error];
    
    PDSDatabaseAccount *fetched = [self.pool getAccount:did error:&error];
    XCTAssertNotNil(fetched, @"Get account failed: %@", error);
    XCTAssertEqualObjects(fetched.handle, @"account.test");
}

- (void)testMetricsCollection {
    NSError *error = nil;
    
    NSString *did = @"did:plc:metrics";
    [self.pool storeForDid:did error:&error];
    
    NSDictionary *metrics = [self.pool collectMetrics];
    XCTAssertNotNil(metrics);
    XCTAssertEqualObjects(metrics[@"max_size"], @(10));
    XCTAssertEqualObjects(metrics[@"current_size"], @(1));
    XCTAssertNotNil(metrics[@"stores"]);
}

@end
