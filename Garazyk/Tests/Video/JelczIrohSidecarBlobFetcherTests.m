// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczIrohSidecarBlobFetcher.h"
#import "Video/GZJelczIrohSidecarPeerRegistry.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoIrohBlobHashMapping.h"
#import "Core/CID.h"

@interface GZJelczIrohSidecarHTTPStub : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, copy, nullable) NSData *bodyToReturn;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy, nullable) NSData *lastRequestBody;
@property (nonatomic, copy, nullable) NSURL *lastURL;
@property (nonatomic, copy, nullable) NSString *lastAuthorization;
@property (nonatomic, assign) NSUInteger requestCount;
@end

@implementation GZJelczIrohSidecarHTTPStub
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
    self.requestCount += 1;
    self.lastURL = request.URL;
    self.lastAuthorization = [request valueForHTTPHeaderField:@"Authorization"];
    self.lastRequestBody = request.HTTPBody;
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:self.statusCode
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:@{}];
    }
    return self.statusCode == 200 ? self.bodyToReturn : nil;
}
@end

@interface JelczIrohSidecarBlobFetcherTests : XCTestCase
@end

@implementation JelczIrohSidecarBlobFetcherTests

- (ATProtoCID *)cidForPayload:(NSData *)payload {
    return [ATProtoCAObjectStore cidForData:payload
                                    profile:ATProtoCAObjectDigestProfileBLAKE3
                                      error:nil];
}

- (void)testParsesIrohProviderHint {
    NSString *endpointId =
        [GZJelczIrohSidecarBlobFetcher endpointIdFromIrohProviderHint:
            @"iroh://ae58ff8833241ac82d6ff7611046ed67b5072d142c588d0063e942d9a75502b6"];
    XCTAssertEqualObjects(endpointId,
                          @"ae58ff8833241ac82d6ff7611046ed67b5072d142c588d0063e942d9a75502b6");
    XCTAssertNil([GZJelczIrohSidecarBlobFetcher endpointIdFromIrohProviderHint:@"https://a.example"]);
}

- (void)testPostsFetchIPCWithFixtureCID {
    NSData *payload = [@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    XCTAssertNotNil(cid);
    XCTAssertTrue([ATProtoIrohBlobHashMapping garazykCAVODCID:cid matchesObjectData:payload]);

    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczIrohSidecarBlobFetcher *fetcher =
        [[GZJelczIrohSidecarBlobFetcher alloc] initWithHTTPClient:stub
                                                    sidecarBaseURL:@"http://127.0.0.1:17352"];
    fetcher.capabilityToken = @"sidecar-capability";
    NSError *error = nil;
    NSData *got = [fetcher fetchObjectBytesForCID:cid
                                        providers:@[ @"iroh://provider-endpoint-id" ]
                                            error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(got, payload);
    XCTAssertTrue([stub.lastURL.path isEqualToString:@"/v1/fetch"]);

    NSDictionary *json =
        [NSJSONSerialization JSONObjectWithData:stub.lastRequestBody options:0 error:nil];
    XCTAssertEqualObjects(json[@"cid"], cid.stringValue);
    XCTAssertEqualObjects(json[@"provider"][@"endpointId"], @"provider-endpoint-id");
}

- (void)testFetchSendsSidecarCapability {
    NSData *payload = [@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczIrohSidecarBlobFetcher *fetcher =
        [[GZJelczIrohSidecarBlobFetcher alloc] initWithHTTPClient:stub
                                                    sidecarBaseURL:@"http://127.0.0.1:17352"];
    fetcher.capabilityToken = @"sidecar-capability";
    XCTAssertEqualObjects([fetcher fetchObjectBytesForCID:cid
                                                 providers:@[ @"iroh://provider-endpoint-id" ]
                                                     error:nil], payload);
    XCTAssertEqualObjects(stub.lastAuthorization, @"Bearer sidecar-capability");
}

- (void)testUsesDefaultProviderWhenNoIrohHintInList {
    NSData *payload = [@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczIrohSidecarBlobFetcher *fetcher =
        [[GZJelczIrohSidecarBlobFetcher alloc] initWithHTTPClient:stub
                                                    sidecarBaseURL:@"http://127.0.0.1:17352"];
    fetcher.defaultProviderEndpointId = @"bootstrap-endpoint";
    fetcher.defaultProviderEndpointTicket = @"ticket-string";
    fetcher.capabilityToken = @"sidecar-capability";
    NSData *got = [fetcher fetchObjectBytesForCID:cid
                                        providers:@[ @"https://origin.example" ]
                                            error:nil];
    XCTAssertEqualObjects(got, payload);
    NSDictionary *json =
        [NSJSONSerialization JSONObjectWithData:stub.lastRequestBody options:0 error:nil];
    XCTAssertEqualObjects(json[@"provider"][@"endpointId"], @"bootstrap-endpoint");
    XCTAssertEqualObjects(json[@"provider"][@"endpointTicket"], @"ticket-string");
}

- (void)testAcceptsEmptySidecarBody {
    NSData *payload = [NSData data];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczIrohSidecarBlobFetcher *fetcher =
        [[GZJelczIrohSidecarBlobFetcher alloc] initWithHTTPClient:stub
                                                    sidecarBaseURL:@"http://127.0.0.1:17352"];
    fetcher.capabilityToken = @"sidecar-capability";
    NSData *got = [fetcher fetchObjectBytesForCID:cid
                                        providers:@[ @"iroh://provider-endpoint-id" ]
                                            error:nil];
    XCTAssertEqualObjects(got, payload);
}

- (void)testRejectsNonLoopbackSidecarURL {
    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    GZJelczIrohSidecarBlobFetcher *fetcher =
        [[GZJelczIrohSidecarBlobFetcher alloc] initWithHTTPClient:stub
                                                    sidecarBaseURL:@"http://203.0.113.1:17352"];
    XCTAssertNil(fetcher);
}

- (void)testMissingCapabilityRejectsBeforeHTTPRequest {
    NSData *payload = [@"hello-ca-store" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    GZJelczIrohSidecarBlobFetcher *fetcher =
        [[GZJelczIrohSidecarBlobFetcher alloc] initWithHTTPClient:stub
                                                    sidecarBaseURL:@"http://127.0.0.1:17352"];
    NSError *error = nil;
    XCTAssertNil([fetcher fetchObjectBytesForCID:cid
                                       providers:@[ @"iroh://provider-endpoint-id" ]
                                           error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(stub.requestCount, 0u);
}

- (void)testRegistryRejectsUntrustedHostsWithoutHTTPRequests {
    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    NSArray<NSString *> *rejected = @[
        @"http://public.example:17352",
        @"http://169.254.169.254:17352",
        @"http://[fe80::1]:17352",
        @"http://iroh-a.rebind.example:17352",
    ];
    GZJelczIrohSidecarPeerRegistry *registry =
        [GZJelczIrohSidecarPeerRegistry registryWithHTTPClient:stub
                                                localSidecarURL:nil
                                                peerSidecarURLs:rejected
                                                       nodeName:@"jelcz"
                                                       trustLan:YES
                                                capabilityToken:@"sidecar-capability"];
    XCTAssertNotNil(registry);
    XCTAssertEqual(stub.requestCount, 0u);
    XCTAssertEqual(registry.remoteIdentities.count, 0u);
}

- (void)testRegistryDoesNotElevateTrustLanForComposeHost {
    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    GZJelczIrohSidecarPeerRegistry *registry =
        [GZJelczIrohSidecarPeerRegistry registryWithHTTPClient:stub
                                                localSidecarURL:nil
                                                peerSidecarURLs:@[ @"http://iroh-a:17352" ]
                                                       nodeName:@"jelcz"
                                                       trustLan:NO
                                                capabilityToken:@"sidecar-capability"];
    XCTAssertNotNil(registry);
    XCTAssertEqual(stub.requestCount, 0u);
}

- (void)testRegistryRequiresCapabilityBeforeHTTPRequest {
    GZJelczIrohSidecarHTTPStub *stub = [[GZJelczIrohSidecarHTTPStub alloc] init];
    GZJelczIrohSidecarPeerRegistry *registry =
        [GZJelczIrohSidecarPeerRegistry registryWithHTTPClient:stub
                                                localSidecarURL:@"http://127.0.0.1:17352"
                                                peerSidecarURLs:@[ @"http://127.0.0.1:17353" ]
                                                       nodeName:@"jelcz"
                                                       trustLan:NO
                                                capabilityToken:nil];
    XCTAssertNotNil(registry);
    XCTAssertEqual(stub.requestCount, 0u);
}

@end
