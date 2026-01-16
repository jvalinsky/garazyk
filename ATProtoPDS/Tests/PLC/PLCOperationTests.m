#import <Foundation/Foundation.h>
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "../../Sources/PLC/PLCOperation.h"

@interface PLCOperationTests : XCTestCase
@end

@implementation PLCOperationTests

- (void)testParseFromDictionary {
    NSDictionary *json = @{
        @"did": @"did:plc:123",
        @"prev": @"cid:456",
        @"sig": @"sig789",
        @"type": @"plc_operation"
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(op);
    XCTAssertEqualObjects(op.did, @"did:plc:123");
    XCTAssertEqualObjects(op.prev, @"cid:456");
    XCTAssertEqualObjects(op.sig, @"sig789");
    XCTAssertEqualObjects(op.data[@"type"], @"plc_operation");
}

- (void)testParseFromDictionaryMissingOptionalPrev {
    NSDictionary *json = @{
        @"did": @"did:plc:123",
        @"sig": @"sig789",
        @"type": @"plc_operation"
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(op);
    XCTAssertEqualObjects(op.did, @"did:plc:123");
    XCTAssertNil(op.prev);
    XCTAssertEqualObjects(op.sig, @"sig789");
    XCTAssertEqualObjects(op.data[@"type"], @"plc_operation");
}

- (void)testParseFromDictionaryMissingRequiredField {
    NSDictionary *json = @{
        @"did": @"did:plc:123"
        // missing sig
    };
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    
    XCTAssertNotNil(error);
    XCTAssertNil(op);
}

@end
