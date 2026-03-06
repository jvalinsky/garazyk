#import <XCTest/XCTest.h>
#import "Core/Base58.h"

@interface Base58Tests : XCTestCase
@end

@implementation Base58Tests

- (void)testEncode {
    NSData *data = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [Base58 encode:data];
    XCTAssertEqualObjects(encoded, @"StV1DL6CwTryKyV");
    
    NSData *empty = [NSData data];
    XCTAssertEqualObjects([Base58 encode:empty], @"");
}

- (void)testDecode {
    NSString *string = @"StV1DL6CwTryKyV";
    NSData *decoded = [Base58 decode:string];
    NSString *decodedString = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(decodedString, @"hello world");
    
    XCTAssertEqualObjects([Base58 decode:@""], [NSData data]);
}

- (void)testInvalidDecode {
    XCTAssertNil([Base58 decode:@"0"]); // '0' is not in alphabet
    XCTAssertNil([Base58 decode:@"I"]); // 'I' is not in alphabet
    XCTAssertNil([Base58 decode:@"l"]); // 'l' is not in alphabet
    XCTAssertNil([Base58 decode:@"O"]); // 'O' is not in alphabet
}

- (void)testEncodeDecodeMatchExpectedValuesForLeadingZeros {
    // 0x00 0x00 0xff
    uint8_t bytes[] = {0x00, 0x00, 0xff};
    NSData *data = [NSData dataWithBytes:bytes length:3];
    // Leading zeros -> '1' in Base58
    // 0xff -> '5Q' (Wait, is it?)
    // 255 = 4 * 58 + 23 ('Q') -> 4 ('5')
    // So 0xff -> '5Q' ? No, 58*4 = 232. 255-232=23. Index 4 is '5', index 23 is 'Q'.
    // 0x00 -> '1'
    // So "115Q"
    
    NSString *encoded = [Base58 encode:data];
    XCTAssertEqualObjects(encoded, @"115Q");
    
    NSData *decoded = [Base58 decode:@"115Q"];
    XCTAssertEqualObjects(decoded, data);
}

- (void)testLargeInputRejection {
    NSMutableData *largeData = [NSMutableData dataWithCapacity:64 * 1024 + 1];
    uint8_t byte = 0x41; // 'A'
    for (NSUInteger i = 0; i < 64 * 1024 + 1; i++) {
        [largeData appendBytes:&byte length:1];
    }
    XCTAssertNil([Base58 encode:largeData], @"Should reject input > 64KB");
}

- (void)testLargeStringRejection {
    NSMutableString *largeString = [NSMutableString string];
    for (NSUInteger i = 0; i < 64 * 1024 + 1; i++) {
        [largeString appendString:@"1"];
    }
    XCTAssertNil([Base58 decode:largeString], @"Should reject string > 64KB");
}

- (void)testMaxValidInput {
    // Use a reasonable size that completes quickly (Base58 is O(n²) in worst case)
    NSMutableData *maxData = [NSMutableData dataWithLength:1024];
    memset(maxData.mutableBytes, 0x41, 1024);
    NSString *encoded = [Base58 encode:maxData];
    XCTAssertNotNil(encoded, @"Should accept 1KB input");
    XCTAssertGreaterThan(encoded.length, (NSUInteger)0);
    
    NSData *decoded = [Base58 decode:encoded];
    XCTAssertNotNil(decoded, @"Should decode valid output");
    XCTAssertEqualObjects(decoded, maxData, @"Decoded data should match original input");
}

@end
