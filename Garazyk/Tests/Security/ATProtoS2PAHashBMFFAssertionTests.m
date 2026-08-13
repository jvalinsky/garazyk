// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PAHashBMFFAssertion.h"
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Security/S2PA/ATProtoS2PAClaim.h"
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
    uint8_t ftypPayload[] = {
        'i', 's', 'o', 'm', 0, 0, 0, 0, 'i', 's', 'o', 'm'
    };
    NSData *ftyp = [self boxWithType:"ftyp"
                             payload:[NSData dataWithBytes:ftypPayload length:sizeof(ftypPayload)]];
    NSData *mdat = [self boxWithType:"mdat"
                             payload:[@"hello-bmff-0123456789" dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableData *media = [ftyp mutableCopy];
    [media appendData:mdat];
    return media;
}

- (NSData *)presentationWithMedia:(NSData *)media {
    NSMutableData *uuidPayload = [[ATProtoS2PAJUMBF c2paBMFFUUID] mutableCopy];
    [uuidPayload appendData:[@"junk" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *uuidBox = [self boxWithType:"uuid" payload:uuidPayload];
    NSMutableData *presentation = [uuidBox mutableCopy];
    [presentation appendData:media];
    return presentation;
}

- (void)testExcludeUUIDAndRoundTripCBOR {
    NSData *presentation = [self presentationWithMedia:[self sampleBMFFMedia]];
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
    NSData *presentation = [self presentationWithMedia:[self sampleBMFFMedia]];
    NSError *error = nil;
    ATProtoS2PAHashBMFFAssertion *a =
        [ATProtoS2PAHashBMFFAssertion assertionExcludingC2PAUUIDForBMFFData:presentation
                                                                      name:nil
                                                                     error:&error];
    XCTAssertNotNil(a);
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

- (void)testMerkleLeafModesAndTree {
    NSError *error = nil;
    NSData *payload = [@"abcdefghij" dataUsingEncoding:NSUTF8StringEncoding]; // 10 bytes

    NSArray *whole = [ATProtoS2PAHashBMFFAssertion leafDigestsForMDATPayload:payload
                                                              fixedBlockSize:nil
                                                         variableBlockSizes:nil
                                                                       error:&error];
    XCTAssertEqual(whole.count, 1u, @"%@", error);

    NSArray *fixed = [ATProtoS2PAHashBMFFAssertion leafDigestsForMDATPayload:payload
                                                              fixedBlockSize:@(4)
                                                         variableBlockSizes:nil
                                                                       error:&error];
    XCTAssertEqual(fixed.count, 3u, @"%@", error); // 4+4+2

    NSArray *varSizes = @[ @3, @7 ];
    NSArray *variable = [ATProtoS2PAHashBMFFAssertion leafDigestsForMDATPayload:payload
                                                                 fixedBlockSize:nil
                                                            variableBlockSizes:varSizes
                                                                          error:&error];
    XCTAssertEqual(variable.count, 2u, @"%@", error);

    NSArray *bothModes = @[ @1 ];
    NSArray *badBoth = [ATProtoS2PAHashBMFFAssertion leafDigestsForMDATPayload:payload
                                                                fixedBlockSize:@(4)
                                                           variableBlockSizes:bothModes
                                                                         error:&error];
    XCTAssertNil(badBoth);
    XCTAssertEqual(error.code, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument);

    NSArray *badSumSizes = @[ @3, @3 ];
    NSArray *badSum = [ATProtoS2PAHashBMFFAssertion leafDigestsForMDATPayload:payload
                                                               fixedBlockSize:nil
                                                          variableBlockSizes:badSumSizes
                                                                        error:&error];
    XCTAssertNil(badSum);
    XCTAssertEqual(error.code, ATProtoS2PAHashBMFFAssertionErrorInvalidArgument);

    NSArray *layers = [ATProtoS2PAHashBMFFAssertion merkleLayersFromLeafHashes:fixed];
    XCTAssertEqual(layers.count, 3u); // 3 leaves → 2 → 1
    XCTAssertEqual([layers[0] count], 3u);
    XCTAssertEqual([layers[1] count], 2u); // pair + promote
    XCTAssertEqual([layers[2] count], 1u);
    // Odd last leaf promoted unchanged into parent.
    NSData *promoted = layers[1][1];
    NSData *lastLeaf = fixed[2];
    XCTAssertEqualObjects(promoted, lastLeaf);
}

- (void)testMerkleAssertionRoundTripAndTamper {
    NSData *presentation = [self presentationWithMedia:[self sampleBMFFMedia]];
    NSError *error = nil;
    ATProtoS2PAHashBMFFAssertion *a =
        [ATProtoS2PAHashBMFFAssertion assertionExcludingC2PAUUIDWithMerkleForBMFFData:presentation
                                                                             uniqueId:1
                                                                              localId:0
                                                                       fixedBlockSize:@(5)
                                                                  variableBlockSizes:nil
                                                                                 name:@"merkle-test"
                                                                                error:&error];
    XCTAssertNotNil(a, @"%@", error);
    XCTAssertEqual(a.merkle.count, 1u);
    XCTAssertEqual(a.exclusions.count, 2u);
    XCTAssertTrue([a verifyAgainstBMFFData:presentation error:&error], @"%@", error);

    NSData *cbor = [a encodeCBOR:&error];
    XCTAssertNotNil(cbor, @"%@", error);
    ATProtoS2PAHashBMFFAssertion *round =
        [ATProtoS2PAHashBMFFAssertion assertionFromCBOR:cbor error:&error];
    XCTAssertNotNil(round, @"%@", error);
    XCTAssertEqual(round.merkle.count, 1u);
    XCTAssertEqualObjects(round.merkle.firstObject.hashes, a.merkle.firstObject.hashes);
    XCTAssertEqual(round.merkle.firstObject.fixedBlockSize.unsignedIntegerValue, 5u);
    XCTAssertTrue([round verifyAgainstBMFFData:presentation error:&error], @"%@", error);

    NSMutableData *tampered = [presentation mutableCopy];
    ((uint8_t *)tampered.mutableBytes)[tampered.length - 1] ^= 0x5a;
    XCTAssertFalse([a verifyAgainstBMFFData:tampered error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAHashBMFFAssertionErrorHashMismatch);
}

- (void)testMerkleVariableAndClaimBoundSign {
    NSData *presentation = [self presentationWithMedia:[self sampleBMFFMedia]];
    // sample mdat payload is "hello-bmff-0123456789" = 21 bytes
    NSError *error = nil;
    NSArray *varBlocks = @[ @8, @8, @5 ];
    ATProtoS2PAHashBMFFAssertion *a =
        [ATProtoS2PAHashBMFFAssertion assertionExcludingC2PAUUIDWithMerkleForBMFFData:presentation
                                                                             uniqueId:7
                                                                              localId:0
                                                                       fixedBlockSize:nil
                                                                  variableBlockSizes:varBlocks
                                                                                 name:nil
                                                                                error:&error];
    XCTAssertNotNil(a, @"%@", error);
    XCTAssertEqual(a.merkle.firstObject.count, 3u);
    XCTAssertTrue([a verifyAgainstBMFFData:presentation error:&error], @"%@", error);

    NSData *cbor = [a encodeCBOR:&error];
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSData *box = [ATProtoS2PAJUMBF uuidBoxSigningAssertions:@[
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashBMFFAssertionLabel cbor:cbor],
    ]
                                                  instanceID:@"urn:uuid:bmff-merkle"
                                              generatorName:@"garazyk-s2pa"
                                                withKeyPair:pair
                                                        did:nil
                                                  notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                                   notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                                      error:&error];
    XCTAssertNotNil(box, @"%@", error);
    XCTAssertTrue([ATProtoS2PAJUMBF verifyUUIDBoxClaimBound:box
                                               expectedDID:pair.didKeyString
                                                     error:&error],
                  @"%@", error);
}

@end
