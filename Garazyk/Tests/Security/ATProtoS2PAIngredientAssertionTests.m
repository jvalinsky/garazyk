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

- (void)testParentOfRoundTrip {
    ATProtoS2PAHashedURI *manifest =
        [self dummyHashedURI:@"self#jumbf=/c2pa/urn:c2pa:parent-1"];
    ATProtoS2PAHashedURI *sig =
        [self dummyHashedURI:@"self#jumbf=/c2pa/urn:c2pa:parent-1/c2pa.signature"];
    NSError *error = nil;
    ATProtoS2PAIngredientAssertion *a =
        [ATProtoS2PAIngredientAssertion parentOfWithTitle:@"source"
                                                   format:@"video/mp4"
                                               instanceID:@"urn:uuid:ing-1"
                                           activeManifest:manifest
                                           claimSignature:sig
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
                  claimSignature:nil];
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

@end
