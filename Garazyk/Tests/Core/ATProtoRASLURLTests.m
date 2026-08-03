// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRASLURLTests.m

 @abstract Tests the `rasl://` URL parser against https://dasl.ing/rasl.html.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "Core/ATProtoRASLURL.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoRASLURLTests : XCTestCase
@property (nonatomic, strong) CID *sampleCID;
@property (nonatomic, copy) NSString *sampleCIDString;
@end

@implementation ATProtoRASLURLTests

- (void)setUp {
    [super setUp];
    NSData *digest = [CID sha256Digest:[@"rasl-url-tests" dataUsingEncoding:NSUTF8StringEncoding]];
    self.sampleCID = [CID daslCIDFromBytes:[self bytesForDigest:digest codec:0x55]
                                    profile:ATProtoDASLCIDProfileBase];
    XCTAssertNotNil(self.sampleCID, @"test fixture setup must itself produce a conformant CID");
    self.sampleCIDString = self.sampleCID.stringValue;
}

- (NSData *)bytesForDigest:(NSData *)digest codec:(uint8_t)codec {
    NSMutableData *bytes = [NSMutableData data];
    uint8_t version = 0x01;
    uint8_t sha256Code = 0x12;
    uint8_t length = 0x20;
    [bytes appendBytes:&version length:1];
    [bytes appendBytes:&codec length:1];
    [bytes appendBytes:&sha256Code length:1];
    [bytes appendBytes:&length length:1];
    [bytes appendData:digest];
    return bytes;
}

#pragma mark - Valid URLs

- (void)testBareCIDNoHints {
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/", self.sampleCIDString];
    NSError *error = nil;
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:&error];
    XCTAssertNotNil(url);
    XCTAssertNil(error);
    XCTAssertTrue([url.cid isEqualToCID:self.sampleCID]);
    XCTAssertEqual(url.hints.count, 0u);
}

- (void)testBareCIDNoTrailingSlashNoPath {
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@", self.sampleCIDString];
    NSError *error = nil;
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:&error];
    XCTAssertNotNil(url);
    XCTAssertTrue([url.cid isEqualToCID:self.sampleCID]);
}

- (void)testSingleHint {
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?hint=example.com", self.sampleCIDString];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    XCTAssertNotNil(url);
    XCTAssertEqualObjects(url.hints, (@[@"example.com"]));
}

- (void)testMultipleRepeatedHints {
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?hint=a.example.com&hint=b.example.com",
                            self.sampleCIDString];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    XCTAssertEqualObjects(url.hints, (@[@"a.example.com", @"b.example.com"]));
}

- (void)testHintWithPort {
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?hint=example.com:8443", self.sampleCIDString];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    XCTAssertEqualObjects(url.hints, (@[@"example.com:8443"]));
}

- (void)testDuplicateHintsAreDeduplicated {
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?hint=example.com&hint=example.com",
                            self.sampleCIDString];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    XCTAssertEqualObjects(url.hints, (@[@"example.com"]));
}

- (void)testInvalidHintValueIsDroppedNotFatal {
    // A hint containing a path/query of its own is not valid bare host syntax
    // and must be dropped, per spec, without failing the whole parse.
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?hint=example.com/evil&hint=good.example.com",
                            self.sampleCIDString];
    NSError *error = nil;
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:&error];
    XCTAssertNotNil(url);
    XCTAssertNil(error);
    XCTAssertEqualObjects(url.hints, (@[@"good.example.com"]));
}

- (void)testUnrelatedQueryParamsAreIgnored {
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/?other=1&hint=example.com",
                            self.sampleCIDString];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    XCTAssertEqualObjects(url.hints, (@[@"example.com"]));
}

- (void)testUppercaseSchemeAccepted {
    NSString *urlString = [NSString stringWithFormat:@"RASL://%@/", self.sampleCIDString];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    XCTAssertNotNil(url);
}

- (void)testWellKnownPath {
    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/", self.sampleCIDString];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:nil];
    NSString *expected = [NSString stringWithFormat:@"/.well-known/rasl/%@", self.sampleCIDString];
    XCTAssertEqualObjects([url wellKnownPath], expected);
    XCTAssertEqualObjects(ATProtoRASLWellKnownPathForCID(self.sampleCID), expected);
}

#pragma mark - Invalid URLs

- (void)testWrongSchemeRejected {
    NSError *error = nil;
    NSString *urlString = [NSString stringWithFormat:@"https://%@/", self.sampleCIDString];
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:&error];
    XCTAssertNil(url);
    XCTAssertEqual(error.code, ATProtoRASLURLErrorInvalidScheme);
}

- (void)testEmptyAuthorityRejected {
    NSError *error = nil;
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:@"rasl:///?hint=example.com" error:&error];
    XCTAssertNil(url);
    XCTAssertEqual(error.code, ATProtoRASLURLErrorMissingCID);
}

- (void)testGarbageAuthorityRejected {
    NSError *error = nil;
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:@"rasl://not-a-cid/" error:&error];
    XCTAssertNil(url);
    XCTAssertEqual(error.code, ATProtoRASLURLErrorInvalidCID);
}

- (void)testDagPBCIDRejected {
    // Valid ATProto wire-syntax CID, but not DASL-conformant (dag-pb codec) —
    // rasl:// authorities must be strict DASL CIDs.
    NSError *error = nil;
    ATProtoRASLURL *url =
        [ATProtoRASLURL raslURLFromString:@"rasl://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/"
                                     error:&error];
    XCTAssertNil(url);
    XCTAssertEqual(error.code, ATProtoRASLURLErrorInvalidCID);
}

- (void)testEmptyStringRejected {
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:@"" error:nil];
    XCTAssertNil(url);
}

- (void)testBigDASLBlake3CIDParsesForClientSideRejection {
    // The URL model preserves a syntactically valid Big DASL CID so the
    // transport client can report its unsupported hash algorithm explicitly.
    // The server route uses the base profile separately and rejects it before
    // resolution; neither path serves BLAKE3 bytes before Phase 6.
    NSData *digest = [CID sha256Digest:[@"blake3-placeholder" dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableData *blake3Bytes = [[self bytesForDigest:digest codec:ATProtoDASLCodecRaw] mutableCopy];
    uint8_t blake3Code = ATProtoDASLMultihashBLAKE3;
    [blake3Bytes replaceBytesInRange:NSMakeRange(2, 1) withBytes:&blake3Code];
    CID *blake3CID = [CID daslCIDFromBytes:blake3Bytes profile:ATProtoDASLCIDProfileBig];
    XCTAssertNotNil(blake3CID, @"test fixture setup must produce a conformant Big DASL CID");

    NSString *urlString = [NSString stringWithFormat:@"rasl://%@/", blake3CID.stringValue];
    NSError *error = nil;
    ATProtoRASLURL *url = [ATProtoRASLURL raslURLFromString:urlString error:&error];
    XCTAssertNotNil(url);
    XCTAssertNil(error);
    XCTAssertTrue([url.cid isEqualToCID:blake3CID]);
}

@end
