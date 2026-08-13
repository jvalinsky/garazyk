// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoCAWatchService.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoCAMediaDenylist.h"
#import "MediaCore/ATProtoCAMirrorResolver.h"
#import "MediaCore/ATProtoVODManifestBuilder.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoCAWatchMirrorStubFetcher : NSObject <ATProtoCAMirrorFetching>
@property (nonatomic, copy, nullable) NSData *bytesToReturn;
@property (nonatomic, assign) NSUInteger fetchCount;
@end

@implementation ATProtoCAWatchMirrorStubFetcher
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
@end

@interface ATProtoCAWatchServiceTests : XCTestCase
@property (nonatomic, copy) NSString *tempRoot;
@property (nonatomic, strong) ATProtoCAObjectStore *store;
@property (nonatomic, strong) ATProtoCAMediaDenylistMemory *denylist;
@property (nonatomic, strong) ATProtoCAWatchService *watch;
@property (nonatomic, strong) ATProtoCID *manifestCID;
@property (nonatomic, strong) ATProtoCID *mediaCID;
@end

@implementation ATProtoCAWatchServiceTests

- (void)setUp {
    [super setUp];
    self.tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"ca-watch-%@", NSUUID.UUID.UUIDString]];
    NSError *error = nil;
    self.store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    XCTAssertNotNil(self.store);

    NSData *initData = [@"INITINIT" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *seg0 = [@"SEGMENT0DATA!!!!" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *produced = @{
        @"/": [@"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n360p/video.m3u8\n" dataUsingEncoding:NSUTF8StringEncoding],
        @"/360p/init.mp4": initData,
        @"/360p/segment_00000.m4s": seg0,
        @"/360p/video.m3u8": [@"#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:6,\nsegment_00000.m4s\n#EXT-X-ENDLIST\n"
                              dataUsingEncoding:NSUTF8StringEncoding],
    };
    ATProtoVODManifestBuildResult *built =
        [ATProtoVODManifestBuilder buildFromProducedData:produced store:self.store error:&error];
    XCTAssertNotNil(built);

    self.manifestCID = [self.store putData:built.drislData
                               expectedCID:nil
                                   profile:ATProtoCAObjectDigestProfileSHA256
                                     error:&error];
    XCTAssertNotNil(self.manifestCID);
    self.mediaCID = built.resourceCIDs[@"/360p/video.fmp4"];
    XCTAssertNotNil(self.mediaCID);

    self.denylist = [[ATProtoCAMediaDenylistMemory alloc] init];
    self.watch = [[ATProtoCAWatchService alloc] initWithObjectStore:self.store denylist:self.denylist];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempRoot error:nil];
    [super tearDown];
}

- (ATProtoHttpRequest *)requestWithPath:(NSString *)path range:(nullable NSString *)range {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (range.length > 0) {
        headers[@"Range"] = range;
    }
    return [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                          methodString:@"GET"
                                                  path:path
                                           queryString:@""
                                           queryParams:@{}
                                               version:@"HTTP/1.1"
                                               headers:headers
                                                  body:[NSData data]
                                         remoteAddress:@"127.0.0.1"];
}

- (void)testBundlePathMappingAndTraversalRejection {
    XCTAssertEqualObjects([ATProtoCAWatchService bundlePathFromWatchRemainder:nil], @"/");
    XCTAssertEqualObjects([ATProtoCAWatchService bundlePathFromWatchRemainder:@""], @"/");
    XCTAssertEqualObjects([ATProtoCAWatchService bundlePathFromWatchRemainder:@"playlist.m3u8"], @"/");
    XCTAssertEqualObjects([ATProtoCAWatchService bundlePathFromWatchRemainder:@"360p/video.fmp4"], @"/360p/video.fmp4");
    XCTAssertNil([ATProtoCAWatchService bundlePathFromWatchRemainder:@"../secret"]);
    XCTAssertNil([ATProtoCAWatchService bundlePathFromWatchRemainder:@"360p/%2e%2e/secret"]);
    XCTAssertNil([ATProtoCAWatchService bundlePathFromWatchRemainder:@"%2e%2e/x"]);
}

- (void)testExactPathHitReturns200AndMASLContentType {
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/360p/video.m3u8",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:nil] response:response];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.contentType, @"application/vnd.apple.mpegurl");
    XCTAssertGreaterThan(response.body.length, 0u);
    NSString *body = [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding];
    XCTAssertTrue([body containsString:@"#EXT-X-BYTERANGE:"]);
}

- (void)testUnknownPathReturns404 {
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/missing.bin",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:nil] response:response];
    XCTAssertEqual(response.statusCode, 404);
}

- (void)testDotDotTraversalReturns404NotFilesystemError {
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/../etc/passwd",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:nil] response:response];
    XCTAssertEqual(response.statusCode, 404);
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertEqualObjects(json[@"error"], @"NotFound");
}

- (void)testEncodedTraversalReturns404 {
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/%%2e%%2e/secret",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:nil] response:response];
    XCTAssertEqual(response.statusCode, 404);
}

- (void)testRangeRequestReturns206WithExactLength {
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/360p/video.fmp4",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:@"bytes=0-3"] response:response];
    XCTAssertEqual(response.statusCode, 206);
    XCTAssertEqual(response.body.length, 4u);
    NSUInteger total = [@"INITINIT" length] + [@"SEGMENT0DATA!!!!" length];
    NSString *expectedRange = [NSString stringWithFormat:@"bytes 0-3/%lu", (unsigned long)total];
    XCTAssertEqualObjects([response headerForKey:@"Content-Range"], expectedRange);
    NSString *slice = [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(slice, @"INIT");
}

- (void)testUnsatisfiableRangeReturns416 {
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/360p/video.fmp4",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:@"bytes=999999-9999999"] response:response];
    XCTAssertEqual(response.statusCode, 416);
    XCTAssertEqual(response.body.length, 0u);
    XCTAssertTrue([[response headerForKey:@"Content-Range"] hasPrefix:@"bytes */"]);
}

- (void)testDeniedManifestCIDReturns403WithoutBytes {
    [self.denylist denyCID:self.manifestCID];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/playlist.m3u8",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:nil] response:response];
    XCTAssertEqual(response.statusCode, 403);
    XCTAssertGreaterThan(response.body.length, 0u); // JSON policy body only
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertEqualObjects(json[@"error"], @"ContentDenied");
    // Ensure we did not stream playlist media bytes.
    NSString *text = [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding];
    XCTAssertFalse([text containsString:@"#EXTM3U"]);
}

- (void)testDeniedResourceCIDReturns403WithoutBytes {
    [self.denylist denyCID:self.mediaCID];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/360p/video.fmp4",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:nil] response:response];
    XCTAssertEqual(response.statusCode, 403);
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertEqualObjects(json[@"error"], @"ContentDenied");
}

- (void)testMirrorResolverFillsMissingManifest {
    // Drop the manifest from the local store, then serve via resolver stub.
    NSData *manifestBytes = [self.store dataForCID:self.manifestCID error:nil];
    XCTAssertNotNil(manifestBytes);
    XCTAssertTrue([self.store deleteCID:self.manifestCID error:nil]);
    XCTAssertNil([self.store dataForCID:self.manifestCID error:nil]);

    ATProtoCAWatchMirrorStubFetcher *stub = [[ATProtoCAWatchMirrorStubFetcher alloc] init];
    stub.bytesToReturn = manifestBytes;
    ATProtoCAMirrorResolver *resolver =
        [[ATProtoCAMirrorResolver alloc] initWithObjectStore:self.store fetcher:stub];
    resolver.mirrorFetchEnabled = YES;
    self.watch.mirrorResolver = resolver;
    self.watch.mirrorProviders = @[ @"https://origin.example" ];

    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSString *path = [NSString stringWithFormat:@"/watch/did:plc:test/%@/playlist.m3u8",
                      self.manifestCID.stringValue];
    [self.watch handleRequest:[self requestWithPath:path range:nil] response:response];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqual(stub.fetchCount, (NSUInteger)1);
    XCTAssertNotNil([self.store dataForCID:self.manifestCID error:nil]);
}

@end
