#import <XCTest/XCTest.h>
#import "TutorialBase64URL.h"

@interface TutorialBase64URLTests : XCTestCase
@end

@implementation TutorialBase64URLTests

- (void)testEncodeEmptyData {
    NSData *data = [NSData data];
    NSString *result = [TutorialBase64URL encode:data];
    XCTAssertEqualObjects(result, @"", @"Empty data should encode to empty string");
}

- (void)testEncodeSingleByte {
    NSData *data = [NSData dataWithBytes:"\x00" length:1];
    NSString *result = [TutorialBase64URL encode:data];
    XCTAssertEqualObjects(result, @"AA", @"Single zero byte should encode to AA");
}

- (void)testEncodeHelloWorld {
    NSData *data = [@"Hello, World!" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *result = [TutorialBase64URL encode:data];
    XCTAssertEqualObjects(result, @"SGVsbG8sIFdvcmxkIQ", @"Hello World should encode correctly without padding");
}

- (void)testEncodeNoPadding {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *result = [TutorialBase64URL encode:data];
    XCTAssertFalse([result hasSuffix:@"="], @"Base64URL encoding should not include padding");
}

- (void)testDecodeEmptyString {
    NSData *result = [TutorialBase64URL decode:@""];
    XCTAssertEqual(result.length, 0, @"Empty string should decode to empty data");
}

- (void)testDecodeRoundTrip {
    NSString *original = @"The quick brown fox jumps over the lazy dog";
    NSData *originalData = [original dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [TutorialBase64URL encode:originalData];
    NSData *decoded = [TutorialBase64URL decode:encoded];
    XCTAssertEqualObjects(decoded, originalData, @"Round-trip encode/decode should produce original data");
}

- (void)testDecodeWithPadding {
    NSData *result = [TutorialBase64URL decode:@"SGVsbG8sIFdvcmxkIQ=="];
    NSData *expected = [@"Hello, World!" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, expected, @"Should decode base64 with padding");
}

- (void)testDecodeBinaryData {
    unsigned char bytes[32];
    for (int i = 0; i < 32; i++) bytes[i] = (unsigned char)(i * 8 + 7);
    NSData *original = [NSData dataWithBytes:bytes length:32];
    NSString *encoded = [TutorialBase64URL encode:original];
    NSData *decoded = [TutorialBase64URL decode:encoded];
    XCTAssertEqualObjects(decoded, original, @"Binary data round-trip should be exact");
}

@end
