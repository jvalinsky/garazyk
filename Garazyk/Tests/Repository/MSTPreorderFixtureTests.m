// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"

/**
 * Sync 1.1 streamable-CAR byte-level regression test.
 *
 * Builds a deterministic eight-rkey MST (rkeys span depths 0, 1, and 2 so the
 * tree is genuinely multi-level), emits a CAR via the pre-order DFS walker
 * with record blocks interleaved, and asserts byte-equality with the
 * committed fixture at Tests/fixtures/mst/sync11-preorder-fixture.car.
 *
 * Regenerate the fixture when Sync 1.1 emitter behaviour drifts:
 *
 *     MST_REGENERATE_FIXTURE=1 \
 *         build/tests/AllTests MSTPreorderFixtureTests/testRegenerateFixtureConditional
 *
 * Setting MST_REGENERATE_FIXTURE also skips the byte-equality check (the
 * freshly-written fixture would tautologically match), so a CI regression
 * test always runs with the env var UNSET.
 */
@interface MSTPreorderFixtureTests : XCTestCase
@end

@interface MSTPreorderFixtureTests ()
// Save and restore the global streamable-CAR ordering flag on a per-instance
// basis so parallel xcodebuild test execution does not lose the saved value
// across interleaved setUp/tearDown pairs. The flag's storage is C11
// `atomic_bool`, so we mirror that type here for the saved value; the
// setter still accepts `BOOL` (cast at the call site below).
@property (nonatomic, assign) atomic_bool originalFlag;
@end

@implementation MSTPreorderFixtureTests

// Hand-picked rkeys spanning three distinct SHA-256 depths so the tree is
// multi-level (forces pre-order to walk into subtrees layer by layer).
// Depths verified against MST.m:keyDepthFromBytes at test design time.
//   - depth-0 entries: 3jzfcijpj2zek, 2zel, post/aaa, post/ccc, post/ddd
//   - depth-1 entries: post/bbb, test/key.005
//   - depth-2 entry:   3jzfcijpj2zep (forces a sub-tree level)
// Replacing any of these without re-running testFixtureKeysSpanMultipleDepths
// would silently flatten the regression coverage.
static NSArray<NSString *> *const kFixtureKeys = @[
    @"app.bsky.feed.post/3jzfcijpj2zek",  // depth 0
    @"app.bsky.feed.post/3jzfcijpj2zel",  // depth 0
    @"app.bsky.feed.post/3jzfcijpj2zep",  // depth 2 (subtree level)
    @"post/aaa",                          // depth 0
    @"post/bbb",                          // depth 1
    @"post/ccc",                          // depth 0
    @"post/ddd",                          // depth 0
    @"test/key.005",                      // depth 1
];

static NSString *const kFixtureFileName = @"sync11-preorder-fixture.car";

#pragma mark - Fixture builders

- (NSData *)fixtureRecordBytesForKey:(NSString *)key {
    NSString *payload = [@"sync1.1.fixture.record for " stringByAppendingString:key];
    return [payload dataUsingEncoding:NSUTF8StringEncoding];
}

- (CID *)fixtureValueCIDForKey:(NSString *)key {
    // Self-consistent: each record's CID is the SHA-256 of its own bytes,
    // so the MST's valueCID matches what the recordProvider returns.
    return [CID sha256:[self fixtureRecordBytesForKey:key]];
}

- (MST *)buildFixtureMST {
    MST *tree = [[MST alloc] init];
    for (NSString *key in kFixtureKeys) {
        [tree put:key valueCID:[self fixtureValueCIDForKey:key]];
    }
    return tree;
}

- (MSTBlockProvider)recordProviderForFixture {
    NSMutableDictionary<NSString *, NSData *> *cache = [NSMutableDictionary dictionary];
    for (NSString *key in kFixtureKeys) {
        CID *cid = [self fixtureValueCIDForKey:key];
        cache[cid.stringValue] = [self fixtureRecordBytesForKey:key];
    }
    return ^NSData *(CID *cid) {
        return cache[cid.stringValue];
    };
}

- (NSData *)buildFixtureCAR {
    MST *tree = [self buildFixtureMST];
    CID *rootCID = tree.rootCID;
    XCTAssertNotNil(rootCID, @"MST root CID must be deterministic");
    CARWriter *writer = [CARWriter writerWithRootCID:rootCID];
    MSTBlockProvider provider = [self recordProviderForFixture];

    NSError *err = nil;
    BOOL ok = [tree enumerateStreamableCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **e) {
        (void)e;
        [writer addBlock:[CARBlock blockWithCID:cid data:data]];
        return YES;
    } recordProvider:provider error:&err];

    XCTAssertTrue(ok, @"Pre-order enumeration failed: %@", err);
    return [writer serialize];
}

#pragma mark - Path resolution

/// Returns the first existing fixture directory (relative to cwd) suitable
/// for reading or writing the fixture file. If none exist, returns the
/// conventional "Garazyk/Tests/fixtures/mst" path so a regenerate-test
/// bootstrap can create it. Path-lookup strategy mirrors the fallback
/// convention used by MSTPersistenceTests.m.
- (NSString *)resolveFixtureBaseDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *relativeBases = @[
        @"Garazyk/Tests/fixtures/mst",
        @"Tests/fixtures/mst",
        @"fixtures/mst",
    ];

    for (NSString *base in relativeBases) {
        if ([fm fileExistsAtPath:base]) {
            return base;
        }
    }

    // Walk up from cwd looking for Tests/fixtures/mst.
    NSString *dir = fm.currentDirectoryPath;
    while ([dir length] > 1) {
        NSString *candidate = [dir stringByAppendingPathComponent:@"Tests/fixtures/mst"];
        if ([fm fileExistsAtPath:candidate]) {
            return candidate;
        }
        dir = [dir stringByDeletingLastPathComponent];
    }

    return relativeBases.firstObject;
}

/// Searches multiple candidate relative paths for an existing fixture file.
/// Returns nil if not found anywhere.
- (nullable NSString *)findFixtureReadPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *filename = kFixtureFileName;

    NSArray<NSString *> *relativeBases = @[
        @"Garazyk/Tests/fixtures/mst",
        @"Tests/fixtures/mst",
        @"fixtures/mst",
        @"../Garazyk/Tests/fixtures/mst",
        @"../../Garazyk/Tests/fixtures/mst",
        @"../../../Garazyk/Tests/fixtures/mst",
    ];

    for (NSString *base in relativeBases) {
        NSString *candidate = [base stringByAppendingPathComponent:filename];
        if ([fm fileExistsAtPath:candidate]) {
            return candidate;
        }
    }

    NSString *dir = fm.currentDirectoryPath;
    while ([dir length] > 1) {
        NSString *candidate = [[dir stringByAppendingPathComponent:@"Tests/fixtures/mst"]
                               stringByAppendingPathComponent:filename];
        if ([fm fileExistsAtPath:candidate]) {
            return candidate;
        }
        dir = [dir stringByDeletingLastPathComponent];
    }

    return nil;
}

#pragma mark - Helper: block classifier (debug-log only)

/// Returns the kind of a CAR block: "node" (MST node), "record" (DAG-CBOR),
/// "commit", "empty", or "other". Decodes the block's CBOR structure and
/// sniffs for the MST "e" (entries) key; a byte-only sniff (0xa0–0xbf)
/// cannot distinguish MST nodes from DAG-CBOR records because both
/// serialize as CBOR maps. Mirrors classifyChunk: in STARPreorderTests.m.
- (NSString *)classifyBlock:(NSData *)data {
    if (data.length == 0) {
        return @"empty";
    }
    CBORValue *value = [CBORValue decode:data];
    if (!value || value.type != CBORTypeMap) {
        return @"other";
    }
    NSDictionary<CBORValue *, CBORValue *> *map = value.map;
    if (map[[CBORValue textString:@"e"]]) {
        return @"node";
    }
    return @"record";
}

#pragma mark - Helper: project-root guard

/// Yes iff currentDirectoryPath is at or under a directory containing a
/// `Garazyk/Tests/fixtures/mst` subtree. The first ancestor with that subtree
/// is treated as the project root; cwd must be at or below it. Refuses
/// regen/fixture-writing in unrecognized cwds (e.g. /tmp).
- (BOOL)isProjectRootedCwd {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = fm.currentDirectoryPath;
    while ([dir length] > [@"/" length]) {
        NSString *candidate = [dir stringByAppendingPathComponent:@"Garazyk/Tests/fixtures/mst"];
        if ([fm fileExistsAtPath:candidate]) {
            return YES;
        }
        dir = [dir stringByDeletingLastPathComponent];
    }
    return NO;
}

#pragma mark - Setup / teardown

- (void)setUp {
    [super setUp];
    self.originalFlag = [MST streamableCARBlockOrderingEnabled];
    [MST setStreamableCARBlockOrderingEnabled:YES];
}

- (void)tearDown {
    [MST setStreamableCARBlockOrderingEnabled:(BOOL)self.originalFlag];
    [super tearDown];
}

#pragma mark - Tests

- (void)testFixtureCARMatchesByteForByte {
    if (getenv("MST_REGENERATE_FIXTURE")) {
        XCTSkip(@"MST_REGENERATE_FIXTURE is set; bootstrap mode. Unset for byte-equality regression check.");
    }

    NSString *path = [self findFixtureReadPath];
    XCTAssertNotNil(path,
                    @"Fixture '%@' not found under any candidate path. "
                    @"Run MSTPreorderFixtureTests/testRegenerateFixtureConditional "
                    @"with MST_REGENERATE_FIXTURE=1 to bootstrap.",
                    kFixtureFileName);

    NSData *expected = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(expected, @"Failed to load fixture at %@", path);

    NSData *actual = [self buildFixtureCAR];
    XCTAssertEqual(actual.length, expected.length,
                   @"CAR byte length diverged (expected=%lu actual=%lu)",
                   (unsigned long)expected.length, (unsigned long)actual.length);

    if (![actual isEqualToData:expected]) {
        NSUInteger minLen = MIN(actual.length, expected.length);
        for (NSUInteger i = 0; i < minLen; i++) {
            uint8_t a = ((const uint8_t *)actual.bytes)[i];
            uint8_t e = ((const uint8_t *)expected.bytes)[i];
            if (a != e) {
                XCTFail(@"CAR bytes diverge at offset %llu: expected=0x%02x actual=0x%02x",
                        (unsigned long long)i, e, a);
                return;
            }
        }
        XCTFail(@"CAR trailing-length differs after byte %llu "
                @"(expected ends at %llu, actual ends at %llu)",
                (unsigned long long)minLen,
                (unsigned long long)expected.length,
                (unsigned long long)actual.length);
    }
}

- (void)testFixtureIsDeterministicAcrossTwoRuns {
    // Sanity-check that two consecutive rebuilds are byte-identical. If this
    // fails, the byte-equality test would be meaningless (it could pass for
    // the wrong reason).
    NSData *firstRun = [self buildFixtureCAR];
    NSData *secondRun = [self buildFixtureCAR];
    XCTAssertTrue([firstRun isEqualToData:secondRun],
                  @"Two consecutive buildFixtureCAR calls produced different bytes; "
                  @"emission must be deterministic.");
}

- (void)testRegenerateFixtureConditional {
    if (!getenv("MST_REGENERATE_FIXTURE")) {
        XCTSkip(@"Set MST_REGENERATE_FIXTURE=1 to regenerate the fixture file.");
    }
    if (![self isProjectRootedCwd]) {
        XCTFail(@"cwd does not live under a directory that contains Garazyk/Tests/fixtures/mst. "
                @"Refusing to write fixture to avoid polluting an unrelated cwd. "
                @"cd to the project root (or any descendant) and retry.");
        return;
    }

    NSData *bytes = [self buildFixtureCAR];
    NSString *baseDir = [self resolveFixtureBaseDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:baseDir]) {
        [fm createDirectoryAtPath:baseDir
     withIntermediateDirectories:YES
                      attributes:nil
                           error:nil];
    }
    NSString *outPath = [baseDir stringByAppendingPathComponent:kFixtureFileName];
    NSError *err = nil;
    BOOL ok = [bytes writeToFile:outPath options:NSDataWritingAtomic error:&err];
    XCTAssertTrue(ok, @"Failed to write fixture to %@: %@", outPath, err);
    NSLog(@"[MSTPreorderFixtureTests] Regenerated fixture: %@ (%lu bytes)",
          outPath, (unsigned long)bytes.length);
}

- (void)testFixtureEmitsDebugSequence {
    // Debug-only: NSLogs the pre-order walk sequence on a labeled channel so a
    // future byte-equality regression has visible walk context at the xctest
    // log. CI stays quiet — set MST_FIXTURE_DEBUG=1 to enable locally.
    if (!getenv("MST_FIXTURE_DEBUG")) {
        XCTSkip(@"Set MST_FIXTURE_DEBUG=1 to print the pre-order walk sequence.");
    }
    MST *tree = [self buildFixtureMST];
    MSTBlockProvider provider = [self recordProviderForFixture];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSError *err = nil;
    BOOL ok = [tree enumerateStreamableCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **e) {
        (void)e;
        NSString *kind = [self classifyBlock:data];
        [labels addObject:[NSString stringWithFormat:@"%@(%@)", kind, cid.stringValue ?: @""]];
        return YES;
    } recordProvider:provider error:&err];
    XCTAssertTrue(ok, @"Pre-order walker failed: %@", err);
    NSLog(@"[MSTPreorderFixtureTests][FIXTURE] === Sync 1.1 streamable CAR (8-rkey multi-level fixture) ===");
    NSLog(@"[MSTPreorderFixtureTests][FIXTURE] rootCID=%@", tree.rootCID.stringValue);
    for (NSUInteger i = 0; i < labels.count; i++) {
        NSLog(@"[MSTPreorderFixtureTests][FIXTURE]   %3lu. %@", (unsigned long)(i + 1), labels[i]);
    }
    NSLog(@"[MSTPreorderFixtureTests][FIXTURE] =================================================");
}

- (void)testFixtureKeysSpanMultipleDepths {
    // Uses the canonical [MST keyDepthString:] API so depth parity with the
    // MST's own algorithm is automatic. Span must be exactly {0, 1, 2}; any
    // future maintainer editing kFixtureKeys must preserve this or the
    // regression coverage degrades.
    NSMutableSet<NSNumber *> *depths = [NSMutableSet set];
    for (NSString *key in kFixtureKeys) {
        NSUInteger d = [MST keyDepthString:key];
        [depths addObject:@(d)];
    }
    XCTAssertTrue([depths containsObject:@(0)],
                  @"Fixture must include at least one depth-0 rkey (shallow leaves)");
    XCTAssertTrue([depths containsObject:@(1)],
                  @"Fixture must include at least one depth-1 rkey (forces multi-level)");
    XCTAssertTrue([depths containsObject:@(2)],
                  @"Fixture must include at least one depth-2 rkey (forces subtrees)");
    XCTAssertEqual(depths.count, (NSUInteger)3,
                   @"Fixture must span exactly three distinct depths; got %@",
                   [[depths allObjects] sortedArrayUsingSelector:@selector(compare:)]);
}

@end
