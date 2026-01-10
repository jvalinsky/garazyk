#import <XCTest/XCTest.h>
#import "Auth/CryptoUtils.h"

@interface CryptoTests : XCTestCase
@end

@implementation CryptoTests

- (void)testSHA256 {
    NSData *input = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hash = [CryptoUtils sha256:input];
    NSString *hex = [CryptoUtils hexStringFromData:hash];
    XCTAssertEqualObjects(hex, @"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
}

- (void)testHMACSHA1 {
    NSData *key = [@"key" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [@"data" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hmac = [CryptoUtils hmacSHA1WithKey:key data:data];
    NSString *hex = [CryptoUtils hexStringFromData:hmac];
    XCTAssertEqualObjects(hex, @"104152c5bfdca07bc633eebd46199f0255c9f49d");
}

- (void)testHMACSHA256 {
    NSData *key = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [@"message" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hmac = [CryptoUtils HMACSHA256:data key:key];
    XCTAssertNotNil(hmac);
    XCTAssertEqual(hmac.length, CC_SHA256_DIGEST_LENGTH);
}

- (void)testRandomBytes {
    NSData *r1 = [CryptoUtils randomBytes:16];
    NSData *r2 = [CryptoUtils randomBytes:16];
    XCTAssertEqual(r1.length, 16);
    XCTAssertEqual(r2.length, 16);
    XCTAssertNotEqualObjects(r1, r2, @"Random bytes should be different");
}

@end
