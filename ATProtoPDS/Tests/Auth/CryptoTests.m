#import <XCTest/XCTest.h>
#import "Auth/CryptoUtils.h"
#import <CommonCrypto/CommonCrypto.h>

@interface CryptoTests : XCTestCase
@end

@implementation CryptoTests

- (void)testSHA256MatchesExpectedHex {
    NSData *input = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hash = [CryptoUtils sha256:input];
    NSString *hex = [CryptoUtils hexStringFromData:hash];
    XCTAssertEqualObjects(hex, @"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
}

- (void)testHMACSHA1MatchesExpectedHex {
    NSData *key = [@"key" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [@"data" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hmac = [CryptoUtils hmacSHA1WithKey:key data:data];
    NSString *hex = [CryptoUtils hexStringFromData:hmac];
    XCTAssertEqualObjects(hex, @"104152c5bfdca07bc633eebd46199f0255c9f49d");
}

- (void)testHMACSHA256 {
    // RFC 4231 Test Case 1: HMAC-SHA256
    // Key: 0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b (20 bytes)
    // Data: "Hi There"
    // Expected: b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7
    const unsigned char keyBytes[] = {0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b};
    NSData *key = [NSData dataWithBytes:keyBytes length:sizeof(keyBytes)];
    NSData *data = [@"Hi There" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hmac = [CryptoUtils hmacSHA256WithKey:key data:data];
    XCTAssertNotNil(hmac);
    XCTAssertEqual(hmac.length, CC_SHA256_DIGEST_LENGTH);
    NSString *hex = [CryptoUtils hexStringFromData:hmac];
    XCTAssertEqualObjects(hex, @"b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
}

- (void)testRandomBytes {
    NSData *r1 = [CryptoUtils randomBytes:16];
    NSData *r2 = [CryptoUtils randomBytes:16];
    XCTAssertEqual(r1.length, 16);
    XCTAssertEqual(r2.length, 16);
    XCTAssertNotEqualObjects(r1, r2, @"Random bytes should be different");
}

#pragma mark - Constant-Time Comparison Tests

- (void)testConstantTimeCompareEqual {
    XCTAssertTrue([CryptoUtils constantTimeCompare:@"abc123xyz" to:@"abc123xyz"]);
    XCTAssertTrue([CryptoUtils constantTimeCompare:@"" to:@""]);
    XCTAssertTrue([CryptoUtils constantTimeCompare:@"a" to:@"a"]);
    XCTAssertTrue([CryptoUtils constantTimeCompare:@"dpop_thumbprint_12345" to:@"dpop_thumbprint_12345"]);
}

- (void)testConstantTimeCompareNotEqual {
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"abc123xyz" to:@"abc123xya"]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"abc123xyz" to:@"xbc123xyz"]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"abc123xyz" to:@"abc123xyZ"]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"abc" to:@"abd"]);
}

- (void)testConstantTimeCompareDifferentLength {
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"abc" to:@"abcd"]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"abcd" to:@"abc"]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"" to:@"a"]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"a" to:@""]);
}

- (void)testConstantTimeCompareNilHandling {
    XCTAssertFalse([CryptoUtils constantTimeCompare:nil to:@"abc"]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"abc" to:nil]);
    XCTAssertTrue([CryptoUtils constantTimeCompare:nil to:nil]);
}

- (void)testConstantTimeCompareSpecialCharacters {
    XCTAssertTrue([CryptoUtils constantTimeCompare:@"base64/url+encoded==" to:@"base64/url+encoded=="]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"base64/url+encoded==" to:@"base64/url+encoded=!"]);
    XCTAssertTrue([CryptoUtils constantTimeCompare:@"did:plc:abc123" to:@"did:plc:abc123"]);
    XCTAssertFalse([CryptoUtils constantTimeCompare:@"did:plc:abc123" to:@"did:plc:abc124"]);
}

@end
