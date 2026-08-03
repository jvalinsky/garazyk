// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRASLClientTests.m

 @abstract Tests the fail-closed paths of `ATProtoRASLClient` that do not
 require a live network fixture.

 @discussion Full fetch-and-verify coverage (successful hint response,
 parallel abort-on-first-success, hint-failure aggregation) would need a
 local HTTPS test server — `ATProtoRASLClient` deliberately builds only
 `https://` request URLs, and this codebase has no local TLS test fixture
 today. What is covered here: both checks the client performs entirely
 before any network call — no hints, and a CID hash algorithm the client
 cannot verify yet (BLAKE3 / Big DASL). The actual fetch, redirect, and SSRF
 behavior is `ATProtoSafeHTTPClient`'s own contract and is covered by its
 existing test suite; this client only composes it.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "Core/ATProtoRASLURL.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Network/ATProtoRASLClient.h"

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

- (void)testNoHintsFailsImmediatelyWithoutNetwork {
    NSData *digest = [CID sha256Digest:[@"no-hints" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID daslCIDFromBytes:[self bytesForDigest:digest hashCode:0x12 codec:0x55]
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
    NSData *digest = [CID sha256Digest:[@"blake3" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID daslCIDFromBytes:[self bytesForDigest:digest hashCode:ATProtoDASLMultihashBLAKE3 codec:0x55]
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

@end
