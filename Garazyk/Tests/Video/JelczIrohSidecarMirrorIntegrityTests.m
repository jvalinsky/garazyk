// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczIrohSidecarBlobFetcher.h"
#import "MediaCore/ATProtoCAMirrorResolver.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoIrohBlobHashMapping.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface GZJelczIrohSidecarIntegrityHTTPStub : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, copy, nullable) NSData *bodyToReturn;
@property (nonatomic, assign) NSInteger statusCode;
@end

@implementation GZJelczIrohSidecarIntegrityHTTPStub
- (instancetype)init {
    self = [super init];
    if (self) {
        _statusCode = 200;
    }
    return self;
}
- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(id)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    (void)options;
    (void)error;
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:self.statusCode
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:@{}];
    }
    return self.statusCode == 200 ? self.bodyToReturn : nil;
}
@end

@interface JelczIrohSidecarMirrorIntegrityTests : XCTestCase
@property (nonatomic, copy) NSString *tempRoot;
@end

@implementation JelczIrohSidecarMirrorIntegrityTests

- (void)setUp {
    [super setUp];
    self.tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"iroh-mirror-%@", NSUUID.UUID.UUIDString]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempRoot error:nil];
    [super tearDown];
}

- (ATProtoCAMirrorResolver *)resolverWithStub:(GZJelczIrohSidecarIntegrityHTTPStub *)stub
                                        store:(ATProtoCAObjectStore *)store {
    GZJelczIrohSidecarBlobFetcher *fetcher =
        [[GZJelczIrohSidecarBlobFetcher alloc] initWithHTTPClient:stub
                                                    sidecarBaseURL:@"http://127.0.0.1:17352"];
    fetcher.capabilityToken = @"sidecar-capability";
    fetcher.defaultProviderEndpointId = @"lab-provider-endpoint";
    ATProtoCAMirrorResolver *resolver =
        [[ATProtoCAMirrorResolver alloc] initWithObjectStore:store fetcher:fetcher];
    resolver.mirrorFetchEnabled = YES;
    return resolver;
}

- (void)testResolverStoresVerifiedSidecarBytes {
    NSError *error = nil;
    ATProtoCAObjectStore *store =
        [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload
                                               profile:ATProtoCAObjectDigestProfileBLAKE3
                                                 error:&error];
    XCTAssertNotNil(cid);
    XCTAssertTrue([ATProtoIrohBlobHashMapping garazykCAVODCID:cid matchesObjectData:payload]);
    XCTAssertNil([store dataForCID:cid error:nil]);

    GZJelczIrohSidecarIntegrityHTTPStub *stub = [[GZJelczIrohSidecarIntegrityHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    ATProtoCAMirrorResolver *resolver = [self resolverWithStub:stub store:store];

    NSData *got = [resolver dataForCID:cid
                             providers:@[ @"iroh://lab-provider-endpoint" ]
                                 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqualObjects([store dataForCID:cid error:&error], payload);
}

- (void)testResolverRejectsTamperedSidecarBytes {
    NSError *error = nil;
    ATProtoCAObjectStore *store =
        [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *honest = [@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:honest
                                               profile:ATProtoCAObjectDigestProfileBLAKE3
                                                 error:&error];

    GZJelczIrohSidecarIntegrityHTTPStub *stub = [[GZJelczIrohSidecarIntegrityHTTPStub alloc] init];
    stub.bodyToReturn = [@"hostile-sidecar-bytes!" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCAMirrorResolver *resolver = [self resolverWithStub:stub store:store];

    NSData *got = [resolver dataForCID:cid
                             providers:@[ @"iroh://lab-provider-endpoint" ]
                                 error:&error];
    XCTAssertNil(got);
    XCTAssertEqual(error.domain, ATProtoCAMirrorResolverErrorDomain);
    XCTAssertEqual(error.code, ATProtoCAMirrorResolverErrorVerificationFailed);
    XCTAssertNil([store dataForCID:cid error:nil]);
}

- (void)testResolverRejectsBytesUnderWrongExpectedCID {
    NSError *error = nil;
    ATProtoCAObjectStore *store =
        [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payloadA = [@"payload-a" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadB = [@"payload-b" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cidForA = [ATProtoCAObjectStore cidForData:payloadA
                                                   profile:ATProtoCAObjectDigestProfileBLAKE3
                                                     error:&error];
    XCTAssertFalse([ATProtoIrohBlobHashMapping garazykCAVODCID:cidForA matchesObjectData:payloadB]);

    GZJelczIrohSidecarIntegrityHTTPStub *stub = [[GZJelczIrohSidecarIntegrityHTTPStub alloc] init];
    stub.bodyToReturn = payloadB;
    ATProtoCAMirrorResolver *resolver = [self resolverWithStub:stub store:store];

    NSData *got = [resolver dataForCID:cidForA
                             providers:@[ @"iroh://lab-provider-endpoint" ]
                                 error:&error];
    XCTAssertNil(got);
    XCTAssertEqual(error.code, ATProtoCAMirrorResolverErrorVerificationFailed);
    XCTAssertNil([store dataForCID:cidForA error:nil]);
}

- (void)testGoldenEmptyFixturePassesResolverVerify {
    NSError *error = nil;
    ATProtoCAObjectStore *store =
        [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [NSData data];
    ATProtoCID *cid = [ATProtoCID daslCIDFromString:
        @"bafkr4ifpcne3t5pzugtkaqcn5i3nzskjtpfslsnnyejlpte2spfoihzsmi"
                                             profile:ATProtoDASLCIDProfileBig];
    XCTAssertNotNil(cid);
    XCTAssertTrue([ATProtoIrohBlobHashMapping garazykCAVODCID:cid matchesObjectData:payload]);

    GZJelczIrohSidecarIntegrityHTTPStub *stub = [[GZJelczIrohSidecarIntegrityHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    ATProtoCAMirrorResolver *resolver = [self resolverWithStub:stub store:store];

    NSData *got = [resolver dataForCID:cid
                             providers:@[ @"iroh://lab-provider-endpoint" ]
                                 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqualObjects([store dataForCID:cid error:&error], payload);
}

@end
