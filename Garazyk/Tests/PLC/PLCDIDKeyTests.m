// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "PLC/PLCDIDKey.h"
#import "Auth/Secp256k1.h"
#import "Core/CID.h"

@interface PLCDIDKeyTests : XCTestCase
@end

@implementation PLCDIDKeyTests

- (void)testParseSecp256k1DidKey {
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(keyPair);
    XCTAssertNil(error);

    NSString *didKey = [keyPair didKeyString];
    XCTAssertTrue([didKey hasPrefix:@"did:key:z"]);

    PLCDIDKey *parsed = [PLCDIDKey parseFromString:didKey error:&error];
    XCTAssertNotNil(parsed);
    XCTAssertNil(error);
    XCTAssertEqual(parsed.type, PLCDIDKeyTypeSecp256k1);
    XCTAssertEqual(parsed.publicKeyBytes.length, 33u);
}

- (void)testParseP256DidKeyFromFixtureString {
    // This is a real did:key used in PLC tests; it decodes to multicodec 0x1200 (p256-pub)
    NSString *didKey = @"did:key:zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX";

    NSError *error = nil;
    PLCDIDKey *parsed = [PLCDIDKey parseFromString:didKey error:&error];
    XCTAssertNotNil(parsed);
    XCTAssertNil(error);
    XCTAssertEqual(parsed.type, PLCDIDKeyTypeP256);
    XCTAssertEqual(parsed.publicKeyBytes.length, 33u);

    const uint8_t first = ((const uint8_t *)parsed.publicKeyBytes.bytes)[0];
    XCTAssertTrue(first == 0x02 || first == 0x03);
}

- (void)testParseReturnsErrorForUnsupportedMultibasePrefix {
    NSError *error = nil;
    PLCDIDKey *parsed = [PLCDIDKey parseFromString:@"did:key:babc" error:&error];
    XCTAssertNil(parsed);
    XCTAssertNotNil(error);
}

- (void)testParseReturnsErrorForUnsupportedMulticodec {
    // Construct a did:key with an unsupported multicodec prefix (ed25519-pub: 0xed 0x01)
    uint8_t bytes[] = {0xED, 0x01, 0x02, 0xAA};
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    NSString *payload = [CID base58btcEncode:data];
    NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", payload];

    NSError *error = nil;
    PLCDIDKey *parsed = [PLCDIDKey parseFromString:didKey error:&error];
    XCTAssertNil(parsed);
    XCTAssertNotNil(error);
}

@end

