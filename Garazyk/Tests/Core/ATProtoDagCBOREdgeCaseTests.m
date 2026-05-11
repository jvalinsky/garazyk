// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"

static NSData *ATProtoDataWithBytes(const uint8_t *bytes, NSUInteger length) {
    return [NSData dataWithBytes:bytes length:length];
}

@interface ATProtoDagCBOREdgeCaseTests : XCTestCase
@end

@implementation ATProtoDagCBOREdgeCaseTests

- (void)assertDecodeFailsForBytes:(const uint8_t *)bytes length:(NSUInteger)length {
    NSError *error = nil;
    NSData *data = ATProtoDataWithBytes(bytes, length);
    id decoded = [ATProtoDagCBOR decodeData:data error:&error];

    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
    XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeDecodingFailed);
}

#pragma mark - Length and Truncation Edge Cases

- (void)testTruncatedCBORLengthField {
    const uint8_t additionalInfo24[] = {0x58};
    const uint8_t additionalInfo25[] = {0x59, 0x00};
    const uint8_t additionalInfo26[] = {0x5A, 0x00, 0x00, 0x00};
    const uint8_t additionalInfo27[] = {0x5B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

    [self assertDecodeFailsForBytes:additionalInfo24 length:sizeof(additionalInfo24)];
    [self assertDecodeFailsForBytes:additionalInfo25 length:sizeof(additionalInfo25)];
    [self assertDecodeFailsForBytes:additionalInfo26 length:sizeof(additionalInfo26)];
    [self assertDecodeFailsForBytes:additionalInfo27 length:sizeof(additionalInfo27)];
}

- (void)testTruncatedMapAndArray {
    const uint8_t truncatedArray[] = {0x82, 0x01};
    const uint8_t truncatedMap[] = {0xA1, 0x61, 0x61};

    [self assertDecodeFailsForBytes:truncatedArray length:sizeof(truncatedArray)];
    [self assertDecodeFailsForBytes:truncatedMap length:sizeof(truncatedMap)];
}

#pragma mark - Structural Rejection

- (void)testMaxDecodeDepthExceeded {
    NSError *error = nil;
    NSMutableData *nested = [NSMutableData data];

    // 65 nested maps exceeds the decoder's depth limit of 64.
    for (NSUInteger i = 0; i < 65; i++) {
        uint8_t mapHeader = 0xA1;
        uint8_t keyHeader = 0x61;
        uint8_t keyValue = 'a';
        [nested appendBytes:&mapHeader length:1];
        [nested appendBytes:&keyHeader length:1];
        [nested appendBytes:&keyValue length:1];
    }

    uint8_t leaf = 0x00;
    [nested appendBytes:&leaf length:1];

    id decoded = [ATProtoDagCBOR decodeData:nested error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
    XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeDecodingFailed);
}

- (void)testCBORMajorType7Rejection {
    const uint8_t simpleValue0[] = {0xE0};
    const uint8_t simpleValue24[] = {0xF8, 0x18};
    const uint8_t halfFloat[] = {0xF9, 0x00, 0x00};
    const uint8_t float32[] = {0xFA, 0x3F, 0x80, 0x00, 0x00};
    const uint8_t float64[] = {0xFB, 0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

    NSArray *cases = @[
        ATProtoDataWithBytes(simpleValue0, sizeof(simpleValue0)),
        ATProtoDataWithBytes(simpleValue24, sizeof(simpleValue24)),
        ATProtoDataWithBytes(halfFloat, sizeof(halfFloat)),
        ATProtoDataWithBytes(float32, sizeof(float32)),
        ATProtoDataWithBytes(float64, sizeof(float64))
    ];

    for (NSData *data in cases) {
        NSError *error = nil;
        id decoded = [ATProtoDagCBOR decodeData:data error:&error];
        XCTAssertNil(decoded);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
        XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeDecodingFailed);
    }
}

- (void)testIndefiniteLengthRejection {
    const uint8_t indefiniteArray[] = {0x9F, 0x01, 0xFF};
    const uint8_t indefiniteMap[] = {0xBF, 0x61, 0x61, 0x01, 0xFF};

    [self assertDecodeFailsForBytes:indefiniteArray length:sizeof(indefiniteArray)];
    [self assertDecodeFailsForBytes:indefiniteMap length:sizeof(indefiniteMap)];
}

- (void)testEmptyCBORData {
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:[NSData data] error:&error];

    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
    XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeDecodingFailed);
}

- (void)testBreakByteOnly {
    const uint8_t breakByte[] = {0xFF};
    [self assertDecodeFailsForBytes:breakByte length:sizeof(breakByte)];
}

#pragma mark - Round Trip and Value Boundaries

- (void)testRoundTripIdentity {
    NSError *error = nil;
    CID *cid = [CID cidWithDigest:[@"round-trip digest" dataUsingEncoding:NSUTF8StringEncoding] codec:0x71];
    NSDictionary *original = @{
        @"a": @[@YES, [NSNull null], @123],
        @"b": @{
            @"bytes": [@"hello" dataUsingEncoding:NSUTF8StringEncoding],
            @"link": cid,
            @"null": [NSNull null],
            @"text": @"dag-cbor"
        },
        @"z": @0
    };

    NSData *encoded = [ATProtoDagCBOR encodeObject:original error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);

    NSData *reencoded = [ATProtoDagCBOR encodeObject:decoded error:&error];
    XCTAssertNotNil(reencoded);
    XCTAssertNil(error);
    XCTAssertEqualObjects(reencoded, encoded);
}

- (void)testLargeIntegerEdgeCases {
    NSError *error = nil;

    // INT64_MAX is supported by the encoder/decoder pair.
    NSNumber *int64Max = [NSNumber numberWithLongLong:INT64_MAX];
    NSData *int64MaxEncoded = [ATProtoDagCBOR encodeObject:int64Max error:&error];
    XCTAssertNotNil(int64MaxEncoded);
    XCTAssertNil(error);

    id int64MaxDecoded = [ATProtoDagCBOR decodeData:int64MaxEncoded error:&error];
    XCTAssertNotNil(int64MaxDecoded);
    XCTAssertNil(error);
    XCTAssertEqualObjects(int64MaxDecoded, int64Max);

    // INT64_MIN is represented directly in raw CBOR bytes to exercise the decode path.
    const uint8_t int64MinBytes[] = {
        0x3B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    };
    id int64MinDecoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(int64MinBytes, sizeof(int64MinBytes)) error:&error];
    XCTAssertNotNil(int64MinDecoded);
    XCTAssertNil(error);
    XCTAssertTrue([int64MinDecoded isKindOfClass:[NSNumber class]]);
    XCTAssertEqual([(NSNumber *)int64MinDecoded longLongValue], INT64_MIN);

    // UINT64_MAX is decoded from raw bytes; re-encoding is only asserted if the implementation supports it.
    const uint8_t uint64MaxBytes[] = {
        0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    };
    NSData *uint64MaxData = ATProtoDataWithBytes(uint64MaxBytes, sizeof(uint64MaxBytes));
    id uint64MaxDecoded = [ATProtoDagCBOR decodeData:uint64MaxData error:&error];
    XCTAssertNotNil(uint64MaxDecoded);
    XCTAssertNil(error);
    XCTAssertTrue([uint64MaxDecoded isKindOfClass:[NSNumber class]]);
    XCTAssertEqual([(NSNumber *)uint64MaxDecoded unsignedLongLongValue], UINT64_MAX);

    NSData *uint64MaxReencoded = [ATProtoDagCBOR encodeObject:uint64MaxDecoded error:&error];
    if (uint64MaxReencoded) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(uint64MaxReencoded, uint64MaxData);
    } else {
        XCTAssertNotNil(error);
    }
}

- (void)testNullValuesInMapsAndArrays {
    NSError *error = nil;
    NSDictionary *object = @{
        @"array": @[[NSNull null], @"value", [NSNull null]],
        @"map": @{
            @"left": [NSNull null],
            @"right": @YES
        }
    };

    NSData *encoded = [ATProtoDagCBOR encodeObject:object error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
    XCTAssertEqualObjects(decoded, object);
}

@end
