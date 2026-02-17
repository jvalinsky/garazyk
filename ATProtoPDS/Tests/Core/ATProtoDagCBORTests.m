#import <XCTest/XCTest.h>
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"

@interface ATProtoDagCBORTests : XCTestCase
@end

@implementation ATProtoDagCBORTests

#pragma mark - Basic Type Encoding/Decoding

- (void)testEncodeDecodeNull {
    NSError *error = nil;
    NSData *encoded = [ATProtoDagCBOR encodeObject:[NSNull null] error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    XCTAssertEqual(encoded.length, 1);
    XCTAssertEqual(((uint8_t *)encoded.bytes)[0], 0xF6);
    
    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
    XCTAssertEqualObjects(decoded, [NSNull null]);
}

- (void)testEncodeDecodeBoolean {
    NSError *error = nil;
    
    // True
    NSData *encodedTrue = [ATProtoDagCBOR encodeObject:@YES error:&error];
    XCTAssertNotNil(encodedTrue);
    XCTAssertNil(error);
    XCTAssertEqual(((uint8_t *)encodedTrue.bytes)[0], 0xF5);
    
    id decodedTrue = [ATProtoDagCBOR decodeData:encodedTrue error:&error];
    XCTAssertNotNil(decodedTrue);
    XCTAssertEqualObjects(decodedTrue, @YES);
    
    // False
    NSData *encodedFalse = [ATProtoDagCBOR encodeObject:@NO error:&error];
    XCTAssertNotNil(encodedFalse);
    XCTAssertEqual(((uint8_t *)encodedFalse.bytes)[0], 0xF4);
    
    id decodedFalse = [ATProtoDagCBOR decodeData:encodedFalse error:&error];
    XCTAssertNotNil(decodedFalse);
    XCTAssertEqualObjects(decodedFalse, @NO);
}

- (void)testEncodeDecodeIntegers {
    NSError *error = nil;
    
    NSArray *testValues = @[@0, @1, @23, @24, @255, @256, @65535, @65536, @4294967295, @4294967296,
                            @(-1), @(-24), @(-25), @(-256), @(-65536)];
    
    for (NSNumber *value in testValues) {
        NSData *encoded = [ATProtoDagCBOR encodeObject:value error:&error];
        XCTAssertNotNil(encoded, @"Failed to encode %@", value);
        XCTAssertNil(error);
        
        id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
        XCTAssertNotNil(decoded);
        XCTAssertEqualObjects(decoded, value, @"Decode mismatch for %@", value);
    }
}

- (void)testRejectFloats {
    NSError *error = nil;
    
    NSData *encoded = [ATProtoDagCBOR encodeObject:@3.14 error:&error];
    XCTAssertNil(encoded);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoDagCBORErrorDomain);
    XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeFloatsNotAllowed);
}

- (void)testEncodeDecodeString {
    NSError *error = nil;
    
    NSArray *testStrings = @[@"", @"hello", @"UTF-8: 你好", @"emoji: 🎉"];
    
    for (NSString *string in testStrings) {
        NSData *encoded = [ATProtoDagCBOR encodeObject:string error:&error];
        XCTAssertNotNil(encoded, @"Failed to encode '%@'", string);
        XCTAssertNil(error);
        
        id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
        XCTAssertNotNil(decoded);
        XCTAssertEqualObjects(decoded, string);
    }
}

- (void)testEncodeDecodeByteString {
    NSError *error = nil;
    
    NSData *testData = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *encoded = [ATProtoDagCBOR encodeObject:testData error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    
    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(decoded, testData);
}

- (void)testEncodeDecodeArray {
    NSError *error = nil;
    
    NSArray *testArray = @[@1, @"hello", @YES, [NSNull null], @[@"nested"]];
    NSData *encoded = [ATProtoDagCBOR encodeObject:testArray error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    
    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(decoded, testArray);
}

#pragma mark - Canonical Map Ordering

- (void)testCanonicalMapOrdering {
    NSError *error = nil;
    
    // Keys should be sorted by encoded representation (length-first, then lexicographic)
    // "a" (0x61 0x61) < "aa" (0x62 0x61 0x61) < "b" (0x61 0x62) < "bb" (0x62 0x62 0x62)
    NSDictionary *dict = @{
        @"bb": @1,
        @"a": @2,
        @"aa": @3,
        @"b": @4
    };
    
    NSData *encoded = [ATProtoDagCBOR encodeObject:dict error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    
    // Manually verify the key order in the encoded bytes
    // After the map header, keys should appear in order: "a", "b", "aa", "bb"
    const uint8_t *bytes = encoded.bytes;
    NSUInteger index = 0;
    
    // Map header (should be 0xA4 for 4 items)
    XCTAssertEqual(bytes[index++], 0xA4);
    
    // First key "a" (0x61 'a')
    XCTAssertEqual(bytes[index++], 0x61); // text string length 1
    XCTAssertEqual(bytes[index++], 'a');
    XCTAssertEqual(bytes[index++], 0x02); // value 2
    
    // Second key "b" (0x61 'b')
    XCTAssertEqual(bytes[index++], 0x61);
    XCTAssertEqual(bytes[index++], 'b');
    XCTAssertEqual(bytes[index++], 0x04); // value 4
    
    // Third key "aa" (0x62 'a' 'a')
    XCTAssertEqual(bytes[index++], 0x62);
    XCTAssertEqual(bytes[index++], 'a');
    XCTAssertEqual(bytes[index++], 'a');
    XCTAssertEqual(bytes[index++], 0x03); // value 3
    
    // Fourth key "bb" (0x62 'b' 'b')
    XCTAssertEqual(bytes[index++], 0x62);
    XCTAssertEqual(bytes[index++], 'b');
    XCTAssertEqual(bytes[index++], 'b');
    XCTAssertEqual(bytes[index++], 0x01); // value 1
}

#pragma mark - CID-Link Encoding (Tag 42)

- (void)testEncodeCIDLink {
    NSError *error = nil;
    
    // Create a test CID
    NSData *digest = [@"test digest here" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid = [CID cidWithDigest:digest codec:0x71]; // DAG-CBOR codec
    XCTAssertNotNil(cid);
    
    NSData *encoded = [ATProtoDagCBOR encodeObject:cid error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    
    // Verify structure: tag 42 (0xD8 0x2A) followed by byte string with 0x00 prefix
    const uint8_t *bytes = encoded.bytes;
    XCTAssertEqual(bytes[0], 0xD8); // Tag, additional info 24
    XCTAssertEqual(bytes[1], 42);   // Tag value 42
    // Next should be byte string header followed by 0x00 and CID bytes
    XCTAssertEqual(bytes[2] >> 5, 2); // Major type 2 (byte string)
    
    // Decode and verify round-trip
    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
    XCTAssertTrue([decoded isKindOfClass:[CID class]]);
    
    CID *decodedCID = (CID *)decoded;
    XCTAssertEqualObjects(decodedCID.stringValue, cid.stringValue);
}

#pragma mark - JSON Wrapper Conversion

- (void)testConvert$LinkToCID {
    NSError *error = nil;
    
    // Create a test CID
    NSData *digest = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid = [CID cidWithDigest:digest codec:0x71];
    NSString *cidString = cid.stringValue;
    
    // JSON object with $link wrapper
    NSDictionary *jsonObject = @{
        @"someField": @"value",
        @"linkField": @{@"$link": cidString}
    };
    
    NSData *encoded = [ATProtoDagCBOR encodeJSONObject:jsonObject error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    
    // Decode and verify the link was converted
    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertTrue([decoded isKindOfClass:[NSDictionary class]]);
    
    NSDictionary *decodedDict = (NSDictionary *)decoded;
    XCTAssertEqualObjects(decodedDict[@"someField"], @"value");
    XCTAssertTrue([decodedDict[@"linkField"] isKindOfClass:[CID class]]);
    
    CID *decodedCID = decodedDict[@"linkField"];
    XCTAssertEqualObjects(decodedCID.stringValue, cidString);
}

- (void)testConvert$BytesToByteString {
    NSError *error = nil;
    
    NSData *testBytes = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64 = [testBytes base64EncodedStringWithOptions:0];
    
    NSDictionary *jsonObject = @{
        @"data": @{@"$bytes": base64}
    };
    
    NSData *encoded = [ATProtoDagCBOR encodeJSONObject:jsonObject error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    
    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertTrue([decoded isKindOfClass:[NSDictionary class]]);
    
    NSDictionary *decodedDict = (NSDictionary *)decoded;
    XCTAssertTrue([decodedDict[@"data"] isKindOfClass:[NSData class]]);
    XCTAssertEqualObjects(decodedDict[@"data"], testBytes);
}

- (void)testDecodeAsJSONConvertsLinksAndBytes {
    NSError *error = nil;
    
    // Create a CID
    NSData *digest = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid = [CID cidWithDigest:digest codec:0x71];
    
    // Create a dict with CID and byte data
    NSDictionary *original = @{
        @"link": cid,
        @"bytes": [@"hello" dataUsingEncoding:NSUTF8StringEncoding],
        @"string": @"plain text"
    };
    
    NSData *encoded = [ATProtoDagCBOR encodeObject:original error:&error];
    XCTAssertNotNil(encoded);
    
    // Decode as JSON
    id decoded = [ATProtoDagCBOR decodeDataAsJSON:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertTrue([decoded isKindOfClass:[NSDictionary class]]);
    
    NSDictionary *decodedDict = (NSDictionary *)decoded;
    
    // Verify $link wrapper
    XCTAssertTrue([decodedDict[@"link"] isKindOfClass:[NSDictionary class]]);
    NSDictionary *linkWrapper = decodedDict[@"link"];
    XCTAssertNotNil(linkWrapper[@"$link"]);
    XCTAssertEqualObjects(linkWrapper[@"$link"], cid.stringValue);
    
    // Verify $bytes wrapper
    XCTAssertTrue([decodedDict[@"bytes"] isKindOfClass:[NSDictionary class]]);
    NSDictionary *bytesWrapper = decodedDict[@"bytes"];
    XCTAssertNotNil(bytesWrapper[@"$bytes"]);
    
    // Plain string unchanged
    XCTAssertEqualObjects(decodedDict[@"string"], @"plain text");
}

#pragma mark - Complex Objects

- (void)testNestedStructures {
    NSError *error = nil;
    
    NSDictionary *complex = @{
        @"array": @[@1, @2, @{@"nested": @YES}],
        @"dict": @{
            @"a": @"value",
            @"b": @[@1, @2, @3]
        },
        @"null": [NSNull null]
    };
    
    NSData *encoded = [ATProtoDagCBOR encodeObject:complex error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    
    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(decoded, complex);
}

#pragma mark - Error Cases

- (void)testInvalid$LinkString {
    NSError *error = nil;
    
    NSDictionary *jsonObject = @{@"$link": @"not-a-valid-cid"};
    
    NSData *encoded = [ATProtoDagCBOR encodeJSONObject:jsonObject error:&error];
    XCTAssertNil(encoded);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeInvalidCIDLink);
}

- (void)testInvalid$BytesBase64 {
    NSError *error = nil;
    
    NSDictionary *jsonObject = @{@"$bytes": @"not!!!valid!!!base64"};
    
    NSData *encoded = [ATProtoDagCBOR encodeJSONObject:jsonObject error:&error];
    XCTAssertNil(encoded);
    XCTAssertNotNil(error);
}

- (void)testEmptyData {
    NSError *error = nil;
    
    id decoded = [ATProtoDagCBOR decodeData:[NSData data] error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoDagCBORErrorCodeDecodingFailed);
}

@end
