// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoCAMirrorResolver.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/ATProtoBao.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoCAMirrorStubFetcher : NSObject <ATProtoCAMirrorFetching>
@property (nonatomic, copy, nullable) NSData *bytesToReturn;
@property (nonatomic, assign) NSUInteger fetchCount;
@property (nonatomic, copy, nullable) NSData *baoSliceToReturn;
@property (nonatomic, assign) NSUInteger baoFetchCount;
@end

@implementation ATProtoCAMirrorStubFetcher
- (NSData *)fetchObjectBytesForCID:(ATProtoCID *)cid
                         providers:(NSArray<NSString *> *)providers
                             error:(NSError **)error {
    self.fetchCount += 1;
    (void)cid;
    (void)providers;
    if (!self.bytesToReturn) {
        if (error) {
            *error = [NSError errorWithDomain:@"stub" code:1 userInfo:nil];
        }
        return nil;
    }
    return self.bytesToReturn;
}
- (NSData *)fetchBaoSliceForCID:(ATProtoCID *)cid
                       rootHash:(NSData *)rootHash
                      providers:(NSArray<NSString *> *)providers
                         offset:(NSUInteger)offset
                         length:(NSUInteger)length
                          error:(NSError **)error {
    self.baoFetchCount += 1;
    (void)cid;
    (void)rootHash;
    (void)providers;
    (void)offset;
    (void)length;
    (void)error;
    return self.baoSliceToReturn;
}
@end

@interface ATProtoCAMirrorResolverTests : XCTestCase
@property (nonatomic, copy) NSString *tempRoot;
@end

@implementation ATProtoCAMirrorResolverTests

- (void)setUp {
    [super setUp];
    self.tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"ca-mirror-%@", NSUUID.UUID.UUIDString]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempRoot error:nil];
    [super tearDown];
}

- (void)testLocalHitDoesNotFetch {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"local-hit" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [store putData:payload expectedCID:nil profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    ATProtoCAMirrorStubFetcher *stub = [[ATProtoCAMirrorStubFetcher alloc] init];
    stub.bytesToReturn = [@"should-not-use" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCAMirrorResolver *resolver = [[ATProtoCAMirrorResolver alloc] initWithObjectStore:store fetcher:stub];
    resolver.mirrorFetchEnabled = YES;

    NSData *got = [resolver dataForCID:cid providers:@[ @"https://mirror.example" ] error:&error];
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqual(stub.fetchCount, (NSUInteger)0);
}

- (void)testLocalMissFetchesVerifiesAndStores {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"from-mirror" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    XCTAssertNotNil(cid);
    XCTAssertNil([store dataForCID:cid error:nil]);

    ATProtoCAMirrorStubFetcher *stub = [[ATProtoCAMirrorStubFetcher alloc] init];
    stub.bytesToReturn = payload;
    ATProtoCAMirrorResolver *resolver = [[ATProtoCAMirrorResolver alloc] initWithObjectStore:store fetcher:stub];
    resolver.mirrorFetchEnabled = YES;

    NSData *got = [resolver dataForCID:cid providers:@[ @"https://mirror.example" ] error:&error];
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqual(stub.fetchCount, (NSUInteger)1);
    XCTAssertEqualObjects([store dataForCID:cid error:&error], payload);
}

- (void)testHostileMismatchRejectedDoesNotPoisonStore {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *honest = [@"honest-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:honest profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];

    ATProtoCAMirrorStubFetcher *stub = [[ATProtoCAMirrorStubFetcher alloc] init];
    stub.bytesToReturn = [@"hostile-payload!!!!" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCAMirrorResolver *resolver = [[ATProtoCAMirrorResolver alloc] initWithObjectStore:store fetcher:stub];
    resolver.mirrorFetchEnabled = YES;

    NSData *got = [resolver dataForCID:cid providers:@[ @"https://evil.example" ] error:&error];
    XCTAssertNil(got);
    XCTAssertEqual(error.code, ATProtoCAMirrorResolverErrorVerificationFailed);
    XCTAssertNil([store dataForCID:cid error:nil]);
    XCTAssertEqual(stub.fetchCount, (NSUInteger)1);
}

- (void)testMirrorDisabledStaysLocalOnly {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    ATProtoCAMirrorStubFetcher *stub = [[ATProtoCAMirrorStubFetcher alloc] init];
    stub.bytesToReturn = payload;
    ATProtoCAMirrorResolver *resolver = [[ATProtoCAMirrorResolver alloc] initWithObjectStore:store fetcher:stub];
    // default mirrorFetchEnabled == NO

    NSData *got = [resolver dataForCID:cid providers:@[ @"https://mirror.example" ] error:&error];
    XCTAssertNil(got);
    XCTAssertEqual(stub.fetchCount, (NSUInteger)0);
}

- (void)testSHA256ManifestCIDFetchesAndStores {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"playlist-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload
                                               profile:ATProtoCAObjectDigestProfileSHA256
                                                 error:&error];
    ATProtoCAMirrorStubFetcher *stub = [[ATProtoCAMirrorStubFetcher alloc] init];
    stub.bytesToReturn = payload;
    ATProtoCAMirrorResolver *resolver = [[ATProtoCAMirrorResolver alloc] initWithObjectStore:store fetcher:stub];
    resolver.mirrorFetchEnabled = YES;

    NSData *got = [resolver dataForCID:cid providers:@[ @"https://mirror.example" ] error:&error];
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqualObjects([store dataForCID:cid error:&error], payload);
}

- (void)testRangeMissUsesBaoSliceWithoutPoisoningOnBadSlice {
    NSError *error = nil;
    ATProtoCAObjectStore *store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSMutableData *payload = [NSMutableData dataWithLength:2048];
    memset(payload.mutableBytes, 0xab, payload.length);
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload profile:ATProtoCAObjectDigestProfileBLAKE3 error:&error];
    NSData *outboard = [ATProtoBao outboardForData:payload error:&error];
    NSData *goodSlice = [ATProtoBao sliceFromData:payload outboard:outboard offset:1000 length:200 error:&error];
    NSData *rootHash = [ATProtoBao hashForData:payload];

    ATProtoCAMirrorStubFetcher *stub = [[ATProtoCAMirrorStubFetcher alloc] init];
    stub.baoSliceToReturn = goodSlice;
    stub.bytesToReturn = payload; // unused when bao succeeds
    ATProtoCAMirrorResolver *resolver = [[ATProtoCAMirrorResolver alloc] initWithObjectStore:store fetcher:stub];
    resolver.mirrorFetchEnabled = YES;

    NSData *got = [resolver dataForCID:cid offset:1000 length:200 providers:@[ @"https://m.example" ] error:&error];
    XCTAssertEqual(got.length, (NSUInteger)200);
    XCTAssertEqual(stub.baoFetchCount, (NSUInteger)1);
    XCTAssertEqual(stub.fetchCount, (NSUInteger)0);
    // Range-only Bao path does not put the full object.
    XCTAssertNil([store dataForCID:cid error:nil]);
    (void)rootHash;

    NSMutableData *badSlice = [goodSlice mutableCopy];
    ((uint8_t *)badSlice.mutableBytes)[badSlice.length - 1] ^= 0x01;
    stub.baoSliceToReturn = badSlice;
    stub.bytesToReturn = nil;
    NSData *gotBad = [resolver dataForCID:cid offset:1000 length:200 providers:@[ @"https://m.example" ] error:&error];
    XCTAssertNil(gotBad);
    XCTAssertNil([store dataForCID:cid error:nil]);
}

@end
