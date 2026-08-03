// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoBDASLVerifierTests.m

 @abstract Tests the bounded BDASL streaming verifier and range mapping.
 */

#import <XCTest/XCTest.h>
#import "Core/ATProtoBDASLVerifier.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#include "Security/Space/Vendor/BLAKE3/blake3.h"

@interface ATProtoBDASLVerifierTests : XCTestCase
@end

@implementation ATProtoBDASLVerifierTests

- (NSData *)blake3DigestForData:(NSData *)data {
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, data.bytes, data.length);
    uint8_t digest[BLAKE3_OUT_LEN];
    blake3_hasher_finalize(&hasher, digest, sizeof(digest));
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

- (CID *)blake3CIDForData:(NSData *)data {
    NSMutableData *bytes = [NSMutableData dataWithCapacity:36];
    uint8_t prefix[] = {0x01, ATProtoDASLCodecRaw, ATProtoDASLMultihashBLAKE3, 0x20};
    [bytes appendBytes:prefix length:sizeof(prefix)];
    [bytes appendData:[self blake3DigestForData:data]];
    return [CID daslCIDFromBytes:bytes profile:ATProtoDASLCIDProfileBig];
}

- (NSArray<NSData *> *)chunkDigestsForData:(NSData *)data {
    NSMutableArray<NSData *> *digests = [NSMutableArray array];
    NSUInteger offset = 0;
    if (data.length == 0) {
        [digests addObject:[self blake3DigestForData:data]];
        return digests;
    }
    while (offset < data.length) {
        NSUInteger length = MIN(ATProtoBDASLChunkSize, data.length - offset);
        NSData *chunk = [data subdataWithRange:NSMakeRange(offset, length)];
        [digests addObject:[self blake3DigestForData:chunk]];
        offset += length;
    }
    return digests;
}

- (NSData *)payload {
    NSMutableData *data = [NSMutableData dataWithLength:ATProtoBDASLChunkSize * 2 + 137];
    uint8_t *bytes = data.mutableBytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        bytes[i] = (uint8_t)((i * 31 + 7) & 0xff);
    }
    return data;
}

- (void)testIncrementalVerificationAcceptsSplitInput {
    NSData *payload = [self payload];
    CID *cid = [self blake3CIDForData:payload];
    NSError *error = nil;
    ATProtoBDASLVerifier *verifier = [[ATProtoBDASLVerifier alloc]
        initWithCID:cid
        chunkDigests:[self chunkDigestsForData:payload]
        totalLength:payload.length
        error:&error];
    XCTAssertNotNil(verifier);
    XCTAssertNil(error);

    XCTAssertTrue([verifier appendData:[payload subdataWithRange:NSMakeRange(0, 333)] error:&error]);
    XCTAssertTrue([verifier appendData:[payload subdataWithRange:NSMakeRange(333, 1700)] error:&error]);
    XCTAssertTrue([verifier appendData:[payload subdataWithRange:NSMakeRange(2033, payload.length - 2033)] error:&error]);
    XCTAssertTrue([verifier finalizeWithError:&error], @"%@", error);
    XCTAssertTrue(verifier.isVerified);
    XCTAssertEqual(verifier.bytesReceived, payload.length);
    XCTAssertEqual(verifier.verifiedChunkCount, 3u);
}

- (void)testCorruptedChunkFailsBeforeFinalize {
    NSData *payload = [self payload];
    CID *cid = [self blake3CIDForData:payload];
    NSMutableArray<NSData *> *digests = [[self chunkDigestsForData:payload] mutableCopy];
    NSMutableData *wrong = [digests[1] mutableCopy];
    uint8_t *wrongBytes = wrong.mutableBytes;
    wrongBytes[0] ^= 0xff;
    digests[1] = wrong;

    NSError *error = nil;
    ATProtoBDASLVerifier *verifier = [[ATProtoBDASLVerifier alloc]
        initWithCID:cid chunkDigests:digests totalLength:payload.length error:&error];
    XCTAssertNotNil(verifier);
    XCTAssertTrue([verifier appendData:payload error:&error] == NO);
    XCTAssertEqual(error.code, ATProtoBDASLVerifierErrorChunkMismatch);
    XCTAssertEqual(verifier.verifiedChunkCount, 1u);
}

- (void)testPayloadCorruptionInFinalShortChunkFailsDuringAppend {
    NSData *originalPayload = [self payload];
    NSMutableData *corruptedPayload = [originalPayload mutableCopy];
    ((uint8_t *)corruptedPayload.mutableBytes)[corruptedPayload.length - 1] ^= 0x80;
    CID *cid = [self blake3CIDForData:originalPayload];
    NSError *error = nil;
    ATProtoBDASLVerifier *verifier = [[ATProtoBDASLVerifier alloc]
        initWithCID:cid
        chunkDigests:[self chunkDigestsForData:originalPayload]
        totalLength:originalPayload.length
        error:&error];
    XCTAssertNotNil(verifier);
    XCTAssertFalse([verifier appendData:corruptedPayload error:&error]);
    XCTAssertEqual(error.code, ATProtoBDASLVerifierErrorChunkMismatch);
    XCTAssertEqual(verifier.verifiedChunkCount, 2u);
    XCTAssertFalse(verifier.isVerified);
    XCTAssertFalse([verifier finalizeWithError:&error]);
}

- (void)testTruncatedStreamFailsClosed {
    NSData *payload = [self payload];
    CID *cid = [self blake3CIDForData:payload];
    NSError *error = nil;
    ATProtoBDASLVerifier *verifier = [[ATProtoBDASLVerifier alloc]
        initWithCID:cid
        chunkDigests:[self chunkDigestsForData:payload]
        totalLength:payload.length
        error:&error];
    XCTAssertTrue([verifier appendData:[payload subdataWithRange:NSMakeRange(0, payload.length - 1)] error:&error]);
    XCTAssertFalse([verifier finalizeWithError:&error]);
    XCTAssertEqual(error.code, ATProtoBDASLVerifierErrorIncomplete);
    XCTAssertFalse(verifier.isVerified);
}

- (void)testRootMismatchIsRejectedEvenWithMatchingChunkSidecar {
    NSData *payload = [self payload];
    NSMutableData *differentPayload = [payload mutableCopy];
    ((uint8_t *)differentPayload.mutableBytes)[differentPayload.length - 1] ^= 0x01;
    CID *wrongCID = [self blake3CIDForData:differentPayload];
    NSError *error = nil;
    ATProtoBDASLVerifier *verifier = [[ATProtoBDASLVerifier alloc]
        initWithCID:wrongCID
        chunkDigests:[self chunkDigestsForData:payload]
        totalLength:payload.length
        error:&error];
    XCTAssertTrue([verifier appendData:payload error:&error]);
    XCTAssertFalse([verifier finalizeWithError:&error]);
    XCTAssertEqual(error.code, ATProtoBDASLVerifierErrorRootMismatch);
}

- (void)testEmptyPayloadVerifies {
    NSData *payload = [NSData data];
    CID *cid = [self blake3CIDForData:payload];
    NSError *error = nil;
    ATProtoBDASLVerifier *verifier = [[ATProtoBDASLVerifier alloc]
        initWithCID:cid chunkDigests:[self chunkDigestsForData:payload]
        totalLength:0 error:&error];
    XCTAssertTrue([verifier finalizeWithError:&error], @"%@", error);
    XCTAssertTrue(verifier.isVerified);
    XCTAssertEqual(verifier.verifiedChunkCount, 1u);
}

- (void)testRangeMapsToContainingChunks {
    NSUInteger first = 0;
    NSUInteger last = 0;
    NSError *error = nil;
    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:900
                                                  hasStart:YES
                                                       end:1299
                                                    hasEnd:YES
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 0u);
    XCTAssertEqual(last, 1u);
    XCTAssertNil(error);

    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:1024
                                                  hasStart:YES
                                                       end:1024
                                                    hasEnd:YES
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 1u);
    XCTAssertEqual(last, 1u);

    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:0
                                                  hasStart:YES
                                                       end:9999
                                                    hasEnd:YES
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 0u);
    XCTAssertEqual(last, 2u);

    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:0
                                                  hasStart:NO
                                                       end:0
                                                    hasEnd:NO
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 0u);
    XCTAssertEqual(last, 2u);

    // Exact chunk boundaries must not skip or duplicate a chunk.
    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:0
                                                  hasStart:YES
                                                       end:0
                                                    hasEnd:YES
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 0u);
    XCTAssertEqual(last, 0u);
    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:1023
                                                  hasStart:YES
                                                       end:1023
                                                    hasEnd:YES
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 0u);
    XCTAssertEqual(last, 0u);
    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:1025
                                                  hasStart:YES
                                                       end:1025
                                                    hasEnd:YES
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 1u);
    XCTAssertEqual(last, 1u);

    // Open-ended bounds are represented explicitly by hasStart/hasEnd.
    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:1024
                                                  hasStart:YES
                                                       end:0
                                                    hasEnd:NO
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 1u);
    XCTAssertEqual(last, 2u);
    XCTAssertTrue([ATProtoBDASLVerifier chunkRangeForStart:0
                                                  hasStart:NO
                                                       end:1023
                                                    hasEnd:YES
                                               totalLength:3000
                                                firstChunk:&first
                                                 lastChunk:&last
                                                     error:&error]);
    XCTAssertEqual(first, 0u);
    XCTAssertEqual(last, 0u);

    // A reversed range is invalid even when both endpoints are in bounds.
    XCTAssertFalse([ATProtoBDASLVerifier chunkRangeForStart:500
                                                   hasStart:YES
                                                        end:100
                                                     hasEnd:YES
                                                totalLength:3000
                                                 firstChunk:&first
                                                  lastChunk:&last
                                                      error:&error]);
    XCTAssertEqual(error.code, ATProtoBDASLVerifierErrorInvalidRange);

    XCTAssertFalse([ATProtoBDASLVerifier chunkRangeForStart:3000
                                                   hasStart:YES
                                                        end:3000
                                                     hasEnd:YES
                                                totalLength:3000
                                                 firstChunk:&first
                                                  lastChunk:&last
                                                      error:&error]);
    XCTAssertEqual(error.code, ATProtoBDASLVerifierErrorInvalidRange);
}

@end
