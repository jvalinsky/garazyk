// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Core/ATProtoMultibase.h"
#import "Core/CID.h"
#import "Core/DID.h"

@interface ATProtoMultibaseTests : XCTestCase
@end

@implementation ATProtoMultibaseTests

- (void)testPublicKeyBytesStripsSecp256k1MulticodecPrefix {
    const uint8_t encodedBytes[] = { 0xE7, 0x01, 0x03, 0x04, 0x05 };
    NSData *encoded = [NSData dataWithBytes:encodedBytes length:sizeof(encodedBytes)];
    NSString *multibase = [@"z" stringByAppendingString:[ATProtoCID base58btcEncode:encoded]];

    NSError *error = nil;
    NSData *decoded = [ATProtoMultibase publicKeyBytesFromMultibase:multibase error:&error];

    const uint8_t expectedBytes[] = { 0x03, 0x04, 0x05 };
    NSData *expected = [NSData dataWithBytes:expectedBytes length:sizeof(expectedBytes)];
    XCTAssertEqualObjects(decoded, expected);
    XCTAssertNil(error);
}

- (void)testPublicKeyBytesRejectsUnsupportedMultibasePrefix {
    NSError *error = nil;

    XCTAssertNil([ATProtoMultibase publicKeyBytesFromMultibase:@"xnot-supported" error:&error]);
    XCTAssertEqualObjects(error.domain, DIDErrorDomain);
    XCTAssertEqual(error.code, DIDErrorInvalidDocument);
}

@end
