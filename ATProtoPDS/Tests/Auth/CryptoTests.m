#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
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

#pragma mark - AES-256-GCM Encrypt/Decrypt Tests

- (NSData *)testKey32 {
    // Deterministic 32-byte key for testing
    const uint8_t keyBytes[32] = {
        0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,
        0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10,
        0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,
        0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f,0x20
    };
    return [NSData dataWithBytes:keyBytes length:32];
}

- (void)testEncryptDecryptRoundTrip {
    NSData *key = [self testKey32];
    NSData *plaintext = [@"Hello, ATProto PDS!" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ciphertext = [CryptoUtils encryptData:plaintext withKey:key];
    XCTAssertNotNil(ciphertext);
    // GCM format: version(1) || nonce(12) || tag(16) || ciphertext
    XCTAssertGreaterThan(ciphertext.length, (NSUInteger)(1 + 12 + 16));
    const uint8_t *bytes = ciphertext.bytes;
    XCTAssertEqual(bytes[0], (uint8_t)0x02, @"Version byte must be 0x02 for GCM");

    NSData *recovered = [CryptoUtils decryptData:ciphertext withKey:key];
    XCTAssertEqualObjects(recovered, plaintext);
}

- (void)testEncryptProducesDifferentCiphertextsEachCall {
    NSData *key = [self testKey32];
    NSData *plaintext = [@"same input" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ct1 = [CryptoUtils encryptData:plaintext withKey:key];
    NSData *ct2 = [CryptoUtils encryptData:plaintext withKey:key];
    XCTAssertNotNil(ct1);
    XCTAssertNotNil(ct2);
    XCTAssertNotEqualObjects(ct1, ct2, @"Random nonce must produce distinct ciphertexts");
}

- (void)testEncryptRejectsShortKey {
    NSData *shortKey = [NSData dataWithLength:16];
    NSData *plaintext = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([CryptoUtils encryptData:plaintext withKey:shortKey]);
}

- (void)testDecryptRejectsTamperedTag {
    NSData *key = [self testKey32];
    NSData *plaintext = [@"tamper test" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *ct = [[CryptoUtils encryptData:plaintext withKey:key] mutableCopy];
    // Flip a bit in the tag (bytes 13–28)
    uint8_t *bytes = ct.mutableBytes;
    bytes[15] ^= 0xFF;
    XCTAssertNil([CryptoUtils decryptData:ct withKey:key], @"Tampered tag must be rejected");
}

- (void)testDecryptRejectsTamperedCiphertext {
    NSData *key = [self testKey32];
    NSData *plaintext = [@"ciphertext tamper test" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *ct = [[CryptoUtils encryptData:plaintext withKey:key] mutableCopy];
    // Flip a bit in the ciphertext body (after version+nonce+tag = 29 bytes)
    uint8_t *bytes = ct.mutableBytes;
    if (ct.length > 29) bytes[29] ^= 0xFF;
    XCTAssertNil([CryptoUtils decryptData:ct withKey:key], @"Tampered ciphertext must be rejected");
}

// Helper: build a versioned CBC blob (0x01 || IV(16) || ciphertext)
- (NSData *)makeVersionedCBCBlob:(NSData *)plaintext key:(NSData *)key {
    uint8_t iv[16] = {
        0xAA,0xBB,0xCC,0xDD,0xEE,0xFF,0x00,0x11,
        0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99
    };
    size_t bufSize = plaintext.length + kCCBlockSizeAES128;
    NSMutableData *ctData = [NSMutableData dataWithLength:bufSize];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv,
                                 plaintext.bytes, plaintext.length,
                                 ctData.mutableBytes, bufSize, &moved);
    if (st != kCCSuccess) return nil;
    ctData.length = moved;

    NSMutableData *blob = [NSMutableData data];
    uint8_t version = 0x01;
    [blob appendBytes:&version length:1];
    [blob appendBytes:iv length:16];
    [blob appendData:ctData];
    return blob;
}

// Helper: build a legacy unversioned CBC blob (IV(16) || ciphertext, no version byte)
- (NSData *)makeLegacyCBCBlob:(NSData *)plaintext key:(NSData *)key {
    uint8_t iv[16] = {
        0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,
        0x99,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF,0x00
    };
    size_t bufSize = plaintext.length + kCCBlockSizeAES128;
    NSMutableData *ctData = [NSMutableData dataWithLength:bufSize];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv,
                                 plaintext.bytes, plaintext.length,
                                 ctData.mutableBytes, bufSize, &moved);
    if (st != kCCSuccess) return nil;
    ctData.length = moved;

    NSMutableData *blob = [NSMutableData data];
    [blob appendBytes:iv length:16];
    [blob appendData:ctData];
    return blob;
}

- (void)testDecryptLegacyCBCVersioned {
    NSData *key = [self testKey32];
    NSData *plaintext = [@"versioned CBC test payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *blob = [self makeVersionedCBCBlob:plaintext key:key];
    XCTAssertNotNil(blob);
    NSData *recovered = [CryptoUtils decryptData:blob withKey:key];
    XCTAssertEqualObjects(recovered, plaintext, @"Versioned CBC (0x01) blob must decrypt correctly");
}

- (void)testDecryptLegacyCBCUnversioned {
    NSData *key = [self testKey32];
    NSData *plaintext = [@"legacy unversioned CBC payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *blob = [self makeLegacyCBCBlob:plaintext key:key];
    XCTAssertNotNil(blob);
    NSData *recovered = [CryptoUtils decryptData:blob withKey:key];
    XCTAssertEqualObjects(recovered, plaintext, @"Unversioned legacy CBC blob must decrypt correctly");
}

#pragma mark - Base64URL Tests

- (void)testBase64URLEncodeMatchesRFC {
    // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    // base64url = 47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU
    NSData *emptyData = [NSData data];
    NSData *hash = [CryptoUtils sha256:emptyData];
    NSString *encoded = [CryptoUtils base64URLEncode:hash];
    XCTAssertEqualObjects(encoded, @"47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU");
}

- (void)testBase64URLDecodeRoundTrip {
    NSData *original = [CryptoUtils randomBytes:32];
    NSString *encoded = [CryptoUtils base64URLEncode:original];
    XCTAssertNotNil(encoded);
    XCTAssertFalse([encoded containsString:@"+"], @"Base64URL must not contain +");
    XCTAssertFalse([encoded containsString:@"/"], @"Base64URL must not contain /");
    XCTAssertFalse([encoded containsString:@"="], @"Base64URL must not contain padding");
    NSData *decoded = [CryptoUtils base64URLDecode:encoded];
    XCTAssertEqualObjects(decoded, original);
}

- (void)testBase64URLDecodeRejectsInvalidInput {
    XCTAssertNil([CryptoUtils base64URLDecode:@"not!valid@base64#"]);
    XCTAssertNil([CryptoUtils base64URLDecode:@""]);
}

#pragma mark - PBKDF2 Key Derivation Tests

- (void)testDeriveKeyFromPasswordLength {
    NSData *salt = [NSData dataWithBytes:"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10" length:16];
    NSData *key = [CryptoUtils deriveKeyFromPassword:@"test-password" salt:salt];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, (NSUInteger)32);
}

- (void)testDeriveKeyDeterminism {
    NSData *salt = [NSData dataWithBytes:"\xde\xad\xbe\xef\xca\xfe\xba\xbe\x01\x02\x03\x04\x05\x06\x07\x08" length:16];
    NSData *key1 = [CryptoUtils deriveKeyFromPassword:@"my-secret" salt:salt];
    NSData *key2 = [CryptoUtils deriveKeyFromPassword:@"my-secret" salt:salt];
    XCTAssertEqualObjects(key1, key2, @"PBKDF2 must be deterministic");
}

- (void)testDeriveKeyDifferentSaltsDifferentKeys {
    NSData *salt1 = [NSData dataWithBytes:"\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" length:16];
    NSData *salt2 = [NSData dataWithBytes:"\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02" length:16];
    NSData *key1 = [CryptoUtils deriveKeyFromPassword:@"same-password" salt:salt1];
    NSData *key2 = [CryptoUtils deriveKeyFromPassword:@"same-password" salt:salt2];
    XCTAssertNotEqualObjects(key1, key2, @"Different salts must produce different keys");
}

- (void)testDeriveKeyDifferentPasswordsDifferentKeys {
    NSData *salt = [NSData dataWithBytes:"\xAA\xBB\xCC\xDD\xEE\xFF\x00\x11\x22\x33\x44\x55\x66\x77\x88\x99" length:16];
    NSData *key1 = [CryptoUtils deriveKeyFromPassword:@"password-one" salt:salt];
    NSData *key2 = [CryptoUtils deriveKeyFromPassword:@"password-two" salt:salt];
    XCTAssertNotEqualObjects(key1, key2);
}

@end
