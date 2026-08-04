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

- (void)testTrailingDataAfterCompleteItemIsRejected {
    // Attack bytes: 0x01 is a CBOR unsigned integer with value 1; the trailing
    // 0xFF is silently dropped by the pre-fix decoder, leaving identical
    // decoded values across unlimited distinct byte strings. Reject so that
    // two distinct bytes cannot both decode to the same canonical value.
    const uint8_t attack[] = {0x01, 0xFF};
    [self assertDecodeFailsForBytes:attack length:sizeof(attack)];
}

- (void)testDuplicateMapKeyIsRejected {
    // A2 = map of 2 entries, then key "a" (61 61), value 1 (01), then key "a"
    // again (61 61), value 2 (02). Pre-fix the NSDictionary last-write-wins
    // silently kept only the second entry; DAG-CBOR rejects duplicate keys so
    // a CID uniquely identifies one logical map.
    const uint8_t attack[] = {0xA2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02};
    [self assertDecodeFailsForBytes:attack length:sizeof(attack)];
}

- (void)testOutOfOrderMapKeysAreRejected {
    // A2 = map of 2 entries, then key "b" (61 62), value 1 (01), then key "a"
    // (61 61), value 2 (02). "a" (0x61) sorts before "b" (0x62) by the
    // DAG-CBOR canonical sort order, so this encoding is not canonical.
    const uint8_t attack[] = {0xA2, 0x61, 0x62, 0x01, 0x61, 0x61, 0x02};
    [self assertDecodeFailsForBytes:attack length:sizeof(attack)];
}

- (void)testInvalidUTF8TextStringIsRejected {
    // 0x62 declares a two-byte text string, but C3 28 is not a valid UTF-8
    // sequence. Foundation must not replace it and let malformed bytes enter
    // a content-addressed document.
    const uint8_t invalidUTF8[] = {0x62, 0xC3, 0x28};
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(invalidUTF8, sizeof(invalidUTF8))
                                      error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
    XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeDecodingFailed);
    XCTAssertEqualObjects(error.localizedDescription, @"Invalid UTF-8 in text string");
}

- (void)testCanonicalMapKeysAccepted {
    // Positive control: the canonical encoding of {"a": 1, "b": 2} must
    // decode cleanly. If this fails after the fix, the comparison is wrong
    // (likely off-by-one on length-first sort).
    const uint8_t canonical[] = {0xA2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02};
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(canonical, sizeof(canonical))
                                      error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
}

- (void)testMapKeyLengthFirstBoundary {
    // Cross-length length-first boundary using two text-string keys (DAG-CBOR
    // requires string-only map keys — see testNonStringMapKeyIsRejected below
    // for that rule; this test is purely about sort order once both keys are
    // legal). Empty string "" encodes as a single byte (0x60); "a" encodes as
    // two bytes (0x61 0x61). By DAG-CBOR canonical sort, the shorter encoded
    // key sorts first regardless of content.
    //
    // Originally used an integer key (0) in place of "" to exercise the same
    // boundary across major types; Phase 1 (docs/adr/0032) made integer keys
    // unconditionally invalid, which made that variant untestable as a
    // positive control. This still checks the same length-first comparison.
    const uint8_t canonical[] = {0xA2, 0x60, 0x01, 0x61, 0x61, 0x02};  // {"": 1, "a": 2}
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(canonical, sizeof(canonical))
                                      error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);

    // Same keys in byte-wise (wrong) order — "a" first, then "" — must reject
    // because the 2-byte key sorts after the 1-byte key by length-first rule.
    const uint8_t outOfOrder[] = {0xA2, 0x61, 0x61, 0x01, 0x60, 0x02};  // {"a": 1, "": 2}
    [self assertDecodeFailsForBytes:outOfOrder length:sizeof(outOfOrder)];
}

- (void)testIntegerMapKeyIsRejected {
    // {0: 1} — DAG-CBOR requires text-string map keys; Phase 1 (docs/adr/0032)
    // closed this as a content-addressing bug: it used to decode successfully
    // and re-encode without the ability to round-trip a non-string key at all,
    // which is exactly the kind of asymmetry that breaks CID stability.
    const uint8_t integerKey[] = {0xA1, 0x00, 0x01};  // {0: 1}
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(integerKey, sizeof(integerKey))
                                      error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
    XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeNonStringMapKey);
}

- (void)testThreeEntryCanonicalMapAccepted {
    // Three-entry positive control: {"a":1, "b":2, "c":3}. Confirms the sort
    // check holds across more than one prior-key update, not just the first
    // transition.
    const uint8_t canonical[] = {0xA3, 0x61, 0x61, 0x01,
                                           0x61, 0x62, 0x02,
                                           0x61, 0x63, 0x03};
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(canonical, sizeof(canonical))
                                      error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
}

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
    // Unassigned/reserved simple values (major type 7, additional info 0-19
    // inline or 24 in the following byte) have no DRISL meaning at all and
    // fail as a generic decode error.
    const uint8_t simpleValue0[] = {0xE0};
    const uint8_t simpleValue24[] = {0xF8, 0x18};
    NSArray *genericCases = @[
        ATProtoDataWithBytes(simpleValue0, sizeof(simpleValue0)),
        ATProtoDataWithBytes(simpleValue24, sizeof(simpleValue24)),
    ];
    for (NSData *data in genericCases) {
        NSError *error = nil;
        id decoded = [ATProtoDagCBOR decodeData:data error:&error];
        XCTAssertNil(decoded);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
        XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeDecodingFailed);
    }

    // Floats (additional info 25/26/27) are a distinct, more specific
    // rejection since Phase 1 (docs/adr/0032) introduced
    // ATProtoDRISLProfile: the default ATProto profile still rejects every
    // float width, but now with ATProtoDagCBORErrorCodeFloatsNotAllowed
    // rather than the generic decoding-failed code, since "this is a float
    // and the ATProto profile forbids floats" is a more specific and more
    // useful diagnosis than "malformed input."
    const uint8_t halfFloat[] = {0xF9, 0x00, 0x00};
    const uint8_t float32[] = {0xFA, 0x3F, 0x80, 0x00, 0x00};
    const uint8_t float64[] = {0xFB, 0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    NSArray *floatCases = @[
        ATProtoDataWithBytes(halfFloat, sizeof(halfFloat)),
        ATProtoDataWithBytes(float32, sizeof(float32)),
        ATProtoDataWithBytes(float64, sizeof(float64))
    ];
    for (NSData *data in floatCases) {
        NSError *error = nil;
        id decoded = [ATProtoDagCBOR decodeData:data error:&error];
        XCTAssertNil(decoded);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
        XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeFloatsNotAllowed);
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

- (void)testNonMinimalLengthEncodingRejectedForAllAdditionalInfoLevels {
    // DAG-CBOR canonical form requires that a length/integer value fits in the
    // smallest natural encoding for its declared `additionalInfo`. Otherwise
    // the same logical value would have multiple valid encodings, breaking
    // content addressing. Each attack below encodes integer 5 in a wider form
    // than necessary; canonical encoding is just `0x05` (1 byte).
    const uint8_t nonMinimal24[] = {0x18, 0x05};                                  // 2 bytes for value 5
    const uint8_t nonMinimal25[] = {0x19, 0x00, 0x05};                            // 3 bytes for value 5
    const uint8_t nonMinimal26[] = {0x1A, 0x00, 0x00, 0x00, 0x05};                // 5 bytes for value 5
    const uint8_t nonMinimal27[] = {0x1B, 0x00, 0x00, 0x00, 0x00,
                                    0x00, 0x00, 0x00, 0x05};                     // 9 bytes for value 5

    [self assertDecodeFailsForBytes:nonMinimal24 length:sizeof(nonMinimal24)];
    [self assertDecodeFailsForBytes:nonMinimal25 length:sizeof(nonMinimal25)];
    [self assertDecodeFailsForBytes:nonMinimal26 length:sizeof(nonMinimal26)];
    [self assertDecodeFailsForBytes:nonMinimal27 length:sizeof(nonMinimal27)];
}

- (void)testCanonicalLengthEncodingAcceptedAtFloor {
    // Positive control: a length value that exactly meets the natural floor
    // for its additionalInfo must decode cleanly. `0x18 0x18` is the
    // canonical encoding of integer 24 (2 bytes: 24 is the smallest value
    // that requires additionalInfo 24). `0x19 0x01 0x00` is the canonical
    // encoding of integer 256.
    NSError *error = nil;
    const uint8_t canonical24[] = {0x18, 0x18};
    id decoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(canonical24, sizeof(canonical24))
                                      error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);

    const uint8_t canonical25[] = {0x19, 0x01, 0x00};
    decoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(canonical25, sizeof(canonical25))
                                  error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
}

#pragma mark - Round Trip and Value Boundaries

- (void)testRoundTripIdentity {
    NSError *error = nil;
    CID *cid = [CID cidWithDigest:[CID sha256Digest:[@"data" dataUsingEncoding:NSUTF8StringEncoding]] codec:0x71];
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

    // UINT64_MAX (major type 0, unsigned) is outside DAG-CBOR's int64 range and
    // must be rejected, not silently truncated by a later int64 cast.
    const uint8_t uint64MaxBytes[] = {
        0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    };
    [self assertDecodeFailsForBytes:uint64MaxBytes length:sizeof(uint64MaxBytes)];
}

- (void)testNegativeIntegerEdgeAtInt64MaxPayloadDecodesToInt64Min {
    // positive control for the §3.3 / §1.5 item 4 fix: a CBOR negative integer
    // with payload 0x7FFFFFFFFFFFFFFF encodes the value -(INT64_MAX+1) = INT64_MIN.
    // The pre-fix expression `-(int64_t)(value + 1)` invoked signed-overflow UB
    // at that exact boundary; the fix ` -1 - (int64_t)value` is well-defined.
    // Pre-fix this would crash the test runner; post-fix it decodes cleanly.
    const uint8_t int64MinPayload[] = {
        0x3B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    };
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:ATProtoDataWithBytes(int64MinPayload, sizeof(int64MinPayload))
                                      error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
    XCTAssertTrue([decoded isKindOfClass:[NSNumber class]]);
    XCTAssertEqual([(NSNumber *)decoded longLongValue], INT64_MIN);
}

#pragma mark - Width Defects (workstream 01 S11)

- (void)testByteStringLengthOverflowRejected {
    // Headline case: index=9 after the header, declared length 2^64-5 wraps
    // `*index + len` back to 4, which is <= length(9) under the old check.
    const uint8_t overflowByteString[] = {
        0x5B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFB
    };
    [self assertDecodeFailsForBytes:overflowByteString length:sizeof(overflowByteString)];
}

- (void)testArrayCountExceedingRemainingDataRejectedWithoutLargeAllocation {
    // Array(8-byte length) declaring far more elements than the (empty)
    // remaining input can possibly hold.
    NSMutableData *data = [NSMutableData data];
    uint8_t header = 0x9B;
    [data appendBytes:&header length:1];
    uint64_t count = OSSwapHostToBigInt64(UINT32_MAX);
    [data appendBytes:&count length:8];

    NSDate *start = [NSDate date];
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:data error:&error];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];

    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertLessThan(duration, 1.0, @"Should reject fast, not allocate for the declared count");
}

- (void)testMapCountExceedingRemainingDataRejectedWithoutLargeAllocation {
    // Map(8-byte length) declaring far more entries than the (empty)
    // remaining input can possibly hold.
    NSMutableData *data = [NSMutableData data];
    uint8_t header = 0xBB;
    [data appendBytes:&header length:1];
    uint64_t count = OSSwapHostToBigInt64(UINT32_MAX);
    [data appendBytes:&count length:8];

    NSDate *start = [NSDate date];
    NSError *error = nil;
    id decoded = [ATProtoDagCBOR decodeData:data error:&error];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];

    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertLessThan(duration, 1.0, @"Should reject fast, not allocate for the declared count");
}

- (void)testUnsignedIntegerAboveInt64RangeRejected {
    // Major type 0, value 2^63 (INT64_MAX + 1): first value outside the
    // representable int64 range.
    const uint8_t aboveInt64Max[] = {
        0x1B, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    [self assertDecodeFailsForBytes:aboveInt64Max length:sizeof(aboveInt64Max)];
}

- (void)testNegativeIntegerEdgeAtTwoPow64MinusOneRejected {
    // Major type 1, value 2^64-1: previously wrapped `-(int64_t)(value + 1)`
    // to 0 instead of being rejected.
    const uint8_t negativeEdge[] = {
        0x3B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    };
    [self assertDecodeFailsForBytes:negativeEdge length:sizeof(negativeEdge)];
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
