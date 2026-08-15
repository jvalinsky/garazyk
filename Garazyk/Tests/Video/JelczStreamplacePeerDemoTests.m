// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczStreamplacePeerDemo.h"
#import "Video/GZJelczStreamplaceIrohBridge.h"
#import "Video/GZJelczPeerProviderIndex.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"
#import "Core/CID.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface ATProtoHttpServer (JelczStreamplacePeerDemoTesting)
- (ATProtoHttpResponse *)dispatchRequest:(ATProtoHttpRequest *)request;
@end

@interface GZJelczStreamplacePeerDemo (Testing)
- (NSDictionary *)pullPeerCID:(NSString *)cidStr
                     provider:(NSString *)provider
                          did:(NSString *)did
                        error:(NSError **)error;
- (NSDictionary *)allowlistedStatsDictionary;
@end

@interface GZJelczPeerDemoHTTPStub : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, copy, nullable) NSData *bodyToReturn;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, assign) NSUInteger requestCount;
@property (nonatomic, copy, nullable) NSURL *lastURL;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *subscribeResponseHeaders;
@property (nonatomic, assign) NSInteger attestationStatusCode;
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *requests;
- (NSUInteger)requestCountForPath:(NSString *)path;
@end

@implementation GZJelczPeerDemoHTTPStub

- (instancetype)init {
    self = [super init];
    if (self) {
        _statusCode = 200;
        _attestationStatusCode = 204;
        _subscribeResponseHeaders = @{ @"X-Jelcz-Bridge-Session": @"demo-session-1" };
        _requests = [NSMutableArray array];
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
    [self.requests addObject:request];
    BOOL isAttestation = [request.URL.path isEqualToString:@"/v1/evidence/muxl-attestations"];
    NSInteger statusCode = isAttestation ? self.attestationStatusCode : self.statusCode;
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:statusCode
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:isAttestation ? @{} : self.subscribeResponseHeaders];
    }
    return isAttestation ? nil : (statusCode == 200 ? self.bodyToReturn : nil);
}

- (NSUInteger)requestCountForPath:(NSString *)path {
    NSUInteger count = 0;
    for (NSURLRequest *request in self.requests) {
        if ([request.URL.path isEqualToString:path]) {
            count += 1;
        }
    }
    return count;
}

@end

@interface JelczStreamplacePeerDemoTests : XCTestCase
@property (nonatomic, copy) NSString *tempRoot;
@end

@implementation JelczStreamplacePeerDemoTests

- (void)setUp {
    [super setUp];
    self.tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"peer-demo-%@", NSUUID.UUID.UUIDString]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempRoot error:nil];
    [super tearDown];
}

- (ATProtoCID *)cidForPayload:(NSData *)payload {
    return [ATProtoCAObjectStore cidForData:payload
                                    profile:ATProtoCAObjectDigestProfileBLAKE3
                                      error:nil];
}

- (GZJelczStreamplacePeerDemo *)demoWithStore:(ATProtoCAObjectStore *)store
                                         stub:(GZJelczPeerDemoHTTPStub *)stub {
    GZJelczStreamplacePeerDemo *demo =
        [[GZJelczStreamplacePeerDemo alloc] initWithObjectStore:store
                                                      httpClient:stub
                                                 upstreamBaseURL:@"https://stream.place"
                                                   publicBaseURL:@"http://127.0.0.1:2596"];
    // The production composition root uses the demo's URLSession client.  The
    // test substitutes the same narrow mirror-client seam to observe transport.
    [demo setValue:stub forKey:@"httpClient"];
    demo.peerHTTPSProviders = @[ @"https://peer.example" ];
    return demo;
}

- (ATProtoCAObjectStore *)newStore {
    NSError *error = nil;
    ATProtoCAObjectStore *store =
        [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(store);
    return store;
}

- (GZJelczPeerProviderEntry *)bridgeOriginUpdatedAt:(NSDate *)updatedAt {
    GZJelczPeerProviderEntry *origin = [[GZJelczPeerProviderEntry alloc] init];
    origin.source = @"broadcast.origin";
    origin.streamerDID = @"did:plc:streamer";
    origin.serverDID = @"did:web:origin.example";
    origin.irohTicket = @"streamplace-node-ticket";
    origin.updatedAt = updatedAt;
    return origin;
}

- (NSData *)validBridgeSegment {
    ATProtoMUXLFragmentSample *sample = [[ATProtoMUXLFragmentSample alloc] init];
    sample.trackID = 1;
    sample.sequenceNumber = 1;
    sample.baseMediaDecodeTime = 0;
    sample.sampleDuration = 1000;
    sample.sampleBytes = [@"muxl bridge sample" dataUsingEncoding:NSUTF8StringEncoding];
    sample.syncSample = YES;
    NSData *fragment = [ATProtoMUXLFragment fragmentWithSample:sample error:nil];
    NSData *avcC = [NSData dataWithBytes:(const uint8_t[]){
        0x01, 0x64, 0x00, 0x1f, 0xff, 0xe1, 0x00, 0x04,
        0x67, 0x64, 0x00, 0x1f, 0x01, 0x00, 0x04, 0x68, 0xee, 0x3c, 0xb0
    } length:19];
    NSDictionary *catalog = @{
        @"video": @{ @"renditions": @{ @"main": @{
            @"codec": @"avc1.64001f",
            @"container": @{ @"kind": @"cmaf", @"timescale": @1000, @"trackId": @1 },
            @"codedWidth": @640,
            @"codedHeight": @360,
            @"description": avcC,
        } } },
    };
    return [ATProtoMUXLBox segmentWithCatalog:catalog fragments:@[ fragment ] error:nil];
}

- (ATProtoHttpRequest *)bridgeRouteRequestWithStreamer:(NSString *)streamer token:(NSString *)token {
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{ @"streamer": streamer }
                                                   options:0
                                                     error:nil];
    NSMutableDictionary *headers = [@{ @"Content-Type": @"application/json" } mutableCopy];
    if (token.length > 0) {
        headers[@"Authorization"] = [@"Bearer " stringByAppendingString:token];
    }
    return [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodPOST
                                           methodString:@"POST"
                                                 path:@"/demo/streamplace/api/pull-streamplace-iroh"
                                          queryString:@""
                                          queryParams:@{}
                                              version:@"HTTP/1.1"
                                             headers:headers
                                                body:body
                                       remoteAddress:@"127.0.0.1"];
}

- (ATProtoHttpRequest *)originMutationRequestWithJSON:(id)json token:(NSString *)token {
    NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    NSMutableDictionary *headers = [@{ @"Content-Type": @"application/json" } mutableCopy];
    if (token.length > 0) {
        headers[@"Authorization"] = [@"Bearer " stringByAppendingString:token];
    }
    return [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodPOST
                                           methodString:@"POST"
                                                 path:@"/demo/streamplace/api/origins"
                                          queryString:@""
                                          queryParams:@{}
                                              version:@"HTTP/1.1"
                                             headers:headers
                                                body:body
                                       remoteAddress:@"127.0.0.1"];
}

- (ATProtoHttpResponse *)dispatchBridgeRouteForDemo:(GZJelczStreamplacePeerDemo *)demo
                                           streamer:(NSString *)streamer {
    ATProtoHttpServer *server = [ATProtoHttpServer serverWithPort:0];
    [demo registerRoutesOnServer:server];
    return [server dispatchRequest:[self bridgeRouteRequestWithStreamer:streamer token:@"demo-capability"]];
}

- (void)testStreamplaceIrohBridgeRouteReportsDisabledWithoutDial {
    ATProtoCAObjectStore *store = [self newStore];
    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    demo.apiToken = @"demo-capability";
    ATProtoHttpResponse *response = [self dispatchBridgeRouteForDemo:demo streamer:@"did:plc:streamer"];
    XCTAssertEqual(response.statusCode, 503);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"BridgeDisabled");
    XCTAssertEqual(stub.requestCount, 0u);
}

- (void)testStreamplaceIrohBridgeRouteRejectsDeniedAndStaleOriginsBeforeDial {
    ATProtoCAObjectStore *store = [self newStore];
    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    demo.apiToken = @"demo-capability";
    demo.originEntries = @[ [self bridgeOriginUpdatedAt:[NSDate date]] ];
    demo.streamplaceIrohBridge =
        [[GZJelczStreamplaceIrohBridge alloc] initWithHTTPClient:stub
                                                    bridgeBaseURL:@"http://127.0.0.1:17401"
                                                  capabilityToken:@"bridge-capability"
                                                         trustLAN:NO
                                                 allowedStreamers:[NSSet setWithObject:@"did:plc:other"]];
    ATProtoHttpResponse *denied = [self dispatchBridgeRouteForDemo:demo streamer:@"did:plc:streamer"];
    XCTAssertEqual(denied.statusCode, 403);
    XCTAssertEqualObjects(denied.jsonBody[@"error"], @"StreamerNotAllowed");
    demo.streamplaceIrohBridge =
        [[GZJelczStreamplaceIrohBridge alloc] initWithHTTPClient:stub
                                                    bridgeBaseURL:@"http://127.0.0.1:17401"
                                                  capabilityToken:@"bridge-capability"
                                                         trustLAN:NO
                                                 allowedStreamers:[NSSet setWithObject:@"did:plc:streamer"]];
    demo.originEntries = @[ [self bridgeOriginUpdatedAt:[NSDate dateWithTimeIntervalSinceNow:-301]] ];
    ATProtoHttpResponse *stale = [self dispatchBridgeRouteForDemo:demo streamer:@"did:plc:streamer"];
    XCTAssertEqual(stale.statusCode, 422);
    XCTAssertEqualObjects(stale.jsonBody[@"error"], @"OriginStale");
    XCTAssertEqual(stub.requestCount, 0u);
}

- (void)testOriginMutationCanReplacePriorAcceptanceFixture {
    ATProtoCAObjectStore *store = [self newStore];
    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    demo.apiToken = @"demo-capability";
    ATProtoHttpServer *server = [ATProtoHttpServer serverWithPort:0];
    [demo registerRoutesOnServer:server];

    NSDictionary *first = @{
        @"$type": @"place.stream.broadcast.origin",
        @"streamer": @"did:plc:first",
        @"server": @"did:web:first.example",
        @"updatedAt": @"2026-08-13T20:00:00Z",
        @"irohTicket": @"first-ticket",
    };
    ATProtoHttpResponse *appended =
        [server dispatchRequest:[self originMutationRequestWithJSON:@[ first ]
                                                             token:@"demo-capability"]];
    XCTAssertEqual(appended.statusCode, 200);
    XCTAssertEqualObjects(appended.jsonBody[@"replaced"], @NO);
    XCTAssertEqualObjects(appended.jsonBody[@"originEntryCount"], @1);

    NSDictionary *second = @{
        @"$type": @"place.stream.broadcast.origin",
        @"streamer": @"did:plc:second",
        @"server": @"did:web:second.example",
        @"updatedAt": @"2026-08-13T20:01:00Z",
        @"irohTicket": @"second-ticket",
    };
    ATProtoHttpResponse *replaced =
        [server dispatchRequest:[self originMutationRequestWithJSON:@{
            @"origins": @[ second ],
            @"replace": @YES,
        } token:@"demo-capability"]];
    XCTAssertEqual(replaced.statusCode, 200);
    XCTAssertEqualObjects(replaced.jsonBody[@"replaced"], @YES);
    XCTAssertEqualObjects(replaced.jsonBody[@"originEntryCount"], @1);
    XCTAssertEqual(demo.originEntries.count, 1u);
    XCTAssertEqualObjects(demo.originEntries[0].streamerDID, @"did:plc:second");
}

- (void)testStreamplaceIrohBridgeRouteReturnsBoundedEvidenceOnly {
    ATProtoCAObjectStore *store = [self newStore];
    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    stub.bodyToReturn = [self validBridgeSegment];
    XCTAssertNotNil(stub.bodyToReturn);
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    demo.apiToken = @"demo-capability";
    demo.originEntries = @[ [self bridgeOriginUpdatedAt:[NSDate date]] ];
    demo.streamplaceIrohBridge =
        [[GZJelczStreamplaceIrohBridge alloc] initWithHTTPClient:stub
                                                    bridgeBaseURL:@"http://127.0.0.1:17401"
                                                  capabilityToken:@"bridge-capability"
                                                         trustLAN:NO
                                                 allowedStreamers:[NSSet setWithObject:@"did:plc:streamer"]];
    ATProtoHttpResponse *response = [self dispatchBridgeRouteForDemo:demo streamer:@"did:plc:streamer"];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"streamer"], @"did:plc:streamer");
    XCTAssertEqual([(NSNumber *)response.jsonBody[@"bytes"] unsignedIntegerValue], stub.bodyToReturn.length);
    XCTAssertEqualObjects(response.jsonBody[@"validation"], @YES);
    XCTAssertEqualObjects(response.jsonBody[@"sessionId"], @"demo-session-1");
    XCTAssertTrue([response.jsonBody[@"ticketFingerprint"] hasPrefix:@"sha256:"]);
    XCTAssertTrue([response.jsonBody[@"contentSha256"] hasPrefix:@"sha256:"]);
    XCTAssertEqualObjects(response.jsonBody[@"digest"], response.jsonBody[@"contentSha256"]);
    XCTAssertNotEqualObjects(response.jsonBody[@"contentSha256"], response.jsonBody[@"ticketFingerprint"]);
    XCTAssertNil(response.jsonBody[@"irohTicket"]);
    XCTAssertNil(response.jsonBody[@"segment"]);
    XCTAssertEqual(stub.requestCount, 2u);
    XCTAssertEqualObjects(stub.requests[0].URL.path, @"/v1/subscribe");
    XCTAssertEqualObjects(stub.requests[1].URL.path, @"/v1/evidence/muxl-attestations");
}

- (void)testHTTPSPullRequiresDestinationMissAndReportsHTTPSSource {
    ATProtoCAObjectStore *store = [self newStore];
    NSData *payload = [@"unique-https-transport-payload" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    XCTAssertNil([store dataForCID:cid error:nil]);

    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    NSDictionary *result = [demo pullPeerCID:cid.stringValue
                                     provider:@"https://peer.example"
                                          did:@"did:web:jelcz.local"
                                        error:nil];

    XCTAssertEqualObjects(result[@"status"], @"peered-verified");
    XCTAssertEqualObjects(result[@"peerSource"], @"https-peer");
    XCTAssertEqualObjects(result[@"blake3Verified"], @YES);
    XCTAssertEqual(stub.requestCount, (NSUInteger)1);
    XCTAssertEqualObjects(stub.lastURL.host, @"peer.example");
    XCTAssertEqualObjects([store dataForCID:cid error:nil], payload);
    XCTAssertEqualObjects([demo allowlistedStatsDictionary][@"recentServes"][0][@"mode"],
                          @"https-peer");
}

- (void)testHTTPPullRequiresDestinationMissAndReportsHTTPSource {
    ATProtoCAObjectStore *store = [self newStore];
    NSData *payload = [@"unique-http-transport-payload" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    XCTAssertNil([store dataForCID:cid error:nil]);

    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    demo.peerHTTPSProviders = @[ @"http://peer.example" ];
    NSDictionary *result = [demo pullPeerCID:cid.stringValue
                                     provider:@"http://peer.example"
                                          did:@"did:web:jelcz.local"
                                        error:nil];

    XCTAssertEqualObjects(result[@"status"], @"peered-verified");
    XCTAssertEqualObjects(result[@"peerSource"], @"http-peer");
    XCTAssertEqualObjects(result[@"blake3Verified"], @YES);
    XCTAssertEqual(stub.requestCount, (NSUInteger)1);
    XCTAssertEqualObjects(stub.lastURL.scheme, @"http");
    XCTAssertEqualObjects([store dataForCID:cid error:nil], payload);
    XCTAssertEqualObjects([demo allowlistedStatsDictionary][@"recentServes"][0][@"mode"],
                          @"http-peer");
}

- (void)testIrohPullRequiresDestinationMissAndReportsIrohSource {
    ATProtoCAObjectStore *store = [self newStore];
    NSData *payload = [@"unique-iroh-transport-payload" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    XCTAssertNil([store dataForCID:cid error:nil]);

    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    demo.irohSidecarURL = @"http://127.0.0.1:17352";
    demo.irohSidecarCapabilityToken = @"sidecar-capability";
    NSString *provider = @"iroh://lab-provider-endpoint";
    demo.irohBootstrapEndpointId = @"lab-provider-endpoint";
    NSDictionary *result = [demo pullPeerCID:cid.stringValue
                                     provider:provider
                                          did:@"did:web:jelcz.local"
                                        error:nil];

    XCTAssertEqualObjects(result[@"status"], @"peered-verified");
    XCTAssertEqualObjects(result[@"peerSource"], @"iroh-peer");
    XCTAssertEqualObjects(result[@"blake3Verified"], @YES);
    XCTAssertEqual(stub.requestCount, (NSUInteger)2);
    XCTAssertEqual([stub requestCountForPath:@"/v1/identity"], (NSUInteger)1);
    XCTAssertEqual([stub requestCountForPath:@"/v1/fetch"], (NSUInteger)1);
    XCTAssertEqualObjects(stub.lastURL.host, @"127.0.0.1");
    XCTAssertEqualObjects(stub.lastURL.path, @"/v1/fetch");
    for (NSURLRequest *request in stub.requests) {
        if ([request.URL.path isEqualToString:@"/v1/identity"] ||
            [request.URL.path isEqualToString:@"/v1/fetch"]) {
            XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Authorization"],
                                  @"Bearer sidecar-capability");
        }
    }
    XCTAssertEqualObjects([store dataForCID:cid error:nil], payload);
}

- (void)testRejectsUnconfiguredHTTPSProviderBeforeOutboundFetch {
    ATProtoCAObjectStore *store = [self newStore];
    NSData *payload = [@"provider-allowlist-payload" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];

    NSDictionary *result = [demo pullPeerCID:cid.stringValue
                                     provider:@"https://unconfigured.example"
                                          did:@"did:web:jelcz.local"
                                        error:nil];

    XCTAssertEqualObjects(result[@"error"], @"ProviderNotAllowed");
    XCTAssertEqual(stub.requestCount, (NSUInteger)0);
    XCTAssertNil([store dataForCID:cid error:nil]);
}

- (void)testRejectsUnknownIrohEndpointBeforeOutboundFetch {
    ATProtoCAObjectStore *store = [self newStore];
    NSData *payload = [@"iroh-provider-allowlist-payload" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    stub.bodyToReturn = payload;
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    demo.irohSidecarURL = @"http://127.0.0.1:17352";
    demo.irohBootstrapEndpointId = @"known-endpoint";

    NSDictionary *result = [demo pullPeerCID:cid.stringValue
                                     provider:@"iroh://unknown-endpoint"
                                          did:@"did:web:jelcz.local"
                                        error:nil];

    XCTAssertEqualObjects(result[@"error"], @"ProviderNotAllowed");
    XCTAssertEqual(stub.requestCount, (NSUInteger)1);
    XCTAssertEqual([stub requestCountForPath:@"/v1/identity"], (NSUInteger)1);
    XCTAssertEqual([stub requestCountForPath:@"/v1/fetch"], (NSUInteger)0);
    XCTAssertNil([store dataForCID:cid error:nil]);
}

- (void)testAlreadyLocalDoesNotClaimATransportTransfer {
    ATProtoCAObjectStore *store = [self newStore];
    NSData *payload = [@"already-local-is-not-a-transfer" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [store putData:payload
                         expectedCID:nil
                             profile:ATProtoCAObjectDigestProfileBLAKE3
                               error:nil];
    XCTAssertNotNil(cid);

    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    NSDictionary *result = [demo pullPeerCID:cid.stringValue
                                     provider:@"https://peer.example"
                                          did:@"did:web:jelcz.local"
                                        error:nil];

    XCTAssertEqualObjects(result[@"status"], @"already-local");
    XCTAssertEqualObjects(result[@"peerSource"], @"ca-store");
    XCTAssertNil(result[@"blake3Verified"]);
    XCTAssertEqual(stub.requestCount, (NSUInteger)0);
}

- (void)testRejectsWrongBytesWithoutClaimingVerifiedTransport {
    ATProtoCAObjectStore *store = [self newStore];
    NSData *expected = [@"expected-transport-payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *wrong = [@"wrong-transport-payload" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForPayload:expected];
    XCTAssertNil([store dataForCID:cid error:nil]);

    GZJelczPeerDemoHTTPStub *stub = [[GZJelczPeerDemoHTTPStub alloc] init];
    stub.bodyToReturn = wrong;
    GZJelczStreamplacePeerDemo *demo = [self demoWithStore:store stub:stub];
    NSDictionary *result = [demo pullPeerCID:cid.stringValue
                                     provider:@"https://peer.example"
                                          did:@"did:web:jelcz.local"
                                        error:nil];

    XCTAssertEqualObjects(result[@"error"], @"PullFailed");
    XCTAssertNil(result[@"status"]);
    XCTAssertNil(result[@"peerSource"]);
    XCTAssertNil([store dataForCID:cid error:nil]);
}

@end
