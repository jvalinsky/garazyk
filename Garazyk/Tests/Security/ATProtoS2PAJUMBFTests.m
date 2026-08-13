// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Security/S2PA/ATProtoS2PACOSE.h"

@interface ATProtoS2PAJUMBFTests : XCTestCase
@end

@implementation ATProtoS2PAJUMBFTests

- (ATProtoSecp256k1KeyPair *)testKeyPair {
    uint8_t privateKeyBytes[32] = {0};
    privateKeyBytes[31] = 1;
    return [ATProtoSecp256k1KeyPair keyPairWithPrivateKey:[NSData dataWithBytes:privateKeyBytes
                                                                         length:32]
                                                     error:nil];
}

- (void)testUUIDBoxRoundTripAndVerify {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSData *payload = [@"muxl-segment-claim" dataUsingEncoding:NSUTF8StringEncoding];
    NSDate *notBefore = [NSDate dateWithTimeIntervalSince1970:1700000000];
    NSDate *notAfter = [NSDate dateWithTimeIntervalSince1970:1800000000];
    NSError *error = nil;
    NSData *box = [ATProtoS2PAJUMBF uuidBoxSigningPayload:payload
                                             withKeyPair:pair
                                                     did:nil
                                               notBefore:notBefore
                                                notAfter:notAfter
                                                   error:&error];
    XCTAssertNotNil(box);
    XCTAssertTrue([ATProtoS2PAJUMBF verifyUUIDBox:box
                                   expectedPayload:payload
                                       expectedDID:pair.didKeyString
                                             error:&error]);

    NSData *second = [ATProtoS2PAJUMBF uuidBoxSigningPayload:payload
                                                withKeyPair:pair
                                                        did:nil
                                                  notBefore:notBefore
                                                   notAfter:notAfter
                                                      error:&error];
    XCTAssertEqualObjects(box, second);
}

- (void)testPresentationPrependsWithoutAlteringMedia {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSData *payload = [@"claim" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *box = [ATProtoS2PAJUMBF uuidBoxSigningPayload:payload
                                             withKeyPair:pair
                                                     did:nil
                                               notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                                notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                                   error:nil];
    NSData *media = [NSData dataWithBytes:(const uint8_t[]){0xaa, 0xbb, 0xcc} length:3];
    NSError *error = nil;
    NSData *out = [ATProtoS2PAJUMBF presentationWithUUIDBox:box mediaData:media error:&error];
    XCTAssertNotNil(out);
    XCTAssertEqualObjects([out subdataWithRange:NSMakeRange(0, box.length)], box);
    XCTAssertEqualObjects([out subdataWithRange:NSMakeRange(box.length, media.length)], media);
}

- (void)testRejectsTamperedPayload {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSData *payload = [@"good" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *box = [ATProtoS2PAJUMBF uuidBoxSigningPayload:payload
                                             withKeyPair:pair
                                                     did:nil
                                               notBefore:[NSDate dateWithTimeIntervalSince1970:1]
                                                notAfter:[NSDate dateWithTimeIntervalSince1970:2]
                                                   error:nil];
    NSError *error = nil;
    BOOL ok = [ATProtoS2PAJUMBF verifyUUIDBox:box
                              expectedPayload:[@"bad" dataUsingEncoding:NSUTF8StringEncoding]
                                  expectedDID:nil
                                        error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqual(error.code, ATProtoS2PAJUMBFErrorVerificationFailed);
}

@end
