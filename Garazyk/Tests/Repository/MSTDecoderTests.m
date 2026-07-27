// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MSTDecoderTests.h"
#import "Repository/CBOR.h"
#import "Repository/MST.h"
#import "Core/CID.h"

@implementation MSTDecoderTests

- (CBORValue *)validCIDTag {
    CID *cid = [CID sha256:[@"mst-decoder-test" dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableData *bytes = [NSMutableData dataWithBytes:"\x00" length:1];
    [bytes appendData:cid.bytes];
    return [CBORValue tag:42 value:[CBORValue byteString:bytes]];
}

- (CBORValue *)entryWithPrefix:(NSUInteger)prefix value:(CBORValue *)value {
    return [CBORValue map:@{
        [CBORValue textString:@"k"]: [CBORValue byteString:[@"app.bsky.feed.post/test" dataUsingEncoding:NSUTF8StringEncoding]],
        [CBORValue textString:@"p"]: [CBORValue unsignedInteger:prefix],
        [CBORValue textString:@"t"]: [CBORValue nilValue],
        [CBORValue textString:@"v"]: value,
    }];
}

- (NSData *)nodeDataWithEntries:(NSArray<CBORValue *> *)entries {
    return [[CBORValue map:@{
        [CBORValue textString:@"e"]: [CBORValue array:entries],
        [CBORValue textString:@"l"]: [CBORValue nilValue],
    }] encode];
}

- (void)testDecoderAcceptsCanonicalNode {
    NSData *data = [self nodeDataWithEntries:@[[self entryWithPrefix:0 value:[self validCIDTag]]]];
    XCTAssertNotNil([MST deserializeFromCBOR:data]);
}

- (void)testDecoderRejectsMalformedEntry {
    NSData *data = [self nodeDataWithEntries:@[[CBORValue textString:@"not-a-map"]]];
    XCTAssertNil([MST deserializeFromCBOR:data]);
}

- (void)testDecoderRejectsOverlongPrefix {
    NSData *data = [self nodeDataWithEntries:@[[self entryWithPrefix:1 value:[self validCIDTag]]]];
    XCTAssertNil([MST deserializeFromCBOR:data]);
}

- (void)testDecoderRejectsNonTagValue {
    NSData *data = [self nodeDataWithEntries:@[[self entryWithPrefix:0 value:[CBORValue byteString:[NSData data]]]]];
    XCTAssertNil([MST deserializeFromCBOR:data]);
}

- (void)testDecoderRejectsEmptyNode {
    NSData *data = [self nodeDataWithEntries:@[]];
    XCTAssertNil([MST deserializeFromCBOR:data]);
}

@end
