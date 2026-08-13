// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoCAObjectStoreTests : XCTestCase
@property (nonatomic, copy) NSString *tempRoot;
@end

@implementation ATProtoCAObjectStoreTests

- (void)setUp {
    [super setUp];
    self.tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"ca-store-%@", NSUUID.UUID.UUIDString]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempRoot error:nil];
    [super tearDown];
}

- (void)testPutGetRoundTripSHA256AndBLAKE3 {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    XCTAssertNotNil(store);
    NSData *payload = [@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding];

    ATProtoCID *shaCID = [store putData:payload expectedCID:nil profile:ATProtoCAObjectDigestProfileSHA256 error:&error];
    XCTAssertNotNil(shaCID);
    XCTAssertTrue([shaCID isDASLConformantForProfile:ATProtoDASLCIDProfileBase]);
    XCTAssertEqualObjects([store dataForCID:shaCID error:&error], payload);

    ATProtoCID *b3CID = [store putData:payload expectedCID:nil profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    XCTAssertNotNil(b3CID);
    XCTAssertTrue([b3CID isDASLConformantForProfile:ATProtoDASLCIDProfileBig]);
    XCTAssertFalse([shaCID isEqual:b3CID]);
    XCTAssertEqualObjects([store dataForCID:b3CID error:&error], payload);
    NSDictionary *stat = [store statCID:b3CID error:&error];
    XCTAssertEqualObjects(stat[@"hasProof"], @YES);
}

- (void)testPutRejectsCIDMismatch {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"a" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *other = [@"b" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *wrong = [ATProtoCAObjectStore cidForData:other profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    ATProtoCID *cid = [store putData:payload expectedCID:wrong profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    XCTAssertNil(cid);
    XCTAssertEqual(error.code, ATProtoCAObjectStoreErrorCIDMismatch);
}

- (void)testGetRangeBoundariesAndPastEOF {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSMutableData *payload = [NSMutableData dataWithLength:2500];
    memset(payload.mutableBytes, 0x5a, payload.length);
    ATProtoCID *cid = [store putData:payload expectedCID:nil profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    XCTAssertNotNil(cid);

    NSData *mid = [store dataForCID:cid offset:1000 length:500 error:&error];
    XCTAssertEqual(mid.length, (NSUInteger)500);
    XCTAssertEqual(((const uint8_t *)mid.bytes)[0], 0x5a);

    NSData *tail = [store dataForCID:cid offset:2000 length:1000 error:&error];
    XCTAssertEqual(tail.length, (NSUInteger)500);

    NSData *empty = [store dataForCID:cid offset:2500 length:10 error:&error];
    XCTAssertEqual(empty.length, (NSUInteger)0);

    NSData *past = [store dataForCID:cid offset:2501 length:1 error:&error];
    XCTAssertNil(past);
    XCTAssertEqual(error.code, ATProtoCAObjectStoreErrorRange);
}

- (void)testProofGenerateProduceVerifyAndRegenerateKeepsCID {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSMutableData *payload = [NSMutableData dataWithLength:3500];
    for (NSUInteger i = 0; i < payload.length; i++) {
        ((uint8_t *)payload.mutableBytes)[i] = (uint8_t)(i & 0xff);
    }
    ATProtoCID *cid = [store putData:payload expectedCID:nil profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    XCTAssertNotNil(cid);

    NSDictionary *proof = [store produceProofForCID:cid offset:1000 length:1200 error:&error];
    XCTAssertNotNil(proof);
    XCTAssertEqual([proof[@"offset"] unsignedIntegerValue], (NSUInteger)1000);
    XCTAssertEqual([proof[@"length"] unsignedIntegerValue], (NSUInteger)1200);
    XCTAssertEqual([(NSData *)proof[@"rangeData"] length], (NSUInteger)1200);
    XCTAssertNotNil(proof[@"baoSlice"]);

    // Untrusted path: no fullObjectData.
    XCTAssertTrue([ATProtoCAObjectStore verifyProof:proof fullObjectData:nil error:&error]);

    NSMutableData *tampered = [proof[@"baoSlice"] mutableCopy];
    uint8_t *bytes = tampered.mutableBytes;
    bytes[tampered.length - 1] ^= 0x01;
    NSMutableDictionary *bad = [proof mutableCopy];
    bad[@"baoSlice"] = tampered;
    XCTAssertFalse([ATProtoCAObjectStore verifyProof:bad fullObjectData:nil error:&error]);

    ATProtoCID *before = cid;
    XCTAssertTrue([store regenerateProofForCID:cid error:&error]);
    NSDictionary *stat = [store statCID:cid error:&error];
    XCTAssertEqualObjects(stat[@"hasProof"], @YES);
    NSData *full = [store dataForCID:cid error:&error];
    XCTAssertEqualObjects(full, payload);
    XCTAssertEqualObjects(before, cid);

    NSDictionary *proof2 = [store produceProofForCID:cid offset:1000 length:1200 error:&error];
    XCTAssertTrue([ATProtoCAObjectStore verifyProof:proof2 fullObjectData:nil error:&error]);
}

- (void)testDeleteRemovesObjectAndProof {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"delete-me" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [store putData:payload expectedCID:nil profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    XCTAssertTrue([store deleteCID:cid error:&error]);
    XCTAssertNil([store dataForCID:cid error:&error]);
    XCTAssertEqual(error.code, ATProtoCAObjectStoreErrorNotFound);
}

@end
