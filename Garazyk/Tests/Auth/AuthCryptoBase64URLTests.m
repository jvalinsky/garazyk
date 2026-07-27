// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/Crypto/AuthCryptoBase64URL.h"

@interface AuthCryptoBase64URLTests : XCTestCase
@end

@implementation AuthCryptoBase64URLTests

#pragma mark - Encode

- (void)testEncode_EmptyData_ReturnsEmptyString {
    NSData *data = [NSData data];
    NSString *result = [AuthCryptoBase64URL encode:data];
    XCTAssertEqualObjects(result, @"");
}

- (void)testEncode_SingleByte_EncodesCorrectly {
    // 0xFB → base64 → +w → base64url → -w
    uint8_t byte = 0xFB;
    NSData *data = [NSData dataWithBytes:&byte length:1];
    NSString *result = [AuthCryptoBase64URL encode:data];
    XCTAssertEqualObjects(result, @"-w");
}

- (void)testEncode_ReplacesPlusWithMinus {
    // 0xFB 0xFF → base64: +/8= → base64url: -_8
    uint8_t bytes[] = {0xFB, 0xFF};
    NSData *data = [NSData dataWithBytes:bytes length:2];
    NSString *result = [AuthCryptoBase64URL encode:data];
    XCTAssertFalse([result containsString:@"+"], @"Should not contain +");
    XCTAssertTrue([result containsString:@"-"], @"Should use - instead of +");
}

- (void)testEncode_ReplacesSlashWithUnderscore {
    // 0xFB 0xFF → base64: +/8= → base64url: -_8
    uint8_t bytes[] = {0xFB, 0xFF};
    NSData *data = [NSData dataWithBytes:bytes length:2];
    NSString *result = [AuthCryptoBase64URL encode:data];
    XCTAssertFalse([result containsString:@"/"], @"Should not contain /");
    XCTAssertTrue([result containsString:@"_"], @"Should use _ instead of /");
}

- (void)testEncode_NoPadding {
    // 3 bytes → 4 base64 chars (no padding needed at all for 3-byte input)
    uint8_t bytes[] = {0x01, 0x02, 0x03};
    NSData *data = [NSData dataWithBytes:bytes length:3];
    NSString *result = [AuthCryptoBase64URL encode:data];
    XCTAssertFalse([result hasSuffix:@"="], @"Should not have padding");
}

- (void)testEncode_SHA256Digest_ProducesKnownLength {
    // SHA-256 digest is 32 bytes → 43 base64url chars (32*8/6 = 42.67 → 43 chars, no padding)
    NSMutableData *data = [NSMutableData dataWithLength:32];
    NSString *result = [AuthCryptoBase64URL encode:data];
    XCTAssertEqual(result.length, (NSUInteger)43);
}

- (void)testEncode_KnownVector {
    // RFC 4648 Test Vectors: 0x14FB9C03D97E → base64url without padding
    uint8_t bytes[] = {0x14, 0xFB, 0x9C, 0x03, 0xD9, 0x7E};
    NSData *data = [NSData dataWithBytes:bytes length:6];
    NSString *result = [AuthCryptoBase64URL encode:data];
    // Standard base64 of this is FPucA9l+
    XCTAssertEqualObjects(result, @"FPucA9l-");
}

#pragma mark - Decode

- (void)testDecode_EmptyString_ReturnsNil {
    NSData *result = [AuthCryptoBase64URL decode:@""];
    XCTAssertNil(result);
}

- (void)testDecode_ValidString_DecodesCorrectly {
    NSString *encoded = [AuthCryptoBase64URL encode:[@"Hello World" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *decoded = [AuthCryptoBase64URL decode:encoded];
    XCTAssertNotNil(decoded);
    NSString *result = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, @"Hello World");
}

- (void)testDecode_KnownVector {
    NSString *encoded = @"FPucA9l-";
    NSData *decoded = [AuthCryptoBase64URL decode:encoded];
    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.length, (NSUInteger)6);
    uint8_t expected[] = {0x14, 0xFB, 0x9C, 0x03, 0xD9, 0x7E};
    NSData *expectedData = [NSData dataWithBytes:expected length:6];
    XCTAssertEqualObjects(decoded, expectedData);
}

- (void)testDecode_NilInput_ReturnsNil {
    NSData *result = [AuthCryptoBase64URL decode:(NSString *)nil];
    XCTAssertNil(result);
}

- (void)testDecode_InvalidCharacters_ReturnsNil {
    // Invalid character (exclamation) is not valid base64 or base64url
    NSData *result = [AuthCryptoBase64URL decode:@"FPucA9!!"];
    XCTAssertNil(result, @"Invalid characters should return nil");
}

- (void)testDecode_HasPadding_ReturnsNil {
    // Base64url must not have padding
    NSData *result = [AuthCryptoBase64URL decode:@"FPucA9k="];
    XCTAssertNil(result, @"Padding not allowed in base64url");
}

#pragma mark - Round-trip

- (void)testRoundTrip_VariousInputs {
    NSArray<NSData *> *inputs = @[
        [@"a" dataUsingEncoding:NSUTF8StringEncoding],
        [@"Hello" dataUsingEncoding:NSUTF8StringEncoding],
        [NSData dataWithBytes:(uint8_t[]){0x00} length:1],
        [NSData dataWithBytes:(uint8_t[]){0xFF, 0x00, 0xFF} length:3],
        [NSData dataWithBytes:(uint8_t[]){0x00, 0x00, 0x00, 0x00} length:4],
        [@"The quick brown fox jumps over the lazy dog" dataUsingEncoding:NSUTF8StringEncoding]
    ];

    for (NSData *input in inputs) {
        NSString *encoded = [AuthCryptoBase64URL encode:input];
        NSData *decoded = [AuthCryptoBase64URL decode:encoded];
        XCTAssertNotNil(decoded, @"Round-trip decode should succeed for input of length %lu", (unsigned long)input.length);
        XCTAssertEqualObjects(decoded, input, @"Round-trip should preserve data for input of length %lu", (unsigned long)input.length);
    }
}

- (void)testRoundTrip_EmptyData {
    NSData *input = [NSData data];
    NSString *encoded = [AuthCryptoBase64URL encode:input];
    XCTAssertEqualObjects(encoded, @"");
}

- (void)testRoundTrip_RandomBytes {
    for (NSUInteger len = 1; len <= 64; len++) {
        NSMutableData *data = [NSMutableData dataWithLength:len];
        arc4random_buf(data.mutableBytes, len);
        NSString *encoded = [AuthCryptoBase64URL encode:data];
        NSData *decoded = [AuthCryptoBase64URL decode:encoded];
        XCTAssertNotNil(decoded);
        XCTAssertEqualObjects(decoded, data, @"Round-trip failed for length %lu", (unsigned long)len);
    }
}

@end
