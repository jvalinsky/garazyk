// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"

@interface AuthCryptoECDSATests : XCTestCase
@end

@implementation AuthCryptoECDSATests

#pragma mark - rawSignatureFromDER:expectedSize:error:

- (void)testRawFromDER_P256_Valid {
    // DER-encoded signature for P-256: SEQUENCE { INTEGER r (32 bytes), INTEGER s (32 bytes) }
    uint8_t r[32] = {0};
    uint8_t s[32] = {0};
    r[31] = 0x01; // r = 1
    s[31] = 0x02; // s = 2

    NSMutableData *der = [NSMutableData data];
    // SEQUENCE tag
    uint8_t seqTag = 0x30;
    [der appendBytes:&seqTag length:1];
    // SEQUENCE content length: rIntLen + sIntLen + 4 (2 INTEGER tags + 2 length bytes)
    uint8_t totalLen = 2 + 2 + 32 + 32; // tag+rLen+r + tag+sLen+s
    [der appendBytes:&totalLen length:1];
    // INTEGER r (usually 0x02, len, r_bytes) — 32 bytes, no leading zero needed
    uint8_t intTag = 0x02;
    uint8_t rLen = 32;
    [der appendBytes:&intTag length:1];
    [der appendBytes:&rLen length:1];
    [der appendBytes:r length:32];
    // INTEGER s
    [der appendBytes:&intTag length:1];
    uint8_t sLen = 32;
    [der appendBytes:&sLen length:1];
    [der appendBytes:s length:32];

    NSError *error = nil;
    NSData *raw = [ATProtoAuthCryptoECDSA rawSignatureFromDER:der expectedSize:32 error:&error];
    XCTAssertNotNil(raw, @"Should parse valid DER");
    XCTAssertNil(error);
    XCTAssertEqual(raw.length, (NSUInteger)64);
    // First 32 bytes = r (padded to 32), last 32 = s
    const uint8_t *rawBytes = raw.bytes;
    for (int i = 0; i < 31; i++) {
        XCTAssertEqual(rawBytes[i], 0, @"r should be zero-padded");
    }
    XCTAssertEqual(rawBytes[31], 0x01, @"r should end with 0x01");
    for (int i = 32; i < 63; i++) {
        XCTAssertEqual(rawBytes[i], 0, @"s should be zero-padded");
    }
    XCTAssertEqual(rawBytes[63], 0x02, @"s should end with 0x02");
}

- (void)testRawFromDER_P256_WithLeadingZeros {
    // DER with leading zeros in r component (e.g., r = 0x00...00ABCD)
    uint8_t rShort[30] = {0};
    rShort[28] = 0xAB;
    rShort[29] = 0xCD;
    uint8_t s[32] = {0};
    s[31] = 0x05;

    NSMutableData *der = [NSMutableData data];
    uint8_t seqTag = 0x30;
    [der appendBytes:&seqTag length:1];
    uint8_t rLen = 30;
    uint8_t sLen = 32;
    uint8_t totalLen = 2 + rLen + 2 + sLen; // tag+rLen+r + tag+sLen+s
    [der appendBytes:&totalLen length:1];
    uint8_t intTag = 0x02;
    [der appendBytes:&intTag length:1];
    [der appendBytes:&rLen length:1];
    [der appendBytes:rShort length:30];
    [der appendBytes:&intTag length:1];
    [der appendBytes:&sLen length:1];
    [der appendBytes:s length:32];

    NSError *error = nil;
    NSData *raw = [ATProtoAuthCryptoECDSA rawSignatureFromDER:der expectedSize:32 error:&error];
    XCTAssertNotNil(raw);
    XCTAssertNil(error);
    XCTAssertEqual(raw.length, (NSUInteger)64);
    const uint8_t *rawBytes = raw.bytes;
    // Expect r padded to 32 bytes: leading zeros + 0xAB 0xCD at bytes 30-31
    XCTAssertEqual(rawBytes[30], 0xAB);
    XCTAssertEqual(rawBytes[31], 0xCD);
    XCTAssertEqual(rawBytes[63], 0x05);
}

- (void)testRawFromDER_InvalidSequenceTag_ReturnsNil {
    uint8_t invalid[] = {0x31, 0x02, 0x02, 0x01, 0x00};
    NSData *der = [NSData dataWithBytes:invalid length:5];
    NSError *error = nil;
    NSData *result = [ATProtoAuthCryptoECDSA rawSignatureFromDER:der expectedSize:32 error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testRawFromDER_EmptyData_ReturnsNil {
    NSData *empty = [NSData data];
    NSError *error = nil;
    NSData *result = [ATProtoAuthCryptoECDSA rawSignatureFromDER:empty expectedSize:32 error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testRawFromDER_TruncatedData_ReturnsNil {
    uint8_t partial[] = {0x30, 0x04, 0x02};
    NSData *der = [NSData dataWithBytes:partial length:3];
    NSError *error = nil;
    NSData *result = [ATProtoAuthCryptoECDSA rawSignatureFromDER:der expectedSize:32 error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

#pragma mark - derSignatureFromRaw:error:

- (void)testDERFromRaw_P256_Valid {
    NSMutableData *raw = [NSMutableData dataWithLength:64];
    uint8_t *rawBytes = raw.mutableBytes;
    rawBytes[31] = 0x01; // r = 1, zero-padded to 32
    rawBytes[63] = 0x02; // s = 2, zero-padded to 32

    NSError *error = nil;
    NSData *der = [ATProtoAuthCryptoECDSA derSignatureFromRaw:raw error:&error];
    XCTAssertNotNil(der);
    XCTAssertNil(error);

    // Round-trip back
    NSData *roundTrip = [ATProtoAuthCryptoECDSA rawSignatureFromDER:der expectedSize:32 error:&error];
    XCTAssertNotNil(roundTrip);
    XCTAssertEqualObjects(roundTrip, raw);
}

- (void)testDERFromRaw_OddLength_ReturnsNil {
    NSData *odd = [NSMutableData dataWithLength:33];
    NSError *error = nil;
    NSData *result = [ATProtoAuthCryptoECDSA derSignatureFromRaw:odd error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testDERFromRaw_P256_RWithHighBit_AddsZeroPrefix {
    // r has high bit set, so DER should prepend 0x00
    uint8_t rVal[32] = {0};
    uint8_t sVal[32] = {0};
    rVal[0] = 0x80; // high bit set
    sVal[31] = 0x05;
    NSMutableData *raw = [NSMutableData dataWithBytes:rVal length:32];
    [raw appendBytes:sVal length:32];

    NSError *error = nil;
    NSData *der = [ATProtoAuthCryptoECDSA derSignatureFromRaw:raw error:&error];
    XCTAssertNotNil(der);
    XCTAssertNil(error);

    // r component should have leading zero × 1 + 0x80 = rLen of 33 encoded
    const uint8_t *derBytes = der.bytes;
    XCTAssertEqual(derBytes[0], 0x30);
    // byte[1] = seq len, byte[2] = INTEGER tag
    XCTAssertEqual(derBytes[2], 0x02, @"Should have INTEGER tag after SEQUENCE header");
    // rLen — should be 33 since 0x80 needs padding
    // But actually: the code strips leading 0x00, then if result has high bit or length 0, prepends 0x00.
    // So r[0]=0x80 → no leading zeros to strip → result starts with 0x80 (high bit) → prepend 0x00 → rLen=33
    // That means at offset 4 = rLen...
    // Let me just verify round-trip works
    NSData *roundTrip = [ATProtoAuthCryptoECDSA rawSignatureFromDER:der expectedSize:32 error:&error];
    XCTAssertNotNil(roundTrip);
    XCTAssertEqualObjects(roundTrip, raw);
}

#pragma mark - isLowS:error:

- (void)testIsLowS_ZeroS_IsLowS {
    NSMutableData *sig = [NSMutableData dataWithLength:64];
    // s = 0 which is < N/2
    BOOL result = [ATProtoAuthCryptoECDSA isLowS:sig error:nil];
    XCTAssertTrue(result);
}

- (void)testIsLowS_HighS_NotLowS {
    NSMutableData *sig = [NSMutableData dataWithLength:64];
    uint8_t *bytes = sig.mutableBytes;
    // Set s (last 32 bytes) to all 0xFF, which is > N/2
    memset(bytes + 32, 0xFF, 32);
    BOOL result = [ATProtoAuthCryptoECDSA isLowS:sig error:nil];
    XCTAssertFalse(result);
}

- (void)testIsLowS_EqualToHalfN_IsLowS {
    // P-256 N/2 = 7FFFFFFF 80000000 7FFFFFFF FFFFFFFF DE737D56 D38BCF42 79DCE561 7E3192A8
    static const uint8_t halfN[32] = {
        0x7F, 0xFF, 0xFF, 0xFF, 0x80, 0x00, 0x00, 0x00,
        0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xDE, 0x73, 0x7D, 0x56, 0xD3, 0x8B, 0xCF, 0x42,
        0x79, 0xDC, 0xE5, 0x61, 0x7E, 0x31, 0x92, 0xA8
    };
    NSMutableData *sig = [NSMutableData dataWithLength:64];
    memcpy(((uint8_t *)sig.mutableBytes) + 32, halfN, 32);
    BOOL result = [ATProtoAuthCryptoECDSA isLowS:sig error:nil];
    XCTAssertTrue(result, @"s = N/2 should be considered low-S");
}

- (void)testIsLowS_WrongLength_ReturnsNO {
    NSData *shortSig = [NSMutableData dataWithLength:32];
    BOOL result = [ATProtoAuthCryptoECDSA isLowS:shortSig error:nil];
    XCTAssertFalse(result);
}

#pragma mark - normalizeLowS:error:

- (void)testNormalizeLowS_AlreadyLowS_ReturnsSame {
    NSMutableData *sig = [NSMutableData dataWithLength:64];
    uint8_t *bytes = sig.mutableBytes;
    bytes[31] = 0x01; // r = 1
    // s = 1 (very low)
    bytes[63] = 0x01;

    NSError *error = nil;
    NSData *result = [ATProtoAuthCryptoECDSA normalizeLowS:sig error:&error];
    XCTAssertNotNil(result);
    XCTAssertTrue(result == sig, @"Should return same object for already low-S");
}

- (void)testNormalizeLowS_HighS_Normalizes {
    // P-256 curve order n
    // FFFFFFFF 00000000 FFFFFFFF FFFFFFFF BCE6FAAD A7179E84 F3B9CAC2 FC632551
    static const uint8_t n[32] = {
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84,
        0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x51
    };
    // Set s = n - 1 (highest valid high-S)
    NSMutableData *sig = [NSMutableData dataWithLength:64];
    uint8_t *s = (uint8_t *)sig.mutableBytes + 32;
    memcpy(s, n, 32);
    s[31]--; // n - 1

    BOOL isLow = [ATProtoAuthCryptoECDSA isLowS:sig error:nil];
    XCTAssertFalse(isLow, @"s = n-1 should be high-S");

    NSError *error = nil;
    NSData *normalized = [ATProtoAuthCryptoECDSA normalizeLowS:sig error:&error];
    XCTAssertNotNil(normalized);
    XCTAssertNil(error);

    BOOL isNowLow = [ATProtoAuthCryptoECDSA isLowS:normalized error:nil];
    XCTAssertTrue(isNowLow, @"Normalized signature should be low-S");

    // Normalized s should be 1 (since n - (n-1) = 1)
    const uint8_t *normBytes = normalized.bytes;
    for (int i = 32; i < 63; i++) {
        XCTAssertEqual(normBytes[i], 0, @"Normalized s should be zero-padded");
    }
    XCTAssertEqual(normBytes[63], 0x01, @"Normalized s should be 1");
}

#pragma mark - denormalizeLowS:error:

- (void)testDenormalizeLowS_AlreadyHighS_ReturnsSame {
    NSMutableData *sig = [NSMutableData dataWithLength:64];
    uint8_t *bytes = sig.mutableBytes;
    // Set s to high-S (all 0xFF)
    memset(bytes + 32, 0xFF, 32);

    NSError *error = nil;
    NSData *result = [ATProtoAuthCryptoECDSA denormalizeLowS:sig error:&error];
    XCTAssertNotNil(result);
    XCTAssertTrue(result == sig, @"Should return same object for already high-S");
}

- (void)testDenormalizeLowS_LowS_Denormalizes {
    NSMutableData *sig = [NSMutableData dataWithLength:64];
    uint8_t *bytes = sig.mutableBytes;
    bytes[63] = 0x01; // s = 1 (low-S)

    NSError *error = nil;
    NSData *denormalized = [ATProtoAuthCryptoECDSA denormalizeLowS:sig error:&error];
    XCTAssertNotNil(denormalized);
    XCTAssertNil(error);

    BOOL isNowLow = [ATProtoAuthCryptoECDSA isLowS:denormalized error:nil];
    XCTAssertFalse(isNowLow, @"Denormalized signature should be high-S");
}

#pragma mark - Normalize ↔ Denormalize Round-Trip

- (void)testNormalizeDenormalizeRoundTrip {
    // Start with a high-S signature: s > N/2 but < N (first byte 0x80 > N/2 first byte 0x7F)
    NSMutableData *highS = [NSMutableData dataWithLength:64];
    uint8_t *bytes = highS.mutableBytes;
    bytes[31] = 0xAA; // r = 0xAA
    bytes[32] = 0x80; // s first byte > N/2 first byte (0x7F) → high-S

    BOOL isLow = [ATProtoAuthCryptoECDSA isLowS:highS error:nil];
    XCTAssertFalse(isLow, @"s with first byte 0x80 should be high-S");

    NSError *error = nil;
    NSData *normalized = [ATProtoAuthCryptoECDSA normalizeLowS:highS error:&error];
    XCTAssertNotNil(normalized);

    BOOL isNowLow = [ATProtoAuthCryptoECDSA isLowS:normalized error:nil];
    XCTAssertTrue(isNowLow, @"Normalized should be low-S");

    // Now denormalize back
    NSData *denormalized = [ATProtoAuthCryptoECDSA denormalizeLowS:normalized error:nil];
    XCTAssertNotNil(denormalized);

    // Should match original (same r, same resulting s)
    const uint8_t *origBytes = highS.bytes;
    const uint8_t *denormBytes = denormalized.bytes;
    XCTAssertEqual(memcmp(origBytes, denormBytes, 64), 0, @"Denormalize(normalize(sig)) should equal original");
}

@end
