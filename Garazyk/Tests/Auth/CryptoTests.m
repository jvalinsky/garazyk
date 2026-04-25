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

#pragma mark - SHA-256 Edge Cases

- (void)testSHA256NilInput {
    NSData *result = [CryptoUtils sha256:nil];
    XCTAssertNil(result);
}

- (void)testSHA256EmptyData {
    NSData *empty = [NSData data];
    NSData *hash = [CryptoUtils sha256:empty];
    XCTAssertNotNil(hash);
    XCTAssertEqual(hash.length, 32);
    // SHA-256 of empty string: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    NSString *hex = [CryptoUtils hexStringFromData:hash];
    XCTAssertEqualObjects(hex, @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
}

#pragma mark - HMAC Edge Cases

- (void)testHMACSHA1NilKey {
    NSData *data = [@"data" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = [CryptoUtils hmacSHA1WithKey:nil data:data];
    XCTAssertNil(result);
}

- (void)testHMACSHA1NilData {
    NSData *key = [@"key" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = [CryptoUtils hmacSHA1WithKey:key data:nil];
    XCTAssertNil(result);
}

- (void)testHMACSHA256NilKey {
    NSData *data = [@"data" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = [CryptoUtils hmacSHA256WithKey:nil data:data];
    XCTAssertNil(result);
}

- (void)testHMACSHA256NilData {
    NSData *key = [@"key" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = [CryptoUtils hmacSHA256WithKey:key data:nil];
    XCTAssertNil(result);
}

#pragma mark - Random Bytes Edge Cases

- (void)testRandomBytesZeroLength {
    NSData *result = [CryptoUtils randomBytes:0];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, 0);
}

#pragma mark - Hex String

- (void)testHexStringFromDataEmpty {
    NSData *empty = [NSData data];
    NSString *hex = [CryptoUtils hexStringFromData:empty];
    XCTAssertEqualObjects(hex, @"");
}

- (void)testHexStringFromDataKnownValue {
    unsigned char bytes[] = {0x00, 0xFF, 0xAB, 0x01};
    NSData *data = [NSData dataWithBytes:bytes length:4];
    NSString *hex = [CryptoUtils hexStringFromData:data];
    XCTAssertEqualObjects(hex, @"00ffab01");
}

#pragma mark - Base64URL

- (void)testBase64URLEncodeDecodeRoundTrip {
    for (NSUInteger len = 1; len < 64; len++) {
        NSMutableData *data = [NSMutableData dataWithLength:len];
        arc4random_buf(data.mutableBytes, len);
        NSString *encoded = [CryptoUtils base64URLEncode:data];
        NSData *decoded = [CryptoUtils base64URLDecode:encoded];
        XCTAssertEqualObjects(decoded, data, @"Round-trip failed for %lu bytes", (unsigned long)len);
    }
}

- (void)testBase64URLEncodeNoPadding {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [CryptoUtils base64URLEncode:data];
    XCTAssertFalse([encoded containsString:@"="], @"Base64URL should not have padding");
}

#pragma mark - AES Encryption

- (void)testEncryptDecryptRoundTrip {
    NSData *key = [CryptoUtils randomBytes:32];
    NSData *plaintext = [@"Hello, World! This is a test of AES-256-CBC encryption." dataUsingEncoding:NSUTF8StringEncoding];
    NSData *encrypted = [CryptoUtils encryptData:plaintext withKey:key];
    XCTAssertNotNil(encrypted);
    XCTAssertTrue(encrypted.length > plaintext.length, @"Ciphertext should be larger due to IV and padding");

    NSData *decrypted = [CryptoUtils decryptData:encrypted withKey:key];
    XCTAssertNotNil(decrypted);
    XCTAssertEqualObjects(decrypted, plaintext);
}

- (void)testEncryptWithInvalidKeySize {
    NSData *shortKey = [NSData dataWithBytes:"\x00\x01\x02" length:3];
    NSData *plaintext = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = [CryptoUtils encryptData:plaintext withKey:shortKey];
    XCTAssertNil(result, @"Encryption should fail with non-32-byte key");
}

- (void)testDecryptWithInvalidKeySize {
    NSData *shortKey = [NSData dataWithBytes:"\x00\x01\x02" length:3];
    NSData *fakeCipher = [NSData dataWithBytes:"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" length:16];
    NSData *result = [CryptoUtils decryptData:fakeCipher withKey:shortKey];
    XCTAssertNil(result, @"Decryption should fail with non-32-byte key");
}

- (void)testDecryptWithTooShortData {
    NSData *key = [CryptoUtils randomBytes:32];
    NSData *shortData = [NSData dataWithBytes:"\x00\x01\x02" length:3];
    NSData *result = [CryptoUtils decryptData:shortData withKey:key];
    XCTAssertNil(result, @"Decryption should fail with data shorter than IV");
}

- (void)testEncryptDecryptEmptyData {
    NSData *key = [CryptoUtils randomBytes:32];
    NSData *empty = [NSData data];
    NSData *encrypted = [CryptoUtils encryptData:empty withKey:key];
    XCTAssertNotNil(encrypted);
    NSData *decrypted = [CryptoUtils decryptData:encrypted withKey:key];
    XCTAssertNotNil(decrypted);
    XCTAssertEqualObjects(decrypted, empty);
}

#pragma mark - PBKDF2 Key Derivation

- (void)testDeriveKeyFromPassword {
    NSData *salt = [CryptoUtils randomBytes:16];
    NSData *key = [CryptoUtils deriveKeyFromPassword:@"testpassword" salt:salt];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32);
}

- (void)testDeriveKeyDeterministic {
    NSData *salt = [@"fixed-salt-1234" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *key1 = [CryptoUtils deriveKeyFromPassword:@"password" salt:salt];
    NSData *key2 = [CryptoUtils deriveKeyFromPassword:@"password" salt:salt];
    XCTAssertEqualObjects(key1, key2, @"Same password and salt should produce same key");
}

- (void)testDeriveKeyDifferentPasswords {
    NSData *salt = [@"fixed-salt-1234" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *key1 = [CryptoUtils deriveKeyFromPassword:@"password1" salt:salt];
    NSData *key2 = [CryptoUtils deriveKeyFromPassword:@"password2" salt:salt];
    XCTAssertNotEqualObjects(key1, key2, @"Different passwords should produce different keys");
}

- (void)testDeriveKeyDifferentSalts {
    NSData *salt1 = [@"salt-1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *salt2 = [@"salt-2" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *key1 = [CryptoUtils deriveKeyFromPassword:@"password" salt:salt1];
    NSData *key2 = [CryptoUtils deriveKeyFromPassword:@"password" salt:salt2];
    XCTAssertNotEqualObjects(key1, key2, @"Different salts should produce different keys");
}

@end
