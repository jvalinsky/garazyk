// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PAClaim.h"
#import "Security/S2PA/ATProtoS2PAHashDataAssertion.h"
#import "Security/S2PA/ATProtoS2PASoftBindingAssertion.h"
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Auth/Crypto/Secp256k1.h"
#import "Core/CBOR.h"

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

- (void)testGatheredAndRedactedAssertionsRoundTrip {
    NSArray<ATProtoS2PAStoredAssertion *> *assertions = [self sampleAssertions];
    ATProtoS2PAClaimGeneratorInfo *info =
        [ATProtoS2PAClaimGeneratorInfo infoWithName:@"garazyk-s2pa" version:nil specVersion:@"2.4"];
    NSError *error = nil;
    ATProtoS2PAClaim *claim = [ATProtoS2PAClaim
        claimWithCreatedAssertions:@[ assertions[0] ]
        gatheredAssertions:@[ assertions[1] ]
        redactedAssertions:@[ @"self#jumbf=/c2pa/urn:c2pa:01234567-89ab-cdef-0123-456789abcdef/c2pa.assertions/c2pa.ingredient.v3" ]
        instanceID:@"urn:uuid:gathered" generatorInfo:info title:nil error:&error];
    XCTAssertNotNil(claim, @"%@", error);
    NSData *cbor = [claim encodeCBOR:&error];
    XCTAssertNotNil(cbor, @"%@", error);
    NSUInteger offset = 0;
    ATProtoCBORValue *root = [ATProtoCBORDecoder decode:cbor offset:&offset];
    XCTAssertEqual(offset, cbor.length);
    __block ATProtoCBORValue *gatheredValue = nil;
    __block ATProtoCBORValue *redactedValue = nil;
    [root.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *key, ATProtoCBORValue *value,
                                                   BOOL *stop) {
        (void)stop;
        if ([key.textString isEqualToString:@"gathered_assertions"]) gatheredValue = value;
        if ([key.textString isEqualToString:@"redacted_assertions"]) redactedValue = value;
    }];
    XCTAssertEqual(gatheredValue.type, CBORTypeArray);
    XCTAssertEqual(gatheredValue.array.count, (NSUInteger)1);
    XCTAssertEqual(gatheredValue.array[0].type, CBORTypeMap);
    XCTAssertEqual(redactedValue.type, CBORTypeArray);
    XCTAssertEqual(redactedValue.array.count, (NSUInteger)1);
    XCTAssertEqual(redactedValue.array[0].type, CBORTypeTextString);
    ATProtoS2PAClaim *round = [ATProtoS2PAClaim claimFromCBOR:cbor error:&error];
    XCTAssertNotNil(round, @"%@", error);
    XCTAssertEqual(round.createdAssertions.count, (NSUInteger)1);
    XCTAssertEqual(round.gatheredAssertions.count, (NSUInteger)1);
    XCTAssertEqualObjects(round.redactedAssertions,
                           (@[ @"self#jumbf=/c2pa/urn:c2pa:01234567-89ab-cdef-0123-456789abcdef/c2pa.assertions/c2pa.ingredient.v3" ]));
    NSData *store = [ATProtoS2PAClaim assertionStoreJUMBFWithAssertions:assertions error:&error];
    XCTAssertNotNil(store, @"%@", error);
    XCTAssertTrue([round verifyHashedURIsAgainstAssertionStore:store error:&error], @"%@", error);
}

- (void)testGatheredAssertionsFailClosedForMissingAndTamperedEntries {
    NSArray<ATProtoS2PAStoredAssertion *> *assertions = [self sampleAssertions];
    ATProtoS2PAClaimGeneratorInfo *info =
        [ATProtoS2PAClaimGeneratorInfo infoWithName:@"garazyk-s2pa" version:nil specVersion:nil];
    NSError *error = nil;
    ATProtoS2PAClaim *claim = [ATProtoS2PAClaim
        claimWithCreatedAssertions:@[ assertions[0] ] gatheredAssertions:@[ assertions[1] ]
        redactedAssertions:nil instanceID:@"urn:uuid:gathered-check" generatorInfo:info title:nil error:&error];
    XCTAssertNotNil(claim, @"%@", error);
    NSData *missing = [ATProtoS2PAClaim assertionStoreJUMBFWithAssertions:@[ assertions[0] ] error:&error];
    XCTAssertFalse([claim verifyHashedURIsAgainstAssertionStore:missing error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAClaimErrorInvalidStructure);

    ATProtoS2PAStoredAssertion *tampered =
        [ATProtoS2PAStoredAssertion assertionWithLabel:assertions[1].label
                                                   cbor:[@"tampered" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *store = [ATProtoS2PAClaim assertionStoreJUMBFWithAssertions:@[ assertions[0], tampered ]
                                                                    error:&error];
    XCTAssertFalse([claim verifyHashedURIsAgainstAssertionStore:store error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAClaimErrorHashMismatch);
}

- (void)testGatheredReferencesRejectDuplicateAndOverlapLabels {
    NSArray<ATProtoS2PAStoredAssertion *> *assertions = [self sampleAssertions];
    ATProtoS2PAClaimGeneratorInfo *info =
        [ATProtoS2PAClaimGeneratorInfo infoWithName:@"garazyk-s2pa" version:nil specVersion:nil];
    NSError *error = nil;
    XCTAssertNil([ATProtoS2PAClaim claimWithCreatedAssertions:@[ assertions[0] ]
                                            gatheredAssertions:@[ assertions[0] ]
                                             redactedAssertions:nil instanceID:@"urn:uuid:overlap"
                                                generatorInfo:info title:nil error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAClaimErrorInvalidArgument);

    ATProtoS2PAClaim *base = [ATProtoS2PAClaim claimWithAssertions:@[ assertions[0] ]
                                                         instanceID:@"urn:uuid:duplicate" generatorInfo:info
                                                                 title:nil error:&error];
    ATProtoS2PAClaim *duplicate = [[ATProtoS2PAClaim alloc]
        initWithInstanceID:base.instanceID generatorInfo:base.generatorInfo signatureURI:base.signatureURI
        createdAssertions:base.createdAssertions gatheredAssertions:base.createdAssertions
        redactedAssertions:nil alg:base.alg title:nil];
    NSData *store = [ATProtoS2PAClaim assertionStoreJUMBFWithAssertions:@[ assertions[0] ] error:&error];
    XCTAssertFalse([duplicate verifyHashedURIsAgainstAssertionStore:store error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAClaimErrorInvalidStructure);
}

- (void)testRedactedAssertionsRejectMalformedAndSelfReferences {
    NSArray<ATProtoS2PAStoredAssertion *> *assertions = [self sampleAssertions];
    ATProtoS2PAClaimGeneratorInfo *info =
        [ATProtoS2PAClaimGeneratorInfo infoWithName:@"garazyk-s2pa" version:nil specVersion:nil];
    NSError *error = nil;
    XCTAssertNil([ATProtoS2PAClaim claimWithCreatedAssertions:@[ assertions[0] ] gatheredAssertions:nil
        redactedAssertions:@[ @"self#jumbf=/c2pa/not-an-assertion" ] instanceID:@"urn:uuid:bad-redaction"
        generatorInfo:info title:nil error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAClaimErrorInvalidArgument);
    XCTAssertNil([ATProtoS2PAClaim claimWithCreatedAssertions:@[ assertions[0] ] gatheredAssertions:nil
        redactedAssertions:@[ @"self#jumbf=/c2pa/../c2pa.assertions/c2pa.ingredient.v3" ]
        instanceID:@"urn:uuid:traversal-redaction" generatorInfo:info title:nil error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAClaimErrorInvalidArgument);
    XCTAssertNil([ATProtoS2PAClaim claimWithCreatedAssertions:@[ assertions[0] ] gatheredAssertions:nil
        redactedAssertions:@[ @"self#jumbf=/c2pa/manifest label/c2pa.assertions/c2pa.ingredient.v3" ]
        instanceID:@"urn:uuid:whitespace-redaction" generatorInfo:info title:nil error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAClaimErrorInvalidArgument);

    ATProtoS2PAClaim *base = [ATProtoS2PAClaim claimWithAssertions:@[ assertions[0] ]
                                                         instanceID:@"urn:uuid:self-redaction" generatorInfo:info
                                                                 title:nil error:&error];
    ATProtoS2PAClaim *selfRedacted = [[ATProtoS2PAClaim alloc]
        initWithInstanceID:base.instanceID generatorInfo:base.generatorInfo signatureURI:base.signatureURI
        createdAssertions:base.createdAssertions gatheredAssertions:nil
        redactedAssertions:@[ @"self#jumbf=c2pa.assertions/c2pa.hash.data" ] alg:base.alg title:nil];
    NSData *store = [ATProtoS2PAClaim assertionStoreJUMBFWithAssertions:@[ assertions[0] ] error:&error];
    XCTAssertFalse([selfRedacted verifyHashedURIsAgainstAssertionStore:store error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAClaimErrorInvalidStructure);
}

@end
