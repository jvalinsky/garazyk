#import <XCTest/XCTest.h>
#import "Identity/Base58.h"

@interface Base58Tests : XCTestCase
@end

@implementation Base58Tests

- (void)testEncodeEmpty {
    NSData *empty = [NSData data];
    NSString *encoded = [Base58 encodeData:empty];
    XCTAssertEqualObjects(encoded, @"");
}

- (void)testDecodeEmpty {
    NSData *decoded = [Base58 decodeString:@""];
    XCTAssertEqual(decoded.length, 0);
}

- (void)testEncodeHelloWorld {
    // "Hello World" in Base58 should be "JxF12TrwUP45BMd"
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [Base58 encodeData:data];
    XCTAssertEqualObjects(encoded, @"JxF12TrwUP45BMd");
}

- (void)testDecodeHelloWorld {
    NSData *decoded = [Base58 decodeString:@"JxF12TrwUP45BMd"];
    NSString *str = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"Hello World");
}

- (void)testEncodeWithLeadingZeros {
    // 3 zero bytes should encode to "111"
    uint8_t bytes[] = {0, 0, 0};
    NSData *data = [NSData dataWithBytes:bytes length:3];
    NSString *encoded = [Base58 encodeData:data];
    XCTAssertTrue([encoded hasPrefix:@"111"]);
}

- (void)testDecodeWithLeadingOnes {
    // "111" should decode to 3 zero bytes
    NSData *decoded = [Base58 decodeString:@"111"];
    const uint8_t *bytes = decoded.bytes;
    XCTAssertEqual(decoded.length, 3);
    XCTAssertEqual(bytes[0], 0);
    XCTAssertEqual(bytes[1], 0);
    XCTAssertEqual(bytes[2], 0);
}

- (void)testMultibaseEncode {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *multibase = [Base58 encodeMultibase:data];
    XCTAssertTrue([multibase hasPrefix:@"z"]);
}

- (void)testMultibaseDecode {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *multibase = [Base58 encodeMultibase:data];
    NSData *decoded = [Base58 decodeMultibase:multibase];
    XCTAssertEqualObjects(decoded, data);
}

- (void)testMultibaseInvalidPrefix {
    // Non-'z' prefix should return nil
    NSData *decoded = [Base58 decodeMultibase:@"mJxF12TrwUP45BMd"]; // 'm' = base64
    XCTAssertNil(decoded);
}

- (void)testRoundTrip {
    // Test various data lengths
    for (int i = 0; i < 100; i++) {
        NSMutableData *data = [NSMutableData dataWithLength:i];
        uint8_t *bytes = data.mutableBytes;
        for (int j = 0; j < i; j++) {
            bytes[j] = (uint8_t)(arc4random() & 0xFF);
        }
        
        NSString *encoded = [Base58 encodeData:data];
        NSData *decoded = [Base58 decodeString:encoded];
        
        XCTAssertEqualObjects(decoded, data, @"Round trip failed for length %d", i);
    }
}

- (void)testBitcoinTestVector {
    // Test vector from Bitcoin
    // hex: 61 -> base58: "2g"
    uint8_t bytes[] = {0x61};
    NSData *data = [NSData dataWithBytes:bytes length:1];
    NSString *encoded = [Base58 encodeData:data];
    XCTAssertEqualObjects(encoded, @"2g");
}

@end
