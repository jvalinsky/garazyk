// Tests for ATProtoBase32: ATProto sortable-alphabet Base32 (alphabet "234567abcdefghijklmnopqrstuvwxyz").

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Core/ATProtoBase32.h"

@interface ATProtoBase32Tests : XCTestCase
@end

@implementation ATProtoBase32Tests

#pragma mark - Encoding

- (void)testEncodeDataReturnsNonEmptyString {
    NSData *data = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [ATProtoBase32 encodeData:data];
    XCTAssertNotNil(encoded);
    XCTAssertGreaterThan(encoded.length, (NSUInteger)0);
}

- (void)testEncodeEmptyDataReturnsEmptyString {
    NSString *encoded = [ATProtoBase32 encodeData:[NSData data]];
    XCTAssertNotNil(encoded);
    XCTAssertEqual(encoded.length, (NSUInteger)0,
                   @"Encoding empty data must return an empty string");
}

- (void)testEncodedStringUsesATProtoAlphabet {
    // ATProto uses sortable alphabet: 2-7, a-z
    NSData *data = [NSData dataWithBytes:"\xff\xfe\xfd\xfc\xfb\xfa\xf9\xf8" length:8];
    NSString *encoded = [ATProtoBase32 encodeData:data];
    NSCharacterSet *validChars = [NSCharacterSet
                                  characterSetWithCharactersInString:
                                  @"234567abcdefghijklmnopqrstuvwxyz"];
    NSCharacterSet *invalidChars = [validChars invertedSet];
    NSRange r = [encoded rangeOfCharacterFromSet:invalidChars];
    XCTAssertEqual(r.location, NSNotFound,
                   @"ATProto Base32 must only use chars from '234567abcdefghijklmnopqrstuvwxyz'");
}

- (void)testEncodedStringIsLowercase {
    NSData *data = [@"Test String" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [ATProtoBase32 encodeData:data];
    XCTAssertEqualObjects(encoded, [encoded lowercaseString],
                          @"ATProto Base32 output must be lowercase");
}

#pragma mark - Decoding

- (void)testDecodeRoundTrip {
    NSData *original = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [ATProtoBase32 encodeData:original];
    NSData *decoded = [ATProtoBase32 decodeString:encoded];
    XCTAssertEqualObjects(decoded, original,
                          @"Decode(Encode(data)) must recover original data");
}

- (void)testDecodeEightByteRoundTrip {
    uint8_t bytes[8] = {0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF};
    NSData *original = [NSData dataWithBytes:bytes length:8];
    NSString *encoded = [ATProtoBase32 encodeData:original];
    NSData *decoded = [ATProtoBase32 decodeString:encoded];
    XCTAssertEqualObjects(decoded, original);
}

- (void)testDecodeEmptyStringReturnsEmptyData {
    NSData *decoded = [ATProtoBase32 decodeString:@""];
    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.length, (NSUInteger)0,
                   @"Decoding empty string must return empty data");
}

- (void)testDecodeInvalidCharacterReturnsNil {
    // '@' is not in ATProto Base32 alphabet
    NSData *decoded = [ATProtoBase32 decodeString:@"@@@@@@@@"];
    XCTAssertNil(decoded,
                 @"Decoding an invalid Base32 string must return nil");
}

- (void)testDecodeNilReturnsNil {
    NSData *decoded = [ATProtoBase32 decodeString:nil];
    XCTAssertNil(decoded,
                 @"Decoding nil must return nil without crashing");
}

#pragma mark - TID-style encode (13 chars for 8 bytes)

- (void)testEightBytesEncodeToThirteenChars {
    // TIDs are 64-bit (8 bytes) encoded as 13 ATProto Base32 chars
    uint8_t bytes[8] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01};
    NSData *data = [NSData dataWithBytes:bytes length:8];
    NSString *encoded = [ATProtoBase32 encodeData:data];
    // 8 bytes → ceil(8 * 8 / 5) = 13 chars (without padding)
    XCTAssertEqual(encoded.length, (NSUInteger)13,
                   @"8 bytes must encode to 13 ATProto Base32 characters");
}

@end
