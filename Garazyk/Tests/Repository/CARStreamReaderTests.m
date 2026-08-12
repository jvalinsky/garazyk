// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/CAR.h"
#import "Core/CID.h"

@interface CARStreamReaderTests : XCTestCase
@end

@implementation CARStreamReaderTests

// Builds a CAR whose body contains the root block plus `count` payload
// blocks. Strict readers require every declared root to appear in the body,
// so the root is included explicitly.
static NSData *CARWithBlocks(NSUInteger count, ATProtoCID **outRootCID,
                             NSArray<ATProtoCARBlock *> **outBlocks) {
    NSData *rootData = [@"root-block" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *rootCID = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:rootData] codec:0x71];
    ATProtoCARWriter *writer = [ATProtoCARWriter writerWithRootCID:rootCID];
    [writer addBlock:[ATProtoCARBlock blockWithCID:rootCID data:rootData]];

    NSMutableArray<ATProtoCARBlock *> *blocks = [NSMutableArray array];
    [blocks addObject:[ATProtoCARBlock blockWithCID:rootCID data:rootData]];
    for (NSUInteger i = 0; i < count; i++) {
        NSString *payload = [NSString stringWithFormat:@"block-payload-%lu", (unsigned long)i];
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        ATProtoCID *cid = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:data] codec:0x71];
        ATProtoCARBlock *block = [ATProtoCARBlock blockWithCID:cid data:data];
        [writer addBlock:block];
        [blocks addObject:block];
    }

    if (outRootCID) *outRootCID = rootCID;
    if (outBlocks) *outBlocks = blocks;
    return [writer serialize];
}

- (void)testStreamReaderRoundTripsAllBlocksInStrictMode {
    ATProtoCID *rootCID = nil;
    NSArray<ATProtoCARBlock *> *expectedBlocks = nil;
    NSData *carData = CARWithBlocks(5, &rootCID, &expectedBlocks);

    NSError *error = nil;
    ATProtoCARStreamReader *reader = [[ATProtoCARStreamReader alloc] initWithData:carData strict:YES error:&error];
    XCTAssertNotNil(reader, @"%@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects(reader.rootCID, rootCID);

    NSMutableArray<ATProtoCARBlock *> *streamed = [NSMutableArray array];
    BOOL ok = [reader enumerateBlocksWithError:&error handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        [streamed addObject:block];
        return YES;
    }];
    XCTAssertTrue(ok, @"%@", error);
    XCTAssertNil(error);
    XCTAssertTrue(reader.isFinished);
    XCTAssertEqual(streamed.count, expectedBlocks.count);

    for (NSUInteger i = 0; i < expectedBlocks.count; i++) {
        XCTAssertEqualObjects(streamed[i].cid, expectedBlocks[i].cid);
        XCTAssertEqualObjects(streamed[i].data, expectedBlocks[i].data);
    }
}

- (void)testStreamReaderBuildsBlockIndexForSeenBlocks {
    ATProtoCID *rootCID = nil;
    NSArray<ATProtoCARBlock *> *blocks = nil;
    NSData *carData = CARWithBlocks(3, &rootCID, &blocks);

    NSError *error = nil;
    ATProtoCARStreamReader *reader = [[ATProtoCARStreamReader alloc] initWithData:carData strict:YES error:&error];
    XCTAssertNotNil(reader);

    // Not yet streamed: lookup must return nil.
    XCTAssertNil([reader blockWithCID:blocks[1].cid]);

    NSError *streamError = nil;
    BOOL ok = [reader enumerateBlocksWithError:&streamError handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        return YES;
    }];
    XCTAssertTrue(ok, @"%@", streamError);

    for (ATProtoCARBlock *block in blocks) {
        ATProtoCARBlock *found = [reader blockWithCID:block.cid];
        XCTAssertNotNil(found);
        XCTAssertEqualObjects(found.data, block.data);
    }
    XCTAssertNil([reader blockWithCID:[ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:[@"absent" dataUsingEncoding:NSUTF8StringEncoding]] codec:0x71]]);
}

- (void)testStreamReaderResetRewindsStream {
    NSData *carData = CARWithBlocks(4, NULL, NULL);

    NSError *error = nil;
    ATProtoCARStreamReader *reader = [[ATProtoCARStreamReader alloc] initWithData:carData strict:YES error:&error];
    XCTAssertNotNil(reader);

    __block NSUInteger firstPass = 0;
    BOOL ok = [reader enumerateBlocksWithError:&error handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        firstPass++;
        return YES;
    }];
    XCTAssertTrue(ok, @"%@", error);
    XCTAssertEqual(firstPass, 5); // root + 4 payload blocks

    [reader reset];
    XCTAssertFalse(reader.isFinished);

    __block NSUInteger secondPass = 0;
    ok = [reader enumerateBlocksWithError:&error handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        secondPass++;
        return YES;
    }];
    XCTAssertTrue(ok, @"%@", error);
    XCTAssertEqual(secondPass, 5);
}

- (void)testStreamReaderStrictModeRejectsTamperedBlock {
    ATProtoCID *rootCID = nil;
    NSData *carData = CARWithBlocks(2, &rootCID, NULL);

    // Corrupt the final byte of the archive (inside the last block's payload).
    NSMutableData *tampered = [carData mutableCopy];
    uint8_t *bytes = tampered.mutableBytes;
    bytes[tampered.length - 1] ^= 0xFF;

    NSError *error = nil;
    ATProtoCARStreamReader *strictReader = [[ATProtoCARStreamReader alloc] initWithData:tampered strict:YES error:&error];
    XCTAssertNotNil(strictReader, @"Header must still parse: %@", error);

    NSError *streamError = nil;
    __block NSUInteger delivered = 0;
    BOOL ok = [strictReader enumerateBlocksWithError:&streamError handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        delivered++;
        return YES;
    }];
    XCTAssertFalse(ok, @"Strict mode must reject a block whose CID does not match its payload");
    XCTAssertNotNil(streamError);

    // The same bytes are accepted without verification in non-strict mode.
    error = nil;
    ATProtoCARStreamReader *lenientReader = [[ATProtoCARStreamReader alloc] initWithData:tampered strict:NO error:&error];
    XCTAssertNotNil(lenientReader);
    NSError *lenientError = nil;
    __block NSUInteger lenientDelivered = 0;
    BOOL lenientOk = [lenientReader enumerateBlocksWithError:&lenientError handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        lenientDelivered++;
        return YES;
    }];
    XCTAssertTrue(lenientOk, @"%@", lenientError);
    XCTAssertGreaterThan(lenientDelivered, 0);
}

- (void)testStreamReaderStrictModeRequiresRootInBody {
    // Build a CAR whose declared root is NOT among the body blocks — a strict
    // reader must fail at exhaustion; a lenient reader must not.
    NSData *rootData = [@"declared-but-absent-root" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *rootCID = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:rootData] codec:0x71];
    ATProtoCARWriter *writer = [ATProtoCARWriter writerWithRootCID:rootCID];

    NSData *payload = [@"orphan-block" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *payloadCID = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:payload] codec:0x71];
    [writer addBlock:[ATProtoCARBlock blockWithCID:payloadCID data:payload]];

    NSData *carData = [writer serialize];

    NSError *error = nil;
    ATProtoCARStreamReader *strictReader = [[ATProtoCARStreamReader alloc] initWithData:carData strict:YES error:&error];
    XCTAssertNotNil(strictReader);

    NSError *streamError = nil;
    BOOL ok = [strictReader enumerateBlocksWithError:&streamError handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        return YES;
    }];
    XCTAssertFalse(ok, @"Strict mode must reject a CAR whose declared root is missing from the body");
    XCTAssertNotNil(streamError);

    error = nil;
    ATProtoCARStreamReader *lenientReader = [[ATProtoCARStreamReader alloc] initWithData:carData strict:NO error:&error];
    XCTAssertNotNil(lenientReader);
    NSError *lenientError = nil;
    BOOL lenientOk = [lenientReader enumerateBlocksWithError:&lenientError handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        return YES;
    }];
    XCTAssertTrue(lenientOk, @"%@", lenientError);
}

- (void)testStreamReaderHandlerStopIsNotAnError {
    NSData *carData = CARWithBlocks(10, NULL, NULL);

    NSError *error = nil;
    ATProtoCARStreamReader *reader = [[ATProtoCARStreamReader alloc] initWithData:carData strict:YES error:&error];
    XCTAssertNotNil(reader);

    NSError *streamError = nil;
    __block NSUInteger delivered = 0;
    BOOL ok = [reader enumerateBlocksWithError:&streamError handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        delivered++;
        return delivered < 2; // stop after two blocks
    }];
    XCTAssertTrue(ok, @"An early handler stop must not surface as an error: %@", streamError);
    XCTAssertNil(streamError);
    XCTAssertEqual(delivered, 2);
    XCTAssertFalse(reader.isFinished);
}

- (void)testStreamReaderRejectsMalformedCARHeader {
    NSData *garbage = [@"this is definitely not a car archive" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoCARStreamReader *reader = [[ATProtoCARStreamReader alloc] initWithData:garbage strict:YES error:&error];
    XCTAssertNil(reader);
    XCTAssertNotNil(error);
}

@end
