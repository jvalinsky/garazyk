#import <XCTest/XCTest.h>
#import "Network/XrpcMethodRegistry.h"

@interface XrpcMethodRegistryTests : XCTestCase
@end

@implementation XrpcMethodRegistryTests

- (void)testPublicKeyBytesFromMultibaseDecodesBase58 {
    NSError *error = nil;
    NSString *key = @"zQ3shZc2QzApp2oymGvQbzP8eKheVshBHbU4ZYjeXqwSKEn6N";
    NSData *bytes = [XrpcMethodRegistry publicKeyBytesFromMultibase:key error:&error];

    XCTAssertNotNil(bytes, @"Decoded bytes should exist for a valid base58 publicKeyMultibase");
    XCTAssertNil(error, @"No error should be produced for valid input");
    XCTAssertGreaterThan(bytes.length, 0, @"Result must not be empty");
}

@end
