// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MSTDecoderTests.h"
#import "Core/CBOR.h"
#import "Repository/MST.h"
#import "Core/CID.h"

@implementation MSTDecoderTests

- (ATProtoCBORValue *)validCIDTag {
    ATProtoCID *cid = [ATProtoCID sha256:[@"mst-decoder-test" dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableData *bytes = [NSMutableData dataWithBytes:"\x00" length:1];
    [bytes appendData:cid.bytes];
    return [ATProtoCBORValue tag:42 value:[ATProtoCBORValue byteString:bytes]];
}

- (ATProtoCBORValue *)entryWithPrefix:(NSUInteger)prefix value:(ATProtoCBORValue *)value {
    return [ATProtoCBORValue map:@{
        [ATProtoCBORValue textString:@"k"]: [ATProtoCBORValue byteString:[@"app.bsky.feed.post/test" dataUsingEncoding:NSUTF8StringEncoding]],
        [ATProtoCBORValue textString:@"p"]: [ATProtoCBORValue unsignedInteger:prefix],
        [ATProtoCBORValue textString:@"t"]: [ATProtoCBORValue nilValue],
        [ATProtoCBORValue textString:@"v"]: value,
    }];
}

- (NSData *)nodeDataWithEntries:(NSArray<ATProtoCBORValue *> *)entries {
    return [[ATProtoCBORValue map:@{
        [ATProtoCBORValue textString:@"e"]: [ATProtoCBORValue array:entries],
        [ATProtoCBORValue textString:@"l"]: [ATProtoCBORValue nilValue],
    }] encode];
}

- (void)testDecoderAcceptsCanonicalNode {
    NSData *data = [self nodeDataWithEntries:@[[self entryWithPrefix:0 value:[self validCIDTag]]]];
    XCTAssertNotNil([ATProtoMST deserializeFromCBOR:data]);
}

- (void)testDecoderRejectsMalformedEntry {
    NSData *data = [self nodeDataWithEntries:@[[ATProtoCBORValue textString:@"not-a-map"]]];
    XCTAssertNil([ATProtoMST deserializeFromCBOR:data]);
}

- (void)testDecoderRejectsOverlongPrefix {
    NSData *data = [self nodeDataWithEntries:@[[self entryWithPrefix:1 value:[self validCIDTag]]]];
    XCTAssertNil([ATProtoMST deserializeFromCBOR:data]);
}

- (void)testDecoderRejectsNonTagValue {
    NSData *data = [self nodeDataWithEntries:@[[self entryWithPrefix:0 value:[ATProtoCBORValue byteString:[NSData data]]]]];
    XCTAssertNil([ATProtoMST deserializeFromCBOR:data]);
}

- (void)testDecoderRejectsEmptyNode {
    NSData *data = [self nodeDataWithEntries:@[]];
    XCTAssertNil([ATProtoMST deserializeFromCBOR:data]);
}

@end
