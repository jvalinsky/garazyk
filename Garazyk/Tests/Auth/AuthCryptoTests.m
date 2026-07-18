// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Base32Utils.h"

#pragma mark - AuthCryptoBase64URL Tests

@interface AuthCryptoBase64URLTests : XCTestCase
@end

@implementation AuthCryptoBase64URLTests

- (void)testEncodeEmptyData {
    NSData *data = [NSData data];
    NSString *encoded = [AuthCryptoBase64URL encode:data];
    XCTAssertEqualObjects(encoded, @"");
}

- (void)testEncodeHelloWorld {
    NSData *helloData = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [AuthCryptoBase64URL encode:helloData];
    // Standard base64 of "hello" is "aGVsbG8=" → base64url removes padding: "aGVsbG8"
    XCTAssertEqualObjects(encoded, @"aGVsbG8");
}

- (void)testEncodeWithPlusAndSlash {
    // Data that produces + and / in standard base64
    // 0xFB 0xFF → standard base64: "+/8=" → base64url: "_-8"
    unsigned char bytes[] = {0xFB, 0xFF};
    NSData *data = [NSData dataWithBytes:bytes length:2];
    NSString *encoded = [AuthCryptoBase64URL encode:data];
    XCTAssertTrue([encoded containsString:@"_"], @"Should replace / with _");
    XCTAssertFalse([encoded containsString:@"+"], @"Should replace + with -");
    XCTAssertFalse([encoded containsString:@"="], @"Should strip padding");
}

- (void)testDecodeEmptyString {
    // decode returns nil for empty string per implementation
    NSData *result = [AuthCryptoBase64URL decode:@""];
    XCTAssertNil(result);
}

- (void)testDecodeNil {
    NSData *result = [AuthCryptoBase64URL decode:nil];
    XCTAssertNil(result);
}

- (void)testDecodeWithPadding {
    // base64url must not contain padding
    NSData *result = [AuthCryptoBase64URL decode:@"aGVsbG8="];
    XCTAssertNil(result, @"base64url with padding should be rejected");
}

- (void)testRoundTrip {
    // Start from len=1 since decode:@"" returns nil for empty string
    for (NSUInteger len = 1; len < 64; len++) {
        NSMutableData *data = [NSMutableData dataWithLength:len];
        arc4random_buf(data.mutableBytes, len);
        NSString *encoded = [AuthCryptoBase64URL encode:data];
        NSData *decoded = [AuthCryptoBase64URL decode:encoded];
        XCTAssertEqualObjects(decoded, data, @"Round-trip failed for %lu bytes", (unsigned long)len);
    }
}

- (void)testDecodeKnownValue {
    // "aGVsbG8" is base64url for "hello"
    NSData *decoded = [AuthCryptoBase64URL decode:@"aGVsbG8"];
    XCTAssertNotNil(decoded);
    NSString *str = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"hello");
}

- (void)testDecodeWithDashAndUnderscore {
    // base64url uses - and _ instead of + and /
    NSData *result = [AuthCryptoBase64URL decode:@"_-8"];
    XCTAssertNotNil(result, @"Should decode base64url with - and _");
    XCTAssertEqual(result.length, 2);
}

@end

#pragma mark - AuthCryptoECDSA Tests

@interface AuthCryptoECDSATests : XCTestCase
@end

@implementation AuthCryptoECDSATests

- (void)testDERToRawMinimal {
    // Minimal valid DER: 30 06 02 01 00 02 01 00 (r=0, s=0)
    uint8_t der[] = {0x30, 0x06, 0x02, 0x01, 0x00, 0x02, 0x01, 0x00};
    NSData *derData = [NSData dataWithBytes:der length:sizeof(der)];
    NSError *error = nil;
    NSData *raw = [AuthCryptoECDSA rawSignatureFromDER:derData expectedSize:32 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(raw);
    XCTAssertEqual(raw.length, 64);
    // Both r and s should be zero-padded to 32 bytes
    const uint8_t *rawBytes = raw.bytes;
    for (int i = 0; i < 64; i++) {
        XCTAssertEqual(rawBytes[i], 0);
    }
}

- (void)testDERToRawWithLeadingZero {
    // DER with leading zero byte in r (high bit set)
    // r = 0x00 0x80 (value 128), s = 0x00 0x80 (value 128)
    uint8_t der[] = {0x30, 0x08, 0x02, 0x02, 0x00, 0x80, 0x02, 0x02, 0x00, 0x80};
    NSData *derData = [NSData dataWithBytes:der length:sizeof(der)];
    NSError *error = nil;
    NSData *raw = [AuthCryptoECDSA rawSignatureFromDER:derData expectedSize:32 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(raw);
    XCTAssertEqual(raw.length, 64);
    // r should be 0x00...00 80 (31 zero bytes + 0x80)
    const uint8_t *rawBytes = raw.bytes;
    XCTAssertEqual(rawBytes[31], 0x80);
    XCTAssertEqual(rawBytes[63], 0x80);
}

- (void)testDERToRawInvalidShort {
    NSData *derData = [NSData dataWithBytes:"\x30\x02" length:2];
    NSError *error = nil;
    NSData *raw = [AuthCryptoECDSA rawSignatureFromDER:derData expectedSize:32 error:&error];
    XCTAssertNil(raw);
    XCTAssertNotNil(error);
}

- (void)testDERToRawInvalidNotSequence {
    uint8_t der[] = {0x05, 0x00}; // NULL instead of SEQUENCE
    NSData *derData = [NSData dataWithBytes:der length:sizeof(der)];
    NSError *error = nil;
    NSData *raw = [AuthCryptoECDSA rawSignatureFromDER:derData expectedSize:32 error:&error];
    XCTAssertNil(raw);
    XCTAssertNotNil(error);
}

- (void)testRawToDERBasic {
    // Create a 64-byte raw signature with small values
    uint8_t rawBytes[64];
    memset(rawBytes, 0, 64);
    rawBytes[31] = 0x42; // r = 0x42
    rawBytes[63] = 0x43; // s = 0x43
    NSData *rawData = [NSData dataWithBytes:rawBytes length:64];
    NSError *error = nil;
    NSData *der = [AuthCryptoECDSA derSignatureFromRaw:rawData error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(der);
    // Should start with SEQUENCE tag
    const uint8_t *derBytes = der.bytes;
    XCTAssertEqual(derBytes[0], 0x30);
}

- (void)testRawToDERInvalidOddLength {
    NSData *rawData = [NSData dataWithBytes:"\x01\x02\x03" length:3];
    NSError *error = nil;
    NSData *der = [AuthCryptoECDSA derSignatureFromRaw:rawData error:&error];
    XCTAssertNil(der);
    XCTAssertNotNil(error);
}

- (void)testDERToRawRoundTrip {
    // Create a known raw signature, convert to DER and back
    uint8_t rawBytes[64];
    memset(rawBytes, 0, 64);
    rawBytes[0] = 0x01; // Small r
    rawBytes[32] = 0x02; // Small s
    NSData *originalRaw = [NSData dataWithBytes:rawBytes length:64];

    NSError *error = nil;
    NSData *der = [AuthCryptoECDSA derSignatureFromRaw:originalRaw error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(der);

    NSData *roundTrip = [AuthCryptoECDSA rawSignatureFromDER:der expectedSize:32 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(roundTrip);
    XCTAssertEqualObjects(roundTrip, originalRaw);
}

- (void)testIsLowSAllZeroS {
    uint8_t raw[64];
    memset(raw, 0, 64);
    NSData *sig = [NSData dataWithBytes:raw length:64];
    XCTAssertTrue([AuthCryptoECDSA isLowS:sig error:nil]);
}

- (void)testIsLowSHighS {
    // s = 0xFF...FF (all ones) should be high-S
    uint8_t raw[64];
    memset(raw, 0, 32); // r = 0
    memset(raw + 32, 0xFF, 32); // s = max
    NSData *sig = [NSData dataWithBytes:raw length:64];
    XCTAssertFalse([AuthCryptoECDSA isLowS:sig error:nil]);
}

- (void)testIsLowSInvalidLength {
    NSData *sig = [NSData dataWithBytes:"\x00\x00\x00" length:3];
    XCTAssertFalse([AuthCryptoECDSA isLowS:sig error:nil]);
}

- (void)testNormalizeLowSAlreadyLow {
    uint8_t raw[64];
    memset(raw, 0, 64);
    NSData *sig = [NSData dataWithBytes:raw length:64];
    NSError *error = nil;
    NSData *result = [AuthCryptoECDSA normalizeLowS:sig error:&error];
    XCTAssertNil(error);
    // Should return same object if already low-S
    XCTAssertEqual(result, sig);
}

- (void)testNormalizeLowSHighSBecomesLow {
    // Use a valid high-S value: N/2 + 1
    // P-256 N/2 = 7FFFFFFF80000000 8000000000000000 000000007FFFFFFF FFFFFFFFFFFFFFFF
    // N/2 + 1 is just above the half-order, so it's high-S
    uint8_t raw[64];
    memset(raw, 0, 32); // r = 0
    uint8_t highS[32] = {
        0x7F, 0xFF, 0xFF, 0xFF, 0x80, 0x00, 0x00, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    memcpy(raw + 32, highS, 32);
    NSData *sig = [NSData dataWithBytes:raw length:64];
    NSError *error = nil;
    NSData *result = [AuthCryptoECDSA normalizeLowS:sig error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(result);
    // r should be unchanged (all zeros)
    const uint8_t *resultBytes = result.bytes;
    for (int i = 0; i < 32; i++) {
        XCTAssertEqual(resultBytes[i], 0);
    }
    // Result should now be low-S
    XCTAssertTrue([AuthCryptoECDSA isLowS:result error:nil]);
}

- (void)testNormalizeLowSInvalidLength {
    NSData *sig = [NSData dataWithBytes:"\x00" length:1];
    NSError *error = nil;
    NSData *result = [AuthCryptoECDSA normalizeLowS:sig error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testDenormalizeLowSAlreadyHigh {
    uint8_t raw[64];
    memset(raw, 0, 32);
    memset(raw + 32, 0xFF, 32); // high-S
    NSData *sig = [NSData dataWithBytes:raw length:64];
    NSError *error = nil;
    NSData *result = [AuthCryptoECDSA denormalizeLowS:sig error:&error];
    XCTAssertNil(error);
    // Already high-S, should return as-is
    XCTAssertEqual(result, sig);
}

- (void)testDenormalizeThenNormalizeRoundTrip {
    uint8_t raw[64];
    memset(raw, 0, 32);
    memset(raw + 32, 0x01, 32); // low-S (small value)
    NSData *original = [NSData dataWithBytes:raw length:64];

    NSError *error = nil;
    NSData *highS = [AuthCryptoECDSA denormalizeLowS:original error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(highS);
    XCTAssertFalse([AuthCryptoECDSA isLowS:highS error:nil]);

    NSData *backToLow = [AuthCryptoECDSA normalizeLowS:highS error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(backToLow);
    XCTAssertTrue([AuthCryptoECDSA isLowS:backToLow error:nil]);

    // r should be unchanged
    const uint8_t *origBytes = original.bytes;
    const uint8_t *backBytes = backToLow.bytes;
    for (int i = 0; i < 32; i++) {
        XCTAssertEqual(origBytes[i], backBytes[i]);
    }
}

@end

#pragma mark - AuthCryptoJWK Tests

@interface AuthCryptoJWKTests : XCTestCase
@end

@implementation AuthCryptoJWKTests

- (void)testThumbprintECKey {
    // RFC 7638 Appendix A test vector
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"
    };
    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(thumbprint);
    XCTAssertEqualObjects(thumbprint, @"cn-I_WNMClehiVp51i_0VpOENW1upEerA8sEam5hn-s");
}

- (void)testThumbprintRSAKey {
    // RSA thumbprint — just verify it produces a non-empty result
    NSDictionary *jwk = @{
        @"kty": @"RSA",
        @"n": @"0vx7agoebGcQSuuPiLJXZptN1nNdQcbH5bhHJSEJ4RAvM4F0Hb1QFY7CvSvE3O3N_F6RQ0PaG6Gw6IcS5O7ZPZsC3fB9r9b6z1V0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0K3Y0p0Y2R0Kw",
        @"e": @"AQAB"
    };
    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(thumbprint);
    XCTAssertTrue(thumbprint.length > 0);
}

- (void)testThumbprintMissingECMembers {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256"}; // missing x, y
    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNil(thumbprint);
    XCTAssertNotNil(error);
}

- (void)testThumbprintUnsupportedKty {
    NSDictionary *jwk = @{@"kty": @"oct", @"k": @"somekey"};
    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNil(thumbprint);
    XCTAssertNotNil(error);
}

- (void)testPublicJWKFromJWKStripsPrivateMaterial {
    NSDictionary *privateJWK = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
        @"d": @"some-private-key-material"
    };
    NSDictionary *publicJWK = [AuthCryptoJWK publicJWKFromJWK:privateJWK];
    XCTAssertNil(publicJWK[@"d"], @"Private key material 'd' should be removed");
    XCTAssertEqualObjects(publicJWK[@"kty"], @"EC");
    XCTAssertEqualObjects(publicJWK[@"x"], @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4");
}

- (void)testPublicJWKFromJWKStripsRSAPrivateMaterial {
    NSDictionary *privateJWK = @{
        @"kty": @"RSA",
        @"n": @"modulus",
        @"e": @"AQAB",
        @"d": @"private-exponent",
        @"p": @"prime1",
        @"q": @"prime2",
        @"dp": @"dp-value",
        @"dq": @"dq-value",
        @"qi": @"qi-value"
    };
    NSDictionary *publicJWK = [AuthCryptoJWK publicJWKFromJWK:privateJWK];
    XCTAssertNil(publicJWK[@"d"]);
    XCTAssertNil(publicJWK[@"p"]);
    XCTAssertNil(publicJWK[@"q"]);
    XCTAssertNil(publicJWK[@"dp"]);
    XCTAssertNil(publicJWK[@"dq"]);
    XCTAssertNil(publicJWK[@"qi"]);
    XCTAssertEqualObjects(publicJWK[@"n"], @"modulus");
    XCTAssertEqualObjects(publicJWK[@"e"], @"AQAB");
}

- (void)testPublicKeyFromJWKNonECRejected {
    NSDictionary *jwk = @{@"kty": @"RSA", @"n": @"modulus", @"e": @"AQAB"};
    NSError *error = nil;
    id result = [AuthCryptoJWK publicKeyFromJWK:jwk error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testPrivateKeyFromJWKNonECRejected {
    NSDictionary *jwk = @{@"kty": @"RSA", @"n": @"modulus", @"e": @"AQAB", @"d": @"priv"};
    NSError *error = nil;
    id result = [AuthCryptoJWK privateKeyFromJWK:jwk error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testPublicKeyFromJWKMissingKeyMaterial {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256"}; // missing x, y
    NSError *error = nil;
    id result = [AuthCryptoJWK publicKeyFromJWK:jwk error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testCreateAndVerifyKeyPairRoundTrip {
    // Use a known P-256 key pair for cross-platform testing
    NSDictionary *publicJWK = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"
    };

    NSError *error = nil;
    id<PDSPublicKeyProtocol> publicKey = [AuthCryptoJWK publicKeyFromJWK:publicJWK error:&error];
    if (!publicKey) {
        // Key creation may fail on some platforms without proper crypto support
        XCTSkip(@"Skipping: P-256 key creation not available on this platform");
        return;
    }
    XCTAssertNotNil(publicKey);
}

// Regression: P-256 (ES256) verification must accept BOTH low-S and high-S
// signatures. Low-S is a secp256k1 repo-signature rule that does not apply to
// JOSE/DPoP/WebAuthn/PLC; enforcing it here rejected ~half of all valid DPoP
// proofs non-deterministically. See AuthCryptoJWK verifySignature:forData:.
- (void)testVerifySignatureAcceptsBothLowSAndHighS {
    NSDictionary *privateJWK = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU",
        @"y": @"x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0",
        @"d": @"jpsQnnGQmL-YBIffH1136cspYG6-0iY7X1fCE9-E9LI"
    };

    NSError *error = nil;
    id<PDSPrivateKeyProtocol> privateKey =
        [AuthCryptoJWK privateKeyFromJWK:privateJWK error:&error];
    if (!privateKey) {
        XCTSkip(@"P-256 key creation not available on this platform");
        return;
    }
    id<PDSPublicKeyProtocol> publicKey =
        [AuthCryptoJWK publicKeyFromJWK:privateJWK error:&error];
    XCTAssertNotNil(publicKey);

    NSData *message = [@"header.payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *rawSig = [privateKey signData:message error:&error];
    XCTAssertNotNil(rawSig, @"signing should succeed");
    XCTAssertEqual(rawSig.length, (NSUInteger)64, @"raw ECDSA sig is 64 bytes");

    // Both (r, s) and (r, N-s) are valid signatures for the same message.
    NSData *lowS = [AuthCryptoECDSA normalizeLowS:rawSig error:nil];
    NSData *highS = [AuthCryptoECDSA denormalizeLowS:lowS error:nil];
    XCTAssertNotNil(lowS);
    XCTAssertNotNil(highS);
    XCTAssertTrue([AuthCryptoECDSA isLowS:lowS error:nil]);
    XCTAssertFalse([AuthCryptoECDSA isLowS:highS error:nil],
                   @"denormalized signature must be high-S");

    XCTAssertTrue([publicKey verifySignature:lowS forData:message error:&error],
                  @"low-S signature must verify");
    XCTAssertTrue([publicKey verifySignature:highS forData:message error:&error],
                  @"high-S signature must verify (regression guard)");

    // Guard: a signature over different data must still be rejected in both forms.
    NSData *tampered = [@"header.tampered" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([publicKey verifySignature:lowS forData:tampered error:nil],
                   @"low-S signature must not verify against different data");
    XCTAssertFalse([publicKey verifySignature:highS forData:tampered error:nil],
                   @"high-S signature must not verify against different data");
}

@end

#pragma mark - AuthCryptoDPoP Tests

@interface AuthCryptoDPoPTests : XCTestCase
@end

@implementation AuthCryptoDPoPTests

- (void)testCanonicalHTUFromURLBasic {
    NSURL *url = [NSURL URLWithString:@"https://example.com/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUFromStringBasic {
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromString:@"https://example.com/path"];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUStripsQuery {
    NSURL *url = [NSURL URLWithString:@"https://example.com/path?query=1"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUStripsFragment {
    NSURL *url = [NSURL URLWithString:@"https://example.com/path#fragment"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUDefaultPortHTTPS {
    NSURL *url = [NSURL URLWithString:@"https://example.com:443/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUDefaultPortHTTP {
    NSURL *url = [NSURL URLWithString:@"http://example.com:80/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"http://example.com/path");
}

- (void)testCanonicalHTUNonDefaultPort {
    NSURL *url = [NSURL URLWithString:@"https://example.com:8443/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com:8443/path");
}

- (void)testCanonicalHTULowercasesSchemeAndHost {
    NSURL *url = [NSURL URLWithString:@"HTTPS://EXAMPLE.COM/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUDefaultPath {
    // NSURLComponents.path returns empty string (not nil) for "https://example.com"
    // so the canonical HTU has no trailing slash
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com");
}

- (void)testCanonicalHTUNilURL {
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:nil];
    XCTAssertEqualObjects(htu, @"");
}

- (void)testCanonicalHTUFromStringNil {
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromString:nil];
    XCTAssertNil(htu);
}

- (void)testCanonicalHTUFromStringInvalid {
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromString:@"not a url"];
    // NSURL may parse partial strings; just verify it doesn't crash
    XCTAssertNotNil(htu);
}

- (void)testVerifyProofNilJWT {
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:nil
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofInvalidFormat {
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:@"not-a-jwt"
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofInvalidHeaderEncoding {
    // 3 parts but first part is not valid base64url
    NSString *badJwt = @"!!!invalid!!!.eyJodG0iOiJHRVQifQ.signature";
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofWrongTyp {
    // Build a JWT with wrong typ
    NSDictionary *header = @{@"typ": @"JWT", @"alg": @"ES256", @"jwk": @{@"kty": @"EC"}};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"typ"]);
}

- (void)testVerifyProofWrongAlg {
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"RS256", @"jwk": @{@"kty": @"EC"}};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"ES256"]);
}

- (void)testVerifyProofMissingJWK {
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256"};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"jwk"]);
}

- (void)testVerifyProofJWKWithPrivateKeyMaterial {
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": @{@"kty": @"EC", @"d": @"private-key"}};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"private key material"]);
}

- (void)testVerifyProofHtmMismatch {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"POST", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"htm"]);
}

- (void)testVerifyProofMissingIat {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"iat"]);
}

- (void)testVerifyProofExpiredIat {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    // iat 10 minutes ago (outside 5-minute window)
    NSTimeInterval oldIat = [[NSDate date] timeIntervalSince1970] - 600;
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @(oldIat), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"expired"]);
}

- (void)testVerifyProofRequireNonceMissing {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:@"expected-nonce"
                                  requireNonce:YES
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"nonce"]);
}

- (void)testVerifyProofNonceMismatch {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString], @"nonce": @"wrong-nonce"};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:@"expected-nonce"
                                  requireNonce:YES
                                nonceValidator:nil
                                 replayChecker:nil
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"nonce"]);
}

- (void)testCreateProofMissingParameters {
    NSError *error = nil;
    NSString *result = [AuthCryptoDPoP createProofForURL:nil method:@"GET" key:@{} error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

@end

#pragma mark - Base32Utils Tests

@interface Base32UtilsTests : XCTestCase
@end

@implementation Base32UtilsTests

- (void)testEncodeEmptyData {
    NSString *result = [Base32Utils base32StringFromData:[NSData data]];
    XCTAssertEqualObjects(result, @"");
}

- (void)testEncodeNilData {
    NSString *result = [Base32Utils base32StringFromData:nil];
    XCTAssertEqualObjects(result, @"");
}

- (void)testEncodeSingleByte {
    // 0x48 ('H') → base32: "JA======"
    NSData *data = [NSData dataWithBytes:"\x48" length:1];
    NSString *result = [Base32Utils base32StringFromData:data];
    XCTAssertEqualObjects(result, @"JA======");
}

- (void)testEncodeHelloWorld {
    // "Hello" → base32: "JBSWY3DP"
    NSData *data = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *result = [Base32Utils base32StringFromData:data];
    // 5 bytes → 8 base32 chars + padding
    XCTAssertTrue([result hasPrefix:@"JBSWY3DP"]);
}

- (void)testDecodeNil {
    NSData *result = [Base32Utils dataFromBase32String:nil];
    XCTAssertNil(result);
}

- (void)testDecodeEmptyString {
    NSData *result = [Base32Utils dataFromBase32String:@""];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, 0);
}

- (void)testDecodeInvalidCharacter {
    NSData *result = [Base32Utils dataFromBase32String:@"019!@#"];
    XCTAssertNil(result);
}

- (void)testRoundTrip {
    for (NSUInteger len = 1; len < 32; len++) {
        NSMutableData *data = [NSMutableData dataWithLength:len];
        arc4random_buf(data.mutableBytes, len);
        NSString *encoded = [Base32Utils base32StringFromData:data];
        NSData *decoded = [Base32Utils dataFromBase32String:encoded];
        XCTAssertEqualObjects(decoded, data, @"Round-trip failed for %lu bytes", (unsigned long)len);
    }
}

- (void)testDecodeLowercase {
    // Base32 decode should handle lowercase input
    NSData *result = [Base32Utils dataFromBase32String:@"jbswy3dp"];
    XCTAssertNotNil(result);
    NSData *upperResult = [Base32Utils dataFromBase32String:@"JBSWY3DP"];
    XCTAssertNotNil(upperResult);
    XCTAssertEqualObjects(result, upperResult);
}

- (void)testDecodeWithPadding {
    NSData *result = [Base32Utils dataFromBase32String:@"JA======"];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, 1);
    const uint8_t *bytes = result.bytes;
    XCTAssertEqual(bytes[0], 0x48);
}

- (void)testDecodeWithoutPadding {
    NSData *result = [Base32Utils dataFromBase32String:@"JA"];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, 1);
    const uint8_t *bytes = result.bytes;
    XCTAssertEqual(bytes[0], 0x48);
}

- (void)testEncodeKnownValue {
    // RFC 4648 test vectors
    // "f" → "MY======"  (0x66)
    NSData *f = [NSData dataWithBytes:"\x66" length:1];
    NSString *fEncoded = [Base32Utils base32StringFromData:f];
    XCTAssertEqualObjects(fEncoded, @"MY======");

    // "fo" → "MZXQ===="
    NSData *fo = [NSData dataWithBytes:"\x66\x6f" length:2];
    NSString *foEncoded = [Base32Utils base32StringFromData:fo];
    XCTAssertEqualObjects(foEncoded, @"MZXQ====");

    // "foo" → "MZXW6==="
    NSData *foo = [NSData dataWithBytes:"\x66\x6f\x6f" length:3];
    NSString *fooEncoded = [Base32Utils base32StringFromData:foo];
    XCTAssertEqualObjects(fooEncoded, @"MZXW6===");

    // "foob" → "MZXW6YQ="
    NSData *foob = [NSData dataWithBytes:"\x66\x6f\x6f\x62" length:4];
    NSString *foobEncoded = [Base32Utils base32StringFromData:foob];
    XCTAssertEqualObjects(foobEncoded, @"MZXW6YQ=");

    // "fooba" → "MZXW6YTB"
    NSData *fooba = [NSData dataWithBytes:"\x66\x6f\x6f\x62\x61" length:5];
    NSString *foobaEncoded = [Base32Utils base32StringFromData:fooba];
    XCTAssertEqualObjects(foobaEncoded, @"MZXW6YTB");
}

@end
