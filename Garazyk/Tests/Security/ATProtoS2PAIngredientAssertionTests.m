// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PAIngredientAssertion.h"
#import "Security/S2PA/ATProtoS2PAHashDataAssertion.h"
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Auth/Crypto/Secp256k1.h"
#import <CommonCrypto/CommonDigest.h>
#include <string.h>

@interface ATProtoS2PAIngredientAssertionTests : XCTestCase
@end

@implementation ATProtoS2PAIngredientAssertionTests

- (ATProtoSecp256k1KeyPair *)testKeyPair {
    uint8_t privateKeyBytes[32] = {0};
    privateKeyBytes[31] = 17;
    return [ATProtoSecp256k1KeyPair keyPairWithPrivateKey:[NSData dataWithBytes:privateKeyBytes
                                                                         length:32]
                                                     error:nil];
}

- (ATProtoS2PAHashedURI *)dummyHashedURI:(NSString *)url {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(url.UTF8String, (CC_LONG)strlen(url.UTF8String), digest);
    return [ATProtoS2PAHashedURI hashedURIWithURL:url
                                           digest:[NSData dataWithBytes:digest length:sizeof(digest)]
                                              alg:@"sha256"];
}

- (ATProtoS2PAIngredientValidationResults *)okResults {
    return [ATProtoS2PAIngredientValidationResults resultsWithSingleSuccessCode:@"claimSignature.validated"
                                                                            url:nil];
}

- (void)testParentOfRoundTripWithValidationResults {
    ATProtoS2PAHashedURI *manifest =
        [self dummyHashedURI:@"self#jumbf=/c2pa/urn:c2pa:parent-1"];
    ATProtoS2PAHashedURI *sig =
        [self dummyHashedURI:@"self#jumbf=/c2pa/urn:c2pa:parent-1/c2pa.signature"];
    ATProtoS2PAIngredientValidationResults *results =
        [ATProtoS2PAIngredientValidationResults
            resultsWithSuccess:@[
                [ATProtoS2PAIngredientValidationStatus statusWithCode:@"claimSignature.validated"
                                                                   url:sig.url],
            ]
                informational:@[
                    [ATProtoS2PAIngredientValidationStatus statusWithCode:@"time.untrusted"
                                                                       url:nil],
                ]
                      failure:@[]];
    NSError *error = nil;
    ATProtoS2PAIngredientAssertion *a =
        [ATProtoS2PAIngredientAssertion parentOfWithTitle:@"source"
                                                   format:@"video/mp4"
                                               instanceID:@"urn:uuid:ing-1"
                                           activeManifest:manifest
                                           claimSignature:sig
                                       validationResults:results
                                                    error:&error];
    XCTAssertNotNil(a, @"%@", error);
    NSData *cbor = [a encodeCBOR:&error];
    XCTAssertNotNil(cbor, @"%@", error);
    ATProtoS2PAIngredientAssertion *round =
        [ATProtoS2PAIngredientAssertion assertionFromCBOR:cbor error:&error];
    XCTAssertNotNil(round, @"%@", error);
    XCTAssertEqualObjects(round.relationship, ATProtoS2PAIngredientRelationshipParentOf);
    XCTAssertEqualObjects(round.title, @"source");
    XCTAssertEqualObjects(round.format, @"video/mp4");
    XCTAssertEqualObjects(round.instanceID, @"urn:uuid:ing-1");
    XCTAssertEqualObjects(round.activeManifest.url, manifest.url);
    XCTAssertEqualObjects(round.activeManifest.digest, manifest.digest);
    XCTAssertEqualObjects(round.claimSignature.url, sig.url);
    XCTAssertEqual(round.validationResults.success.count, 1u);
    XCTAssertEqualObjects(round.validationResults.success.firstObject.code,
                          @"claimSignature.validated");
    XCTAssertEqualObjects(round.validationResults.success.firstObject.url, sig.url);
    XCTAssertEqual(round.validationResults.informational.count, 1u);
    XCTAssertEqualObjects(round.validationResults.informational.firstObject.code,
                          @"time.untrusted");
    XCTAssertEqual(round.validationResults.failure.count, 0u);
}

- (void)testActiveManifestRequiresValidationResults {
    ATProtoS2PAHashedURI *manifest = [self dummyHashedURI:@"self#jumbf=/c2pa/x"];
    NSError *error = nil;
    ATProtoS2PAIngredientAssertion *missing =
        [ATProtoS2PAIngredientAssertion parentOfWithTitle:@"t"
                                                   format:nil
                                               instanceID:nil
                                           activeManifest:manifest
                                           claimSignature:nil
                                       validationResults:nil
                                                    error:&error];
    XCTAssertNil(missing);
    XCTAssertEqual(error.code, ATProtoS2PAIngredientAssertionErrorInvalidArgument);

    ATProtoS2PAIngredientAssertion *built =
        [[ATProtoS2PAIngredientAssertion alloc]
            initWithRelationship:ATProtoS2PAIngredientRelationshipParentOf
                           title:nil
                          format:nil
                      instanceID:nil
                 descriptionText:nil
               digitalSourceType:nil
                  activeManifest:manifest
                  claimSignature:nil
              validationResults:nil];
    XCTAssertNil([built encodeCBOR:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAIngredientAssertionErrorInvalidArgument);
}

- (void)testInputToAndMutualExclusion {
    NSError *error = nil;
    ATProtoS2PAIngredientAssertion *a =
        [ATProtoS2PAIngredientAssertion inputToWithDigitalSourceType:@"http://cv.iptc.org/newscodes/digitalsourcetype/algorithmicMedia"
                                                               title:@"gen"
                                                              format:@"image/png"
                                                               error:&error];
    XCTAssertNotNil(a, @"%@", error);
    XCTAssertEqualObjects(a.relationship, ATProtoS2PAIngredientRelationshipInputTo);
    XCTAssertNotNil([a encodeCBOR:&error]);

    ATProtoS2PAHashedURI *manifest = [self dummyHashedURI:@"self#jumbf=/c2pa/x"];
    ATProtoS2PAIngredientAssertion *bad =
        [[ATProtoS2PAIngredientAssertion alloc]
            initWithRelationship:ATProtoS2PAIngredientRelationshipParentOf
                           title:nil
                          format:nil
                      instanceID:nil
                 descriptionText:nil
               digitalSourceType:@"http://example.com/src"
                  activeManifest:manifest
                  claimSignature:nil
              validationResults:[self okResults]];
    XCTAssertNil([bad encodeCBOR:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAIngredientAssertionErrorInvalidArgument);
}

- (void)testIngredientInClaimBoundStore {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSError *error = nil;
    NSData *media = [@"ing-media" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoS2PAHashDataAssertion *hash =
        [ATProtoS2PAHashDataAssertion assertionHardBindingMediaData:media name:nil error:&error];
    NSData *hashCBOR = [hash encodeCBOR:&error];
    ATProtoS2PAIngredientAssertion *ing =
        [ATProtoS2PAIngredientAssertion parentOfWithTitle:@"parent"
                                                   format:@"video/mp4"
                                               instanceID:@"urn:uuid:p"
                                           activeManifest:[self dummyHashedURI:@"self#jumbf=/c2pa/p"]
                                           claimSignature:[self dummyHashedURI:@"self#jumbf=/c2pa/p/c2pa.signature"]
                                       validationResults:[self okResults]
                                                    error:&error];
    NSData *ingCBOR = [ing encodeCBOR:&error];
    NSArray *assertions = @[
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashDataAssertionLabel
                                                  cbor:hashCBOR],
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAIngredientAssertionLabel
                                                  cbor:ingCBOR],
    ];
    NSData *box = [ATProtoS2PAJUMBF uuidBoxSigningAssertions:assertions
                                                  instanceID:@"urn:uuid:child"
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

- (void)testEmbedChildAndVerifyHashedURIs {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSError *error = nil;
    NSData *childMedia = [@"child-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoS2PAHashDataAssertion *childHash =
        [ATProtoS2PAHashDataAssertion assertionHardBindingMediaData:childMedia name:nil error:&error];
    NSData *childHashCBOR = [childHash encodeCBOR:&error];
    NSData *childBox =
        [ATProtoS2PAJUMBF uuidBoxSigningAssertions:@[
            [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashDataAssertionLabel
                                                      cbor:childHashCBOR],
        ]
                                        instanceID:@"urn:uuid:child-active"
                                    generatorName:@"garazyk-s2pa-child"
                                      withKeyPair:pair
                                              did:nil
                                        notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                         notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                            error:&error];
    XCTAssertNotNil(childBox, @"%@", error);
    NSData *childStore = [ATProtoS2PAJUMBF manifestStoreFromBMFFUUIDBox:childBox error:&error];
    XCTAssertNotNil(childStore, @"%@", error);

    NSString *ingID = @"urn:uuid:ing-embed-1";
    NSData *embedded = nil;
    ATProtoS2PAIngredientAssertion *ing =
        [ATProtoS2PAIngredientAssertion parentOfEmbeddingChildStore:childStore
                                                         instanceID:ingID
                                                              title:@"source"
                                                             format:@"video/mp4"
                                              outEmbeddedManifestJUMBF:&embedded
                                                              error:&error];
    XCTAssertNotNil(ing, @"%@", error);
    XCTAssertNotNil(embedded);
    XCTAssertEqualObjects(ing.activeManifest.url,
                          ([NSString stringWithFormat:@"self#jumbf=/c2pa/%@", ingID]));
    XCTAssertEqualObjects(ing.claimSignature.url,
                          ([NSString stringWithFormat:@"self#jumbf=/c2pa/%@/c2pa.signature", ingID]));
    XCTAssertNotNil(ing.validationResults);
    // Child store labels active as "c2pa", not ingID — verify against parent store below.
    XCTAssertFalse([ing verifyEmbeddedManifestsInStore:childStore error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAIngredientAssertionErrorMissingTarget);

    NSData *parentMedia = [@"parent-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoS2PAHashDataAssertion *parentHash =
        [ATProtoS2PAHashDataAssertion assertionHardBindingMediaData:parentMedia name:nil error:&error];
    NSData *parentHashCBOR = [parentHash encodeCBOR:&error];
    NSData *ingCBOR = [ing encodeCBOR:&error];
    XCTAssertNotNil(ingCBOR, @"%@", error);
    NSArray *parentAssertions = @[
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashDataAssertionLabel
                                                  cbor:parentHashCBOR],
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAIngredientAssertionLabel
                                                  cbor:ingCBOR],
    ];
    NSData *parentBox =
        [ATProtoS2PAJUMBF uuidBoxSigningAssertions:parentAssertions
                                        instanceID:@"urn:uuid:parent-active"
                                    generatorName:@"garazyk-s2pa-parent"
                                embeddedManifests:@[embedded]
                                      withKeyPair:pair
                                              did:nil
                                        notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                         notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                            error:&error];
    XCTAssertNotNil(parentBox, @"%@", error);
    XCTAssertTrue([ATProtoS2PAJUMBF verifyUUIDBoxClaimBound:parentBox
                                               expectedDID:pair.didKeyString
                                                     error:&error],
                  @"%@", error);
    NSData *parentStore = [ATProtoS2PAJUMBF manifestStoreFromBMFFUUIDBox:parentBox error:&error];
    XCTAssertNotNil(parentStore, @"%@", error);
    XCTAssertTrue([ing verifyEmbeddedManifestsInStore:parentStore error:&error], @"%@", error);
}

- (void)testEmbeddedManifestTamperFails {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSError *error = nil;
    NSData *childMedia = [@"tamper-child" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoS2PAHashDataAssertion *childHash =
        [ATProtoS2PAHashDataAssertion assertionHardBindingMediaData:childMedia name:nil error:&error];
    NSData *childBox =
        [ATProtoS2PAJUMBF uuidBoxSigningAssertions:@[
            [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashDataAssertionLabel
                                                      cbor:[childHash encodeCBOR:&error]],
        ]
                                        instanceID:@"urn:uuid:tamper-child"
                                    generatorName:@"garazyk-s2pa"
                                      withKeyPair:pair
                                              did:nil
                                        notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                         notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                            error:&error];
    NSData *childStore = [ATProtoS2PAJUMBF manifestStoreFromBMFFUUIDBox:childBox error:&error];
    NSString *ingID = @"urn:uuid:tamper-ing";
    NSData *embedded = nil;
    ATProtoS2PAIngredientAssertion *ing =
        [ATProtoS2PAIngredientAssertion parentOfEmbeddingChildStore:childStore
                                                         instanceID:ingID
                                                              title:nil
                                                             format:nil
                                              outEmbeddedManifestJUMBF:&embedded
                                                              error:&error];
    XCTAssertNotNil(ing, @"%@", error);

    NSData *parentMedia = [@"tamper-parent" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoS2PAHashDataAssertion *parentHash =
        [ATProtoS2PAHashDataAssertion assertionHardBindingMediaData:parentMedia name:nil error:&error];
    NSData *parentBox =
        [ATProtoS2PAJUMBF uuidBoxSigningAssertions:@[
            [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashDataAssertionLabel
                                                      cbor:[parentHash encodeCBOR:&error]],
            [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAIngredientAssertionLabel
                                                      cbor:[ing encodeCBOR:&error]],
        ]
                                        instanceID:@"urn:uuid:tamper-parent"
                                    generatorName:@"garazyk-s2pa"
                                embeddedManifests:@[embedded]
                                      withKeyPair:pair
                                              did:nil
                                        notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                         notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                            error:&error];
    NSData *parentStore = [ATProtoS2PAJUMBF manifestStoreFromBMFFUUIDBox:parentBox error:&error];
    XCTAssertTrue([ing verifyEmbeddedManifestsInStore:parentStore error:&error], @"%@", error);

    // Flip a byte inside the embedded manifest body (past the 8-byte jumb header).
    NSMutableData *tamperedEmbedded = [embedded mutableCopy];
    XCTAssertGreaterThan(tamperedEmbedded.length, 16u);
    ((uint8_t *)tamperedEmbedded.mutableBytes)[tamperedEmbedded.length - 1] ^= 0x5a;
    NSData *tamperedBox =
        [ATProtoS2PAJUMBF uuidBoxSigningAssertions:@[
            [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashDataAssertionLabel
                                                      cbor:[parentHash encodeCBOR:&error]],
            [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAIngredientAssertionLabel
                                                      cbor:[ing encodeCBOR:&error]],
        ]
                                        instanceID:@"urn:uuid:tamper-parent-2"
                                    generatorName:@"garazyk-s2pa"
                                embeddedManifests:@[tamperedEmbedded]
                                      withKeyPair:pair
                                              did:nil
                                        notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                         notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                            error:&error];
    NSData *tamperedParentStore =
        [ATProtoS2PAJUMBF manifestStoreFromBMFFUUIDBox:tamperedBox error:&error];
    XCTAssertNotNil(tamperedParentStore, @"%@", error);
    XCTAssertFalse([ing verifyEmbeddedManifestsInStore:tamperedParentStore error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAIngredientAssertionErrorHashMismatch, @"%@", error);
}

@end
