// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoPFPTests.m

 @abstract Tests the bounded DASL PFP identifier implementation.
 */

#import <XCTest/XCTest.h>
#import "Core/ATProtoPFP.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoPFPTests : XCTestCase
@end

@implementation ATProtoPFPTests

- (ATProtoCID *)sampleCID {
    NSData *bytes = [NSData dataWithBytes:(const uint8_t[]) {
        0x01, 0x55, 0x12, 0x20,
        0x58, 0x91, 0xb5, 0xb5, 0x22, 0xd5, 0xdf, 0x08,
        0x6d, 0x0f, 0xf0, 0xb1, 0x10, 0xfb, 0xd9, 0xd2,
        0x1b, 0xb4, 0xfc, 0x71, 0x63, 0xaf, 0x34, 0xd0,
        0x82, 0x86, 0xa2, 0xe8, 0x46, 0xf6, 0xbe, 0x03
    } length:36];
    return [ATProtoCID daslCIDFromBytes:bytes profile:ATProtoDASLCIDProfileBase];
}

- (NSData *)pdqBytes {
    NSMutableData *data = [NSMutableData dataWithBytes:(const uint8_t[]) {0x01, 0x20} length:2];
    uint8_t hash[32];
    for (NSUInteger i = 0; i < sizeof(hash); i++) hash[i] = (uint8_t)i;
    [data appendBytes:hash length:sizeof(hash)];
    return data;
}

- (void)testPDQRoundTripAndEquality {
    NSError *error = nil;
    ATProtoPFP *pfp = [ATProtoPFP pfpFromBytes:[self pdqBytes] error:&error];
    XCTAssertNotNil(pfp);
    XCTAssertEqual(pfp.algorithm, ATProtoPFPAlgorithmPDQ);
    XCTAssertNil(pfp.dataCID);
    XCTAssertNil(error);
    XCTAssertEqualObjects(pfp.bytes, [self pdqBytes]);

    ATProtoPFP *fromString = [ATProtoPFP pfpFromString:pfp.stringValue error:&error];
    XCTAssertEqualObjects(fromString, pfp);
    XCTAssertEqualObjects(fromString.stringValue, pfp.stringValue);
    XCTAssertNil(error);
}

- (void)testTMKPDQFUsesStrictCIDData {
    ATProtoCID *cid = [self sampleCID];
    NSMutableData *bytes = [NSMutableData dataWithBytes:(const uint8_t[]) {0x02, 0x24} length:2];
    [bytes appendData:cid.bytes];

    NSError *error = nil;
    ATProtoPFP *pfp = [ATProtoPFP pfpFromBytes:bytes error:&error];
    XCTAssertNotNil(pfp);
    XCTAssertEqual(pfp.algorithm, ATProtoPFPAlgorithmTMKPDQF);
    XCTAssertEqualObjects(pfp.dataCID, cid);
    XCTAssertEqualObjects(pfp.bytes, bytes);
    XCTAssertNil(error);

    ATProtoPFP *decoded = [ATProtoPFP pfpFromString:pfp.stringValue error:&error];
    XCTAssertEqualObjects(decoded, pfp);
    XCTAssertNil(error);
}

- (void)testJSONObjectPseudoTypeIsExactAndRoundTrips {
    NSError *error = nil;
    ATProtoPFP *pfp = [ATProtoPFP pfpFromBytes:[self pdqBytes] error:&error];
    NSDictionary *json = pfp.JSONObjectRepresentation;
    XCTAssertEqualObjects(json.allKeys, @[@"__pfp"]);
    XCTAssertEqualObjects([ATProtoPFP pfpFromJSONObject:json error:&error], pfp);
    XCTAssertNil(error);

    XCTAssertNil(([ATProtoPFP pfpFromJSONObject:@{ @"__pfp": pfp.stringValue, @"extra": @1 }
                                           error:&error]));
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidType);
    error = nil;
    XCTAssertNil(([ATProtoPFP pfpFromJSONObject:@{ @"__pfp": @1 } error:&error]));
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidType);
}

- (void)testRejectsNonCanonicalBase32Padding {
    NSError *error = nil;
    // The decoded payload is one zero byte, but "aa" contains an extra
    // zero-only base32 group and is not the canonical encoding of that byte.
    XCTAssertNil([ATProtoPFP pfpFromString:@"paaa" error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidBase32);
}

- (void)testRejectsInvalidPrefixesAndBase32 {
    NSError *error = nil;
    XCTAssertNil([ATProtoPFP pfpFromString:@"babc" error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidPrefix);
    error = nil;
    XCTAssertNil([ATProtoPFP pfpFromString:@"pABC" error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidBase32);
    error = nil;
    XCTAssertNil([ATProtoPFP pfpFromString:@"pab=" error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidBase32);
}

- (void)testRejectsUnknownAlgorithmsLengthAndTrailingData {
    NSError *error = nil;
    const uint8_t unknown[] = {0x00, 0x20};
    XCTAssertNil([ATProtoPFP pfpFromBytes:[NSData dataWithBytes:unknown length:sizeof(unknown)] error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorUnsupportedAlgorithm);

    error = nil;
    const uint8_t wrongLength[] = {0x01, 0x1f};
    XCTAssertNil([ATProtoPFP pfpFromBytes:[NSData dataWithBytes:wrongLength length:sizeof(wrongLength)] error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidLength);

    error = nil;
    NSMutableData *trailing = [[self pdqBytes] mutableCopy];
    uint8_t extra = 0;
    [trailing appendBytes:&extra length:1];
    XCTAssertNil([ATProtoPFP pfpFromBytes:trailing error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorTrailingData);
}

- (void)testRejectsNonCanonicalVarintsAndInvalidTMKCid {
    NSError *error = nil;
    NSMutableData *nonCanonical = [NSMutableData dataWithBytes:(const uint8_t[]) {0x81, 0x00, 0x20} length:3];
    XCTAssertNil([ATProtoPFP pfpFromBytes:nonCanonical error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorNonCanonicalVarint);

    error = nil;
    NSMutableData *badCID = [NSMutableData dataWithBytes:(const uint8_t[]) {0x02, 0x24} length:2];
    uint8_t zeros[36] = {0};
    [badCID appendBytes:zeros length:sizeof(zeros)];
    XCTAssertNil([ATProtoPFP pfpFromBytes:badCID error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidCID);

    error = nil;
    uint8_t overflow[11] = {0};
    for (NSUInteger i = 0; i < sizeof(overflow); i++) overflow[i] = 0x80;
    XCTAssertNil([ATProtoPFP pfpFromBytes:[NSData dataWithBytes:overflow length:sizeof(overflow)] error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidLength);

    error = nil;
    NSMutableData *blakeCID = [NSMutableData dataWithBytes:(const uint8_t[]) {0x02, 0x24} length:2];
    uint8_t blakeBytes[36] = {
        0x01, 0x55, 0x1e, 0x20,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0
    };
    [blakeCID appendBytes:blakeBytes length:sizeof(blakeBytes)];
    XCTAssertNil([ATProtoPFP pfpFromBytes:blakeCID error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorInvalidCID);
}

- (void)testPDQHammingDistanceAndThreshold {
    ATProtoPFP *left = [ATProtoPFP pfpFromBytes:[self pdqBytes] error:nil];
    ATProtoPFP *right = [ATProtoPFP pfpFromBytes:[self pdqBytes] error:nil];
    NSUInteger distance = 99;
    NSError *error = nil;
    XCTAssertTrue([ATProtoPFP hammingDistanceBetweenPDQ:left
                                                 andPDQ:right
                                               distance:&distance
                                                  error:&error]);
    XCTAssertEqual(distance, 0U);
    XCTAssertLessThanOrEqual(distance, [ATProtoPFP recommendedPDQMatchDistance]);

    NSMutableData *mutated = [[self pdqBytes] mutableCopy];
    // Flip one bit in the PDQ hash payload (after algorithm/length varints 0x01 0x20).
    uint8_t *bytes = mutated.mutableBytes;
    bytes[2] ^= 0x01;
    ATProtoPFP *near = [ATProtoPFP pfpFromBytes:mutated error:&error];
    XCTAssertNotNil(near);
    XCTAssertTrue([ATProtoPFP hammingDistanceBetweenPDQ:left
                                                 andPDQ:near
                                               distance:&distance
                                                  error:&error]);
    XCTAssertEqual(distance, 1U);

    ATProtoCID *cid = [self sampleCID];
    NSMutableData *tmk = [NSMutableData dataWithBytes:(const uint8_t[]){0x02, 0x24} length:2];
    [tmk appendData:cid.bytes];
    ATProtoPFP *video = [ATProtoPFP pfpFromBytes:tmk error:&error];
    XCTAssertNotNil(video);
    error = nil;
    XCTAssertFalse([ATProtoPFP hammingDistanceBetweenPDQ:left
                                                  andPDQ:video
                                                distance:&distance
                                                   error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPErrorUnsupportedAlgorithm);
}

@end
