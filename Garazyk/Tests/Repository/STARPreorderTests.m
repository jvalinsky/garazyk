// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Repository/STAR.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"

/**
 * Pins STAR-L0's depth-first / record-interleaved chunk emission order against
 * Sync 1.1 "Streamable CAR Block Ordering" (the draft spec's pre-order DFS rules).
 *
 * Cross-validates STARL0Writer against the MST pre-order walker landed in
 * MSTPreorderTests; both implementations should produce the same
 * "(MST node / record)" sequence for any given repo's MST. A failure of the
 * equivalence assertion tells us which side drifted (this test unblocks future
 * spec promotion by being the one place we have to update either side from).
 *
 * Note: when adding new tests under Garazyk/Tests/Repository/, run
 *   cmake -S . -B build
 * before `cmake --build build --target AllTests`. The repository test glob
 * is cached at configure time; an incremental build will not pick up newly
 * added files.
 */
@interface STARPreorderTests : XCTestCase
@end

@implementation STARPreorderTests

#pragma mark - Setup / teardown

- (void)setUp {
    [super setUp];
    // The MST pre-order walker is gated; enable it for the duration of this
    // suite so we can cross-validate STAR emission against it. MSTPreorderTests
    // also enables this flag and tears it down; we do the same.
    [MST setStreamableCARBlockOrderingEnabled:YES];
}

- (void)tearDown {
    [MST setStreamableCARBlockOrderingEnabled:NO];
    [super tearDown];
}

#pragma mark - Test data helpers

- (CID *)testCIDForKey:(NSString *)key {
    return [CID sha256:[key dataUsingEncoding:NSUTF8StringEncoding]];
}

- (NSData *)testRecordDataForCID:(CID *)cid {
    // Deterministic per-record data so byte-identity checks are stable.
    NSMutableData *out = [NSMutableData data];
    uint8_t marker = 0xA1;
    [out appendBytes:&marker length:1];
    [out appendData:cid.bytes];
    return out;
}

- (MSTBlockProvider)recordProviderForTree:(MST *)tree {
    // Walk the same MST the writer will see, so the cache is intentionally in
    // lock-step with the entries the writer will traverse. Deterministic per-CID
    // payload keeps byte-identity stable across runs.
    NSMutableDictionary<NSString *, NSData *> *cache = [NSMutableDictionary dictionary];
    for (MSTEntry *e in [tree allEntries]) {
        cache[e.valueCID.stringValue] = [self testRecordDataForCID:e.valueCID];
    }
    MSTBlockProvider provider = ^NSData *(CID *cid) {
        return cache[cid.stringValue];
    };
    return provider;
}

- (MST *)buildSmallDeterministicFixture {
    // Eight TID-format keys; their SHA-256 depths span multiple levels so the
    // MST is multi-level. The exact tree shape is irrelevant — invariants are
    // cross-checked against the MST pre-order walker for these exact keys.
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
    MST *tree = [[MST alloc] init];
    for (NSString *key in keys) {
        [tree put:key valueCID:[self testCIDForKey:key]];
    }
    return tree;
}

- (STARCommit *)buildCommitForRoot:(CID *)rootCID {
    return [STARCommit commitWithDid:@"did:plc:starfixture"
                              version:3
                                data:rootCID
                                 rev:@"3jzfcijpj2z2z"
                                prev:nil
                                 sig:[@"fixture-sig" dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - Chunk classification

/// Classify a chunk by inspecting its decoded DAG-CBOR structure.
/// Returns one of: "commit", "node", "record", "other".
- (NSString *)classifyChunk:(NSData *)chunk {
    if (chunk.length == 0) {
        return @"empty";
    }
    CBORValue *v = [CBORValue decode:chunk];
    if (!v || v.type != CBORTypeMap) {
        return @"other";
    }
    NSDictionary<CBORValue *, CBORValue *> *dict = v.map;
    if (dict[[CBORValue textString:@"did"]]) {
        return @"commit";
    }
    if (dict[[CBORValue textString:@"e"]]) {
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
    MST *tree = [self buildSmallDeterministicFixture];
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc]
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
    MST *tree = [self buildSmallDeterministicFixture];
    MSTBlockProvider recProvider = [self recordProviderForTree:tree];

    // Expected order via the new MST pre-order walker (gated, enabled in setUp).
    NSMutableArray<NSString *> *expectedOrder = [NSMutableArray array];
    NSError *e1 = nil;
    BOOL ok1 = [tree
        enumerateStreamableCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data,
                                                    NSError **e) {
            [expectedOrder addObject:[self classifyChunk:data]];
            return YES;
        }
                      recordProvider:recProvider
                              error:&e1];
    XCTAssertTrue(ok1, @"MST preorder walker failed: %@", e1);
    XCTAssertGreaterThan(expectedOrder.count, (NSUInteger)0);

    // Actual order from STARL0Writer streamed chunks.
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc]
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
    MST *tree = [self buildSmallDeterministicFixture];
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc]
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
    MST *tree = [self buildSmallDeterministicFixture];
    MSTBlockProvider recProvider = [self recordProviderForTree:tree];

    // Count emitted blocks via MST pre-order walker.
    NSError *err = nil;
    __block NSUInteger blockCount = 0;
    [tree enumerateStreamableCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data,
                                                        NSError **e) {
        blockCount++;
        return YES;
    } recordProvider:recProvider error:&err];

    // Capture chunks from STAR and assert header(4) + 2*blockCount.
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc]
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
    MST *tree = [self buildSmallDeterministicFixture];
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc]
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
        @"Eight TID-format leaves: every entry's record must be emitted (each at the spot its entry appears in the DFS).");
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

- (void)testSTARL0VFlagAbsentWhenVIsAbsent {
    // Per the STAR spec, V "must not be present when v is not present."
    // At layer 0, the writer omits 'v' for archived records (the record
    // follows inline), and the absence of 'v' IS the archived signal.
    // This test asserts the wire-format fix from Slice A: no 'V' key
    // appears in any entry that lacks a 'v' key.
    MST *tree = [self buildSmallDeterministicFixture];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc] initWithCommit:commit];
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

        CBORValue *v = [CBORValue decode:blockData];
        if (!v || v.type != CBORTypeMap) continue;

        // Is this an MST node? (has 'e' key)
        CBORValue *entriesVal = v.map[[CBORValue textString:@"e"]];
        if (!entriesVal || entriesVal.type != CBORTypeArray) continue;

        nodesInspected++;
        for (CBORValue *entryCBOR in entriesVal.array) {
            if (entryCBOR.type != CBORTypeMap) continue;
            NSDictionary<CBORValue *, CBORValue *> *entryMap = entryCBOR.map;
            BOOL hasV = entryMap[[CBORValue textString:@"v"]] != nil;
            BOOL hasVFlag = entryMap[[CBORValue textString:@"V"]] != nil;

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
    MST *tree = [self buildSmallDeterministicFixture];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // Read back with verifying reader
    STARReader *reader = [STARReader readFromData:starData error:&err];
    XCTAssertNotNil(reader, @"Verifying reader failed: %@", err);
    XCTAssertNil(err);
    XCTAssertEqual(reader.variant, STARVariantL0);
    XCTAssertNotNil(reader.commit);

    // Root CID must match commit.data (the MST root)
    XCTAssertNotNil(reader.rootCID);
    XCTAssertEqualObjects(reader.rootCID, tree.rootCID,
        @"Reader rootCID must match the MST root CID");

    // Blocks must be present and indexed
    XCTAssertGreaterThan(reader.blocks.count, (NSUInteger)0);
    for (CARBlock *block in reader.blocks) {
        CARBlock *found = [reader blockWithCID:block.cid];
        XCTAssertNotNil(found, @"Block %@ not indexed", block.cid.stringValue);
        XCTAssertEqualObjects(found.data, block.data);
    }

    // Every MST node block must be tagged as a node
    NSUInteger nodeCount = 0;
    NSUInteger recordCount = 0;
    for (CARBlock *block in reader.blocks) {
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
    STARCommit *emptyCommit = [STARCommit commitWithDid:@"did:plc:empty"
                                                 version:3
                                                   data:nil
                                                    rev:@"3jzfcijpj2z2z"
                                                   prev:nil
                                                    sig:[@"fixture-sig" dataUsingEncoding:NSUTF8StringEncoding]];
    STARL0Writer *w = [[STARL0Writer alloc] initWithCommit:emptyCommit];
    NSError *err = nil;
    // nil MST = truly empty tree (no root node)
    XCTAssertTrue([w writeFromMST:nil blockProvider:nil error:&err]);
    NSData *starData = [w serialize];
    XCTAssertGreaterThan(starData.length, (NSUInteger)0);

    STARReader *reader = [STARReader readFromData:starData error:&err];
    XCTAssertNotNil(reader, @"Reader failed on empty tree: %@", err);
    XCTAssertNil(err);
    XCTAssertNil(reader.rootCID, @"Empty tree must have nil rootCID");
    XCTAssertEqual(reader.blocks.count, (NSUInteger)0,
        @"Empty tree must produce zero blocks");
}

/// Malformed: trailing bytes after the tree completes must be rejected.
- (void)testSTARL0ReaderRejectsTrailingBytes {
    MST *tree = [self buildSmallDeterministicFixture];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // Append 4 garbage bytes
    NSMutableData *malformed = [starData mutableCopy];
    uint8_t garbage[] = {0xFF, 0xFF, 0xFF, 0xFF};
    [malformed appendBytes:garbage length:4];

    STARReader *reader = [STARReader readFromData:malformed error:&err];
    XCTAssertNil(reader, @"Reader must reject trailing bytes");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 32, @"Expected error 32 (failed to read block length from 0xFF varint), got %ld", (long)err.code);
}

/// Malformed: truncated block length varint must be rejected.
- (void)testSTARL0ReaderRejectsTruncatedBlock {
    MST *tree = [self buildSmallDeterministicFixture];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc] initWithCommit:commit];
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

    STARReader *reader = [STARReader readFromData:truncated error:&err];
    XCTAssertNil(reader, @"Reader must reject truncated body");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 31, @"Expected error 31 (truncated stream), got %ld", (long)err.code);
}

/// Full STAR -> CAR conversion round trip.
- (void)testSTARL0STARToCARConversion {
    MST *tree = [self buildSmallDeterministicFixture];
    STARCommit *commit = [self buildCommitForRoot:tree.rootCID];
    STARL0Writer *w = [[STARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // Convert STAR to CAR
    NSData *carData = [STARConverter carDataFromSTARData:starData error:&err];
    XCTAssertNotNil(carData, @"STAR->CAR conversion failed: %@", err);
    XCTAssertNil(err);

    // Parse the CAR
    CARReader *carReader = [CARReader readFromData:carData error:&err];
    XCTAssertNotNil(carReader, @"CAR parse failed: %@", err);
    XCTAssertNil(err);

    // CAR root must be the commit CID, not the MST root
    XCTAssertNotNil(carReader.rootCID);
    XCTAssertNotEqualObjects(carReader.rootCID, tree.rootCID,
        @"CAR root must be commit CID, not MST root CID");

    // Must contain a commit block (with did key)
    CARBlock *commitBlock = [carReader blockWithCID:carReader.rootCID];
    XCTAssertNotNil(commitBlock, @"CAR must contain commit block");
    CBORValue *commitVal = [CBORValue decode:commitBlock.data];
    XCTAssertNotNil(commitVal);
    XCTAssertNotNil(commitVal.map[[CBORValue textString:@"did"]]);

    // Must contain at least the same number of blocks as the STAR reader produced
    STARReader *starReader = [STARReader readFromData:starData error:&err];
    XCTAssertNotNil(starReader);
    // CAR has 1 extra block (the commit) beyond what STAR reader produces
    XCTAssertGreaterThanOrEqual(carReader.blocks.count, starReader.blocks.count + 1,
        @"CAR must contain commit + all STAR blocks");
}

/// Sig-less STAR must be rejected by the CAR converter.
- (void)testSTARL0CARConversionRejectsSigmlessArchive {
    MST *tree = [self buildSmallDeterministicFixture];
    STARCommit *commit = [STARCommit commitWithDid:@"did:plc:nosig"
                                           version:3
                                             data:tree.rootCID
                                              rev:@"3jzfcijpj2z2z"
                                             prev:nil
                                              sig:nil];
    STARL0Writer *w = [[STARL0Writer alloc] initWithCommit:commit];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starData = [w serialize];

    // STAR reader should still parse it (verifying reader only checks CIDs, sig is for CAR conversion)
    STARReader *reader = [STARReader readFromData:starData error:&err];
    XCTAssertNotNil(reader, @"Reader must accept sig-less STAR for verification");

    // But CAR conversion must reject
    NSData *carData = [STARConverter carDataFromSTARData:starData error:&err];
    XCTAssertNil(carData, @"CAR conversion must reject sig-less STAR");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 21, @"Expected error 21 (no signature), got %ld", (long)err.code);
}

#pragma mark - STAR-Lite (separate format)

- (void)testSTARLiteHasNoMSTNodesAndUsesVersionTwo {
    MST *tree = [self buildSmallDeterministicFixture];
    STARLiteWriter *w = [[STARLiteWriter alloc]
        initWithCommit:[self buildCommitForRoot:tree.rootCID]];
    NSError *err = nil;
    XCTAssertTrue([w writeFromMST:tree
                    blockProvider:[self recordProviderForTree:tree]
                            error:&err]);
    NSData *starLite = [w serialize];
    XCTAssertGreaterThan(starLite.length, (NSUInteger)0);

    // STAR-Lite magic is the same byte (0x2A) but version varint is 2.
    XCTAssertEqual(((const uint8_t *)starLite.bytes)[0], (uint8_t)0x2A);

    // Round-trip: STARReader reports STARVariantLite and contains only record
    // blocks (no MST nodes, because Lite is a flat key-record format that does
    // NOT follow the Sync 1.1 depth-first + record-interleaved layout; it
    // drains [mst allEntries] in key order).
    STARReader *reader = [STARReader readFromData:starLite error:&err];
    XCTAssertNil(err);
    XCTAssertEqual(reader.variant, STARVariantLite);
    NSUInteger nodes = 0;
    NSUInteger records = 0;
    for (CARBlock *block in reader.blocks) {
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
