#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "Core/CID.h"
#import "Core/TID.h"
#import "Core/DID.h"
#import "Repository/CBOR.h"
#import "Repository/MST.h"
#import "Auth/JWT.h"

@interface ATProtoCoreTests : XCTestCase
@end

@implementation ATProtoCoreTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - CID Tests

- (void)testCIDCreation {
    NSData *multihash = [CID sha256Digest:[@"hello world" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithMultihash:multihash codec:0x71];

    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.version, 1);
    XCTAssertEqual(cid.codec, 0x71);
    XCTAssertNotNil(cid.multihash);
}

- (void)testCIDStringValue {
    NSData *multihash = [CID sha256Digest:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithMultihash:multihash codec:0x71];
    NSString *stringValue = [cid stringValue];

    XCTAssertNotNil(stringValue);
    XCTAssertTrue([stringValue hasPrefix:@"b"]);
}

- (void)testCIDEquality {
    NSData *multihash = [CID sha256Digest:[@"same data" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid1 = [CID cidWithMultihash:multihash codec:0x71];
    CID *cid2 = [CID cidWithMultihash:multihash codec:0x71];

    XCTAssertEqualObjects(cid1, cid2);
    XCTAssertTrue([cid1 isEqualToCID:cid2]);
}

- (void)testCIDBytesReturnsNonEmptyData {
    NSData *multihash = [CID sha256Digest:[@"bytes test" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithMultihash:multihash codec:0x71];
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

- (void)testCIDFromEmptyBytes {
    XCTAssertNil([CID cidFromBytes:[NSData data]]);
    XCTAssertNil([CID cidFromBytes:nil]);
}

- (void)testCIDValidLength {
    NSData *multihash = [CID sha256Digest:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid = [CID cidWithMultihash:multihash codec:0x71];
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
    XCTAssertEqual(tid1.length, 14);
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
    XCTAssertEqual(encoded.length, 1);
    XCTAssertEqual(((uint8_t *)encoded.bytes)[0], 42);
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
    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.issuer = @"test-issuer";

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
    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.issuer = @"test-issuer";

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
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.expectedIssuer = @"test-issuer";

    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.issuer = @"test-issuer";

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
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.expectedIssuer = @"test-issuer";

    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.issuer = @"test-issuer";

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
    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.issuer = @"test-issuer";

    JWT *token = [minter mintAccessTokenForDID:@"did:web:test.com"
                                        handle:@"test.bsky.social"
                                        scopes:@[@"atproto", @"app.bsky"]
                                          error:nil];

    XCTAssertNotNil(token);
    XCTAssertEqualObjects(token.payload.did, @"did:web:test.com");
    XCTAssertEqualObjects(token.payload.handle, @"test.bsky.social");
}

#pragma mark - CID Extended Tests

- (void)testCIDFromStringRoundTrip {
    NSData *multihash = [CID sha256Digest:[@"round-trip test" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *original = [CID cidWithMultihash:multihash codec:0x71];
    NSString *str = [original stringValue];
    XCTAssertNotNil(str);

    CID *parsed = [CID cidFromString:str];
    XCTAssertNotNil(parsed, @"cidFromString: must parse a valid CID string");
    XCTAssertEqualObjects(parsed.multihash, original.multihash,
                          @"Round-trip must preserve multihash");
    XCTAssertEqual(parsed.codec, original.codec);
}

- (void)testCIDFromInvalidStringReturnsNil {
    XCTAssertNil([CID cidFromString:@"not-a-cid"]);
    XCTAssertNil([CID cidFromString:@""]);
}

- (void)testCIDsForDifferentDataDiffer {
    NSData *mh1 = [CID sha256Digest:[@"data one" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *mh2 = [CID sha256Digest:[@"data two" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *cid1 = [CID cidWithMultihash:mh1 codec:0x71];
    CID *cid2 = [CID cidWithMultihash:mh2 codec:0x71];
    XCTAssertNotEqualObjects([cid1 stringValue], [cid2 stringValue]);
}

#pragma mark - DID Extended Tests

- (void)testDIDDocumentParsing {
    NSDictionary *docDict = @{
        @"id": @"did:plc:abc123",
        @"alsoKnownAs": @[@"at://alice.test"],
        @"service": @[@{
            @"id": @"#atproto_pds",
            @"type": @"AtprotoPersonalDataServer",
            @"serviceEndpoint": @"https://pds.example.com"
        }]
    };
    NSError *error = nil;
    DIDDocument *doc = [DIDDocument documentWithJSON:docDict error:&error];
    XCTAssertNotNil(doc, @"DIDDocument must parse from a valid dictionary: %@", error);
    XCTAssertEqualObjects(doc.id, @"did:plc:abc123");
}

- (void)testDIDDocumentFromNilDictionaryReturnsNil {
    XCTAssertNil([DIDDocument documentWithJSON:nil error:nil]);
}

@end
