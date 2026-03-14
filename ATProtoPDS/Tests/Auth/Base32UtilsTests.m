// Tests for Base32Utils: RFC 4648 Base32 encoding and decoding.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Auth/Base32Utils.h"

@interface Base32UtilsTests : XCTestCase
@end

@implementation Base32UtilsTests

#pragma mark - Decode Known Vectors (RFC 4648 §10)

- (void)testDecodeEmptyString {
    NSData *result = [Base32Utils dataFromBase32String:@""];
    // Empty string is a valid input; result must be empty or nil (both are acceptable)
    if (result) {
        XCTAssertEqual(result.length, (NSUInteger)0);
    }
}

- (void)testDecodeKnownVector_f {
    // "f" → "MY" (or "MY======" with padding)
    NSData *expected = [@"f" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *decoded = [Base32Utils dataFromBase32String:@"MY"];
    XCTAssertEqualObjects(decoded, expected, @"'MY' must decode to 'f'");
}

- (void)testDecodeKnownVector_foo {
    // "foo" → "MZXQ" (no padding)
    NSData *expected = [@"foo" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *decoded = [Base32Utils dataFromBase32String:@"MZXQ"];
    XCTAssertEqualObjects(decoded, expected, @"'MZXQ' must decode to 'foo'");
}

- (void)testDecodeKnownVector_foobar {
    // "foobar" → "MZXW6YTBOI"
    NSData *expected = [@"foobar" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *decoded = [Base32Utils dataFromBase32String:@"MZXW6YTBOI"];
    XCTAssertEqualObjects(decoded, expected);
}

- (void)testDecodeIgnoresPaddingChars {
    // "foo" encoded with padding
    NSData *expected = [@"foo" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *decoded = [Base32Utils dataFromBase32String:@"MZXQ===="];
    XCTAssertEqualObjects(decoded, expected, @"Padding characters must be stripped before decoding");
}

- (void)testDecodeLowercaseInput {
    // Should be case-insensitive
    NSData *upper = [Base32Utils dataFromBase32String:@"MZXQ"];
    NSData *lower = [Base32Utils dataFromBase32String:@"mzxq"];
    XCTAssertEqualObjects(upper, lower, @"Base32 decode must be case-insensitive");
}

- (void)testDecodeNilInputReturnsNil {
    NSData *result = [Base32Utils dataFromBase32String:nil];
    XCTAssertNil(result);
}

#pragma mark - Encode

- (void)testEncodeKnownVector_foo {
    NSData *input = [@"foo" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [Base32Utils base32StringFromData:input];
    // RFC 4648: "foo" → "MZXQ"
    XCTAssertEqualObjects(encoded, @"MZXQ");
}

- (void)testEncodeKnownVector_foobar {
    NSData *input = [@"foobar" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [Base32Utils base32StringFromData:input];
    XCTAssertEqualObjects(encoded, @"MZXW6YTBOI");
}

#pragma mark - Round-Trip

- (void)testEncodeDecodeRoundTrip {
    const uint8_t rawBytes[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE };
    NSData *original = [NSData dataWithBytes:rawBytes length:sizeof(rawBytes)];
    NSString *encoded = [Base32Utils base32StringFromData:original];
    XCTAssertNotNil(encoded);
    NSData *decoded = [Base32Utils dataFromBase32String:encoded];
    XCTAssertEqualObjects(decoded, original, @"Encode→Decode round-trip must recover original bytes");
}

@end
