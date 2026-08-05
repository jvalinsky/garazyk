// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file DASLConformanceTests.m

 @abstract Runs the upstream DASL conformance vectors against Core's DRISL and
 ATProtoCID implementations.

 @discussion Vectors come from https://github.com/hyphacoop/dasl-testing and
 live in Garazyk/Tests/fixtures/dasl-testing/. Each has a type:

 - `roundtrip`  — decoding then re-encoding must reproduce the input byte for
                  byte. This is the property content addressing rests on.
 - `invalid_in` — decoding must fail.
 - `invalid_out`— the value the bytes describe must not be encodable.

 Only vectors tagged `basic`, `dag-cbor` or `dasl-cid` apply. The suite also
 covers dCBOR, CDE, plain RFC 8949 and CBOR Core, which are different profiles
 — several of their vectors are deliberate inverses of the DAG-CBOR ones
 (`f93e00` round-trips under `rfc8949` and is invalid under `dag-cbor`), so
 running them all against one implementation would be incoherent.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import <math.h>
#import <string.h>
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

/// Tags that mean "this vector describes the profile Garazyk implements".
static NSSet<NSString *> *DASLApplicableTags(void) {
    static NSSet<NSString *> *tags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tags = [NSSet setWithArray:@[@"basic", @"dag-cbor", @"dasl-cid"]];
    });
    return tags;
}

/*!
 Vectors Garazyk knowingly does not satisfy, keyed `file/name/type`.

 Each entry is a decision, not a bug queue: the test fails if a listed vector
 starts passing, so the list cannot rot into a stale excuse. Anything failing
 that is *not* listed here is a defect.
 */
static NSDictionary<NSString *, NSString *> *DASLKnownDeviations(void) {
    static NSDictionary<NSString *, NSString *> *deviations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *intRange =
            @"ATProtoDagCBOR clamps integers to int64. The full CBOR range needs a boxed "
            @"wide-integer type NSNumber cannot provide (-(2^64) has no NSNumber "
            @"representation at all), and the clamp is a deliberate bound on "
            @"attacker-supplied input. No ATProto record carries integers this large. "
            @"See docs/adr/0032-dasl-conformance-profiles.md.";
        deviations = @{
            @"integer_range.json/largest CBOR integer, 2^64-1/roundtrip": intRange,
            @"integer_range.json/smallest CBOR integer, -(2^64)/roundtrip": intRange,
        };
    });
    return deviations;
}

#pragma mark - Lenient reader for invalid_out vectors

/*!
 Minimal permissive CBOR reader, used only to build the value an `invalid_out`
 vector describes so the encoder can be asked to reject it.

 It exists because the production decoders correctly refuse this input — the
 whole point of `invalid_out` is that the *bytes* may be readable while the
 *value* must not be writable. Returns nil when the value has no representation
 in Garazyk's object model at all (bignums, datetimes, `undefined`), in which
 case the vector is satisfied trivially: an inexpressible value cannot be
 encoded.
 */
static id DASLLenientDecode(const uint8_t *bytes, NSUInteger length, NSUInteger *index);

static double DASLHalfToDouble(uint16_t half) {
    int exponent = (half >> 10) & 0x1F;
    int mantissa = half & 0x3FF;
    double magnitude;
    if (exponent == 0) {
        magnitude = ldexp((double)mantissa, -24);
    } else if (exponent == 31) {
        magnitude = mantissa ? NAN : INFINITY;
    } else {
        magnitude = ldexp((double)(mantissa + 1024), exponent - 25);
    }
    return (half & 0x8000) ? -magnitude : magnitude;
}

static BOOL DASLReadCount(const uint8_t *bytes, NSUInteger length, NSUInteger *index,
                          uint8_t additional, uint64_t *out) {
    NSUInteger width;
    switch (additional) {
        case 24: width = 1; break;
        case 25: width = 2; break;
        case 26: width = 4; break;
        case 27: width = 8; break;
        default:
            if (additional >= 28) return NO;
            *out = additional;
            return YES;
    }
    if (*index > length || length - *index < width) return NO;
    uint64_t value = 0;
    for (NSUInteger i = 0; i < width; i++) {
        value = (value << 8) | bytes[*index + i];
    }
    *index += width;
    *out = value;
    return YES;
}

static id DASLLenientDecode(const uint8_t *bytes, NSUInteger length, NSUInteger *index) {
    if (*index >= length) return nil;
    uint8_t initial = bytes[(*index)++];
    uint8_t major = (initial >> 5) & 0x7;
    uint8_t additional = initial & 0x1F;

    uint64_t count = 0;
    if (major != 7 && !DASLReadCount(bytes, length, index, additional, &count)) {
        return nil;
    }

    switch (major) {
        case 0:
            if (count > (uint64_t)INT64_MAX) return nil;
            return @((int64_t)count);
        case 1:
            if (count > (uint64_t)INT64_MAX) return nil;
            return @(-1 - (int64_t)count);
        case 2:
        case 3: {
            if (*index > length || count > length - *index) return nil;
            NSData *payload = [NSData dataWithBytes:bytes + *index length:(NSUInteger)count];
            *index += (NSUInteger)count;
            if (major == 2) return payload;
            return [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
        }
        case 4: {
            NSMutableArray *array = [NSMutableArray array];
            for (uint64_t i = 0; i < count; i++) {
                id item = DASLLenientDecode(bytes, length, index);
                if (!item) return nil;
                [array addObject:item];
            }
            return array;
        }
        case 5: {
            // Non-string keys are kept deliberately: `a10000` exists so that
            // the *encoder* can be asked to reject an integer-keyed map.
            NSMutableDictionary *map = [NSMutableDictionary dictionary];
            for (uint64_t i = 0; i < count; i++) {
                id key = DASLLenientDecode(bytes, length, index);
                if (!key) return nil;
                id value = DASLLenientDecode(bytes, length, index);
                if (!value) return nil;
                map[key] = value;
            }
            return map;
        }
        case 6: {
            id tagged = DASLLenientDecode(bytes, length, index);
            if (count != 42 || ![tagged isKindOfClass:[NSData class]]) {
                return nil;  // bignums, datetimes, self-describing CBOR
            }
            NSData *linkBytes = (NSData *)tagged;
            if (linkBytes.length < 1 || ((const uint8_t *)linkBytes.bytes)[0] != 0x00) return nil;
            return [ATProtoCID cidFromBytes:[linkBytes subdataWithRange:NSMakeRange(1, linkBytes.length - 1)]];
        }
        case 7: {
            switch (additional) {
                case 20: return @NO;
                case 21: return @YES;
                case 22: return [NSNull null];
                case 25:
                case 26:
                case 27: {
                    NSUInteger width = (additional == 25) ? 2 : (additional == 26) ? 4 : 8;
                    if (*index > length || length - *index < width) return nil;
                    uint64_t raw = 0;
                    for (NSUInteger i = 0; i < width; i++) {
                        raw = (raw << 8) | bytes[*index + i];
                    }
                    *index += width;
                    double value;
                    if (width == 2) {
                        value = DASLHalfToDouble((uint16_t)raw);
                    } else if (width == 4) {
                        uint32_t single = (uint32_t)raw;
                        float f;
                        memcpy(&f, &single, sizeof(f));
                        value = f;
                    } else {
                        memcpy(&value, &raw, sizeof(value));
                    }
                    return [ATProtoDRISLFloat floatWithValue:value];
                }
                default:
                    return nil;  // `undefined` and unassigned simple values
            }
        }
        default:
            return nil;
    }
}

#pragma mark - Tests

@interface DASLConformanceTests : XCTestCase
@end

@implementation DASLConformanceTests {
    NSUInteger _applied;
    NSUInteger _skippedByTag;
    NSUInteger _inexpressible;
}

- (nullable NSString *)fixturePath:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = fm.currentDirectoryPath;
    NSArray<NSString *> *bases = @[
        @"Garazyk/Tests/fixtures/dasl-testing",
        @"Tests/fixtures/dasl-testing",
        @"fixtures/dasl-testing",
        @"../Garazyk/Tests/fixtures/dasl-testing",
        @"../../Garazyk/Tests/fixtures/dasl-testing",
        @"../../../Garazyk/Tests/fixtures/dasl-testing",
    ];
    for (NSString *base in bases) {
        NSString *candidate = [base stringByAppendingPathComponent:name];
        NSString *path = [candidate hasPrefix:@"/"] ? candidate
                                                    : [cwd stringByAppendingPathComponent:candidate];
        if ([fm fileExistsAtPath:path]) return path;
    }
    NSString *bundled = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:name];
    if (bundled && [fm fileExistsAtPath:bundled]) return bundled;
    return nil;
}

- (nullable NSArray<NSDictionary *> *)vectorsFromFixture:(NSString *)name {
    NSString *path = [self fixturePath:name];
    XCTAssertNotNil(path, @"DASL fixture not found: %@", name);
    if (!path) return nil;

    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"Could not read DASL fixture: %@", path);
    if (!data) return nil;

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertTrue([parsed isKindOfClass:[NSArray class]],
                  @"DASL fixture %@ is not a JSON array: %@", name, error);
    return [parsed isKindOfClass:[NSArray class]] ? parsed : nil;
}

- (nullable NSData *)dataFromHex:(NSString *)hex {
    if (hex.length % 2 != 0) return nil;
    NSMutableData *data = [NSMutableData dataWithCapacity:hex.length / 2];
    const char *chars = hex.UTF8String;
    for (NSUInteger i = 0; i < hex.length; i += 2) {
        int high = -1, low = -1;
        for (int pass = 0; pass < 2; pass++) {
            char c = chars[i + pass];
            int value;
            if (c >= '0' && c <= '9') value = c - '0';
            else if (c >= 'a' && c <= 'f') value = c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') value = c - 'A' + 10;
            else return nil;
            if (pass == 0) high = value; else low = value;
        }
        uint8_t byte = (uint8_t)((high << 4) | low);
        [data appendBytes:&byte length:1];
    }
    return data;
}

- (NSString *)hexFromData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

/// Runs one vector. Returns YES when the implementation behaved as the vector
/// requires, so the caller can compare against the known-deviation list.
- (BOOL)satisfiesVector:(NSDictionary *)vector
                   data:(NSData *)data
                failure:(NSString **)failure {
    NSString *type = vector[@"type"];

    if ([type isEqualToString:@"roundtrip"]) {
        NSError *error = nil;
        id decoded = [ATProtoDagCBOR decodeData:data
                                        profile:ATProtoDRISLProfileDRISL
                                          error:&error];
        if (!decoded) {
            if (failure) *failure = [NSString stringWithFormat:@"decode failed: %@",
                                     error.localizedDescription];
            return NO;
        }
        NSError *encodeError = nil;
        NSData *reencoded = [ATProtoDagCBOR encodeObject:decoded
                                                 profile:ATProtoDRISLProfileDRISL
                                                   error:&encodeError];
        if (!reencoded) {
            if (failure) *failure = [NSString stringWithFormat:@"re-encode failed: %@",
                                     encodeError.localizedDescription];
            return NO;
        }
        if (![reencoded isEqualToData:data]) {
            if (failure) *failure = [NSString stringWithFormat:@"re-encoded to %@",
                                     [self hexFromData:reencoded]];
            return NO;
        }
        return YES;
    }

    if ([type isEqualToString:@"invalid_in"]) {
        NSError *error = nil;
        id decoded = [ATProtoDagCBOR decodeData:data
                                        profile:ATProtoDRISLProfileDRISL
                                          error:&error];
        if (decoded) {
            if (failure) *failure = [NSString stringWithFormat:@"decoded to %@ instead of failing",
                                     decoded];
            return NO;
        }
        return YES;
    }

    if ([type isEqualToString:@"invalid_out"]) {
        NSUInteger index = 0;
        id value = DASLLenientDecode(data.bytes, data.length, &index);
        if (!value) {
            // No representation for this value, so it cannot be encoded.
            _inexpressible++;
            return YES;
        }
        NSError *error = nil;
        NSData *encoded = [ATProtoDagCBOR encodeObject:value
                                               profile:ATProtoDRISLProfileDRISL
                                                 error:&error];
        if (encoded) {
            if (failure) *failure = [NSString stringWithFormat:@"encoded to %@ instead of failing",
                                     [self hexFromData:encoded]];
            return NO;
        }
        return YES;
    }

    if (failure) *failure = [NSString stringWithFormat:@"unknown vector type %@", type];
    return NO;
}

- (void)runFixture:(NSString *)name {
    NSArray<NSDictionary *> *vectors = [self vectorsFromFixture:name];
    if (!vectors) return;

    NSDictionary<NSString *, NSString *> *deviations = DASLKnownDeviations();

    for (NSDictionary *vector in vectors) {
        NSArray<NSString *> *tags = vector[@"tags"] ?: @[];
        NSMutableSet<NSString *> *tagSet = [NSMutableSet setWithArray:tags];
        [tagSet intersectSet:DASLApplicableTags()];
        if (tagSet.count == 0) {
            _skippedByTag++;
            continue;
        }

        NSData *data = [self dataFromHex:vector[@"data"]];
        XCTAssertNotNil(data, @"%@: vector '%@' has unparseable hex", name, vector[@"name"]);
        if (!data) continue;

        _applied++;

        NSString *key = [NSString stringWithFormat:@"%@/%@/%@", name, vector[@"name"], vector[@"type"]];
        NSString *deviationReason = deviations[key];

        NSString *failure = nil;
        BOOL satisfied = [self satisfiesVector:vector data:data failure:&failure];

        if (deviationReason) {
            // A deviation that starts passing means the list is out of date.
            // Leaving it in place would quietly excuse a future regression.
            XCTAssertFalse(satisfied,
                           @"%@ is listed as a known deviation but now passes — remove it from "
                           @"DASLKnownDeviations(). Recorded reason: %@", key, deviationReason);
            continue;
        }

        XCTAssertTrue(satisfied, @"%@ [%@] %@\n  %@\n  data: %@\n  %@",
                      name, [tags componentsJoinedByString:@","], vector[@"name"],
                      vector[@"desc"], vector[@"data"], failure);
    }
}

- (void)setUp {
    [super setUp];
    _applied = 0;
    _skippedByTag = 0;
    _inexpressible = 0;
}

#pragma mark - Per-fixture vectors

- (void)testDASLVectorsCID { [self runFixture:@"cid.json"]; }
- (void)testDASLVectorsConcatenation { [self runFixture:@"concat.json"]; }
- (void)testDASLVectorsFloats { [self runFixture:@"floats.json"]; }
- (void)testDASLVectorsIndefiniteLengths { [self runFixture:@"indefinite.json"]; }
- (void)testDASLVectorsIntegerRange { [self runFixture:@"integer_range.json"]; }
- (void)testDASLVectorsMapKeys { [self runFixture:@"map_keys.json"]; }
- (void)testDASLVectorsNumericReduction { [self runFixture:@"numeric_reduction.json"]; }
- (void)testDASLVectorsShortForm { [self runFixture:@"short_form.json"]; }
- (void)testDASLVectorsSimpleValues { [self runFixture:@"simple.json"]; }
- (void)testDASLVectorsTags { [self runFixture:@"tags.json"]; }
- (void)testDASLVectorsUTF8 { [self runFixture:@"utf8.json"]; }

#pragma mark - Whole-corpus accounting

/// Guards against the fixture set silently shrinking — a refresh that drops
/// files would otherwise turn into a quietly smaller suite.
- (void)testEveryVectorIsAccountedFor {
    NSArray<NSString *> *files = @[
        @"cid.json", @"concat.json", @"floats.json", @"indefinite.json",
        @"integer_range.json", @"map_keys.json", @"numeric_reduction.json",
        @"short_form.json", @"simple.json", @"tags.json", @"utf8.json",
    ];
    NSUInteger total = 0;
    for (NSString *file in files) {
        NSArray *vectors = [self vectorsFromFixture:file];
        XCTAssertNotNil(vectors, @"Missing DASL fixture %@", file);
        total += vectors.count;
    }
    XCTAssertEqual(total, (NSUInteger)104,
                   @"Expected 104 upstream DASL vectors; the fixture set changed. Review the "
                   @"new vectors, then update this count.");
}

#pragma mark - Profile boundary

/// The ATProto profile is the one repository data uses, and it must keep
/// rejecting every float regardless of what DRISL permits.
- (void)testATProtoProfileRejectsFloatsThatDRISLAccepts {
    NSData *positiveOne = [self dataFromHex:@"fb3ff0000000000000"];
    XCTAssertNotNil(positiveOne);

    NSError *drislError = nil;
    id underDRISL = [ATProtoDagCBOR decodeData:positiveOne
                                       profile:ATProtoDRISLProfileDRISL
                                         error:&drislError];
    XCTAssertTrue([underDRISL isKindOfClass:[ATProtoDRISLFloat class]],
                  @"DRISL permits 64-bit floats: %@", drislError);

    NSError *atprotoError = nil;
    id underATProto = [ATProtoDagCBOR decodeData:positiveOne
                                         profile:ATProtoDRISLProfileATProto
                                           error:&atprotoError];
    XCTAssertNil(underATProto, @"ATProto records must not accept floats");
    XCTAssertEqual(atprotoError.code, ATProtoDagCBORErrorCodeFloatsNotAllowed);

    NSError *encodeError = nil;
    NSData *encoded = [ATProtoDagCBOR encodeObject:[ATProtoDRISLFloat floatWithValue:1.0]
                                           profile:ATProtoDRISLProfileATProto
                                             error:&encodeError];
    XCTAssertNil(encoded, @"ATProto records must not emit floats");
    XCTAssertEqual(encodeError.code, ATProtoDagCBORErrorCodeFloatsNotAllowed);
}

/// Negative zero and positive zero are different bytes and therefore different
/// CIDs. Collapsing them would be a content-addressing bug, not a rounding one.
- (void)testNegativeZeroIsDistinctFromZero {
    NSData *negativeZero = [self dataFromHex:@"fb8000000000000000"];
    NSData *positiveZero = [self dataFromHex:@"fb0000000000000000"];

    id decodedNegative = [ATProtoDagCBOR decodeData:negativeZero
                                            profile:ATProtoDRISLProfileDRISL
                                              error:nil];
    id decodedPositive = [ATProtoDagCBOR decodeData:positiveZero
                                            profile:ATProtoDRISLProfileDRISL
                                              error:nil];
    XCTAssertNotNil(decodedNegative);
    XCTAssertNotNil(decodedPositive);
    XCTAssertNotEqualObjects(decodedNegative, decodedPositive);

    XCTAssertEqualObjects([ATProtoDagCBOR encodeObject:decodedNegative
                                               profile:ATProtoDRISLProfileDRISL
                                                 error:nil],
                          negativeZero);
    XCTAssertEqualObjects([ATProtoDagCBOR encodeObject:decodedPositive
                                               profile:ATProtoDRISLProfileDRISL
                                                 error:nil],
                          positiveZero);
}

#pragma mark - Strict ATProtoCID profile

- (void)testDASLCIDRejectsNonConformantForms {
    // A conformant ATProtoCID, for contrast: CIDv1 + raw + sha2-256 + 32 bytes.
    NSData *valid = [self dataFromHex:
        @"015512205891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"];
    ATProtoCID *cid = [ATProtoCID daslCIDFromBytes:valid];
    XCTAssertNotNil(cid, @"raw + sha2-256 is the canonical DASL CID shape");
    XCTAssertTrue(cid.isDASLConformant);

    NSDictionary<NSString *, NSString *> *rejected = @{
        @"CIDv0 (no version prefix)":
            @"122022ad631c69ee983095b5b8acd029ff94aff1dc6c48837878589a92b90dfea317",
        @"dag-pb codec":
            @"0170122 0e9822efc7c48027a5429fdbd988d02b2b8e4eaee8f62c32bd1021dcf922e05de",
        @"SHA-1 multihash":
            @"0155 1114f572d396fae9206628714fb2ce00f72e94f2258f",
        @"digest shorter than 32 bytes":
            @"0155121f5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be",
        @"non-canonical varint version (0x81 0x00 for 0x01)":
            @"81005512205891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03",
    };
    for (NSString *label in rejected) {
        NSString *hex = [rejected[label] stringByReplacingOccurrencesOfString:@" " withString:@""];
        NSData *data = [self dataFromHex:hex];
        XCTAssertNotNil(data, @"bad test hex for %@", label);
        XCTAssertNil([ATProtoCID daslCIDFromBytes:data], @"strict profile must reject: %@", label);
    }

    // BLAKE3 is Big DASL only — accepting it in the base profile would let a
    // non-interoperable ATProtoCID into repository data.
    NSData *blake3 = [self dataFromHex:
        @"01551e208e4c7c1b99dbfd50e7a95185fead5ee1448fa904a2fdd778eaf5f2dbfd629a99"];
    XCTAssertNil([ATProtoCID daslCIDFromBytes:blake3 profile:ATProtoDASLCIDProfileBase],
                 @"BLAKE3 is not part of the base DASL CID spec");
    XCTAssertNotNil([ATProtoCID daslCIDFromBytes:blake3 profile:ATProtoDASLCIDProfileBig],
                    @"BLAKE3 is a valid Big DASL CID");
}

- (void)testDASLCIDStringFormIsSingleSpelling {
    NSData *valid = [self dataFromHex:
        @"015512205891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"];
    ATProtoCID *cid = [ATProtoCID daslCIDFromBytes:valid];
    XCTAssertNotNil(cid);

    NSString *canonical = cid.stringValue;
    XCTAssertEqual(canonical.length, ATProtoDASLCIDStringLength);
    XCTAssertEqualObjects([ATProtoCID daslCIDFromString:canonical], cid);

    // Each of these decodes to the same bytes under a permissive parser, and
    // each is a second spelling of one ATProtoCID — which is exactly what a strict
    // profile exists to prevent.
    XCTAssertNil([ATProtoCID daslCIDFromString:canonical.uppercaseString], @"uppercase base32");
    XCTAssertNil([ATProtoCID daslCIDFromString:[canonical stringByAppendingString:@"="]], @"padding");
    XCTAssertNil([ATProtoCID daslCIDFromString:[@"f" stringByAppendingString:
                                         [canonical substringFromIndex:1]]], @"base16 prefix");

    // The final character carries two padding bits that must be zero; `b` is
    // index 1, whose low bit is set.
    NSString *nonZeroTrailingBits =
        [[canonical substringToIndex:canonical.length - 1] stringByAppendingString:@"b"];
    XCTAssertNil([ATProtoCID daslCIDFromString:nonZeroTrailingBits], @"non-zero trailing bits");

    // Still permissive where ATProto needs it to be: the syntax fixtures and
    // legacy blob references depend on this parser accepting dag-pb.
    XCTAssertNotNil([ATProtoCID cidFromString:@"bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"],
                    @"the permissive parser must keep accepting dag-pb CIDs");
    XCTAssertNil([ATProtoCID daslCIDFromString:@"bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"],
                 @"the strict profile must not");
}

@end
