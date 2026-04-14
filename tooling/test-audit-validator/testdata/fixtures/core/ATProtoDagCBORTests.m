#import <XCTest/XCTest.h>

// Sample Core domain test with round-trip property
@interface ATProtoDagCBORTests : XCTestCase
@end

@implementation ATProtoDagCBORTests

- (void)testCBORRoundTrip {
    // Test that encoding and decoding produces the same result
    NSData *original = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *encoded = [self encodeCBOR:original];
    NSData *decoded = [self decodeCBOR:encoded];
    XCTAssertEqualObjects(original, decoded, @"Round-trip should preserve data");
}

- (void)testCBOREncodeNilValue {
    NSData *result = [self encodeCBOR:nil];
    XCTAssertNotNil(result);
}

- (void)testCBORDecodeInvalidData {
    NSData *garbage = [@"not cbor" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertThrows([self decodeCBOR:garbage], @"Should throw on invalid CBOR");
}

- (void)testCBORMapSerialization {
    NSDictionary *input = @{@"key": @"value", @"count": @42};
    NSData *encoded = [self encodeCBOR:input];
    NSDictionary *decoded = [self decodeCBORMap:encoded];
    XCTAssertEqualObjects(input[@"key"], decoded[@"key"]);
    XCTAssertEqualObjects(input[@"count"], decoded[@"count"]);
}

@end
