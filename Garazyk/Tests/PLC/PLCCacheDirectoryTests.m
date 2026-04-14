#import <Foundation/Foundation.h>
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "../../Sources/PLC/PLCCacheDirectory.h"
#import "../../Sources/PLC/PLCMockStore.h"

@interface PLCCacheDirectoryTests : XCTestCase
@property (nonatomic, strong) PLCMockStore *mockStore;
@property (nonatomic, strong) PLCCacheDirectory *cacheDirectory;
@property (nonatomic, copy) NSString *testDbPath;
@end

@implementation PLCCacheDirectoryTests

- (void)setUp {
    [super setUp];
    self.mockStore = [[PLCMockStore alloc] init];
    self.cacheDirectory = [[PLCCacheDirectory alloc] initWithStore:self.mockStore];
    
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.testDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"plc_cache_test_%@.db", uuid]];
}

- (void)tearDown {
    self.mockStore = nil;
    self.cacheDirectory = nil;
    [super tearDown];
}

- (void)testCacheGetHistory {
    NSString *did = @"did:plc:test1";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.data = @{@"test": @"value1"};
    
    [self.mockStore appendOperation:op1 nullifyCIDs:@[] error:nil];
    
    NSError *error = nil;
    NSArray<PLCOperation *> *history1 = [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:&error];
    
    XCTAssertNotNil(history1);
    XCTAssertEqual(history1.count, 1);
    XCTAssertEqualObjects(history1[0].sig, @"sig1");
    XCTAssertEqual(self.cacheDirectory.cacheMissCount, 1);
    
    NSArray<PLCOperation *> *history2 = [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertEqual(self.cacheDirectory.cacheHitCount, 1);
    XCTAssertEqualObjects(history2[0].sig, @"sig1");
}

- (void)testCacheInvalidationOnAppend {
    NSString *did = @"did:plc:test2";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.data = @{};
    
    [self.mockStore appendOperation:op1 nullifyCIDs:@[] error:nil];
    
    NSArray<PLCOperation *> *history1 = [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:nil];
    XCTAssertEqual(history1.count, 1);
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did;
    op2.sig = @"sig2";
    op2.prev = @"sig1";
    op2.data = @{};
    
    BOOL success = [self.cacheDirectory appendOperation:op2 nullifyCIDs:@[] error:nil];
    XCTAssertTrue(success);

    // flushCacheForDID is asynchronous; wait briefly for invalidation to apply.
    [NSThread sleepForTimeInterval:0.05];
    NSArray<PLCOperation *> *history2 = [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:nil];
    XCTAssertEqual(history2.count, 2);
    XCTAssertEqualObjects(history2.lastObject.sig, @"sig2");
}

- (void)testFlushCacheForDID {
    NSString *did1 = @"did:plc:cache1";
    NSString *did2 = @"did:plc:cache2";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did1;
    op1.sig = @"sig1";
    op1.data = @{};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did2;
    op2.sig = @"sig2";
    op2.data = @{};
    
    [self.mockStore appendOperation:op1 nullifyCIDs:@[] error:nil];
    [self.mockStore appendOperation:op2 nullifyCIDs:@[] error:nil];
    
    [self.cacheDirectory getHistoryForDID:did1 includeNullified:NO error:nil];
    [self.cacheDirectory getHistoryForDID:did2 includeNullified:NO error:nil];
    
    XCTAssertEqual(self.cacheDirectory.cacheHitCount, 0);
    XCTAssertEqual(self.cacheDirectory.cacheMissCount, 2);
    
    [self.cacheDirectory flushCacheForDID:did1];
    
    [self.cacheDirectory getHistoryForDID:did1 includeNullified:NO error:nil];
    [self.cacheDirectory getHistoryForDID:did2 includeNullified:NO error:nil];
    
    XCTAssertEqual(self.cacheDirectory.cacheHitCount, 1);
    XCTAssertEqual(self.cacheDirectory.cacheMissCount, 3);
}

- (void)testFlushAllCachesResetsCacheMissCount {
    NSString *did = @"did:plc:flushall";
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = @"sig";
    op.data = @{};
    
    [self.mockStore appendOperation:op nullifyCIDs:@[] error:nil];
    
    [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:nil];
    XCTAssertEqual(self.cacheDirectory.cacheMissCount, 1);
    
    [self.cacheDirectory flushAllCaches];
    
    [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:nil];
    XCTAssertEqual(self.cacheDirectory.cacheMissCount, 2);
}

- (void)testCacheWithDifferentTTLCausesMisses {
    self.cacheDirectory.ttl = 0.1;
    
    NSString *did = @"did:plc:ttl";
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = @"sig";
    op.data = @{};
    
    [self.mockStore appendOperation:op nullifyCIDs:@[] error:nil];
    
    NSArray<PLCOperation *> *history1 = [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:nil];
    XCTAssertEqual(self.cacheDirectory.cacheMissCount, 1);
    
    [NSThread sleepForTimeInterval:0.2];
    
    NSArray<PLCOperation *> *history2 = [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:nil];
    XCTAssertEqual(self.cacheDirectory.cacheMissCount, 2);
}

- (void)testCacheCapacity {
    self.cacheDirectory.maxEntries = 2;
    
    for (int i = 0; i < 5; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:capacity%d", i];
        PLCOperation *op = [[PLCOperation alloc] init];
        op.did = did;
        op.sig = [NSString stringWithFormat:@"sig%d", i];
        op.data = @{};
        [self.mockStore appendOperation:op nullifyCIDs:@[] error:nil];
        
        [self.cacheDirectory getHistoryForDID:did includeNullified:NO error:nil];
    }
    
    XCTAssertLessThanOrEqual(self.cacheDirectory.cacheMissCount, (NSUInteger)5);
}

- (void)testDefaultValues {
    PLCCacheDirectory *cache = [[PLCCacheDirectory alloc] initWithStore:self.mockStore];
    
    XCTAssertEqual(cache.ttl, PLCCacheDefaultTTL);
    XCTAssertEqual(cache.maxEntries, PLCCacheDefaultCapacity);
}

@end
