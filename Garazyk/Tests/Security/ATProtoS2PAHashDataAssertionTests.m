// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PAHashDataAssertion.h"
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Auth/Crypto/Secp256k1.h"

@interface ATProtoS2PAHashDataAssertionTests : XCTestCase
@end

@implementation ATProtoS2PAHashDataAssertionTests

- (ATProtoSecp256k1KeyPair *)testKeyPair {
    uint8_t privateKeyBytes[32] = {0};
    privateKeyBytes[31] = 9;
    return [ATProtoSecp256k1KeyPair keyPairWithPrivateKey:[NSData dataWithBytes:privateKeyBytes
                                                                         length:32]
                                                     error:nil];
}

- (void)testEmptyExclusionMatchesWholeDigest {
    NSData *media = [@"muxl-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoS2PAHashDataAssertion *a =
        [ATProtoS2PAHashDataAssertion assertionHardBindingMediaData:media name:@"c2pa.hash.data" error:&error];
    XCTAssertNotNil(a);
    XCTAssertEqual(a.exclusions.count, (NSUInteger)0);
    XCTAssertTrue([a verifyAgainstData:media error:&error]);
    NSData *cbor = [a encodeCBOR:&error];
    XCTAssertNotNil(cbor);
    ATProtoS2PAHashDataAssertion *round = [ATProtoS2PAHashDataAssertion assertionFromCBOR:cbor error:&error];
    XCTAssertEqualObjects(round.digest, a.digest);
    XCTAssertEqualObjects(round.alg, @"sha256");
    XCTAssertEqualObjects(round.name, @"c2pa.hash.data");
}

- (void)testExclusionSkipsPrefix {
    NSData *prefix = [@"UUIDBOX" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *media = [@"segment" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *presentation = [prefix mutableCopy];
    [presentation appendData:media];
    NSError *error = nil;
    ATProtoS2PAHashDataAssertion *a =
        [ATProtoS2PAHashDataAssertion assertionForPresentation:presentation
                                         excludedPrefixLength:prefix.length
                                                         name:nil
                                                        error:&error];
    XCTAssertNotNil(a);
    XCTAssertEqual(a.exclusions.count, (NSUInteger)1);
    XCTAssertEqual(a.exclusions.firstObject.start, (NSUInteger)0);
    XCTAssertEqual(a.exclusions.firstObject.length, prefix.length);
    XCTAssertTrue([a verifyAgainstData:presentation error:&error]);
    // Same digest as hashing media alone.
    NSData *mediaOnly = [ATProtoS2PAHashDataAssertion sha256DigestForData:media exclusions:@[] error:nil];
    XCTAssertEqualObjects(a.digest, mediaOnly);
}

- (void)testJUMBFSignsHashDataAssertion {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSData *media = [NSData dataWithBytes:(const uint8_t[]){0x10, 0x20, 0x30} length:3];
    NSError *error = nil;
    NSData *box =
        [ATProtoS2PAJUMBF uuidBoxSigningHashDataAssertionForMediaData:media
                                                         withKeyPair:pair
                                                                 did:nil
                                                           notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                                            notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                                               error:&error];
    XCTAssertNotNil(box, @"%@", error);
    XCTAssertTrue([ATProtoS2PAJUMBF verifyUUIDBox:box
                            hardBoundToMediaData:media
                                    expectedDID:pair.didKeyString
                                          error:&error],
                  @"%@", error);
}

@end
