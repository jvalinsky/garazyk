// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Repository/STAR.h"
#import "Core/CBOR.h"
#import "Core/CID.h"

/**
 * Conformance tests for upstream STAR-lite version 0 — the interoperable
 * `application/x.microcosm.star-lite` encoding consumed by microcosm's Hubble,
 * as distinct from the local STAR-lite variant (version 2) pinned by ADR 0009.
 *
 * The wire format under test is:
 *
 *     [ 2A 6C 00 | mst-root-cid (36 bytes) | varint(len) | partial-commit ]
 *     [ varint(keyLen) | key | varint(recLen) | record ] ...
 *
 * Header/record byte layout is pinned against a real archive served by
 * hetz-test-hubble.microcosm.blue, decoded during implementation.
 *
 * Note: when adding new tests under Garazyk/Tests/Repository/, run
 *   cmake -S . -B build
 * before `cmake --build build --target AllTests`. The repository test glob is
 * cached at configure time; an incremental build will not pick up new files.
 * The class must also be listed in Garazyk/Tests/test_main.m.
 */
@interface STARLiteV0Tests : XCTestCase {
    NSMutableDictionary<NSString *, NSData *> *_cidToRecordData;
}
@end

@implementation STARLiteV0Tests

#pragma mark - Fixtures

- (NSData *)recordDataForKey:(NSString *)key {
    NSDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *map = @{
        [ATProtoCBORValue textString:@"$type"] : [ATProtoCBORValue textString:@"app.bsky.feed.post"],
        [ATProtoCBORValue textString:@"text"] : [ATProtoCBORValue textString:key]
    };
    return [[ATProtoCBORValue map:map] encode];
}

- (ATProtoMST *)buildFixtureTree {
    NSArray<NSString *> *keys = @[
        @"app.bsky.actor.profile/self",
        @"app.bsky.feed.like/3jzfcijpj2z2b",
        @"app.bsky.feed.post/3jzfcijpj2z2a",
        @"app.bsky.feed.post/3jzfcijpj2z2c",
        @"app.bsky.graph.follow/3jzfcijpj2z2d"
    ];
    _cidToRecordData = [NSMutableDictionary dictionary];
    ATProtoMST *tree = [[ATProtoMST alloc] init];
    for (NSString *key in keys) {
        NSData *recordData = [self recordDataForKey:key];
        ATProtoCID *cid = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:recordData] codec:0x71];
        _cidToRecordData[cid.stringValue] = recordData;
        [tree put:key valueCID:cid];
    }
    return tree;
}

- (MSTBlockProvider)recordProvider {
    NSDictionary<NSString *, NSData *> *cache = [_cidToRecordData copy];
    return ^NSData *(ATProtoCID *cid) {
        return cache[cid.stringValue];
    };
}

/// A stored commit block in the shape a PDS persists it, including `data`.
- (NSData *)commitBlockForRoot:(ATProtoCID *)rootCID includeNullPrev:(BOOL)includeNullPrev {
    NSMutableData *tagged = [NSMutableData dataWithBytes:(uint8_t[]){0x00} length:1];
    [tagged appendData:rootCID.bytes];

    NSMutableDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *map = [NSMutableDictionary dictionary];
    map[[ATProtoCBORValue textString:@"did"]] = [ATProtoCBORValue textString:@"did:plc:starlitefixture"];
    map[[ATProtoCBORValue textString:@"version"]] = [ATProtoCBORValue unsignedInteger:3];
    map[[ATProtoCBORValue textString:@"data"]] =
        [ATProtoCBORValue tag:42 value:[ATProtoCBORValue byteString:tagged]];
    map[[ATProtoCBORValue textString:@"rev"]] = [ATProtoCBORValue textString:@"3jzfcijpj2z2z"];
    map[[ATProtoCBORValue textString:@"sig"]] =
        [ATProtoCBORValue byteString:[@"fixture-signature-64-bytes-placeholder"
                                         dataUsingEncoding:NSUTF8StringEncoding]];
    if (includeNullPrev) {
        map[[ATProtoCBORValue textString:@"prev"]] = [ATProtoCBORValue nilValue];
    }
    return [[ATProtoCBORValue map:map] encode];
}

#pragma mark - Byte-level parsing helpers

static NSUInteger ReadVarint(const uint8_t *bytes, NSUInteger maxLength, uint64_t *value) {
    uint64_t result = 0;
    NSUInteger shift = 0;
    NSUInteger offset = 0;
    while (offset < maxLength) {
        uint8_t byte = bytes[offset++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) {
            *value = result;
            return offset;
        }
    }
    return 0;
}

#pragma mark - Header layout

- (void)testHeaderUsesUpstreamMagicRootCIDAndPartialCommit {
    ATProtoMST *tree = [self buildFixtureTree];
    NSData *commitBlock = [self commitBlockForRoot:tree.rootCID includeNullPrev:NO];

    NSError *err = nil;
    ATProtoSTARLiteV0Writer *writer =
        [[ATProtoSTARLiteV0Writer alloc] initWithMSTRootCID:tree.rootCID
                                                commitBlock:commitBlock
                                                      error:&err];
    XCTAssertNotNil(writer, @"writer init failed: %@", err);

    NSData *header = [writer headerData];
    const uint8_t *bytes = header.bytes;

    // Magic: "*l\0" — three bytes, not the single 0x2A of the local variant.
    XCTAssertGreaterThan(header.length, (NSUInteger)39);
    XCTAssertEqual(bytes[0], (uint8_t)0x2A);
    XCTAssertEqual(bytes[1], (uint8_t)0x6C);
    XCTAssertEqual(bytes[2], (uint8_t)0x00);

    // 36-byte raw CID: 0x01711220 prefix + 32-byte sha256 digest.
    NSData *cidBytes = [header subdataWithRange:NSMakeRange(3, 36)];
    XCTAssertEqualObjects(cidBytes, tree.rootCID.bytes);
    const uint8_t *cid = cidBytes.bytes;
    XCTAssertEqual(cid[0], (uint8_t)0x01);
    XCTAssertEqual(cid[1], (uint8_t)0x71);
    XCTAssertEqual(cid[2], (uint8_t)0x12);
    XCTAssertEqual(cid[3], (uint8_t)0x20);

    uint64_t commitLength = 0;
    NSUInteger consumed = ReadVarint(bytes + 39, header.length - 39, &commitLength);
    XCTAssertGreaterThan(consumed, (NSUInteger)0);
    XCTAssertEqual(header.length, 39 + consumed + (NSUInteger)commitLength);
    XCTAssertLessThanOrEqual((NSUInteger)commitLength, (NSUInteger)4096);

    NSData *partial = [header subdataWithRange:NSMakeRange(39 + consumed, (NSUInteger)commitLength)];
    ATProtoCBORValue *decoded = [ATProtoCBORValue decode:partial];
    XCTAssertEqual(decoded.type, CBORTypeMap);

    // `data` lives in the header CID, so the commit carried here omits it.
    XCTAssertNil(decoded.map[[ATProtoCBORValue textString:@"data"]],
                 @"STAR-lite v0 header commit must not carry `data`");
    XCTAssertNotNil(decoded.map[[ATProtoCBORValue textString:@"did"]]);
    XCTAssertNotNil(decoded.map[[ATProtoCBORValue textString:@"rev"]]);
    XCTAssertNotNil(decoded.map[[ATProtoCBORValue textString:@"sig"]]);
    XCTAssertNotNil(decoded.map[[ATProtoCBORValue textString:@"version"]]);
}

/**
 * The property that makes signatures verifiable on the far side: a reader
 * re-inserts `data` from the header CID and must recover the exact bytes the
 * commit signature covers. This fails if the writer rebuilds the commit from a
 * fixed field list instead of stripping one key from the stored bytes.
 */
- (void)testReinsertingDataRecoversOriginalCommitBytes {
    ATProtoMST *tree = [self buildFixtureTree];

    for (NSNumber *withNullPrev in @[@NO, @YES]) {
        NSData *commitBlock = [self commitBlockForRoot:tree.rootCID
                                       includeNullPrev:withNullPrev.boolValue];
        NSError *err = nil;
        ATProtoSTARLiteV0Writer *writer =
            [[ATProtoSTARLiteV0Writer alloc] initWithMSTRootCID:tree.rootCID
                                                    commitBlock:commitBlock
                                                          error:&err];
        XCTAssertNotNil(writer, @"writer init failed: %@", err);

        // Reader side: decode the partial commit, re-insert `data` from the
        // header CID, re-encode canonically.
        ATProtoCBORValue *partial = [ATProtoCBORValue decode:writer.partialCommit];
        NSMutableDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *rebuilt = [partial.map mutableCopy];
        NSMutableData *tagged = [NSMutableData dataWithBytes:(uint8_t[]){0x00} length:1];
        [tagged appendData:writer.mstRootCID.bytes];
        rebuilt[[ATProtoCBORValue textString:@"data"]] =
            [ATProtoCBORValue tag:42 value:[ATProtoCBORValue byteString:tagged]];

        XCTAssertEqualObjects([[ATProtoCBORValue map:rebuilt] encode], commitBlock,
                              @"data re-insertion must reproduce the signed commit byte-for-byte "
                              @"(null prev present: %@)", withNullPrev);
    }
}

- (void)testPartialCommitPreservesNullPrev {
    ATProtoMST *tree = [self buildFixtureTree];
    NSData *commitBlock = [self commitBlockForRoot:tree.rootCID includeNullPrev:YES];

    NSError *err = nil;
    ATProtoSTARLiteV0Writer *writer =
        [[ATProtoSTARLiteV0Writer alloc] initWithMSTRootCID:tree.rootCID
                                                commitBlock:commitBlock
                                                      error:&err];
    XCTAssertNotNil(writer, @"writer init failed: %@", err);

    // Hubble's own archives carry `prev: null`; dropping a present-but-null key
    // would change the bytes the signature covers.
    ATProtoCBORValue *decoded = [ATProtoCBORValue decode:writer.partialCommit];
    ATProtoCBORValue *prev = decoded.map[[ATProtoCBORValue textString:@"prev"]];
    XCTAssertNotNil(prev, @"a present-but-null `prev` must survive the strip");
    XCTAssertEqual(prev.type, CBORTypeSimpleOrFloat);
}

- (void)testEmptyRepositoryUsesComputedEmptyTreeCID {
    NSData *commitBlock = [self commitBlockForRoot:ATProtoMSTEmptyRootCID()
                                   includeNullPrev:NO];
    NSError *err = nil;
    ATProtoSTARLiteV0Writer *writer =
        [[ATProtoSTARLiteV0Writer alloc] initWithMSTRootCID:nil
                                                commitBlock:commitBlock
                                                      error:&err];
    XCTAssertNotNil(writer, @"writer init failed: %@", err);
    XCTAssertEqualObjects(writer.mstRootCID, ATProtoMSTEmptyRootCID());

    // An empty archive is header-only.
    XCTAssertTrue([writer writeFromMST:nil blockProvider:nil error:&err]);
    XCTAssertEqualObjects([writer serialize], [writer headerData]);
}

/**
 * The empty-tree root is computed from an empty tree, never hard-coded, so the
 * header can't name a root that disagrees with what we actually build.
 *
 * The upstream readme states this CID as
 * bafyreihmh6lpqcmyus4kt4rsypvxgvnvzkmj4aqczyewol5rsf7pdzzta4 and describes it
 * as "the CID of a single empty atproto MST node". That appears to be an error
 * in the spec: an empty MST node is {e: [], l: null}, which in canonical
 * DAG-CBOR hashes to the value asserted below — the well-known atproto
 * empty-repo root. No plausible alternative encoding of an empty node produces
 * the readme's digest. If upstream corrects the readme, this test is where the
 * disagreement is recorded.
 */
- (void)testEmptyTreeCIDIsComputedFromAnEmptyMST {
    XCTAssertEqualObjects(ATProtoMSTEmptyRootCID(), [[ATProtoMST alloc] init].rootCID);
    XCTAssertEqualObjects(ATProtoMSTEmptyRootCID().stringValue,
                          @"bafyreie5737gdxlw5i64vzichcalba3z2v5n6icifvx5xytvske7mr3hpm");
}

#pragma mark - Record section

- (void)testRecordsAreLexicographicKeyRecordPairsWithNoTrailingBytes {
    ATProtoMST *tree = [self buildFixtureTree];
    NSData *commitBlock = [self commitBlockForRoot:tree.rootCID includeNullPrev:NO];

    NSError *err = nil;
    ATProtoSTARLiteV0Writer *writer =
        [[ATProtoSTARLiteV0Writer alloc] initWithMSTRootCID:tree.rootCID
                                                commitBlock:commitBlock
                                                      error:&err];
    XCTAssertNotNil(writer, @"writer init failed: %@", err);
    XCTAssertTrue([writer writeFromMST:tree blockProvider:[self recordProvider] error:&err],
                  @"writeFromMST failed: %@", err);

    NSData *archive = [writer serialize];
    NSUInteger offset = [writer headerData].length;
    const uint8_t *bytes = archive.bytes;

    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    while (offset < archive.length) {
        uint64_t keyLength = 0;
        NSUInteger consumed = ReadVarint(bytes + offset, archive.length - offset, &keyLength);
        XCTAssertGreaterThan(consumed, (NSUInteger)0, @"truncated key varint");
        offset += consumed;

        XCTAssertLessThanOrEqual((NSUInteger)keyLength, STARLiteV0MaxKeyLength);
        NSString *key = [[NSString alloc] initWithData:[archive subdataWithRange:NSMakeRange(offset, (NSUInteger)keyLength)]
                                              encoding:NSUTF8StringEncoding];
        XCTAssertNotNil(key, @"record key must be valid UTF-8");
        offset += (NSUInteger)keyLength;

        uint64_t recordLength = 0;
        consumed = ReadVarint(bytes + offset, archive.length - offset, &recordLength);
        XCTAssertGreaterThan(consumed, (NSUInteger)0, @"truncated record varint");
        offset += consumed;

        XCTAssertLessThanOrEqual((NSUInteger)recordLength, STARLiteV0MaxRecordLength);
        NSData *record = [archive subdataWithRange:NSMakeRange(offset, (NSUInteger)recordLength)];
        offset += (NSUInteger)recordLength;

        XCTAssertEqualObjects(record, [self recordDataForKey:key],
                              @"record bytes must round-trip for key %@", key);
        [keys addObject:key];
    }

    XCTAssertEqual(offset, archive.length, @"archive must be fully consumed, no trailing bytes");
    XCTAssertEqual(keys.count, (NSUInteger)5);

    NSArray<NSString *> *sorted = [keys sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(keys, sorted, @"keys must be in strict lexicographic order");
    XCTAssertEqual([NSSet setWithArray:keys].count, keys.count, @"keys must be unique");
}

- (void)testMissingRecordBlockIsRejected {
    ATProtoMST *tree = [self buildFixtureTree];
    NSData *commitBlock = [self commitBlockForRoot:tree.rootCID includeNullPrev:NO];

    NSError *err = nil;
    ATProtoSTARLiteV0Writer *writer =
        [[ATProtoSTARLiteV0Writer alloc] initWithMSTRootCID:tree.rootCID
                                                commitBlock:commitBlock
                                                      error:&err];
    XCTAssertNotNil(writer, @"writer init failed: %@", err);

    // A truncated archive would name an MST root the record stream cannot
    // rebuild, so a missing block must fail loudly rather than be skipped.
    XCTAssertFalse([writer writeFromMST:tree
                          blockProvider:^NSData *(ATProtoCID *cid) { return nil; }
                                  error:&err]);
    XCTAssertNotNil(err);
}

/**
 * The pre-serve guard: we run the consumer's own verification step (re-insert
 * `data`, compare to the signed bytes) before serving. A root CID that doesn't
 * match the commit's `data` field would produce an archive that fails
 * verification on the far side, so it must fail here instead.
 */
- (void)testRootCIDDisagreeingWithCommitDataIsRejected {
    ATProtoMST *tree = [self buildFixtureTree];
    NSData *commitBlock = [self commitBlockForRoot:tree.rootCID includeNullPrev:NO];

    NSError *err = nil;
    XCTAssertNil([[ATProtoSTARLiteV0Writer alloc]
                     initWithMSTRootCID:ATProtoMSTEmptyRootCID()
                            commitBlock:commitBlock
                                  error:&err],
                 @"a root CID that is not the commit's `data` must be refused");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 59);

    // The matching root is accepted.
    err = nil;
    XCTAssertNotNil([[ATProtoSTARLiteV0Writer alloc] initWithMSTRootCID:tree.rootCID
                                                            commitBlock:commitBlock
                                                                  error:&err]);
    XCTAssertNil(err);
}

- (void)testCommitBlockWithoutDataIsRejected {
    // A commit that never carried `data` cannot be re-assembled into the bytes
    // its signature covers, whatever root we put in the header.
    NSMutableDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *map = [NSMutableDictionary dictionary];
    map[[ATProtoCBORValue textString:@"did"]] = [ATProtoCBORValue textString:@"did:plc:starlitefixture"];
    map[[ATProtoCBORValue textString:@"version"]] = [ATProtoCBORValue unsignedInteger:3];
    map[[ATProtoCBORValue textString:@"rev"]] = [ATProtoCBORValue textString:@"3jzfcijpj2z2z"];

    NSError *err = nil;
    XCTAssertNil([[ATProtoSTARLiteV0Writer alloc]
                     initWithMSTRootCID:nil
                            commitBlock:[[ATProtoCBORValue map:map] encode]
                                  error:&err]);
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 59);
}

- (void)testMalformedCommitBlockIsRejected {
    NSError *err = nil;
    XCTAssertNil([[ATProtoSTARLiteV0Writer alloc]
                     initWithMSTRootCID:nil
                            commitBlock:[NSData data]
                                  error:&err]);
    XCTAssertNotNil(err);

    err = nil;
    NSData *notAMap = [[ATProtoCBORValue textString:@"nope"] encode];
    XCTAssertNil([[ATProtoSTARLiteV0Writer alloc]
                     initWithMSTRootCID:nil
                            commitBlock:notAMap
                                  error:&err]);
    XCTAssertNotNil(err);
}

#pragma mark - Content negotiation

- (void)testAcceptHeaderNegotiatesUpstreamStarLite {
    XCTAssertEqual(PDSRepoFormatFromAcceptHeader(@"application/x.microcosm.star-lite"),
                   PDSRepoFormatSTARLiteV0);
    XCTAssertEqual(
        PDSRepoFormatFromAcceptHeader(@"application/x.microcosm.star-lite, application/vnd.ipld.car;q=0.5"),
        PDSRepoFormatSTARLiteV0);
    XCTAssertEqual(
        PDSRepoFormatFromAcceptHeader(@"application/x.microcosm.star-lite;q=0.4, application/vnd.ipld.car;q=0.9"),
        PDSRepoFormatCAR);

    // The local variant keeps its own media type and must not be confused with
    // the upstream one.
    XCTAssertEqual(PDSRepoFormatFromAcceptHeader(@"application/vnd.atproto.star-lite"),
                   PDSRepoFormatSTARLite);
    XCTAssertEqualObjects(ContentTypeForPDSRepoFormat(PDSRepoFormatSTARLiteV0),
                          @"application/x.microcosm.star-lite");
    XCTAssertEqualObjects(PDSRepoAcceptHeaderForPreferredFormat(PDSRepoFormatSTARLiteV0),
                          @"application/x.microcosm.star-lite, application/vnd.ipld.car;q=0.8");
}

- (void)testAcceptQueryParameterOverridesHeader {
    PDSRepoFormat format = PDSRepoFormatCAR;

    XCTAssertTrue(PDSRepoFormatFromAcceptQueryParameter(@"star-lite", &format));
    XCTAssertEqual(format, PDSRepoFormatSTARLiteV0);

    format = PDSRepoFormatCAR;
    XCTAssertTrue(PDSRepoFormatFromAcceptQueryParameter(@"  STAR-LITE  ", &format));
    XCTAssertEqual(format, PDSRepoFormatSTARLiteV0);

    format = PDSRepoFormatCAR;
    XCTAssertTrue(PDSRepoFormatFromAcceptQueryParameter(@"application/x.microcosm.star-lite", &format));
    XCTAssertEqual(format, PDSRepoFormatSTARLiteV0);

    format = PDSRepoFormatSTARLiteV0;
    XCTAssertTrue(PDSRepoFormatFromAcceptQueryParameter(@"car", &format));
    XCTAssertEqual(format, PDSRepoFormatCAR);

    // Unrecognized or absent values leave negotiation to the Accept header.
    XCTAssertFalse(PDSRepoFormatFromAcceptQueryParameter(nil, &format));
    XCTAssertFalse(PDSRepoFormatFromAcceptQueryParameter(@"", &format));
    XCTAssertFalse(PDSRepoFormatFromAcceptQueryParameter(@"protobuf", &format));
}

@end
