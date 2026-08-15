// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoIrohBlobHashMapping.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoIrohBlobHashMappingTests : XCTestCase
@end

@implementation ATProtoIrohBlobHashMappingTests

- (NSData *)payloadOfLength:(NSUInteger)len {
    NSMutableData *data = [NSMutableData dataWithLength:len];
    if (len > 0) {
        uint8_t *bytes = data.mutableBytes;
        for (NSUInteger i = 0; i < len; i++) {
            bytes[i] = (uint8_t)(i & 0xff);
        }
    }
    return data;
}

- (NSString *)hex:(NSData *)data {
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    const uint8_t *b = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        [s appendFormat:@"%02x", b[i]];
    }
    return s;
}

- (void)assertFixtureForPayload:(NSData *)payload label:(NSString *)label {
    NSError *error = nil;
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload
                                               profile:ATProtoCAObjectDigestProfileBLAKE3
                                                 error:&error];
    XCTAssertNotNil(cid, @"%@ cid: %@", label, error);
    NSData *fromCID = [ATProtoIrohBlobHashMapping irohBlobsHashFromGarazykCAVODCID:cid error:&error];
    NSData *baoRoot = [ATProtoIrohBlobHashMapping baoRootHashForObjectData:payload];
    XCTAssertNotNil(fromCID, @"%@ extract: %@", label, error);
    XCTAssertEqual(fromCID.length, (NSUInteger)32);
    XCTAssertTrue([ATProtoIrohBlobHashMapping garazykCAVODCID:cid matchesObjectData:payload],
                  @"%@ mirror contract", label);
    XCTAssertEqualObjects(fromCID, baoRoot, @"%@ CID digest must equal Bao root for iroh fetch", label);
    // Round-trip: strict parser accepts the CID string.
    ATProtoCID *parsed = [ATProtoCID daslCIDFromString:cid.stringValue profile:ATProtoDASLCIDProfileBig];
    XCTAssertNotNil(parsed, @"%@", label);
    NSData *reparsed = [ATProtoIrohBlobHashMapping irohBlobsHashFromGarazykCAVODCID:parsed error:&error];
    XCTAssertEqualObjects(fromCID, reparsed, @"%@", label);
}

- (void)testEmptySmallAndMultiChunkFixtures {
    [self assertFixtureForPayload:[NSData data] label:@"empty"];
    [self assertFixtureForPayload:[@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding] label:@"small"];
    [self assertFixtureForPayload:[self payloadOfLength:2500] label:@"multi-chunk"];
}

- (void)testRejectsSHA256CID {
    NSError *error = nil;
    NSData *payload = [@"sha-only" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *sha = [ATProtoCAObjectStore cidForData:payload
                                               profile:ATProtoCAObjectDigestProfileSHA256
                                                 error:&error];
    XCTAssertNil([ATProtoIrohBlobHashMapping irohBlobsHashFromGarazykCAVODCID:sha error:&error]);
    XCTAssertEqual(error.code, ATProtoIrohBlobHashMappingErrorUnsupportedHash);
}

- (void)testRejectsMalformedCIDString {
    NSError *error = nil;
    ATProtoCID *cid = [ATProtoCID cidFromString:@"not-a-cid"];
    XCTAssertNil(cid);
    cid = [ATProtoCID daslCIDFromString:@"bafkr4iinvalid" profile:ATProtoDASLCIDProfileBig];
    if (cid) {
        XCTAssertNil([ATProtoIrohBlobHashMapping irohBlobsHashFromGarazykCAVODCID:cid error:&error]);
    }
}

- (void)testWrongExpectedCIDFailsMatch {
    NSData *a = [@"object-a" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *b = [@"object-b" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoCID *cidA = [ATProtoCAObjectStore cidForData:a profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    XCTAssertFalse([ATProtoIrohBlobHashMapping garazykCAVODCID:cidA matchesObjectData:b]);
}

- (void)testGoldenEmptyCID {
    NSError *error = nil;
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:[NSData data]
                                               profile:ATProtoCAObjectDigestProfileBLAKE3
                                                 error:&error];
    XCTAssertNotNil(cid, @"%@", error);
    XCTAssertEqualObjects(cid.stringValue,
                          @"bafkr4ifpcne3t5pzugtkaqcn5i3nzskjtpfslsnnyejlpte2spfoihzsmi");
}

- (void)testGoldenVectorSmallFixture {
    NSData *small = [@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:small
                                               profile:ATProtoCAObjectDigestProfileBLAKE3
                                                 error:&error];
    NSData *hash = [ATProtoIrohBlobHashMapping irohBlobsHashFromGarazykCAVODCID:cid error:&error];
    XCTAssertNotNil(hash, @"%@", error);
    XCTAssertEqualObjects(cid.stringValue,
                          @"bafkr4iadewxtddpf7wzglzmsoxbm4gqkmq6n3hieephctfxj5ht2n4b43e");
}

@end
