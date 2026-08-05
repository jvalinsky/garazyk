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

#pragma mark - ATProtoCID Generation and Parsing

- (void)testCIDv1FromSHA256 {
    NSData *digest = [ATProtoCID sha256Digest:[@"hello world" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid = [ATProtoCID cidWithDigest:digest codec:0x71];

    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.version, 1U);
    XCTAssertEqual(cid.codec, 0x71U);
    XCTAssertEqualObjects(cid.stringValue, @"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e");
}

- (void)testCIDParsing {
    NSString *cidString = @"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e";
    ATProtoCID *parsed = [ATProtoCID cidFromString:cidString];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(parsed.version, 1U);
    XCTAssertEqual(parsed.codec, 0x71U);
    XCTAssertEqualObjects(parsed.stringValue, cidString);
    XCTAssertEqual(parsed.multihash.length, 34U);
}

- (void)testCIDInvalidFormats {
    XCTAssertNil([ATProtoCID cidFromString:@"xafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"], @"Should reject CID strings with the wrong multibase prefix");
    XCTAssertNil([ATProtoCID cidFromString:@"bafyre"], @"Should reject truncated CID strings");
    XCTAssertNil([ATProtoCID cidFromString:@"bafyrgifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"], @"Should reject unsupported multihash algorithms");
    
    // Type safety tests
    XCTAssertNil([ATProtoCID cidFromString:(id)@[@"not a string"]], @"Should return nil for non-string input (NSArray)");
    XCTAssertNil([ATProtoCID cidFromString:(id)@{@"$link": @"bafy..."}], @"Should return nil for non-string input (NSDictionary)");
    XCTAssertNil([ATProtoCID cidFromString:(id)[NSNull null]], @"Should return nil for NSNull");
}

#pragma mark - ATProtoCID Equality

- (void)testCIDEquality {
    NSData *input = [@"same content" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid1 = [ATProtoCID sha256:input];
    ATProtoCID *cid2 = [ATProtoCID sha256:input];

    XCTAssertEqualObjects(cid1, cid2);
    XCTAssertTrue([cid1 isEqualToCID:cid2]);
    XCTAssertEqualObjects(cid1.stringValue, cid2.stringValue);
}

- (void)testCIDInequality {
    ATProtoCID *cid1 = [ATProtoCID sha256:[@"content one" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid2 = [ATProtoCID sha256:[@"content two" dataUsingEncoding:NSUTF8StringEncoding]];

    XCTAssertNotEqualObjects(cid1, cid2);
    XCTAssertFalse([cid1 isEqualToCID:cid2]);
}

#pragma mark - DAG-CBOR Integration

- (void)testCIDIntegrationWithDAGCBOR {
    ATProtoCID *left = [ATProtoCID sha256:[@"left" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *right = [ATProtoCID sha256:[@"right" dataUsingEncoding:NSUTF8StringEncoding]];

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
    ATProtoCID *decodedLeft = decodedDict[@"left"];
    XCTAssertTrue([decodedLeft isKindOfClass:[ATProtoCID class]]);
    XCTAssertEqualObjects(decodedLeft.stringValue, left.stringValue);

    NSDictionary *decodedNested = decodedDict[@"nested"];
    XCTAssertTrue([decodedNested isKindOfClass:[NSDictionary class]]);
    ATProtoCID *decodedRight = decodedNested[@"right"];
    XCTAssertTrue([decodedRight isKindOfClass:[ATProtoCID class]]);
    XCTAssertEqualObjects(decodedRight.stringValue, right.stringValue);
}

@end
