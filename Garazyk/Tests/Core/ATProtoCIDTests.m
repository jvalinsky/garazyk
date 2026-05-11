// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"

@interface ATProtoCIDTests : XCTestCase
@end

@implementation ATProtoCIDTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - CID Generation and Parsing

- (void)testCIDv1FromSHA256 {
    NSData *digest = [CID sha256Digest:[@"hello world" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithDigest:digest codec:0x71];

    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.version, 1U);
    XCTAssertEqual(cid.codec, 0x71U);
    XCTAssertEqualObjects(cid.stringValue, @"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e");
}

- (void)testCIDParsing {
    NSString *cidString = @"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e";
    CID *parsed = [CID cidFromString:cidString];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(parsed.version, 1U);
    XCTAssertEqual(parsed.codec, 0x71U);
    XCTAssertEqualObjects(parsed.stringValue, cidString);
    XCTAssertEqual(parsed.multihash.length, 34U);
}

- (void)testCIDInvalidFormats {
    XCTAssertNil([CID cidFromString:@"xafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"], @"Should reject CID strings with the wrong multibase prefix");
    XCTAssertNil([CID cidFromString:@"bafyre"], @"Should reject truncated CID strings");
    XCTAssertNil([CID cidFromString:@"bafyrgifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"], @"Should reject unsupported multihash algorithms");
}

#pragma mark - CID Equality

- (void)testCIDEquality {
    NSData *input = [@"same content" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid1 = [CID sha256:input];
    CID *cid2 = [CID sha256:input];

    XCTAssertEqualObjects(cid1, cid2);
    XCTAssertTrue([cid1 isEqualToCID:cid2]);
    XCTAssertEqualObjects(cid1.stringValue, cid2.stringValue);
}

- (void)testCIDInequality {
    CID *cid1 = [CID sha256:[@"content one" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid2 = [CID sha256:[@"content two" dataUsingEncoding:NSUTF8StringEncoding]];

    XCTAssertNotEqualObjects(cid1, cid2);
    XCTAssertFalse([cid1 isEqualToCID:cid2]);
}

#pragma mark - DAG-CBOR Integration

- (void)testCIDIntegrationWithDAGCBOR {
    CID *left = [CID sha256:[@"left" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *right = [CID sha256:[@"right" dataUsingEncoding:NSUTF8StringEncoding]];

    NSDictionary *object = @{
        @"left": left,
        @"nested": @{
            @"right": right
        }
    };

    NSError *error = nil;
    NSData *encoded = [ATProtoDagCBOR encodeObject:object error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
    XCTAssertTrue([decoded isKindOfClass:[NSDictionary class]]);

    NSDictionary *decodedDict = (NSDictionary *)decoded;
    CID *decodedLeft = decodedDict[@"left"];
    XCTAssertTrue([decodedLeft isKindOfClass:[CID class]]);
    XCTAssertEqualObjects(decodedLeft.stringValue, left.stringValue);

    NSDictionary *decodedNested = decodedDict[@"nested"];
    XCTAssertTrue([decodedNested isKindOfClass:[NSDictionary class]]);
    CID *decodedRight = decodedNested[@"right"];
    XCTAssertTrue([decodedRight isKindOfClass:[CID class]]);
    XCTAssertEqualObjects(decodedRight.stringValue, right.stringValue);
}

@end
