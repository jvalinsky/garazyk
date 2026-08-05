// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "Core/CID.h"
#import "Core/TID.h"
#import "Core/DID.h"
#import "Core/CBOR.h"
#import "Repository/MST.h"
#import "Auth/Crypto/JWT.h"
#import "Auth/Crypto/Secp256k1.h"

@interface ATProtoCoreTests : XCTestCase
@end

@implementation ATProtoCoreTests

- (ATProtoJWTMinter *)testMinterWithPublicKey:(NSData **)publicKeyOut {
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [ATProtoSecp256k1KeyPair generateKeyPair:&keyError];
    XCTAssertNotNil(keyPair, @"Failed to generate test key pair: %@", keyError);
    if (!keyPair) return nil;

    ATProtoJWTMinter *minter = [[ATProtoJWTMinter alloc] init];
    minter.issuer = @"test-issuer";
    minter.signingAlgorithm = @"ES256K";
    minter.privateKey = keyPair.privateKey;
    minter.publicKey = keyPair.publicKey;
    if (publicKeyOut) {
        *publicKeyOut = keyPair.publicKey;
    }
    return minter;
}

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - ATProtoCID Tests

- (void)testCIDCreation {
    NSData *digest = [ATProtoCID sha256Digest:[@"hello world" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid = [ATProtoCID cidWithDigest:digest codec:0x71];

    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.version, 1);
    XCTAssertEqual(cid.codec, 0x71);
    XCTAssertNotNil(cid.multihash);
}

- (void)testCIDStringValue {
    NSData *digest = [ATProtoCID sha256Digest:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid = [ATProtoCID cidWithDigest:digest codec:0x71];
    NSString *stringValue = [cid stringValue];

    XCTAssertNotNil(stringValue);
    XCTAssertTrue([stringValue hasPrefix:@"b"]);
}

- (void)testCIDEquality {
    NSData *digest = [ATProtoCID sha256Digest:[@"same data" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid1 = [ATProtoCID cidWithDigest:digest codec:0x71];
    ATProtoCID *cid2 = [ATProtoCID cidWithDigest:digest codec:0x71];

    XCTAssertEqualObjects(cid1, cid2);
    XCTAssertTrue([cid1 isEqualToCID:cid2]);
}

- (void)testCIDBytesReturnsNonEmptyData {
    NSData *digest = [ATProtoCID sha256Digest:[@"bytes test" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid = [ATProtoCID cidWithDigest:digest codec:0x71];
    NSData *bytes = [cid bytes];

    XCTAssertNotNil(bytes);
    XCTAssertGreaterThan(bytes.length, 0);
}

- (void)testCIDSHA256 {
    NSData *data = [@"sha256 test" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCID sha256:data];

    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.codec, 0x55);
}

- (void)testCIDFromStringMaxLength {
    NSMutableString *longString = [NSMutableString stringWithString:@"b"];
    for (int i = 0; i < 300; i++) {
        [longString appendString:@"a"];
    }
    XCTAssertNil([ATProtoCID cidFromString:longString], @"Should reject CID string > 256 chars");
}

- (void)testCIDFromBytesMaxLength {
    NSMutableData *longData = [NSMutableData dataWithCapacity:300];
    uint8_t versionByte = 0x01;
    [longData appendBytes:&versionByte length:1];
    uint8_t codecByte = 0x71;
    [longData appendBytes:&codecByte length:1];
    for (int i = 0; i < 300; i++) {
        uint8_t byte = 0x12;
        [longData appendBytes:&byte length:1];
    }
    XCTAssertNil([ATProtoCID cidFromBytes:longData], @"Should reject CID bytes > 256");
}

- (void)testCIDFromEmptyString {
    XCTAssertNil([ATProtoCID cidFromString:@""]);
    XCTAssertNil([ATProtoCID cidFromString:nil]);
}

- (void)testCIDFromBufferReportsConsumedLength {
    NSData *digest = [ATProtoCID sha256Digest:[@"buffer-consume" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *original = [ATProtoCID cidWithDigest:digest codec:0x71];
    NSData *cidBytes = original.bytes;

    NSMutableData *withTrailer = [NSMutableData dataWithData:cidBytes];
    uint8_t trailer[] = {0xDE, 0xAD, 0xBE, 0xEF};
    [withTrailer appendBytes:trailer length:sizeof(trailer)];

    NSUInteger consumed = 0;
    ATProtoCID *parsed = [ATProtoCID cidFromBuffer:withTrailer.bytes length:withTrailer.length consumed:&consumed];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(consumed, cidBytes.length);
    XCTAssertTrue([parsed isEqualToCID:original]);
}

- (void)testCIDFromBufferCIDv0 {
    uint8_t v0[34] = {0x12, 0x20};
    for (int i = 2; i < 34; i++) v0[i] = (uint8_t)i;
    NSMutableData *buffer = [NSMutableData dataWithBytes:v0 length:34];
    uint8_t junk[] = {0x01, 0x02, 0x03};
    [buffer appendBytes:junk length:sizeof(junk)];

    NSUInteger consumed = 0;
    ATProtoCID *parsed = [ATProtoCID cidFromBuffer:buffer.bytes length:buffer.length consumed:&consumed];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(consumed, (NSUInteger)34);
    XCTAssertEqual(parsed.version, (NSUInteger)0);
}

- (void)testCIDFromBufferRejectsTruncatedVarint {
    uint8_t truncated[] = {0x81}; // continuation bit set, no next byte
    NSUInteger consumed = 999;
    ATProtoCID *parsed = [ATProtoCID cidFromBuffer:truncated length:sizeof(truncated) consumed:&consumed];
    XCTAssertNil(parsed);
}

- (void)testCIDFromBufferRejectsOversizeMultihash {
    // version=1, codec=0x71 (dag-cbor), mh_code=0x12, mh_len = 0xFFFFFFFF (varint)
    uint8_t hostile[] = {0x01, 0x71, 0x12, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F};
    NSUInteger consumed = 999;
    ATProtoCID *parsed = [ATProtoCID cidFromBuffer:hostile length:sizeof(hostile) consumed:&consumed];
    XCTAssertNil(parsed);
}

- (void)testCIDFromBufferAcceptsArbitraryCodec {
    NSData *digest = [ATProtoCID sha256Digest:[@"raw-codec" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *rawCID = [ATProtoCID cidWithDigest:digest codec:0x55]; // raw
    NSData *cidBytes = rawCID.bytes;

    NSUInteger consumed = 0;
    ATProtoCID *parsed = [ATProtoCID cidFromBuffer:cidBytes.bytes length:cidBytes.length consumed:&consumed];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(consumed, cidBytes.length);
    XCTAssertEqual(parsed.codec, (NSUInteger)0x55);
    XCTAssertTrue([parsed isEqualToCID:rawCID]);
}

- (void)testCIDFromEmptyBytes {
    XCTAssertNil([ATProtoCID cidFromBytes:[NSData data]]);
    XCTAssertNil([ATProtoCID cidFromBytes:nil]);
}

- (void)testCIDValidLength {
    NSData *digest = [ATProtoCID sha256Digest:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid = [ATProtoCID cidWithDigest:digest codec:0x71];
    NSString *stringValue = cid.stringValue;
    
    XCTAssertLessThanOrEqual(stringValue.length, 256, @"Valid CID should be <= 256 chars");
    
    ATProtoCID *parsed = [ATProtoCID cidFromString:stringValue];
    XCTAssertNotNil(parsed, @"Should parse valid CID string");
    XCTAssertEqualObjects(parsed.stringValue, stringValue);
}

#pragma mark - ATProtoTID Tests

- (void)testTIDGeneration {
    NSString *tid1 = [[ATProtoTID tid] stringValue];
    NSString *tid2 = [[ATProtoTID tid] stringValue];

    XCTAssertNotNil(tid1);
    XCTAssertNotNil(tid2);
    XCTAssertEqual(tid1.length, 13);
}

- (void)testTIDUniqueness {
    NSMutableSet<NSString *> *tids = [NSMutableSet set];
    for (int i = 0; i < 100; i++) {
        [tids addObject:[[ATProtoTID tid] stringValue]];
    }
    XCTAssertEqual(tids.count, 100);
}

- (void)testTIDOrderingYieldsDescending {
    NSString *tid1 = [[ATProtoTID tid] stringValue];
    [NSThread sleepForTimeInterval:0.01];
    NSString *tid2 = [[ATProtoTID tid] stringValue];

    XCTAssertTrue([tid2 compare:tid1] == NSOrderedDescending);
}

#pragma mark - DID Tests

/* Removed tests for non-existent DID class
- (void)testDIDWebParsingReturnsParsedObject {
    NSString *did = @"did:web:example.com";
    DID *parsed = [DID didWithString:did];

    XCTAssertNotNil(parsed);
    XCTAssertEqualObjects(parsed.method, @"web");
}

- (void)testDIDEquality {
    DID *did1 = [DID didWithString:@"did:web:test.com"];
    DID *did2 = [DID didWithString:@"did:web:test.com"];

    XCTAssertEqualObjects(did1, did2);
}
*/

#pragma mark - CBOR Tests

- (void)testCBORIntegerEncoding {
    ATProtoCBORValue *value = [ATProtoCBORValue unsignedInteger:42];
    NSData *encoded = [value encode];

    XCTAssertNotNil(encoded);
    XCTAssertEqual(encoded.length, 2);
    XCTAssertEqual(((uint8_t *)encoded.bytes)[0], 0x18);
    XCTAssertEqual(((uint8_t *)encoded.bytes)[1], 42);
}

- (void)testEncodeTextStringReturnsNonEmptyData {
    ATProtoCBORValue *value = [ATProtoCBORValue textString:@"hello"];
    NSData *encoded = [value encode];

    XCTAssertNotNil(encoded);
    XCTAssertGreaterThan(encoded.length, 0);
}

- (void)testEncodeArrayReturnsNonEmptyData {
    NSArray<ATProtoCBORValue *> *array = @[
        [ATProtoCBORValue unsignedInteger:1],
        [ATProtoCBORValue unsignedInteger:2],
        [ATProtoCBORValue unsignedInteger:3]
    ];
    ATProtoCBORValue *value = [ATProtoCBORValue array:array];
    NSData *encoded = [value encode];

    XCTAssertNotNil(encoded);
    XCTAssertGreaterThan(encoded.length, 0);
}

- (void)testEncodeMapReturnsNonEmptyData {
    NSMutableDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *map = [NSMutableDictionary dictionary];
    map[[ATProtoCBORValue textString:@"key"]] = [ATProtoCBORValue textString:@"value"];
    ATProtoCBORValue *value = [ATProtoCBORValue map:map];
    NSData *encoded = [value encode];

    XCTAssertNotNil(encoded);
    XCTAssertGreaterThan(encoded.length, 0);
}

- (void)testCBORRoundTripYieldsMap {
    NSMutableDictionary<ATProtoCBORValue *, ATProtoCBORValue *> *original = [NSMutableDictionary dictionary];
    original[[ATProtoCBORValue textString:@"name"]] = [ATProtoCBORValue textString:@"test"];
    original[[ATProtoCBORValue textString:@"count"]] = [ATProtoCBORValue unsignedInteger:42];
    original[[ATProtoCBORValue textString:@"nested"]] = [ATProtoCBORValue map:@{
        [ATProtoCBORValue textString:@"inner"]: [ATProtoCBORValue textString:@"value"]
    }];

    NSData *encoded = [[ATProtoCBORValue map:original] encode];
    ATProtoCBORValue *decoded = [ATProtoCBORValue decode:encoded];

    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.type, CBORTypeMap);
}

#pragma mark - MST Tests

- (void)testMSTBasicOperationsGetEqualsObject {
    MST *mst = [[MST alloc] init];

    ATProtoCID *cid1 = [ATProtoCID sha256:[@"value1" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid2 = [ATProtoCID sha256:[@"value2" dataUsingEncoding:NSUTF8StringEncoding]];

    [mst put:@"key1" valueCID:cid1];
    [mst put:@"key2" valueCID:cid2 subKey:@"sub1"];

    XCTAssertEqualObjects([mst get:@"key1"], cid1);
    XCTAssertEqualObjects([mst get:@"key2" subKey:@"sub1"], cid2);
}

- (void)testMSTDelete {
    MST *mst = [[MST alloc] init];
    ATProtoCID *cid = [ATProtoCID sha256:[@"delete test" dataUsingEncoding:NSUTF8StringEncoding]];

    [mst put:@"deleteMe" valueCID:cid];
    XCTAssertNotNil([mst get:@"deleteMe"]);

    [mst delete:@"deleteMe"];
    XCTAssertNil([mst get:@"deleteMe"]);
}

- (void)testMSTAllEntries {
    MST *mst = [[MST alloc] init];

    for (int i = 0; i < 10; i++) {
        ATProtoCID *cid = [ATProtoCID sha256:[[NSString stringWithFormat:@"entry%d", i] dataUsingEncoding:NSUTF8StringEncoding]];
        [mst put:[NSString stringWithFormat:@"key%d", i] valueCID:cid];
    }

    NSArray<MSTEntry *> *entries = [mst allEntries];
    XCTAssertEqual(entries.count, 10);
}

- (void)testEntriesWithPrefixReturnsExpectedCount {
    MST *mst = [[MST alloc] init];

    ATProtoCID *cid1 = [ATProtoCID sha256:[@"app.bsky.feed.post1" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid2 = [ATProtoCID sha256:[@"app.bsky.feed.post2" dataUsingEncoding:NSUTF8StringEncoding]];
    ATProtoCID *cid3 = [ATProtoCID sha256:[@"app.bsky.actor.profile" dataUsingEncoding:NSUTF8StringEncoding]];

    [mst put:@"app.bsky.feed.post1" valueCID:cid1];
    [mst put:@"app.bsky.feed.post2" valueCID:cid2];
    [mst put:@"app.bsky.actor.profile" valueCID:cid3];

    NSArray<MSTEntry *> *feedEntries = [mst entriesWithPrefix:@"app.bsky.feed."];
    XCTAssertEqual(feedEntries.count, 2);
}

- (void)testMSTCBORSerialization {
    MST *mst = [[MST alloc] init];
    ATProtoCID *cid = [ATProtoCID sha256:[@"cbor test" dataUsingEncoding:NSUTF8StringEncoding]];
    [mst put:@"testKey" valueCID:cid];

    NSData *cborData = [mst serializeToCBOR];
    XCTAssertNotNil(cborData);

    MST *deserialized = [MST deserializeFromCBOR:cborData];
    XCTAssertNotNil(deserialized);
    XCTAssertEqualObjects([deserialized get:@"testKey"], cid);
}

#pragma mark - ATProtoJWT Tests

- (void)testJWTMintingProducesThreeParts {
    ATProtoJWTMinter *minter = [self testMinterWithPublicKey:nil];

    NSString *token = [minter signPayload:@{
        @"sub": @"did:web:test.com",
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"exp": @([[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970])
    } error:nil];

    XCTAssertNotNil(token);
    NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
    XCTAssertEqual(parts.count, 3);
}

- (void)testJWTParsing {
    ATProtoJWTMinter *minter = [self testMinterWithPublicKey:nil];

    NSString *token = [minter signPayload:@{
        @"sub": @"did:web:test.com",
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"exp": @([[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970])
    } error:nil];

    ATProtoJWT *jwt = [ATProtoJWT jwtWithToken:token error:nil];
    XCTAssertNotNil(jwt);
    XCTAssertNotNil(jwt.header);
    XCTAssertNotNil(jwt.payload);
    XCTAssertEqualObjects(jwt.payload.sub, @"did:web:test.com");
}

- (void)testJWTVerificationSucceeds {
    NSData *publicKey = nil;
    ATProtoJWTMinter *minter = [self testMinterWithPublicKey:&publicKey];

    ATProtoJWTVerifier *verifier = [[ATProtoJWTVerifier alloc] init];
    verifier.expectedIssuer = @"test-issuer";
    verifier.allowedAlgorithms = @[@"ES256K"];
    verifier.publicKey = publicKey;

    NSString *token = [minter signPayload:@{
        @"sub": @"did:web:test.com",
        @"iss": @"test-issuer",
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"exp": @([[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970])
    } error:nil];

    ATProtoJWT *jwt = [ATProtoJWT jwtWithToken:token error:nil];
    XCTAssertNotNil(jwt);

    NSError *error = nil;
    BOOL valid = [verifier verifyJWT:jwt error:&error];
    XCTAssertTrue(valid);
}

- (void)testJWTExpiredToken {
    NSData *publicKey = nil;
    ATProtoJWTMinter *minter = [self testMinterWithPublicKey:&publicKey];

    ATProtoJWTVerifier *verifier = [[ATProtoJWTVerifier alloc] init];
    verifier.expectedIssuer = @"test-issuer";
    verifier.allowedAlgorithms = @[@"ES256K"];
    verifier.publicKey = publicKey;

    NSString *token = [minter signPayload:@{
        @"sub": @"did:web:test.com",
        @"iss": @"test-issuer",
        @"iat": @([[NSDate dateWithTimeIntervalSinceNow:-4000] timeIntervalSince1970]),
        @"exp": @([[NSDate dateWithTimeIntervalSinceNow:-1000] timeIntervalSince1970])
    } error:nil];

    ATProtoJWT *jwt = [ATProtoJWT jwtWithToken:token error:nil];
    XCTAssertNotNil(jwt);

    NSError *error = nil;
    BOOL valid = [verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorTokenExpired);
}

- (void)testAccessTokenMinting {
    ATProtoJWTMinter *minter = [self testMinterWithPublicKey:nil];

    ATProtoJWT *token = [minter mintAccessTokenForDID:@"did:web:test.com"
                                        handle:@"test.bsky.social"
                                        scopes:@[@"atproto", @"app.bsky"]
                                          error:nil];

    XCTAssertNotNil(token);
    XCTAssertEqualObjects(token.payload.did, @"did:web:test.com");
    XCTAssertEqualObjects(token.payload.handle, @"test.bsky.social");
}

@end
