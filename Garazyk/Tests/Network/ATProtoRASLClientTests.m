// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRASLClientTests.m

 @abstract Tests the fail-closed paths and bounded BDASL range integration of
 `ATProtoRASLClient` without requiring a live network fixture.

 @discussion The range fixture supplies exact bodies while deliberately
 returning incorrect Content-Range and Content-Length metadata. This proves
 the client uses its request bounds and caller-supplied digests rather than
 server metadata. Live HTTPS/SSRF evidence remains a GNUstep/Docker gate.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "Core/ATProtoRASLURL.h"
#import "Core/ATProtoBDASLVerifier.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Network/ATProtoRASLClient.h"
#include "Security/Space/Vendor/BLAKE3/blake3.h"

@interface ATProtoRASLRangeFixture : NSObject <ATProtoRASLHTTPFetching>
@property (nonatomic, copy) NSData *payload;
@property (nonatomic, assign) NSUInteger corruptedChunk;
@property (nonatomic, strong) NSMutableArray<NSString *> *ranges;
@end

@implementation ATProtoRASLRangeFixture

- (instancetype)init {
    self = [super init];
    if (self) {
        _ranges = [NSMutableArray array];
        _corruptedChunk = NSUIntegerMax;
    }
    return self;
}

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(ATProtoSafeHTTPClientOptions *)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    NSString *range = [request valueForHTTPHeaderField:@"Range"];
    [self.ranges addObject:range ?: @"missing"];
    if (![range hasPrefix:@"bytes="]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoRASLRangeFixture"
                                                  code:1
                                              userInfo:@{NSLocalizedDescriptionKey: @"Range header missing"}];
        return nil;
    }
    NSArray<NSString *> *bounds = [[range substringFromIndex:6] componentsSeparatedByString:@"-"];
    if (bounds.count != 2) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoRASLRangeFixture"
                                                  code:2
                                              userInfo:@{NSLocalizedDescriptionKey: @"Range header malformed"}];
        return nil;
    }
    NSUInteger start = (NSUInteger)bounds[0].longLongValue;
    NSUInteger end = (NSUInteger)bounds[1].longLongValue;
    if (start > end || end >= self.payload.length) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoRASLRangeFixture"
                                                  code:3
                                              userInfo:@{NSLocalizedDescriptionKey: @"Range out of bounds"}];
        return nil;
    }

    NSMutableData *body = [[self.payload subdataWithRange:NSMakeRange(start, end - start + 1)] mutableCopy];
    NSUInteger chunk = start / ATProtoBDASLChunkSize;
    if (chunk == self.corruptedChunk && body.length > 0) {
        ((uint8_t *)body.mutableBytes)[0] ^= 0x80;
    }
    if (response) {
        // Deliberately wrong metadata proves the client uses its request bounds
        // and verified body bytes, not server-provided range or length values.
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:206
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:@{
            @"Content-Range": @"bytes 9000-9000/1",
            @"Content-Length": @"1"
        }];
    }
    return body;
}

@end

@interface ATProtoRASLClientTests : XCTestCase
@end

@implementation ATProtoRASLClientTests

- (NSData *)bytesForDigest:(NSData *)digest hashCode:(uint8_t)hashCode codec:(uint8_t)codec {
    NSMutableData *bytes = [NSMutableData data];
    uint8_t version = 0x01;
    uint8_t length = 0x20;
    [bytes appendBytes:&version length:1];
    [bytes appendBytes:&codec length:1];
    [bytes appendBytes:&hashCode length:1];
    [bytes appendBytes:&length length:1];
    [bytes appendData:digest];
    return bytes;
}

- (NSData *)blake3DigestForData:(NSData *)data {
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, data.bytes, data.length);
    uint8_t digest[BLAKE3_OUT_LEN];
    blake3_hasher_finalize(&hasher, digest, sizeof(digest));
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

- (ATProtoCID *)blake3CIDForData:(NSData *)data {
    return [ATProtoCID daslCIDFromBytes:[self bytesForDigest:[self blake3DigestForData:data]
                                                       hashCode:ATProtoDASLMultihashBLAKE3
                                                          codec:ATProtoDASLCodecRaw]
                                  profile:ATProtoDASLCIDProfileBig];
}

- (NSArray<NSData *> *)chunkDigestsForData:(NSData *)data {
    NSMutableArray<NSData *> *digests = [NSMutableArray array];
    for (NSUInteger offset = 0; offset < data.length; offset += ATProtoBDASLChunkSize) {
        NSUInteger length = MIN(ATProtoBDASLChunkSize, data.length - offset);
        [digests addObject:[self blake3DigestForData:[data subdataWithRange:NSMakeRange(offset, length)]]];
    }
    return digests;
}

- (void)testNoHintsFailsImmediatelyWithoutNetwork {
    NSData *digest = [ATProtoCID sha256Digest:[@"no-hints" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid = [ATProtoCID daslCIDFromBytes:[self bytesForDigest:digest hashCode:0x12 codec:0x55]
                              profile:ATProtoDASLCIDProfileBase];
    XCTAssertNotNil(cid);
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/", cid.stringValue];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    XCTAssertNotNil(url);
    XCTAssertEqual(url.hints.count, 0u);

    XCTestExpectation *expectation = [self expectationWithDescription:@"no-hints completion"];
    [[ATProtoRASLClient sharedClient] fetchDataForRASLURL:url
                                          maxResponseBytes:1024
                                                    timeout:1.0
                                                 completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        XCTAssertNil(data);
        XCTAssertEqualObjects(error.domain, ATProtoRASLClientErrorDomain);
        XCTAssertEqual(error.code, ATProtoRASLClientErrorNoHints);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testBlake3CIDFailsClosedWithoutNetwork {
    NSData *digest = [ATProtoCID sha256Digest:[@"blake3" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid = [ATProtoCID daslCIDFromBytes:[self bytesForDigest:digest hashCode:ATProtoDASLMultihashBLAKE3 codec:0x55]
                              profile:ATProtoDASLCIDProfileBig];
    XCTAssertNotNil(cid, @"test fixture setup must itself produce a conformant Big DASL CID");
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?hint=example.com", cid.stringValue];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    XCTAssertNotNil(url);
    XCTAssertEqual(url.hints.count, 1u, @"the hint must parse so the failure below is provably about the hash algorithm, not a hint problem");

    XCTestExpectation *expectation = [self expectationWithDescription:@"blake3 completion"];
    [[ATProtoRASLClient sharedClient] fetchDataForRASLURL:url
                                          maxResponseBytes:1024
                                                    timeout:1.0
                                                 completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        XCTAssertNil(data, @"must never return unverified data");
        XCTAssertEqualObjects(error.domain, ATProtoRASLClientErrorDomain);
        XCTAssertEqual(error.code, ATProtoRASLClientErrorUnsupportedHashAlgorithm);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testBDASLRangeDownloadVerifiesChunksAndIgnoresResponseMetadata {
    NSMutableData *payload = [NSMutableData dataWithLength:ATProtoBDASLChunkSize * 2 + 137];
    uint8_t *bytes = payload.mutableBytes;
    for (NSUInteger i = 0; i < payload.length; i++) {
        bytes[i] = (uint8_t)((i * 17 + 3) & 0xff);
    }
    ATProtoCID *cid = [self blake3CIDForData:payload];
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?hint=example.com", cid.stringValue];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    ATProtoRASLRangeFixture *fixture = [[ATProtoRASLRangeFixture alloc] init];
    fixture.payload = payload;
    ATProtoRASLClient *client = [[ATProtoRASLClient alloc] initWithHTTPClient:fixture];

    XCTestExpectation *expectation = [self expectationWithDescription:@"BDASL range completion"];
    [client fetchBDASLDataForRASLURL:url
                        chunkDigests:[self chunkDigestsForData:payload]
                         totalLength:payload.length
                     maxResponseBytes:ATProtoBDASLChunkSize
                               timeout:1.0
                            completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        XCTAssertNil(error, @"%@", error);
        XCTAssertEqualObjects(data, payload);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqualObjects(fixture.ranges, (@[
        @"bytes=0-1023", @"bytes=1024-2047", @"bytes=2048-2184"
    ]));
}

- (void)testBDASLRangeDownloadRejectsCorruptedChunk {
    NSData *payload = [self blake3DigestForData:[@"payload" dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableData *largePayload = [NSMutableData dataWithLength:ATProtoBDASLChunkSize + 17];
    memcpy(largePayload.mutableBytes, payload.bytes, MIN(payload.length, largePayload.length));
    ATProtoCID *cid = [self blake3CIDForData:largePayload];
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?hint=example.com", cid.stringValue];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    ATProtoRASLRangeFixture *fixture = [[ATProtoRASLRangeFixture alloc] init];
    fixture.payload = largePayload;
    fixture.corruptedChunk = 1;
    ATProtoRASLClient *client = [[ATProtoRASLClient alloc] initWithHTTPClient:fixture];

    XCTestExpectation *expectation = [self expectationWithDescription:@"BDASL corruption completion"];
    [client fetchBDASLDataForRASLURL:url
                        chunkDigests:[self chunkDigestsForData:largePayload]
                         totalLength:largePayload.length
                     maxResponseBytes:ATProtoBDASLChunkSize
                               timeout:1.0
                            completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        XCTAssertNil(data);
        XCTAssertEqualObjects(error.domain, ATProtoRASLClientErrorDomain);
        XCTAssertEqual(error.code, ATProtoRASLClientErrorBDASLRangeFailed);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

@end
