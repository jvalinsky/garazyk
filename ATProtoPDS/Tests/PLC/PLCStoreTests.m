#import <Foundation/Foundation.h>
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "../../Sources/PLC/PLCOperation.h"
#import "../../Sources/PLC/PLCMockStore.h"
#import "../../Sources/PLC/PLCPersistentStore.h"

@interface PLCStoreTests : XCTestCase
@property (nonatomic, copy) NSString *testDbPath;
@end

@implementation PLCStoreTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.testDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"plc_test_%@.db", uuid]];
}

- (void)tearDown {
    if (self.testDbPath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.testDbPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[self.testDbPath stringByAppendingString:@"-wal"] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[self.testDbPath stringByAppendingString:@"-shm"] error:nil];
    }
    [super tearDown];
}

- (void)testPersistentStoreOpen {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    
    XCTAssertNotNil(store);
    XCTAssertNil(error);
    XCTAssertTrue(store.isOpen);
    
    [store close];
}

- (void)testPersistentStoreAppendAndGetHistory {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did = @"did:plc:test1";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.prev = nil;
    op1.data = @{@"foo": @"bar"};
    
    BOOL success = [store appendOperation:op1 nullifyCIDs:@[] error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 1);
    XCTAssertEqualObjects(history[0].sig, @"sig1");
    XCTAssertEqualObjects(history[0].did, did);
    XCTAssertNotNil(history[0].data);
    
    [store close];
}

- (void)testPersistentStoreMultipleOperations {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did = @"did:plc:test_chain";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.prev = nil;
    op1.data = @{@"step": @"1"};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did;
    op2.sig = @"sig2";
    op2.prev = [NSString stringWithFormat:@"prev_%@", op1.sig];
    op2.data = @{@"step": @"2"};
    
    PLCOperation *op3 = [[PLCOperation alloc] init];
    op3.did = did;
    op3.sig = @"sig3";
    op3.prev = [NSString stringWithFormat:@"prev_%@", op2.sig];
    op3.data = @{@"step": @"3"};
    
    XCTAssertTrue([store appendOperation:op1 nullifyCIDs:@[] error:&error]);
    XCTAssertTrue([store appendOperation:op2 nullifyCIDs:@[] error:&error]);
    XCTAssertTrue([store appendOperation:op3 nullifyCIDs:@[] error:&error]);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertEqual(history.count, 3);
    XCTAssertEqualObjects(history[0].sig, @"sig1");
    XCTAssertEqualObjects(history[1].sig, @"sig2");
    XCTAssertEqualObjects(history[2].sig, @"sig3");
    
    [store close];
}

- (void)testPersistentStoreMultipleDIDs {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did1 = @"did:plc:test_a";
    NSString *did2 = @"did:plc:test_b";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did1;
    op1.sig = @"sig_a";
    op1.data = @{};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did2;
    op2.sig = @"sig_b";
    op2.data = @{};
    
    [store appendOperation:op1 nullifyCIDs:@[] error:nil];
    [store appendOperation:op2 nullifyCIDs:@[] error:nil];
    
    NSArray<PLCOperation *> *history1 = [store getHistoryForDID:did1 includeNullified:NO error:nil];
    NSArray<PLCOperation *> *history2 = [store getHistoryForDID:did2 includeNullified:NO error:nil];
    
    XCTAssertEqual(history1.count, 1);
    XCTAssertEqualObjects(history1[0].sig, @"sig_a");
    
    XCTAssertEqual(history2.count, 1);
    XCTAssertEqualObjects(history2[0].sig, @"sig_b");
    
    [store close];
}

- (void)testPersistentStoreEmptyHistory {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:@"did:plc:nonexistent" includeNullified:NO error:&error];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 0);
    
    [store close];
}

- (void)testPersistentStoreOperationCount {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did = @"did:plc:count_test";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.data = @{};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did;
    op2.sig = @"sig2";
    op2.data = @{};
    
    XCTAssertEqual([store operationCountForDid:did error:&error], 0);
    
    [store appendOperation:op1 nullifyCIDs:@[] error:nil];
    XCTAssertEqual([store operationCountForDid:did error:&error], 1);
    
    [store appendOperation:op2 nullifyCIDs:@[] error:nil];
    XCTAssertEqual([store operationCountForDid:did error:&error], 2);
    
    [store close];
}

- (void)testPersistentStoreDeleteOperations {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did = @"did:plc:delete_test";
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = @"sig_to_delete";
    op.data = @{};
    
    [store appendOperation:op nullifyCIDs:@[] error:nil];
    XCTAssertEqual([store operationCountForDid:did error:&error], 1);
    
    BOOL deleted = [store deleteOperationsForDid:did error:&error];
    XCTAssertTrue(deleted);
    XCTAssertEqual([store operationCountForDid:did error:&error], 0);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertEqual(history.count, 0);
    
    [store close];
}

- (void)testMockStoreAppendAndGetHistory {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    NSString *did = @"did:plc:test1";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.data = @{@"foo": @"bar"};
    
    NSError *error = nil;
    BOOL success = [store appendOperation:op1 nullifyCIDs:@[] error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 1);
    XCTAssertEqualObjects(history[0].sig, @"sig1");
}

- (void)testMockStoreMultipleDIDs {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    NSString *did1 = @"did:plc:test1";
    NSString *did2 = @"did:plc:test2";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did1;
    op1.sig = @"sig1";
    op1.data = @{};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did2;
    op2.sig = @"sig2";
    op2.data = @{};
    
    [store appendOperation:op1 nullifyCIDs:@[] error:nil];
    [store appendOperation:op2 nullifyCIDs:@[] error:nil];
    
    NSArray<PLCOperation *> *history1 = [store getHistoryForDID:did1 includeNullified:NO error:nil];
    NSArray<PLCOperation *> *history2 = [store getHistoryForDID:did2 includeNullified:NO error:nil];
    
    XCTAssertEqual(history1.count, 1);
    XCTAssertEqualObjects(history1[0].sig, @"sig1");
    
    XCTAssertEqual(history2.count, 1);
    XCTAssertEqualObjects(history2[0].sig, @"sig2");
}

- (void)testMockStoreEmptyHistory {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    NSArray<PLCOperation *> *history = [store getHistoryForDID:@"did:plc:nonexistent" includeNullified:NO error:nil];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 0);
}

@end
