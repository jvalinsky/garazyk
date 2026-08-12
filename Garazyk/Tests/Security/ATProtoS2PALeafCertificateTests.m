// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PALeafCertificate.h"

@interface ATProtoS2PALeafCertificateTests : XCTestCase
@end

@implementation ATProtoS2PALeafCertificateTests

- (ATProtoSecp256k1KeyPair *)testKeyPair {
    uint8_t privateKeyBytes[32] = {0};
    privateKeyBytes[31] = 1;
    return [ATProtoSecp256k1KeyPair keyPairWithPrivateKey:[NSData dataWithBytes:privateKeyBytes
                                                                         length:32]
                                                     error:nil];
}

- (void)testMintIsDeterministicAndSelfVerifying {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSDate *notBefore = [NSDate dateWithTimeIntervalSince1970:1700000000];
    NSDate *notAfter = [NSDate dateWithTimeIntervalSince1970:1700000000 + 3600 * 24 * 365];
    NSError *error = nil;
    NSData *first = [ATProtoS2PALeafCertificate certificateWithKeyPair:pair
                                                                   did:nil
                                                             notBefore:notBefore
                                                              notAfter:notAfter
                                                                 error:&error];
    XCTAssertNotNil(first, @"%@", error);
    XCTAssertNil(error);
    NSData *second = [ATProtoS2PALeafCertificate certificateWithKeyPair:pair
                                                                    did:nil
                                                              notBefore:notBefore
                                                               notAfter:notAfter
                                                                  error:&error];
    XCTAssertEqualObjects(first, second);
    XCTAssertTrue([ATProtoS2PALeafCertificate verifyCertificate:first
                                                    expectedDID:pair.didKeyString
                                                          error:&error], @"%@", error);
}

- (void)testExplicitDIDBinding {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSString *did = @"did:web:example.com";
    NSDate *notBefore = [NSDate dateWithTimeIntervalSince1970:1609459200];
    NSDate *notAfter = [NSDate dateWithTimeIntervalSince1970:1924992000]; // 2030
    NSError *error = nil;
    NSData *cert = [ATProtoS2PALeafCertificate certificateWithKeyPair:pair
                                                                  did:did
                                                            notBefore:notBefore
                                                             notAfter:notAfter
                                                                error:&error];
    XCTAssertNotNil(cert);
    XCTAssertTrue([ATProtoS2PALeafCertificate verifyCertificate:cert expectedDID:did error:&error]);
    XCTAssertFalse([ATProtoS2PALeafCertificate verifyCertificate:cert
                                                     expectedDID:@"did:web:other.example"
                                                           error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PALeafErrorVerificationFailed);
}

- (void)testRejectsInvalidValidityWindow {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSDate *t = [NSDate dateWithTimeIntervalSince1970:1700000000];
    NSError *error = nil;
    XCTAssertNil([ATProtoS2PALeafCertificate certificateWithKeyPair:pair
                                                                did:nil
                                                          notBefore:t
                                                           notAfter:t
                                                              error:&error]);
    XCTAssertEqual(error.code, ATProtoS2PALeafErrorInvalidArgument);
}

- (void)testSubjectKeyIdentifierIsSHA1OfUncompressedKey {
    ATProtoSecp256k1KeyPair *pair = [self testKeyPair];
    NSData *ski = [ATProtoS2PALeafCertificate subjectKeyIdentifierForPublicKey:pair.publicKey];
    XCTAssertEqual(ski.length, (NSUInteger)20);
    NSData *cert = [ATProtoS2PALeafCertificate certificateWithKeyPair:pair
                                                                  did:nil
                                                            notBefore:[NSDate dateWithTimeIntervalSince1970:1700000000]
                                                             notAfter:[NSDate dateWithTimeIntervalSince1970:1800000000]
                                                                error:nil];
    NSRange found = [cert rangeOfData:ski options:0 range:NSMakeRange(0, cert.length)];
    XCTAssertNotEqual(found.location, (NSUInteger)NSNotFound);
}

@end
