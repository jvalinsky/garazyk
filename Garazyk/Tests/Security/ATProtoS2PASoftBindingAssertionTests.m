// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PASoftBindingAssertion.h"
#import "Security/S2PA/ATProtoS2PAHashDataAssertion.h"
#import "Security/S2PA/ATProtoS2PAClaim.h"
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Auth/Crypto/Secp256k1.h"
#import <CommonCrypto/CommonDigest.h>

@interface ATProtoS2PASoftBindingAssertionTests : XCTestCase
@end

@implementation ATProtoS2PASoftBindingAssertionTests

- (ATProtoSecp256k1KeyPair *)testKeyPair {
    uint8_t privateKeyBytes[32] = {0};
    privateKeyBytes[31] = 19;
    return [ATProtoSecp256k1KeyPair keyPairWithPrivateKey:[NSData dataWithBytes:privateKeyBytes
                                                                         length:32]
                                                     error:nil];
}

- (void)testRoundTripWithTimespan {
    ATProtoS2PASoftBindingBlock *b0 =
        [ATProtoS2PASoftBindingBlock blockWithValue:[@"v1" dataUsingEncoding:NSUTF8StringEncoding]
                                           timespan:[ATProtoS2PASoftBindingTimespan timespanWithStart:0
                                                                                                  end:100]];
    ATProtoS2PASoftBindingBlock *b1 =
        [ATProtoS2PASoftBindingBlock blockWithValue:[@"v2" dataUsingEncoding:NSUTF8StringEncoding]
                                           timespan:nil];
    ATProtoS2PASoftBindingAssertion *a =
        [[ATProtoS2PASoftBindingAssertion alloc] initWithAlg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                                                      blocks:@[ b0, b1 ]
                                                        name:ATProtoS2PASoftBindingAssertionLabel
                                                   algParams:nil];
    NSError *error = nil;
    NSData *cbor = [a encodeCBOR:&error];
    XCTAssertNotNil(cbor, @"%@", error);
    ATProtoS2PASoftBindingAssertion *round =
        [ATProtoS2PASoftBindingAssertion assertionFromCBOR:cbor error:&error];
    XCTAssertNotNil(round, @"%@", error);
    XCTAssertEqualObjects(round.alg, ATProtoS2PASoftBindingAlgorithmMonolithSHA256);
    XCTAssertEqual(round.blocks.count, (NSUInteger)2);
    XCTAssertEqual(round.blocks[0].timespan.start, (NSUInteger)0);
    XCTAssertEqual(round.blocks[0].timespan.end, (NSUInteger)100);
    XCTAssertNil(round.blocks[1].timespan);
}

- (void)testRejectsEmptyBlocks {
    ATProtoS2PASoftBindingAssertion *a =
        [[ATProtoS2PASoftBindingAssertion alloc] initWithAlg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                                                      blocks:@[]
                                                        name:nil
                                                   algParams:nil];
    NSError *error = nil;
    XCTAssertNil([a encodeCBOR:&error]);
    XCTAssertEqual(error.code, ATProtoS2PASoftBindingAssertionErrorInvalidArgument);
}

- (void)testMonolithSHA256ComputeIsDeterministic {
    NSData *media = [@"soft-bind-fixture" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSData *v1 = [ATProtoS2PASoftBindingAssertion computeValueForData:media
                                                                  alg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                                                            algParams:nil
                                                                error:&error];
    NSData *v2 = [ATProtoS2PASoftBindingAssertion computeValueForData:media
                                                                  alg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                                                            algParams:nil
                                                                error:&error];
    XCTAssertNotNil(v1, @"%@", error);
    XCTAssertEqual(v1.length, (NSUInteger)CC_SHA256_DIGEST_LENGTH);
    XCTAssertEqualObjects(v1, v2);

    uint8_t expected[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(media.bytes, (CC_LONG)media.length, expected);
    XCTAssertEqualObjects(v1, [NSData dataWithBytes:expected length:sizeof(expected)]);

    XCTAssertNil([ATProtoS2PASoftBindingAssertion computeValueForData:media
                                                                  alg:@"phash"
                                                            algParams:nil
                                                                error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PASoftBindingAssertionErrorUnsupportedAlgorithm);
}

- (void)testVerifyMatchAndMismatch {
    NSData *media = [@"verify-soft" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoS2PASoftBindingAssertion *a =
        [ATProtoS2PASoftBindingAssertion assertionMonolithSHA256ForData:media
                                                               timespan:nil
                                                                   name:nil
                                                                  error:&error];
    XCTAssertNotNil(a, @"%@", error);
    XCTAssertTrue([a verifyAgainstData:media timespan:nil error:&error], @"%@", error);

    NSMutableData *tampered = [media mutableCopy];
    ((uint8_t *)tampered.mutableBytes)[0] ^= 0xff;
    XCTAssertFalse([a verifyAgainstData:tampered timespan:nil error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PASoftBindingAssertionErrorMismatch);
}

- (void)testTimespanSelectsBlock {
    NSData *whole = [@"whole-asset" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *clip = [@"clip-asset" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSData *wholeVal =
        [ATProtoS2PASoftBindingAssertion computeValueForData:whole
                                                         alg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                                                   algParams:nil
                                                       error:&error];
    NSData *clipVal =
        [ATProtoS2PASoftBindingAssertion computeValueForData:clip
                                                         alg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                                                   algParams:nil
                                                       error:&error];
    ATProtoS2PASoftBindingTimespan *span =
        [ATProtoS2PASoftBindingTimespan timespanWithStart:10 end:20];
    ATProtoS2PASoftBindingAssertion *a =
        [[ATProtoS2PASoftBindingAssertion alloc]
            initWithAlg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                 blocks:@[
                     [ATProtoS2PASoftBindingBlock blockWithValue:wholeVal timespan:nil],
                     [ATProtoS2PASoftBindingBlock blockWithValue:clipVal timespan:span],
                 ]
                   name:nil
              algParams:nil];
    XCTAssertTrue([a verifyAgainstData:whole timespan:nil error:&error], @"%@", error);
    XCTAssertTrue([a verifyAgainstData:clip timespan:span error:&error], @"%@", error);
    XCTAssertFalse([a verifyAgainstData:whole timespan:span error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PASoftBindingAssertionErrorMismatch);
}

- (void)testClaimBoundHardPlusSoftDoesNotReplaceHard {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSError *error = nil;
    NSData *media = [@"hard-and-soft" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoS2PAHashDataAssertion *hard =
        [ATProtoS2PAHashDataAssertion assertionHardBindingMediaData:media name:nil error:&error];
    XCTAssertNotNil(hard, @"%@", error);
    ATProtoS2PASoftBindingAssertion *soft =
        [ATProtoS2PASoftBindingAssertion assertionMonolithSHA256ForData:media
                                                               timespan:nil
                                                                   name:nil
                                                                  error:&error];
    XCTAssertNotNil(soft, @"%@", error);
    NSArray *assertions = @[
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PAHashDataAssertionLabel
                                                  cbor:[hard encodeCBOR:&error]],
        [ATProtoS2PAStoredAssertion assertionWithLabel:ATProtoS2PASoftBindingAssertionLabel
                                                  cbor:[soft encodeCBOR:&error]],
    ];
    NSData *box = [ATProtoS2PAJUMBF uuidBoxSigningAssertions:assertions
                                                  instanceID:@"urn:uuid:soft-claim"
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
    XCTAssertTrue([hard verifyAgainstData:media error:&error], @"%@", error);
    XCTAssertTrue([soft verifyAgainstData:media timespan:nil error:&error], @"%@", error);
    NSMutableData *tampered = [media mutableCopy];
    ((uint8_t *)tampered.mutableBytes)[0] ^= 0xff;
    XCTAssertFalse([hard verifyAgainstData:tampered error:&error]);
    XCTAssertFalse([soft verifyAgainstData:tampered timespan:nil error:&error]);
}

@end
