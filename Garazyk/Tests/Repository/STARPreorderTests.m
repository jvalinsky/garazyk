// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Repository/STAR.h"
#import "Repository/CAR.h"
#import "Core/CBOR.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"

/**
 * Pins STAR-L0's depth-first / record-interleaved chunk emission order against
 * Sync 1.1 "Streamable CAR Block Ordering" (the draft spec's pre-order DFS rules).
 *
 * Cross-validates ATProtoSTARL0Writer against the ATProtoMST pre-order walker landed in
 * MSTPreorderTests; both implementations should produce the same
 * "(MST node / record)" sequence for any given repo's ATProtoMST. A failure of the
 * equivalence assertion tells us which side drifted (this test unblocks future
 * spec promotion by being the one place we have to update either side from).
 *
 * Note: when adding new tests under Garazyk/Tests/Repository/, run
 *   cmake -S . -B build
 * before `cmake --build build --target AllTests`. The repository test glob
 * is cached at configure time; an incremental build will not pick up newly
 * added files.
 */
@interface STARPreorderTests : XCTestCase {
    NSMutableDictionary<NSString *, NSData *> *_cidToRecordData;
}
@end

@implementation STARPreorderTests

- (void)testRepoFormatNegotiationHonorsQualityAndFallbacks {
    XCTAssertEqual(PDSRepoFormatFromAcceptHeader(nil), PDSRepoFormatCAR);
    XCTAssertEqual(PDSRepoFormatFromAcceptHeader(@"application/vnd.atproto.star"),
                   PDSRepoFormatSTARL0);
    XCTAssertEqual(PDSRepoFormatFromAcceptHeader(@"application/vnd.atproto.star-lite"),
                   PDSRepoFormatSTARLite);
    XCTAssertEqual(
        PDSRepoFormatFromAcceptHeader(
            @"application/vnd.ipld.car, application/vnd.atproto.star;q=0.8"),
        PDSRepoFormatCAR);
    XCTAssertEqual(
        PDSRepoFormatFromAcceptHeader(
            @"application/vnd.atproto.star, application/vnd.ipld.car;q=0.9"),
        PDSRepoFormatSTARL0);
    XCTAssertEqual(
        PDSRepoFormatFromAcceptHeader(
            @"application/vnd.atproto.star;q=0, application/vnd.ipld.car;q=0.5"),
        PDSRepoFormatCAR);
    XCTAssertEqual(PDSRepoFormatFromAcceptHeader(@"*/*"), PDSRepoFormatCAR);
}

- (void)testRepoAcceptHeadersAlwaysProvideCompatibleFallbacks {
    XCTAssertEqualObjects(
        PDSRepoAcceptHeaderForPreferredFormat(PDSRepoFormatCAR),
        @"application/vnd.ipld.car");
    XCTAssertEqualObjects(
        PDSRepoAcceptHeaderForPreferredFormat(PDSRepoFormatSTARL0),
        @"application/vnd.atproto.star, application/vnd.ipld.car;q=0.9");
    XCTAssertEqualObjects(
        PDSRepoAcceptHeaderForPreferredFormat(PDSRepoFormatSTARLite),
        @"application/vnd.atproto.star-lite, application/vnd.atproto.star;q=0.9, application/vnd.ipld.car;q=0.8");
}

#pragma mark - Setup / teardown

- (void)setUp {
    [super setUp];
    // The ATProtoMST pre-order walker is gated; enable it for the duration of this
    // suite so we can cross-validate STAR emission against it. MSTPreorderTests
    // also enables this flag and tears it down; we do the same.
    [ATProtoMST setStreamableCARBlockOrderingEnabled:YES];
}

- (void)tearDown {
    [ATProtoMST setStreamableCARBlockOrderingEnabled:NO];
    [super tearDown];
}

#pragma mark - Test data helpers

- (NSData *)testRecordDataForKey:(NSString *)key {
    // Deterministic per-record data: valid canonical DAG-CBOR map.
    // ATProtoCID is SHA-256 of this data — cryptographically consistent round-trip.
    NSError *error = nil;
    NSData *cbor = [[[ATProtoCBORSerialization alloc] initWithContentAddressed:YES]
        encodeDataWithJSONObject:@{@"v": key} error:&error];
    NSCAssert(cbor != nil, @"Failed to encode record CBOR: %@", error);
    return cbor;
}

- (MSTBlockProvider)recordProviderForTree:(ATProtoMST *)tree {
    // ATProtoCID→recordData mapping was precomputed in buildSmallDeterministicFixture.
    NSDictionary<NSString *, NSData *> *cache = [_cidToRecordData copy];
    return ^NSData *(ATProtoCID *cid) {
        return cache[cid.stringValue];
    };
}

- (ATProtoMST *)buildSmallDeterministicFixture {
    // Eight ATProtoTID-format keys; their SHA-256 depths span multiple levels so the
    // ATProtoMST is multi-level. The exact tree shape is irrelevant — invariants are
    // cross-checked against the ATProtoMST pre-order walker for these exact keys.
    //
    // Record data is computed first, then CIDs are derived from SHA-256(data),
    // so ATProtoCID(record) == entry.value — the invariant required for verifying
    // round-trip through the STAR reader.
    NSArray<NSString *> *keys = @[
        @"app.bsky.feed.post/3jzfcijpj2z2a",
        @"app.bsky.feed.post/3jzfcijpj2z2b",
        @"app.bsky.feed.post/3jzfcijpj2z2c",
        @"app.bsky.feed.post/3jzfcijpj2z2d",
        @"app.bsky.feed.post/3jzfcijpj2z2e",
        @"app.bsky.feed.post/3jzfcijpj2z2f",
        @"app.bsky.feed.post/3jzfcijpj2z2g",
        @"app.bsky.feed.post/3jzfcijpj2z2h"
    ];
    _cidToRecordData = [NSMutableDictionary dictionary];
    ATProtoMST *tree = [[ATProtoMST alloc] init];
    for (NSString *key in keys) {
        NSData *recordData = [self testRecordDataForKey:key];
        ATProtoCID *cid = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:recordData] codec:0x71];
        _cidToRecordData[cid.stringValue] = recordData;
        [tree put:key valueCID:cid];
    }
    return tree;
}

- (ATProtoSTARCommit *)buildCommitForRoot:(ATProtoCID *)rootCID {
    return [ATProtoSTARCommit commitWithDid:@"did:plc:starfixture"
                              version:3
                                data:rootCID
                                 rev:@"3jzfcijpj2z2z"
                                prev:nil
                                 sig:[@"fixture-sig" dataUsingEncoding:NSUTF8StringEncoding]];
}

/// A stored commit block in the shape a PDS persists it, as raw DAG-CBOR
/// (not routed through ATProtoSTARCommit's fixed-field-list model). `extraKey`
/// stands in for a field this implementation does not otherwise model.
- (NSData *)rawCommitBlockForRoot:(ATProtoCID *)rootCID
                   includeNullPrev:(BOOL)includeNullPrev
                          extraKey:(nullable NSString *)extraKey {
    NSMutableData *tagged = [NSMutableData dataWithBytes:(uint8_t[]){0x00} length:1];
    [tagged appendData:rootCID.bytes];

    NSMutableDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *map = [NSMutableDictionary dictionary];
    map[[ATProtoCBORValue textString:@"did"]] = [ATProtoCBORValue textString:@"did:plc:starfixture"];
    map[[ATProtoCBORValue textString:@"version"]] = [ATProtoCBORValue unsignedInteger:3];
    map[[ATProtoCBORValue textString:@"data"]] =
        [ATProtoCBORValue tag:42 value:[ATProtoCBORValue byteString:tagged]];
    map[[ATProtoCBORValue textString:@"rev"]] = [ATProtoCBORValue textString:@"3jzfcijpj2z2z"];
    if (includeNullPrev) {
        map[[ATProtoCBORValue textString:@"prev"]] = [ATProtoCBORValue nilValue];
    }
    if (extraKey) {
        map[[ATProtoCBORValue textString:extraKey]] = [ATProtoCBORValue textString:@"unmodeled-value"];
    }
    map[[ATProtoCBORValue textString:@"sig"]] =
        [ATProtoCBORValue byteString:[@"fixture-signature-64-bytes-placeholder"
                                         dataUsingEncoding:NSUTF8StringEncoding]];
    return [[ATProtoCBORValue map:map] encode];
}

#pragma mark - Chunk classification

/// Classify a chunk by inspecting its decoded DAG-CBOR structure.
/// Returns one of: "commit", "node", "record", "other".
- (NSString *)classifyChunk:(NSData *)chunk {
    if (chunk.length == 0) {
        return @"empty";
    }
    ATProtoCBORValue *v = [ATProtoCBORValue decode:chunk];
    if (!v || v.type != CBORTypeMap) {
        return @"other";
    }
    NSDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *dict = v.map;
    if (dict[[ATProtoCBORValue textString:@"did"]]) {
        return @"commit";
    }
    if (dict[[ATProtoCBORValue textString:@"e"]]) {
        return @"node";
    }
    return @"record";
}

/// Treats STAR-L0 chunks as: [magic, ver, commitLen, commitCBOR, len, content, len, content, ...].
/// Returns classification of every content chunk (the syncopated half of the
/// alternating pattern, starting at index 5).
- (NSArray<NSString *> *)classifySTARL0ContentChunks:(NSArray<NSData *> *)chunks {
    NSMutableArray<NSString *> *kinds = [NSMutableArray array];
    for (NSUInteger i = 5; i < chunks.count; i += 2) {
        [kinds addObject:[self classifyChunk:chunks[i]]];
    }
    return kinds;
}

#pragma mark - Header structure

- (void)testSTARL0HeaderIsFourChunks {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc]
        initWithCommit:commit
            outputBlock:^(NSData *chunk) { [chunks addObject:chunk]; }];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err],
                  @"writeFromMST failed: %@", err);
    XCTAssertGreaterThanOrEqual(chunks.count, (NSUInteger)4);

    // Chunk 0: STAR magic byte (0x2A).
    XCTAssertEqual(chunks[0].length, (NSUInteger)1);
    XCTAssertEqual(((const uint8_t *)chunks[0].bytes)[0], (uint8_t)0x2A);

    // Chunk 1: version varint. STAR-L0 always writes version=1.
    XCTAssertGreaterThanOrEqual(chunks[1].length, (NSUInteger)1);

    // Chunk 2: commit-length varint (>= 1 byte).
    XCTAssertGreaterThanOrEqual(chunks[2].length, (NSUInteger)1);

    // Chunk 3: commit DAG-CBOR (decode as commit).
    XCTAssertEqualObjects([self classifyChunk:chunks[3]], @"commit");
}

#pragma mark - Spec-order equivalence

- (void)testSTARL0EmissionMatchesMSTPreorderSpec {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    MSTBlockProvider recProvider = [self recordProviderForTree:tree];

    // Expected order via the new ATProtoMST pre-order walker (gated, enabled in setUp).
    NSMutableArray<NSString *> *expectedOrder = [NSMutableArray array];
    NSError *e1 = nil;
    BOOL ok1 = [tree
        enumerateStreamableCARBlocksUsingBlock:^BOOL(ATProtoCID *cid, NSData *data,
                                                    NSError **e) {
            [expectedOrder addObject:[self classifyChunk:data]];
            return YES;
        }
                      recordProvider:recProvider
                              error:&e1];
    XCTAssertTrue(ok1, @"MST preorder walker failed: %@", e1);
    XCTAssertGreaterThan(expectedOrder.count, (NSUInteger)0);

    // Actual order from ATProtoSTARL0Writer streamed chunks.
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc]
        initWithCommit:commit
            outputBlock:^(NSData *chunk) { [chunks addObject:chunk]; }];
    NSError *e2 = nil;
    BOOL ok2 = [w writeFromMST:tree
                    blockProvider:recProvider
                            error:&e2];
    XCTAssertTrue(ok2, @"STAR-L0 write failed: %@", e2);
    NSArray<NSString *> *actualOrder = [self classifySTARL0ContentChunks:chunks];

    // The two implementations must agree on the (node/record) kind at every
    // emission step. If they diverge, one of the two needs to change to match
    // the Sync 1.1 draft.
    XCTAssertEqualObjects(actualOrder, expectedOrder,
        @"STAR-L0 emission must match MST pre-order DFS (Sync 1.1 spec). "
        @"actual=%@ expected=%@",
        actualOrder, expectedOrder);
}

#pragma mark - Structural invariants

- (void)testSTARL0FirstContentChunkIsMSTNode {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc]
        initWithCommit:commit
            outputBlock:^(NSData *chunk) { [chunks addObject:chunk]; }];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSArray<NSString *> *kinds = [self classifySTARL0ContentChunks:chunks];
    XCTAssertGreaterThan(kinds.count, (NSUInteger)0);
    XCTAssertEqualObjects(kinds.firstObject, @"node",
        @"First body chunk after the header must be the root MST node.");
}

- (void)testSTARL0ChunkCountMatchesBlockCount {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    MSTBlockProvider recProvider = [self recordProviderForTree:tree];

    // Count emitted blocks via ATProtoMST pre-order walker.
    NSError *err = nil;
    __block NSUInteger blockCount = 0;
    [tree enumerateStreamableCARBlocksUsingBlock:^BOOL(ATProtoCID *cid, NSData *data,
                                                        NSError **e) {
        blockCount++;
        return YES;
    } recordProvider:recProvider error:&err];

    // Capture chunks from STAR and assert header(4) + 2*blockCount.
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc]
        initWithCommit:commit
            outputBlock:^(NSData *chunk) { [chunks addObject:chunk]; }];
    NSError *e2 = nil;
    BOOL ok = [w writeFromMST:tree blockProvider:recProvider error:&e2];
    XCTAssertTrue(ok);
    XCTAssertEqual(chunks.count, (NSUInteger)4 + 2 * blockCount,
        @"STAR-L0 must emit 4 header chunks + 2 chunks per logical block "
        @"(length-prefix + DAG-CBOR).");
}

#pragma mark - Fixture capture (pin)

- (void)testEmitsSTARL0FixtureForComparison {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc]
        initWithCommit:commit
            outputBlock:^(NSData *chunk) { [chunks addObject:chunk]; }];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);

    NSArray<NSString *> *kinds = [self classifySTARL0ContentChunks:chunks];
    NSMutableArray<NSString *> *humanReadable = [NSMutableArray array];
    NSUInteger nodeCount = 0;
    NSUInteger recordCount = 0;
    for (NSString *kind in kinds) {
        if ([kind isEqualToString:@"node"]) {
            nodeCount++;
            [humanReadable addObject:[NSString stringWithFormat:@"#%lu node", (unsigned long)nodeCount]];
        } else if ([kind isEqualToString:@"record"]) {
            recordCount++;
            [humanReadable addObject:[NSString stringWithFormat:@"#%lu record", (unsigned long)recordCount]];
        } else {
            [humanReadable addObject:[NSString stringWithFormat:@"(unexpected:%@)", kind]];
        }
    }

    NSLog(@"[STARPreorderTests][FIXTURE] === STAR-L0 Sync 1.1 emission (small fixture) ===");
    NSLog(@"[STARPreorderTests][FIXTURE] rootCID=%@ (8 entries: feed.post deterministic TIDs)", tree.rootCID.stringValue);
    NSLog(@"[STARPreorderTests][FIXTURE] chunks: header=4  blocks=%lu  nodes=%lu  records=%lu",
          (unsigned long)kinds.count, (unsigned long)nodeCount, (unsigned long)recordCount);
    NSLog(@"[STARPreorderTests][FIXTURE] emission sequence:");
    for (NSUInteger i = 0; i < humanReadable.count; i++) {
        NSLog(@"[STARPreorderTests][FIXTURE]   %3lu. %@", (unsigned long)(i + 1), humanReadable[i]);
    }
    NSLog(@"[STARPreorderTests][FIXTURE] ================================================");

    // Pin structural shape so a failure prints an obvious diff in xcTest output.
    XCTAssertGreaterThan(nodeCount, (NSUInteger)0, @"Fixture must contain at least one MST node.");
    XCTAssertEqual(nodeCount + recordCount, kinds.count);
    XCTAssertEqualObjects(kinds.firstObject, @"node",
        @"Root MST node must be emitted first, before any record.");
    XCTAssertEqual(recordCount, (NSUInteger)8,
        @"Eight ATProtoTID-format leaves: every entry's record must be emitted (each at the spot its entry appears in the DFS).");
}

#pragma mark - STAR-Lite (separate format)

#pragma mark - V-flag conformance (Slice A: spec wire-format fix)

/// Inline LEB128 varint reader (mirrors STARReadVarint, which is module-private).
static NSUInteger TestReadVarint(const uint8_t *bytes, NSUInteger maxLength, uint64_t *value) {
    if (maxLength == 0) return 0;
    uint64_t result = 0;
    NSUInteger shift = 0;
    NSUInteger off = 0;
    while (off < maxLength) {
        uint8_t byte = bytes[off++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) {
            *value = result;
            return off;
        }
        if (shift >= 64) return 0;
    }
    return 0;
}

#pragma mark - STAR-L0 commit fidelity (mirrors STARLiteV0Writer's strip/verify pattern)

- (void)testL0HeaderEmbedsStoredCommitVerbatimIncludingNullPrev {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    NSData *commitBlock = [self rawCommitBlockForRoot:tree.rootCID includeNullPrev:YES extraKey:nil];

    NSError *err = nil;
    ATProtoSTARL0Writer *writer = [[ATProtoSTARL0Writer alloc] initWithCommitBlock:commitBlock error:&err];
    XCTAssertNotNil(writer, @"writer init failed: %@", err);
    XCTAssertTrue([writer writeFromMST:tree
                         blockProvider:[self recordProviderForTree:tree]
                                 error:&err]);
    NSData *starData = [writer serialize];

    const uint8_t *bytes = starData.bytes;
    NSUInteger offset = 1; // past magic
    uint64_t ver = 0;
    offset += TestReadVarint(bytes + offset, starData.length - offset, &ver);
    uint64_t commitLen = 0;
    offset += TestReadVarint(bytes + offset, starData.length - offset, &commitLen);
    NSData *embeddedCommit = [starData subdataWithRange:NSMakeRange(offset, (NSUInteger)commitLen)];

    XCTAssertEqualObjects(embeddedCommit, commitBlock,
                          @"STAR-L0 must embed the stored commit verbatim, including a present-but-null `prev`");
}

- (void)testL0HeaderPreservesUnmodeledField {
    NSData *commitBlock = [self rawCommitBlockForRoot:[self buildSmallDeterministicFixture].rootCID
                                       includeNullPrev:NO
                                              extraKey:@"futureField"];

    NSError *err = nil;
    ATProtoSTARL0Writer *writer = [[ATProtoSTARL0Writer alloc] initWithCommitBlock:commitBlock error:&err];
    XCTAssertNotNil(writer, @"writer init failed: %@", err);
    XCTAssertEqualObjects([ATProtoSTARL0Writer commitBytesFromCommitBlock:commitBlock error:nil], commitBlock,
                          @"An unmodeled field must survive the round-trip verification unchanged");
}

- (void)testL0RejectsNonMapCommitBlock {
    NSData *notAMap = [[ATProtoCBORValue textString:@"nope"] encode];
    NSError *err = nil;
    ATProtoSTARL0Writer *writer = [[ATProtoSTARL0Writer alloc] initWithCommitBlock:notAMap error:&err];
    XCTAssertNil(writer);
    XCTAssertNotNil(err);
}

- (void)testL0RejectsEmptyCommitBlock {
    NSError *err = nil;
    ATProtoSTARL0Writer *writer = [[ATProtoSTARL0Writer alloc] initWithCommitBlock:[NSData data] error:&err];
    XCTAssertNil(writer);
    XCTAssertNotNil(err);
}

- (void)testSTARL0VFlagAbsentWhenVIsAbsent {
    // Per the STAR spec, V "must not be present when v is not present."
    // At layer 0, the writer omits 'v' for archived records (the record
    // follows inline), and the absence of 'v' IS the archived signal.
    // This test asserts the wire-format fix from Slice A: no 'V' key
    // appears in any entry that lacks a 'v' key.
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];
    XCTAssertGreaterThan(starData.length, (NSUInteger)0);

    const uint8_t *bytes = starData.bytes;
    NSUInteger length = starData.length;
    NSUInteger offset = 0;

    // Walk past header: magic(0x2A) + varint(version) + varint(commitLen) + commit
    if (length < 1 || bytes[0] != 0x2A) {
        XCTFail(@"Missing STAR magic byte");
        return;
    }
    offset = 1;
    uint64_t ver = 0;
    NSUInteger verLen = TestReadVarint(bytes + offset, length - offset, &ver);
    XCTAssertGreaterThan(verLen, (NSUInteger)0, @"Failed to read STAR version varint");
    offset += verLen;

    uint64_t commitLen = 0;
    NSUInteger cLen = TestReadVarint(bytes + offset, length - offset, &commitLen);
    XCTAssertGreaterThan(cLen, (NSUInteger)0, @"Failed to read commit length varint");
    offset += cLen;
    offset += (NSUInteger)commitLen;

    // Walk the body: each block is varint(length) + data
    NSUInteger nodesInspected = 0;
    while (offset < length) {
        uint64_t blockLen = 0;
        NSUInteger lSize = TestReadVarint(bytes + offset, length - offset, &blockLen);
        if (lSize == 0) {
            XCTFail(@"Truncated block length at offset %lu", (unsigned long)offset);
            return;
        }
        offset += lSize;

        if (offset + blockLen > length) {
            XCTFail(@"Truncated block data at offset %lu", (unsigned long)offset);
            return;
        }

        NSData *blockData = [NSData dataWithBytes:bytes + offset length:(NSUInteger)blockLen];
        offset += (NSUInteger)blockLen;

        ATProtoCBORValue *v = [ATProtoCBORValue decode:blockData];
        if (!v || v.type != CBORTypeMap) continue;

        // Is this an ATProtoMST node? (has 'e' key)
        ATProtoCBORValue *entriesVal = v.map[[ATProtoCBORValue textString:@"e"]];
        if (!entriesVal || entriesVal.type != CBORTypeArray) continue;

        nodesInspected++;
        for (ATProtoCBORValue *entryCBOR in entriesVal.array) {
            if (entryCBOR.type != CBORTypeMap) continue;
            NSDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *entryMap = entryCBOR.map;
            BOOL hasV = entryMap[[ATProtoCBORValue textString:@"v"]] != nil;
            BOOL hasVFlag = entryMap[[ATProtoCBORValue textString:@"V"]] != nil;

            if (!hasV) {
                XCTAssertFalse(hasVFlag,
                    @"Wire-format spec violation in node #%lu: 'V' flag present without 'v'. "
                    @"Per STAR spec §3: 'V must not be present when v is not present.' "
                    @"At layer 0, absence of 'v' IS the archived signal.",
                    (unsigned long)nodesInspected);
            }
        }
    }

    XCTAssertGreaterThan(nodesInspected, (NSUInteger)0,
        @"Fixture must contain at least one MST node to validate V-flag conformance.");
    NSLog(@"[STARPreorderTests][V-FLAG] Inspected %lu MST nodes; no V-without-v violations found.",
          (unsigned long)nodesInspected);
}

#pragma mark - Verifying reader (Slice B: round-trip, empty-tree, malformed-input)

/// Build a STAR-L0 archive from the deterministic fixture and read it back
/// with the verifying reader, asserting CIDs match and blocks are correct.
- (void)testSTARL0RoundTripViaVerifyingReader {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // Read back with verifying reader
    ATProtoSTARReader *reader = [ATProtoSTARReader readFromData:starData error:&err];
    XCTAssertNotNil(reader, @"Verifying reader failed: %@", err);
    XCTAssertNil(err);
    XCTAssertEqual(reader.variant, STARVariantL0);
    XCTAssertNotNil(reader.commit);

    // Root ATProtoCID must match commit.data (the ATProtoMST root)
    XCTAssertNotNil(reader.rootCID);
    XCTAssertEqualObjects(reader.rootCID, tree.rootCID,
        @"Reader rootCID must match the MST root CID");

    // Blocks must be present and indexed
    XCTAssertGreaterThan(reader.blocks.count, (NSUInteger)0);
    for (ATProtoCARBlock *block in reader.blocks) {
        ATProtoCARBlock *found = [reader blockWithCID:block.cid];
        XCTAssertNotNil(found, @"Block %@ not indexed", block.cid.stringValue);
        XCTAssertEqualObjects(found.data, block.data);
    }

    // Every ATProtoMST node block must be tagged as a node
    NSUInteger nodeCount = 0;
    NSUInteger recordCount = 0;
    for (ATProtoCARBlock *block in reader.blocks) {
        NSString *kind = [self classifyChunk:block.data];
        if ([kind isEqualToString:@"node"]) nodeCount++;
        else if ([kind isEqualToString:@"record"]) recordCount++;
    }
    XCTAssertGreaterThan(nodeCount, (NSUInteger)0, @"Must contain at least one MST node");
    XCTAssertEqual(recordCount, (NSUInteger)8,
        @"Must contain all 8 records from the fixture");
}

/// Empty tree: the writer emits only a header (commit with nil data).
/// The verifying reader must accept this and return zero blocks.
- (void)testSTARL0EmptyTreeRoundTrip {
    ATProtoSTARCommit *emptyCommit = [ATProtoSTARCommit commitWithDid:@"did:plc:empty"
                                                 version:3
                                                   data:nil
                                                    rev:@"3jzfcijpj2z2z"
                                                   prev:nil
                                                    sig:[@"fixture-sig" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc] initWithCommit:emptyCommit];
    NSError *err = nil;
    // nil ATProtoMST = truly empty tree (no root node)
    XCTAssertTrue([w writeFromMST:nil blockProvider:nil error:&err]);
    NSData *starData = [w serialize];
    XCTAssertGreaterThan(starData.length, (NSUInteger)0);

    ATProtoSTARReader *reader = [ATProtoSTARReader readFromData:starData error:&err];
    XCTAssertNotNil(reader, @"Reader failed on empty tree: %@", err);
    XCTAssertNil(err);
    XCTAssertNil(reader.rootCID, @"Empty tree must have nil rootCID");
    XCTAssertEqual(reader.blocks.count, (NSUInteger)0,
        @"Empty tree must produce zero blocks");
}

/// Malformed: trailing bytes after the tree completes must be rejected.
- (void)testSTARL0ReaderRejectsTrailingBytes {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // Append 4 garbage bytes
    NSMutableData *malformed = [starData mutableCopy];
    uint8_t garbage[] = {0xFF, 0xFF, 0xFF, 0xFF};
    [malformed appendBytes:garbage length:4];

    ATProtoSTARReader *reader = [ATProtoSTARReader readFromData:malformed error:&err];
    XCTAssertNil(reader, @"Reader must reject trailing bytes");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 44, @"Expected error 44 (trailing bytes after tree completes), got %ld", (long)err.code);
}

/// Malformed: truncated block length varint must be rejected.
- (void)testSTARL0ReaderRejectsTruncatedBlock {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // Truncate to just the header (magic + version varint + commit len varint + commit)
    // We need to find where the header ends and truncate there
    const uint8_t *bytes = starData.bytes;
    NSUInteger offset = 1; // skip magic
    uint64_t verVal = 0;
    offset += TestReadVarint(bytes + offset, starData.length - offset, &verVal);
    uint64_t commitLenVal = 0;
    offset += TestReadVarint(bytes + offset, starData.length - offset, &commitLenVal);
    offset += (NSUInteger)commitLenVal;

    // Truncate right at the start of the first body block's length varint
    NSData *truncated = [starData subdataWithRange:NSMakeRange(0, offset)];

    ATProtoSTARReader *reader = [ATProtoSTARReader readFromData:truncated error:&err];
    XCTAssertNil(reader, @"Reader must reject truncated body");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 31, @"Expected error 31 (truncated stream), got %ld", (long)err.code);
}

/// Full STAR -> CAR conversion round trip.
- (void)testSTARL0STARToCARConversion {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    ATProtoSTARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // Convert STAR to CAR
    NSData *carData = [ATProtoSTARConverter carDataFromSTARData:starData error:&err];
    XCTAssertNotNil(carData, @"STAR->CAR conversion failed: %@", err);
    XCTAssertNil(err);

    // Parse the CAR
    ATProtoCARReader *carReader = [ATProtoCARReader readFromData:carData error:&err];
    XCTAssertNotNil(carReader, @"CAR parse failed: %@", err);
    XCTAssertNil(err);

    // CAR root must be the commit ATProtoCID, not the ATProtoMST root
    XCTAssertNotNil(carReader.rootCID);
    XCTAssertNotEqualObjects(carReader.rootCID, tree.rootCID,
        @"CAR root must be commit CID, not MST root CID");

    // Must contain a commit block (with did key)
    ATProtoCARBlock *commitBlock = [carReader blockWithCID:carReader.rootCID];
    XCTAssertNotNil(commitBlock, @"CAR must contain commit block");
    ATProtoCBORValue *commitVal = [ATProtoCBORValue decode:commitBlock.data];
    XCTAssertNotNil(commitVal);
    XCTAssertNotNil(commitVal.map[[ATProtoCBORValue textString:@"did"]]);

    // Must contain at least the same number of blocks as the STAR reader produced
    ATProtoSTARReader *starReader = [ATProtoSTARReader readFromData:starData error:&err];
    XCTAssertNotNil(starReader);
    // CAR has 1 extra block (the commit) beyond what STAR reader produces
    XCTAssertGreaterThanOrEqual(carReader.blocks.count, starReader.blocks.count + 1,
        @"CAR must contain commit + all STAR blocks");
}

/// Sig-less STAR must be rejected by the CAR converter.
- (void)testSTARL0CARConversionRejectsSigmlessArchive {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    ATProtoSTARCommit *commit = [ATProtoSTARCommit commitWithDid:@"did:plc:nosig"
                                           version:3
                                             data:tree.rootCID
                                              rev:@"3jzfcijpj2z2z"
                                             prev:nil
                                              sig:nil];
    ATProtoSTARL0Writer *w = [[ATProtoSTARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // STAR reader should still parse it (verifying reader only checks CIDs, sig is for CAR conversion)
    ATProtoSTARReader *reader = [ATProtoSTARReader readFromData:starData error:&err];
    XCTAssertNotNil(reader, @"Reader must accept sig-less STAR for verification");

    // But CAR conversion must reject
    NSData *carData = [ATProtoSTARConverter carDataFromSTARData:starData error:&err];
    XCTAssertNil(carData, @"CAR conversion must reject sig-less STAR");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 21, @"Expected error 21 (no signature), got %ld", (long)err.code);
}

#pragma mark - STAR-Lite (separate format)

- (void)testSTARLiteHasNoMSTNodesAndUsesVersionTwo {
    ATProtoMST *tree = [self buildSmallDeterministicFixture];
    ATProtoSTARLiteWriter *w = [[ATProtoSTARLiteWriter alloc]
        initWithCommit:[self buildCommitForRoot:tree.rootCID]];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starLite = [w serialize];
    XCTAssertGreaterThan(starLite.length, (NSUInteger)0);

    // STAR-Lite magic is the same byte (0x2A) but version varint is 2.
    XCTAssertEqual(((const uint8_t *)starLite.bytes)[0], (uint8_t)0x2A);

    // Round-trip: ATProtoSTARReader reports STARVariantLite and contains only record
    // blocks (no ATProtoMST nodes, because Lite is a flat key-record format that does
    // NOT follow the Sync 1.1 depth-first + record-interleaved layout; it
    // drains [mst allEntries] in key order).
    ATProtoSTARReader *reader = [ATProtoSTARReader readFromData:starLite error:&err];
    XCTAssertNil(err);
    XCTAssertEqual(reader.variant, STARVariantLite);
    NSUInteger nodes = 0;
    NSUInteger records = 0;
    for (ATProtoCARBlock *block in reader.blocks) {
        if ([[self classifyChunk:block.data] isEqualToString:@"node"]) {
            nodes++;
        } else if ([[self classifyChunk:block.data] isEqualToString:@"record"]) {
            records++;
        }
    }
    XCTAssertEqual(nodes, (NSUInteger)0,
        @"STAR-Lite must not contain MST node blocks; it is a flat key-record format.");
    XCTAssertEqual(records, (NSUInteger)8,
        @"STAR-Lite must contain one record per MST entry (8 leaves in this fixture).");
}

@end
