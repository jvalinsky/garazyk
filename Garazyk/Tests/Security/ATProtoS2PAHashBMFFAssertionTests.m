// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PAHashBMFFAssertion.h"
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Auth/Crypto/Secp256k1.h"
#include <string.h>

@interface ATProtoS2PAHashBMFFAssertionTests : XCTestCase
@end

@implementation ATProtoS2PAHashBMFFAssertionTests

- (ATProtoSecp256k1KeyPair *)testKeyPair {
    uint8_t privateKeyBytes[32] = {0};
    privateKeyBytes[31] = 11;
    return [ATProtoSecp256k1KeyPair keyPairWithPrivateKey:[NSData dataWithBytes:privateKeyBytes
                                                                         length:32]
                                                     error:nil];
}

- (NSData *)boxWithType:(const char *)type4 payload:(NSData *)payload {
    NSUInteger size = 8 + payload.length;
    NSMutableData *box = [NSMutableData dataWithLength:size];
    uint8_t *b = box.mutableBytes;
    b[0] = (uint8_t)((size >> 24) & 0xff);
    b[1] = (uint8_t)((size >> 16) & 0xff);
    b[2] = (uint8_t)((size >> 8) & 0xff);
    b[3] = (uint8_t)(size & 0xff);
    memcpy(b + 4, type4, 4);
    if (payload.length > 0) {
        memcpy(b + 8, payload.bytes, payload.length);
    }
    return box;
}

- (NSData *)sampleBMFFMedia {
    // ftyp: major=isom, minor=0, compatible brand isom
    uint8_t ftypPayload[] = {
        'i', 's', 'o', 'm', 0, 0, 0, 0, 'i', 's', 'o', 'm'
    };
    NSData *ftyp = [self boxWithType:"ftyp"
                             payload:[NSData dataWithBytes:ftypPayload length:sizeof(ftypPayload)]];
    NSData *mdat = [self boxWithType:"mdat"
                             payload:[@"hello-bmff" dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableData *media = [ftyp mutableCopy];
    [media appendData:mdat];
    return media;
}

- (void)testExcludeUUIDAndRoundTripCBOR {
    NSData *media = [self sampleBMFFMedia];
    // Synthetic C2PA uuid box (not a real JUMBF) to exercise exclusion + offset hashing.
    NSMutableData *uuidPayload = [[ATProtoS2PAJUMBF c2paBMFFUUID] mutableCopy];
    [uuidPayload appendData:[@"junk" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *uuidBox = [self boxWithType:"uuid" payload:uuidPayload];
    NSMutableData *presentation = [uuidBox mutableCopy];
    [presentation appendData:media];

    NSError *error = nil;
    ATProtoS2PAHashBMFFAssertion *a =
        [ATProtoS2PAHashBMFFAssertion assertionExcludingC2PAUUIDForBMFFData:presentation
                                                                      name:ATProtoS2PAHashBMFFAssertionLabel
                                                                     error:&error];
    XCTAssertNotNil(a, @"%@", error);
    XCTAssertEqual(a.exclusions.count, (NSUInteger)1);
    XCTAssertEqualObjects(a.exclusions.firstObject.xpath, @"/uuid");
    XCTAssertTrue([a verifyAgainstBMFFData:presentation error:&error], @"%@", error);

    NSData *cbor = [a encodeCBOR:&error];
    XCTAssertNotNil(cbor, @"%@", error);
    ATProtoS2PAHashBMFFAssertion *round =
        [ATProtoS2PAHashBMFFAssertion assertionFromCBOR:cbor error:&error];
    XCTAssertNotNil(round, @"%@", error);
    XCTAssertEqualObjects(round.digest, a.digest);
    XCTAssertEqualObjects(round.alg, @"sha256");
    XCTAssertEqualObjects(round.name, ATProtoS2PAHashBMFFAssertionLabel);
    XCTAssertTrue([round verifyAgainstBMFFData:presentation error:&error], @"%@", error);
}

- (void)testTamperedMDATFails {
    NSData *media = [self sampleBMFFMedia];
    NSMutableData *uuidPayload = [[ATProtoS2PAJUMBF c2paBMFFUUID] mutableCopy];
    [uuidPayload appendBytes:"x" length:1];
    NSData *uuidBox = [self boxWithType:"uuid" payload:uuidPayload];
    NSMutableData *presentation = [uuidBox mutableCopy];
    [presentation appendData:media];
    NSError *error = nil;
    ATProtoS2PAHashBMFFAssertion *a =
        [ATProtoS2PAHashBMFFAssertion assertionExcludingC2PAUUIDForBMFFData:presentation
                                                                      name:nil
                                                                     error:&error];
    XCTAssertNotNil(a);
    // Flip one mdat payload byte after the uuid + ftyp headers.
    NSMutableData *tampered = [presentation mutableCopy];
    uint8_t *bytes = tampered.mutableBytes;
    bytes[tampered.length - 1] ^= 0xff;
    XCTAssertFalse([a verifyAgainstBMFFData:tampered error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAHashBMFFAssertionErrorHashMismatch);
}

- (void)testJUMBFTwoPassBMFFSignVerify {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSData *media = [self sampleBMFFMedia];
    NSError *error = nil;
    NSData *box =
        [ATProtoS2PAJUMBF uuidBoxSigningHashBMFFAssertionForBMFFMediaData:media
                                                             withKeyPair:pair
                                                                     did:nil
                                                               notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                                                notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                                                   error:&error];
    XCTAssertNotNil(box, @"%@", error);
    NSMutableData *presentation = [box mutableCopy];
    [presentation appendData:media];
    XCTAssertTrue([ATProtoS2PAJUMBF verifyUUIDBox:box
                            bmffBoundToPresentation:presentation
                                       expectedDID:pair.didKeyString
                                             error:&error],
                  @"%@", error);
}

@end
