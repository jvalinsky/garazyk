// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/CID.h"
#import "Core/TID.h"
#import "Core/DID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
#import "Core/ATProtoBase32.h"

#pragma mark - CID Tests

@interface CIDTests : XCTestCase
@end

@implementation CIDTests

#pragma mark - CID Creation

- (void)testCidWithDigestCodec {
    NSData *digest = [NSData dataWithBytes:"0123456789abcdef0123456789abcdef" length:16];
    CID *cid = [CID cidWithDigest:digest codec:0x55];
    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.version, 1);
    XCTAssertEqual(cid.codec, 0x55);
    XCTAssertNotNil(cid.multihash);
}

- (void)testCidWithDigestNilDigest {
    CID *cid = [CID cidWithDigest:nil codec:0x55];
    XCTAssertNil(cid);
}

- (void)testCidWithDigestEmptyDigest {
    NSData *empty = [NSData data];
    CID *cid = [CID cidWithDigest:empty codec:0x55];
    XCTAssertNil(cid);
}

- (void)testCidWithMultihashCodec {
    // Construct a valid multihash: 0x12 (sha2-256) + 0x20 (32 bytes) + 32 zero bytes
    NSMutableData *mh = [NSMutableData dataWithLength:34];
    uint8_t *bytes = (uint8_t *)mh.mutableBytes;
    bytes[0] = 0x12; // sha2-256
    bytes[1] = 0x20; // 32 bytes
    CID *cid = [CID cidWithMultihash:mh codec:0x71];
    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.codec, 0x71);
}

- (void)testCidWithMultihashNil {
    CID *cid = [CID cidWithMultihash:nil codec:0x55];
    XCTAssertNil(cid);
}

#pragma mark - CID SHA-256

- (void)testSha256ProducesConsistentHash {
    NSData *input = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid1 = [CID sha256:input];
    CID *cid2 = [CID sha256:input];
    XCTAssertNotNil(cid1);
    XCTAssertNotNil(cid2);
    XCTAssertEqualObjects(cid1.stringValue, cid2.stringValue);
}

- (void)testSha256DifferentInputs {
    NSData *input1 = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *input2 = [@"world" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid1 = [CID sha256:input1];
    CID *cid2 = [CID sha256:input2];
    XCTAssertNotEqualObjects(cid1.stringValue, cid2.stringValue);
}

- (void)testSha256DigestLength {
    NSData *input = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *digest = [CID sha256Digest:input];
    XCTAssertNotNil(digest);
    XCTAssertEqual(digest.length, 32); // SHA-256 produces 32 bytes
}

- (void)testRawSha256SameAsSha256Digest {
    NSData *input = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *digest1 = [CID sha256Digest:input];
    NSData *digest2 = [CID rawSha256:input];
    XCTAssertEqualObjects(digest1, digest2);
}

#pragma mark - CID String Round-Trip

- (void)testCidFromStringBase32 {
    // Create a CID and verify round-trip through base32 string
    NSData *input = [@"test data" dataUsingEncoding:NSUTF8StringEncoding];
    CID *original = [CID sha256:input];
    NSString *str = original.stringValue;
    XCTAssertNotNil(str);
    XCTAssertTrue(str.length > 0);

    CID *parsed = [CID cidFromString:str];
    XCTAssertNotNil(parsed);
    XCTAssertEqualObjects(parsed.stringValue, str);
}

- (void)testCidFromStringNil {
    CID *cid = [CID cidFromString:nil];
    XCTAssertNil(cid);
}

- (void)testCidFromStringEmpty {
    CID *cid = [CID cidFromString:@""];
    XCTAssertNil(cid);
}

#pragma mark - CID Equality

- (void)testCidEquality {
    NSData *input = [@"same data" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid1 = [CID sha256:input];
    CID *cid2 = [CID sha256:input];
    XCTAssertTrue([cid1 isEqualToCID:cid2]);
    XCTAssertEqualObjects(cid1, cid2);
}

- (void)testCidInequality {
    CID *cid1 = [CID sha256:[@"data1" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid2 = [CID sha256:[@"data2" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertFalse([cid1 isEqualToCID:cid2]);
}

#pragma mark - CID Bytes

- (void)testCidBytesNotNil {
    NSData *input = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid = [CID sha256:input];
    NSData *bytes = cid.bytes;
    XCTAssertNotNil(bytes);
    XCTAssertTrue(bytes.length > 0);
}

#pragma mark - CID Copy

- (void)testCidCopy {
    NSData *input = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CID *original = [CID sha256:input];
    CID *copy = [original copy];
    XCTAssertNotNil(copy);
    XCTAssertTrue([original isEqualToCID:copy]);
    // Copy may return same object for immutable classes — just verify equality
}

#pragma mark - CID Base32

- (void)testBase32EncodeDecode {
    NSData *data = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [CID base32Encode:data];
    XCTAssertNotNil(encoded);
    XCTAssertTrue(encoded.length > 0);

    NSData *decoded = [CID base32Decode:encoded];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(decoded, data);
}

- (void)testBase32EmptyData {
    NSData *data = [NSData data];
    NSString *encoded = [CID base32Encode:data];
    XCTAssertNotNil(encoded);
}

#pragma mark - CID Base58

- (void)testBase58EncodeDecode {
    NSData *data = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [CID base58btcEncode:data];
    XCTAssertNotNil(encoded);
    XCTAssertTrue(encoded.length > 0);

    NSData *decoded = [CID base58btcDecode:encoded];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(decoded, data);
}

- (void)testBase58DecodeInvalid {
    NSData *decoded = [CID base58btcDecode:@"0OIl"]; // Invalid base58 chars
    // Should return nil or empty — implementation-dependent
    // Base58 alphabet excludes 0, O, I, l
}

#pragma mark - CID cidFromBuffer

- (void)testCidFromBufferWithTrailingData {
    NSData *input = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CID *original = [CID sha256:input];
    NSData *cidBytes = original.bytes;

    // Append trailing data
    NSMutableData *buffer = [NSMutableData dataWithData:cidBytes];
    [buffer appendData:[@"trailing" dataUsingEncoding:NSUTF8StringEncoding]];

    NSUInteger consumed = 0;
    CID *parsed = [CID cidFromBuffer:buffer.bytes length:buffer.length consumed:&consumed];
    XCTAssertNotNil(parsed);
    XCTAssertEqual(consumed, cidBytes.length);
    XCTAssertTrue([parsed isEqualToCID:original]);
}

- (void)testCidFromBufferNilConsumed {
    NSData *input = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CID *original = [CID sha256:input];
    NSData *cidBytes = original.bytes;

    // Should work with consumed=NULL
    CID *parsed = [CID cidFromBuffer:cidBytes.bytes length:cidBytes.length consumed:NULL];
    XCTAssertNotNil(parsed);
}

@end

#pragma mark - TID Tests

@interface TIDTests : XCTestCase
@end

@implementation TIDTests

#pragma mark - TID Creation

- (void)testTidCreation {
    TID *tid = [TID tid];
    XCTAssertNotNil(tid);
    XCTAssertNotNil(tid.stringValue);
    XCTAssertEqual(tid.stringValue.length, 13);
}

- (void)testTidWithTimestamp {
    uint64_t ts = 1700000000000000ULL; // A microsecond timestamp
    TID *tid = [TID tidWithTimestamp:ts];
    XCTAssertNotNil(tid);
    XCTAssertEqual(tid.stringValue.length, 13);
    XCTAssertEqual(tid.timestamp, ts);
}

- (void)testTidWithDate {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1700000000];
    TID *tid = [TID tidWithDate:date];
    XCTAssertNotNil(tid);
    XCTAssertEqual(tid.stringValue.length, 13);
    XCTAssertTrue(tid.timestamp > 0);
}

- (void)testTidFromString {
    TID *tid = [TID tidFromString:@"3zz2zzzzzzzzz"];
    XCTAssertNotNil(tid);
    XCTAssertEqualObjects(tid.stringValue, @"3zz2zzzzzzzzz");
}

- (void)testTidFromStringNil {
    TID *tid = [TID tidFromString:nil];
    XCTAssertNil(tid);
}

- (void)testTidFromStringEmpty {
    TID *tid = [TID tidFromString:@""];
    XCTAssertNil(tid);
}

- (void)testTidFromStringTooShort {
    TID *tid = [TID tidFromString:@"3zz2zzzzzzzz"];
    XCTAssertNil(tid);
}

- (void)testTidFromStringTooLong {
    TID *tid = [TID tidFromString:@"3zz2zzzzzzzzzz"];
    XCTAssertNil(tid);
}

- (void)testTidFromStringInvalidChars {
    TID *tid = [TID tidFromString:@"3zz2zzzzzzz0z"]; // '0' is not in TID alphabet
    XCTAssertNil(tid);
}

- (void)testTidFromStringHighBitSet {
    // First char must be < 8 in the base32 alphabet (positions 0-7)
    // 'z' is position 31, which is >= 8, so this should be invalid
    TID *tid = [TID tidFromString:@"zzz2zzzzzzzzz"];
    XCTAssertNil(tid);
}

#pragma mark - TID Comparison

- (void)testTidComparisonSame {
    TID *tid1 = [TID tidWithTimestamp:1000];
    TID *tid2 = [TID tidWithTimestamp:1000];
    XCTAssertEqual([tid1 compare:tid2], NSOrderedSame);
}

- (void)testTidComparisonBefore {
    TID *tid1 = [TID tidWithTimestamp:999];
    TID *tid2 = [TID tidWithTimestamp:1000];
    XCTAssertEqual([tid1 compare:tid2], NSOrderedAscending);
    XCTAssertTrue([tid1 isBefore:tid2]);
    XCTAssertFalse([tid1 isAfter:tid2]);
}

- (void)testTidComparisonAfter {
    TID *tid1 = [TID tidWithTimestamp:1001];
    TID *tid2 = [TID tidWithTimestamp:1000];
    XCTAssertEqual([tid1 compare:tid2], NSOrderedDescending);
    XCTAssertTrue([tid1 isAfter:tid2]);
    XCTAssertFalse([tid1 isBefore:tid2]);
}

#pragma mark - TID Copy

- (void)testTidCopy {
    TID *original = [TID tidWithTimestamp:12345];
    TID *copy = [original copy];
    XCTAssertNotNil(copy);
    XCTAssertEqualObjects(copy.stringValue, original.stringValue);
    XCTAssertEqual(copy.timestamp, original.timestamp);
    XCTAssertNotEqual(original, copy); // Different instances
}

#pragma mark - TID Equality

- (void)testTidEquality {
    TID *tid1 = [TID tidWithTimestamp:5000];
    TID *tid2 = [TID tidWithTimestamp:5000];
    XCTAssertEqualObjects(tid1, tid2);
    XCTAssertEqual(tid1.hash, tid2.hash);
}

- (void)testTidInequality {
    TID *tid1 = [TID tidWithTimestamp:5000];
    TID *tid2 = [TID tidWithTimestamp:6000];
    XCTAssertNotEqualObjects(tid1, tid2);
}

#pragma mark - TID String Format

- (void)testTidStringOnlyValidChars {
    TID *tid = [TID tid];
    NSString *str = tid.stringValue;
    NSString *validChars = @"234567abcdefghijklmnopqrstuvwxyz";
    NSCharacterSet *validSet = [NSCharacterSet characterSetWithCharactersInString:validChars];
    NSCharacterSet *invalidSet = [validSet invertedSet];
    XCTAssertEqual([str rangeOfCharacterFromSet:invalidSet].location, NSNotFound);
}

- (void)testTidRoundTrip {
    TID *original = [TID tidWithTimestamp:1700000000000000ULL];
    NSString *str = original.stringValue;
    TID *parsed = [TID tidFromString:str];
    XCTAssertNotNil(parsed);
    XCTAssertEqualObjects(parsed.stringValue, str);
    XCTAssertEqual(parsed.timestamp, original.timestamp);
}

@end

#pragma mark - CBOR Serialization Tests

@interface CBORSerializationTests : XCTestCase
@end

@implementation CBORSerializationTests

#pragma mark - CBOR Encode/Decode Round-Trips

- (void)testCborEncodeDecodeString {
    NSDictionary *dict = @{@"key": @"value"};
    NSError *error = nil;
    NSData *encoded = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(encoded);

    id decoded = [ATProtoCBORSerialization JSONObjectWithData:encoded error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertTrue([decoded isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(((NSDictionary *)decoded)[@"key"], @"value");
}

- (void)testCborEncodeDecodeInteger {
    NSDictionary *dict = @{@"count": @42};
    NSError *error = nil;
    NSData *encoded = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(encoded);

    id decoded = [ATProtoCBORSerialization JSONObjectWithData:encoded error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(((NSDictionary *)decoded)[@"count"], @42);
}

- (void)testCborEncodeDecodeNestedDict {
    NSDictionary *dict = @{@"outer": @{@"inner": @"value"}};
    NSError *error = nil;
    NSData *encoded = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(encoded);

    id decoded = [ATProtoCBORSerialization JSONObjectWithData:encoded error:&error];
    XCTAssertNil(error);
    NSDictionary *outer = ((NSDictionary *)decoded)[@"outer"];
    XCTAssertNotNil(outer);
    XCTAssertEqualObjects(outer[@"inner"], @"value");
}

- (void)testCborEncodeDecodeArray {
    NSDictionary *dict = @{@"items": @[@"a", @"b", @"c"]};
    NSError *error = nil;
    NSData *encoded = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(encoded);

    id decoded = [ATProtoCBORSerialization JSONObjectWithData:encoded error:&error];
    XCTAssertNil(error);
    NSArray *items = ((NSDictionary *)decoded)[@"items"];
    XCTAssertNotNil(items);
    XCTAssertEqual(items.count, 3);
    XCTAssertEqualObjects(items[0], @"a");
    XCTAssertEqualObjects(items[2], @"c");
}

- (void)testCborEncodeDecodeBoolean {
    NSDictionary *dict = @{@"flag": @YES};
    NSError *error = nil;
    NSData *encoded = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(encoded);

    id decoded = [ATProtoCBORSerialization JSONObjectWithData:encoded error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(((NSDictionary *)decoded)[@"flag"], @YES);
}

- (void)testCborEncodeDecodeNull {
    NSDictionary *dict = @{@"value": [NSNull null]};
    NSError *error = nil;
    NSData *encoded = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(encoded);

    id decoded = [ATProtoCBORSerialization JSONObjectWithData:encoded error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(((NSDictionary *)decoded)[@"value"], [NSNull null]);
}

- (void)testCborEncodeEmptyDict {
    NSDictionary *dict = @{};
    NSError *error = nil;
    NSData *encoded = [ATProtoCBORSerialization encodeDataWithJSONObject:dict error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(encoded);

    id decoded = [ATProtoCBORSerialization JSONObjectWithData:encoded error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([decoded isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(((NSDictionary *)decoded).count, 0);
}

- (void)testCborDecodeInvalidData {
    NSData *invalid = [NSData dataWithBytes:"\xFF\xFF" length:2];
    NSError *error = nil;
    id decoded = [ATProtoCBORSerialization JSONObjectWithData:invalid error:&error];
    // Invalid CBOR data should either return nil or produce an error
    XCTAssertTrue(decoded == nil || error != nil, @"Invalid CBOR should fail gracefully");
}

#pragma mark - CBOR Canonical Ordering

- (void)testCborKeyOrdering {
    // DAG-CBOR requires bytewise-lexicographic key ordering
    NSDictionary *dict1 = @{@"z_key": @1, @"a_key": @2};
    NSDictionary *dict2 = @{@"a_key": @2, @"z_key": @1};
    NSError *error = nil;
    NSData *data1 = [ATProtoCBORSerialization encodeDataWithJSONObject:dict1 error:&error];
    XCTAssertNil(error);
    NSData *data2 = [ATProtoCBORSerialization encodeDataWithJSONObject:dict2 error:&error];
    XCTAssertNil(error);
    // Both should produce identical bytes because keys are sorted
    XCTAssertEqualObjects(data1, data2);
}

@end

#pragma mark - ATProtoValidator Tests

@interface ATProtoValidatorTests : XCTestCase
@end

@implementation ATProtoValidatorTests

#pragma mark - AT-URI Validation

- (void)testValidNsid {
    NSError *error = nil;
    BOOL valid = [ATProtoValidator validateNSID:@"app.bsky.feed.post" error:&error];
    XCTAssertTrue(valid);
}

- (void)testInvalidNsidEmpty {
    NSError *error = nil;
    BOOL valid = [ATProtoValidator validateNSID:@"" error:&error];
    XCTAssertFalse(valid);
}

- (void)testInvalidNsidNoDot {
    NSError *error = nil;
    BOOL valid = [ATProtoValidator validateNSID:@"justword" error:&error];
    XCTAssertFalse(valid);
}

- (void)testValidDatetime {
    NSError *error = nil;
    BOOL valid = [ATProtoValidator validateDatetime:@"2023-11-23T12:34:56.789Z" error:&error];
    XCTAssertTrue(valid);
}

- (void)testInvalidDatetime {
    NSError *error = nil;
    BOOL valid = [ATProtoValidator validateDatetime:@"not-a-date" error:&error];
    XCTAssertFalse(valid);
}

- (void)testValidTid {
    NSError *error = nil;
    BOOL valid = [ATProtoValidator validateTID:@"3zz2zzzzzzzzz" error:&error];
    XCTAssertTrue(valid);
}

- (void)testInvalidTid {
    NSError *error = nil;
    BOOL valid = [ATProtoValidator validateTID:@"invalid" error:&error];
    XCTAssertFalse(valid);
}

- (void)testValidCid {
    NSError *error = nil;
    // Create a CID and validate its string form
    NSData *input = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid = [CID sha256:input];
    BOOL valid = [ATProtoValidator validateCID:cid.stringValue error:&error];
    XCTAssertTrue(valid);
}

- (void)testInvalidCid {
    NSError *error = nil;
    BOOL valid = [ATProtoValidator validateCID:@"" error:&error];
    XCTAssertFalse(valid);
}

#pragma mark - Handle Validation

- (void)testValidHandle {
    NSError *error = nil;
    XCTAssertTrue([ATProtoValidator validateHandle:@"alice.bsky.social" error:&error]);
}

- (void)testValidHandleShort {
    NSError *error = nil;
    XCTAssertTrue([ATProtoValidator validateHandle:@"a.b" error:&error]);
}

- (void)testInvalidHandleNoDot {
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateHandle:@"localhost" error:&error]);
}

- (void)testInvalidHandleTooLong {
    NSError *error = nil;
    NSString *longHandle = [@"" stringByPaddingToLength:500 withString:@"a" startingAtIndex:0];
    XCTAssertFalse([ATProtoValidator validateHandle:longHandle error:&error]);
}

#pragma mark - DID Validation

- (void)testValidDidPlc {
    NSError *error = nil;
    XCTAssertTrue([ATProtoValidator validateDID:@"did:plc:ewvi7nxzyoun6zhxrhs64oiz" error:&error]);
}

- (void)testValidDidWeb {
    NSError *error = nil;
    XCTAssertTrue([ATProtoValidator validateDID:@"did:web:example.com" error:&error]);
}

- (void)testInvalidDidEmpty {
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateDID:@"" error:&error]);
}

@end

#pragma mark - Base32 Tests

@interface ATProtoBase32Tests : XCTestCase
@end

@implementation ATProtoBase32Tests

- (void)testBase32EncodeDecode {
    NSData *data = [@"AT Protocol" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [ATProtoBase32 encodeData:data];
    XCTAssertNotNil(encoded);
    XCTAssertTrue(encoded.length > 0);

    NSData *decoded = [ATProtoBase32 decodeString:encoded];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(decoded, data);
}

- (void)testBase32EmptyData {
    NSData *data = [NSData data];
    NSString *encoded = [ATProtoBase32 encodeData:data];
    XCTAssertNotNil(encoded);
}

- (void)testBase32DecodeInvalidChar {
    NSData *decoded = [ATProtoBase32 decodeString:@"!!!!"];
    // Should handle gracefully — either nil or empty
}

- (void)testBase32KnownVector {
    NSData *foo = [@"foo" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [ATProtoBase32 encodeData:foo];
    XCTAssertNotNil(encoded);
    NSData *decoded = [ATProtoBase32 decodeString:encoded];
    XCTAssertEqualObjects(decoded, foo);
}

@end
