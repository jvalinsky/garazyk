// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PAClaim.h"
#import "Security/S2PA/ATProtoS2PAHashDataAssertion.h"
#import "Security/S2PA/ATProtoS2PASoftBindingAssertion.h"
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Auth/Crypto/Secp256k1.h"

@interface ATProtoS2PAClaimTests : XCTestCase
@end

@implementation ATProtoS2PAClaimTests

- (ATProtoSecp256k1KeyPair *)testKeyPair {
    uint8_t privateKeyBytes[32] = {0};
    privateKeyBytes[31] = 13;
    return [ATProtoSecp256k1KeyPair keyPairWithPrivateKey:[NSData dataWithBytes:privateKeyBytes
                                                                         length:32]
                                                     error:nil];
}

- (NSArray<ATProtoS2PAStoredAssertion *> *)sampleAssertions {
    NSError *error = nil;
    NSData *media = [@"claim-media" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoS2PAHashDataAssertion *hash =
        [ATProtoS2PAHashDataAssertion assertionHardBindingMediaData:media name:nil error:&error];
    XCTAssertNotNil(hash, @"%@", error);
    NSData *hashCBOR = [hash encodeCBOR:&error];
    XCTAssertNotNil(hashCBOR);

    ATProtoS2PASoftBindingAssertion *soft =
        [ATProtoS2PASoftBindingAssertion assertionMonolithSHA256ForData:media
                                                               timespan:nil
                                                                   name:nil
                                                                  error:&error];
    XCTAssertNotNil(soft, @"%@", error);
    NSData *softCBOR = [soft encodeCBOR:&error];
    XCTAssertNotNil(softCBOR, @"%@", error);

    return @[
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashDataAssertionLabel
                                                  cbor:hashCBOR],
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PASoftBindingAssertionLabel
                                                  cbor:softCBOR],
    ];
}

- (void)testClaimRoundTripAndHashedURIs {
    NSArray *assertions = [self sampleAssertions];
    ATProtoS2PAClaimGeneratorInfo *info =
        [ATProtoS2PAClaimGeneratorInfo infoWithName:@"garazyk-s2pa"
                                            version:@"0.1"
                                        specVersion:@"2.2"];
    NSError *error = nil;
    ATProtoS2PAClaim *claim = [ATProtoS2PAClaim claimWithAssertions:assertions
                                                         instanceID:@"urn:uuid:test-1"
                                                     generatorInfo:info
                                                             title:@"demo"
                                                             error:&error];
    XCTAssertNotNil(claim, @"%@", error);
    XCTAssertEqual(claim.createdAssertions.count, (NSUInteger)2);
    NSData *cbor = [claim encodeCBOR:&error];
    XCTAssertNotNil(cbor, @"%@", error);
    ATProtoS2PAClaim *round = [ATProtoS2PAClaim claimFromCBOR:cbor error:&error];
    XCTAssertNotNil(round, @"%@", error);
    XCTAssertEqualObjects(round.instanceID, @"urn:uuid:test-1");
    XCTAssertEqualObjects(round.title, @"demo");
    XCTAssertEqualObjects(round.generatorInfo.name, @"garazyk-s2pa");
    XCTAssertEqual(round.createdAssertions.count, (NSUInteger)2);

    NSData *store = [ATProtoS2PAClaim assertionStoreJUMBFWithAssertions:assertions error:&error];
    XCTAssertNotNil(store, @"%@", error);
    XCTAssertTrue([round verifyHashedURIsAgainstAssertionStore:store error:&error], @"%@", error);

    NSData *hashCBOR = [ATProtoS2PAClaim assertionCBORWithLabel:ATProtoS2PAHashDataAssertionLabel
                                              inAssertionStore:store
                                                         error:&error];
    XCTAssertNotNil(hashCBOR, @"%@", error);
    ATProtoS2PAHashDataAssertion *parsed =
        [ATProtoS2PAHashDataAssertion assertionFromCBOR:hashCBOR error:&error];
    XCTAssertNotNil(parsed, @"%@", error);
}

- (void)testJUMBFClaimBoundSignVerify {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSArray *assertions = [self sampleAssertions];
    NSError *error = nil;
    NSData *box = [ATProtoS2PAJUMBF uuidBoxSigningAssertions:assertions
                                                  instanceID:@"urn:uuid:test-2"
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
