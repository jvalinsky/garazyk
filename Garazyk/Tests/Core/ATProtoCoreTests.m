// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "Core/CID.h"
#import "Core/TID.h"
#import "Core/DID.h"
#import "Repository/CBOR.h"
#import "Repository/MST.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"

@interface ATProtoCoreTests : XCTestCase
@end

@implementation ATProtoCoreTests

- (JWTMinter *)testMinterWithPublicKey:(NSData **)publicKeyOut {
    NSError *keyError = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&keyError];
    XCTAssertNotNil(keyPair, @"Failed to generate test key pair: %@", keyError);
    if (!keyPair) return nil;

    JWTMinter *minter = [[JWTMinter alloc] init];
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

#pragma mark - CID Tests

- (void)testCIDCreation {
    NSData *digest = [CID sha256Digest:[@"hello world" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithDigest:digest codec:0x71];

    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.version, 1);
    XCTAssertEqual(cid.codec, 0x71);
    XCTAssertNotNil(cid.multihash);
}

- (void)testCIDStringValue {
    NSData *digest = [CID sha256Digest:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithDigest:digest codec:0x71];
    NSString *stringValue = [cid stringValue];

    XCTAssertNotNil(stringValue);
    XCTAssertTrue([stringValue hasPrefix:@"b"]);
}

- (void)testCIDEquality {
    NSData *digest = [CID sha256Digest:[@"same data" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid1 = [CID cidWithDigest:digest codec:0x71];
    CID *cid2 = [CID cidWithDigest:digest codec:0x71];

    XCTAssertEqualObjects(cid1, cid2);
    XCTAssertTrue([cid1 isEqualToCID:cid2]);
}

- (void)testCIDBytesReturnsNonEmptyData {
    NSData *digest = [CID sha256Digest:[@"bytes test" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithDigest:digest codec:0x71];
    NSData *bytes = [cid bytes];

    XCTAssertNotNil(bytes);
    XCTAssertGreaterThan(bytes.length, 0);
}

- (void)testCIDSHA256 {
    NSData *data = [@"sha256 test" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid = [CID sha256:data];

    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.codec, 0x55);
}

- (void)testCIDFromStringMaxLength {
    NSMutableString *longString = [NSMutableString stringWithString:@"b"];
    for (int i = 0; i < 300; i++) {
        [longString appendString:@"a"];
    }
    XCTAssertNil([CID cidFromString:longString], @"Should reject CID string > 256 chars");
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
    XCTAssertNil([CID cidFromBytes:longData], @"Should reject CID bytes > 256");
}

- (void)testCIDFromEmptyString {
    XCTAssertNil([CID cidFromString:@""]);
    XCTAssertNil([CID cidFromString:nil]);
}

- (void)testCIDFromBufferReportsConsumedLength {
    NSData *digest = [CID sha256Digest:[@"buffer-consume" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *original = [CID cidWithDigest:digest codec:0x71];
    NSData *cidBytes = original.bytes;

    NSMutableData *withTrailer = [NSMutableData dataWithData:cidBytes];
    uint8_t trailer[] = {0xDE, 0xAD, 0xBE, 0xEF};
    [withTrailer appendBytes:trailer length:sizeof(trailer)];

    NSUInteger consumed = 0;
    CID *parsed = [CID cidFromBuffer:withTrailer.bytes length:withTrailer.length consumed:&consumed];

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
    CID *parsed = [CID cidFromBuffer:buffer.bytes length:buffer.length consumed:&consumed];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(consumed, (NSUInteger)34);
    XCTAssertEqual(parsed.version, (NSUInteger)0);
}

- (void)testCIDFromBufferRejectsTruncatedVarint {
    uint8_t truncated[] = {0x81}; // continuation bit set, no next byte
    NSUInteger consumed = 999;
    CID *parsed = [CID cidFromBuffer:truncated length:sizeof(truncated) consumed:&consumed];
    XCTAssertNil(parsed);
}

- (void)testCIDFromBufferRejectsOversizeMultihash {
    // version=1, codec=0x71 (dag-cbor), mh_code=0x12, mh_len = 0xFFFFFFFF (varint)
    uint8_t hostile[] = {0x01, 0x71, 0x12, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F};
    NSUInteger consumed = 999;
    CID *parsed = [CID cidFromBuffer:hostile length:sizeof(hostile) consumed:&consumed];
    XCTAssertNil(parsed);
}

- (void)testCIDFromBufferAcceptsArbitraryCodec {
    NSData *digest = [CID sha256Digest:[@"raw-codec" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *rawCID = [CID cidWithDigest:digest codec:0x55]; // raw
    NSData *cidBytes = rawCID.bytes;

    NSUInteger consumed = 0;
    CID *parsed = [CID cidFromBuffer:cidBytes.bytes length:cidBytes.length consumed:&consumed];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(consumed, cidBytes.length);
    XCTAssertEqual(parsed.codec, (NSUInteger)0x55);
    XCTAssertTrue([parsed isEqualToCID:rawCID]);
}

- (void)testCIDFromEmptyBytes {
    XCTAssertNil([CID cidFromBytes:[NSData data]]);
    XCTAssertNil([CID cidFromBytes:nil]);
}

- (void)testCIDValidLength {
    NSData *digest = [CID sha256Digest:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithDigest:digest codec:0x71];
    NSString *stringValue = cid.stringValue;
    
    XCTAssertLessThanOrEqual(stringValue.length, 256, @"Valid CID should be <= 256 chars");
    
    CID *parsed = [CID cidFromString:stringValue];
    XCTAssertNotNil(parsed, @"Should parse valid CID string");
    XCTAssertEqualObjects(parsed.stringValue, stringValue);
}

#pragma mark - TID Tests

- (void)testTIDGeneration {
    NSString *tid1 = [[TID tid] stringValue];
    NSString *tid2 = [[TID tid] stringValue];

    XCTAssertNotNil(tid1);
    XCTAssertNotNil(tid2);
    XCTAssertEqual(tid1.length, 13);
}

- (void)testTIDUniqueness {
    NSMutableSet<NSString *> *tids = [NSMutableSet set];
    for (int i = 0; i < 100; i++) {
        [tids addObject:[[TID tid] stringValue]];
    }
    XCTAssertEqual(tids.count, 100);
}

- (void)testTIDOrderingYieldsDescending {
    NSString *tid1 = [[TID tid] stringValue];
    [NSThread sleepForTimeInterval:0.01];
    NSString *tid2 = [[TID tid] stringValue];

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
    CBORValue *value = [CBORValue unsignedInteger:42];
    NSData *encoded = [value encode];

    XCTAssertNotNil(encoded);
    XCTAssertEqual(encoded.length, 2);
    XCTAssertEqual(((uint8_t *)encoded.bytes)[0], 0x18);
    XCTAssertEqual(((uint8_t *)encoded.bytes)[1], 42);
}

- (void)testEncodeTextStringReturnsNonEmptyData {
    CBORValue *value = [CBORValue textString:@"hello"];
    NSData *encoded = [value encode];

    XCTAssertNotNil(encoded);
    XCTAssertGreaterThan(encoded.length, 0);
}

- (void)testEncodeArrayReturnsNonEmptyData {
    NSArray<CBORValue *> *array = @[
        [CBORValue unsignedInteger:1],
        [CBORValue unsignedInteger:2],
        [CBORValue unsignedInteger:3]
    ];
    CBORValue *value = [CBORValue array:array];
    NSData *encoded = [value encode];

    XCTAssertNotNil(encoded);
    XCTAssertGreaterThan(encoded.length, 0);
}

- (void)testEncodeMapReturnsNonEmptyData {
    NSMutableDictionary<CBORValue *, CBORValue *> *map = [NSMutableDictionary dictionary];
    map[[CBORValue textString:@"key"]] = [CBORValue textString:@"value"];
    CBORValue *value = [CBORValue map:map];
    NSData *encoded = [value encode];

    XCTAssertNotNil(encoded);
    XCTAssertGreaterThan(encoded.length, 0);
}

- (void)testCBORRoundTripYieldsMap {
    NSMutableDictionary<CBORValue *, CBORValue *> *original = [NSMutableDictionary dictionary];
    original[[CBORValue textString:@"name"]] = [CBORValue textString:@"test"];
    original[[CBORValue textString:@"count"]] = [CBORValue unsignedInteger:42];
    original[[CBORValue textString:@"nested"]] = [CBORValue map:@{
        [CBORValue textString:@"inner"]: [CBORValue textString:@"value"]
    }];

    NSData *encoded = [[CBORValue map:original] encode];
    CBORValue *decoded = [CBORValue decode:encoded];

    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.type, CBORTypeMap);
}

#pragma mark - MST Tests

- (void)testMSTBasicOperationsGetEqualsObject {
    MST *mst = [[MST alloc] init];

    CID *cid1 = [CID sha256:[@"value1" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid2 = [CID sha256:[@"value2" dataUsingEncoding:NSUTF8StringEncoding]];

    [mst put:@"key1" valueCID:cid1];
    [mst put:@"key2" valueCID:cid2 subKey:@"sub1"];

    XCTAssertEqualObjects([mst get:@"key1"], cid1);
    XCTAssertEqualObjects([mst get:@"key2" subKey:@"sub1"], cid2);
}

- (void)testMSTDelete {
    MST *mst = [[MST alloc] init];
    CID *cid = [CID sha256:[@"delete test" dataUsingEncoding:NSUTF8StringEncoding]];

    [mst put:@"deleteMe" valueCID:cid];
    XCTAssertNotNil([mst get:@"deleteMe"]);

    [mst delete:@"deleteMe"];
    XCTAssertNil([mst get:@"deleteMe"]);
}

- (void)testMSTAllEntries {
    MST *mst = [[MST alloc] init];

    for (int i = 0; i < 10; i++) {
        CID *cid = [CID sha256:[[NSString stringWithFormat:@"entry%d", i] dataUsingEncoding:NSUTF8StringEncoding]];
        [mst put:[NSString stringWithFormat:@"key%d", i] valueCID:cid];
    }

    NSArray<MSTEntry *> *entries = [mst allEntries];
    XCTAssertEqual(entries.count, 10);
}

- (void)testEntriesWithPrefixReturnsExpectedCount {
    MST *mst = [[MST alloc] init];

    CID *cid1 = [CID sha256:[@"app.bsky.feed.post1" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid2 = [CID sha256:[@"app.bsky.feed.post2" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid3 = [CID sha256:[@"app.bsky.actor.profile" dataUsingEncoding:NSUTF8StringEncoding]];

    [mst put:@"app.bsky.feed.post1" valueCID:cid1];
    [mst put:@"app.bsky.feed.post2" valueCID:cid2];
    [mst put:@"app.bsky.actor.profile" valueCID:cid3];

    NSArray<MSTEntry *> *feedEntries = [mst entriesWithPrefix:@"app.bsky.feed."];
    XCTAssertEqual(feedEntries.count, 2);
}

- (void)testMSTCBORSerialization {
    MST *mst = [[MST alloc] init];
    CID *cid = [CID sha256:[@"cbor test" dataUsingEncoding:NSUTF8StringEncoding]];
    [mst put:@"testKey" valueCID:cid];

    NSData *cborData = [mst serializeToCBOR];
    XCTAssertNotNil(cborData);

    MST *deserialized = [MST deserializeFromCBOR:cborData];
    XCTAssertNotNil(deserialized);
    XCTAssertEqualObjects([deserialized get:@"testKey"], cid);
}

#pragma mark - JWT Tests

- (void)testJWTMintingProducesThreeParts {
    JWTMinter *minter = [self testMinterWithPublicKey:nil];

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
    JWTMinter *minter = [self testMinterWithPublicKey:nil];

    NSString *token = [minter signPayload:@{
        @"sub": @"did:web:test.com",
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"exp": @([[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970])
    } error:nil];

    JWT *jwt = [JWT jwtWithToken:token error:nil];
    XCTAssertNotNil(jwt);
    XCTAssertNotNil(jwt.header);
    XCTAssertNotNil(jwt.payload);
    XCTAssertEqualObjects(jwt.payload.sub, @"did:web:test.com");
}

- (void)testJWTVerificationSucceeds {
    NSData *publicKey = nil;
    JWTMinter *minter = [self testMinterWithPublicKey:&publicKey];

    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.expectedIssuer = @"test-issuer";
    verifier.publicKey = publicKey;

    NSString *token = [minter signPayload:@{
        @"sub": @"did:web:test.com",
        @"iss": @"test-issuer",
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"exp": @([[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970])
    } error:nil];

    JWT *jwt = [JWT jwtWithToken:token error:nil];
    XCTAssertNotNil(jwt);

    NSError *error = nil;
    BOOL valid = [verifier verifyJWT:jwt error:&error];
    XCTAssertTrue(valid);
}

- (void)testJWTExpiredToken {
    NSData *publicKey = nil;
    JWTMinter *minter = [self testMinterWithPublicKey:&publicKey];

    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.expectedIssuer = @"test-issuer";
    verifier.publicKey = publicKey;

    NSString *token = [minter signPayload:@{
        @"sub": @"did:web:test.com",
        @"iss": @"test-issuer",
        @"iat": @([[NSDate dateWithTimeIntervalSinceNow:-4000] timeIntervalSince1970]),
        @"exp": @([[NSDate dateWithTimeIntervalSinceNow:-1000] timeIntervalSince1970])
    } error:nil];

    JWT *jwt = [JWT jwtWithToken:token error:nil];
    XCTAssertNotNil(jwt);

    NSError *error = nil;
    BOOL valid = [verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorTokenExpired);
}

- (void)testAccessTokenMinting {
    JWTMinter *minter = [self testMinterWithPublicKey:nil];

    JWT *token = [minter mintAccessTokenForDID:@"did:web:test.com"
                                        handle:@"test.bsky.social"
                                        scopes:@[@"atproto", @"app.bsky"]
                                          error:nil];

    XCTAssertNotNil(token);
    XCTAssertEqualObjects(token.payload.did, @"did:web:test.com");
    XCTAssertEqualObjects(token.payload.handle, @"test.bsky.social");
}

@end
