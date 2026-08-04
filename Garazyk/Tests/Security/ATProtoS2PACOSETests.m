// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PACOSE.h"
#import "Core/CBOR.h"

@interface ATProtoS2PACOSETests : XCTestCase
@end

@implementation ATProtoS2PACOSETests

- (Secp256k1KeyPair *)testKeyPair {
    uint8_t privateKeyBytes[32] = {0};
    privateKeyBytes[31] = 1;
    NSData *privateKey = [NSData dataWithBytes:privateKeyBytes length:sizeof(privateKeyBytes)];
    NSError *error = nil;
    Secp256k1KeyPair *pair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:&error];
    XCTAssertNotNil(pair, @"Fixed test key must be valid: %@", error);
    return pair;
}

- (void)testCanonicalProtectedHeadersAreCOSEIntegerMap {
    NSData *headers = [ATProtoS2PACOSE canonicalProtectedHeaders];
    const uint8_t expected[] = {0xA1, 0x01, 0x38, 0x2E};
    XCTAssertEqualObjects(headers, [NSData dataWithBytes:expected length:sizeof(expected)]);
}

- (void)testSigStructureMatchesCOSEShape {
    NSData *payload = [@"claim-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *structure = [ATProtoS2PACOSE sigStructureForPayload:payload error:nil];
    XCTAssertNotNil(structure);

    NSUInteger offset = 0;
    CBORValue *decoded = [CBORDecoder decode:structure offset:&offset];
    XCTAssertEqual(offset, structure.length);
    XCTAssertEqual(decoded.type, CBORTypeArray);
    XCTAssertEqual(decoded.array.count, 4U);
    XCTAssertEqualObjects(decoded.array[0].textString, @"Signature1");
    XCTAssertEqualObjects(decoded.array[1].byteString, [ATProtoS2PACOSE canonicalProtectedHeaders]);
    XCTAssertEqual(decoded.array[2].byteString.length, 0U);
    XCTAssertEqualObjects(decoded.array[3].byteString, payload);
}

- (void)testSignAndVerifyAttachedPayload {
    Secp256k1KeyPair *pair = [self testKeyPair];
    NSData *payload = [@"deterministic claim" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSData *envelope = [ATProtoS2PACOSE signPayload:payload withKeyPair:pair error:&error];
    XCTAssertNotNil(envelope, @"Signing must succeed: %@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects([ATProtoS2PACOSE payloadFromEnvelope:envelope error:&error], payload);
    XCTAssertTrue([ATProtoS2PACOSE verifyEnvelope:envelope withPublicKey:pair.compressedPublicKey error:&error]);
    XCTAssertNil(error);
}

- (void)testSigningIsDeterministic {
    Secp256k1KeyPair *pair = [self testKeyPair];
    NSData *payload = [@"same bytes" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *first = [ATProtoS2PACOSE signPayload:payload withKeyPair:pair error:nil];
    NSData *second = [ATProtoS2PACOSE signPayload:payload withKeyPair:pair error:nil];
    XCTAssertEqualObjects(first, second);
}

- (void)testPayloadTamperingFailsVerification {
    Secp256k1KeyPair *pair = [self testKeyPair];
    NSData *originalPayload = [@"original" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signedEnvelope = [ATProtoS2PACOSE signPayload:originalPayload
                                             withKeyPair:pair
                                                    error:nil];

    // Rebuild the fixed four-field COSE_Sign1 shape with a changed attached
    // payload. This deliberately preserves a valid envelope so the assertion
    // exercises cryptographic failure rather than parser rejection.
    NSUInteger offset = 0;
    CBORValue *decoded = [CBORDecoder decode:signedEnvelope offset:&offset];
    XCTAssertEqual(offset, signedEnvelope.length);
    NSMutableData *tamperedPayload = [originalPayload mutableCopy];
    ((uint8_t *)tamperedPayload.mutableBytes)[0] ^= 0x01;
    CBORValue *tampered = [CBORValue array:@[
        decoded.array[0], decoded.array[1],
        [CBORValue byteString:tamperedPayload], decoded.array[3]
    ]];

    NSError *error = nil;
    XCTAssertFalse([ATProtoS2PACOSE verifyEnvelope:tampered.encode
                                      withPublicKey:pair.publicKey
                                              error:&error]);
    XCTAssertNotNil(error);
}

- (void)testWrongPublicKeyFailsVerification {
    Secp256k1KeyPair *signer = [self testKeyPair];
    Secp256k1KeyPair *other = [Secp256k1KeyPair keyPairWithPrivateKey:
        [NSData dataWithBytes:(uint8_t[32]){0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2} length:32]
                                                                 error:nil];
    NSData *envelope = [ATProtoS2PACOSE signPayload:[NSData data] withKeyPair:signer error:nil];
    NSError *error = nil;
    XCTAssertFalse([ATProtoS2PACOSE verifyEnvelope:envelope withPublicKey:other.publicKey error:&error]);
    XCTAssertNotNil(error);
}

- (void)testRejectsUnsupportedAlgorithm {
    CBORValue *protectedMap = [CBORValue map:@{
        [CBORValue unsignedInteger:1]: [CBORValue negativeInteger:-7]
    }];
    CBORValue *envelope = [CBORValue array:@[
        [CBORValue byteString:protectedMap.encode],
        [CBORValue map:@{}],
        [CBORValue byteString:[NSData data]],
        [CBORValue byteString:[NSMutableData dataWithLength:64]]
    ]];
    NSError *error = nil;
    XCTAssertNil([ATProtoS2PACOSE payloadFromEnvelope:envelope.encode error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAErrorUnsupportedAlgorithm);
}

- (void)testRejectsNonCanonicalEnvelopeEncoding {
    // The empty unprotected map is encoded with a non-minimal map length.
    const uint8_t nonCanonical[] = {
        0x84, 0x44, 0xA1, 0x01, 0x38, 0x2E,
        0xB8, 0x00,
        0x40,
        0x58, 0x40,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    };
    NSError *error = nil;
    XCTAssertNil([ATProtoS2PACOSE payloadFromEnvelope:
                  [NSData dataWithBytes:nonCanonical length:sizeof(nonCanonical)] error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PAErrorNonCanonicalEncoding);
}

- (void)testVerificationDoesNotConsultTrustAnchors {
    Secp256k1KeyPair *pair = [self testKeyPair];
    NSData *envelope = [ATProtoS2PACOSE signPayload:[NSData data] withKeyPair:pair error:nil];
    NSError *error = nil;
    XCTAssertTrue([ATProtoS2PACOSE verifyEnvelope:envelope withPublicKey:pair.publicKey error:&error]);
    XCTAssertNil(error);
}

@end
