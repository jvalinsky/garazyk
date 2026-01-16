#import <Foundation/Foundation.h>
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "../../Sources/PLC/PLCOperation.h"
#import "../../Sources/PLC/PLCMockStore.h"

@interface PLCStoreTests : XCTestCase
@end

@implementation PLCStoreTests

- (void)testMockStoreAppendAndGetHistory {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    NSString *did = @"did:plc:test1";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.data = @{@"foo": @"bar"};
    
    NSError *error = nil;
    BOOL success = [store appendOperation:op1 error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did error:&error];
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
    
    [store appendOperation:op1 error:nil];
    [store appendOperation:op2 error:nil];
    
    NSArray<PLCOperation *> *history1 = [store getHistoryForDID:did1 error:nil];
    NSArray<PLCOperation *> *history2 = [store getHistoryForDID:did2 error:nil];
    
    XCTAssertEqual(history1.count, 1);
    XCTAssertEqualObjects(history1[0].sig, @"sig1");
    
    XCTAssertEqual(history2.count, 1);
    XCTAssertEqualObjects(history2[0].sig, @"sig2");
}

- (void)testMockStoreEmptyHistory {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    NSArray<PLCOperation *> *history = [store getHistoryForDID:@"did:plc:nonexistent" error:nil];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 0);
}

@end
