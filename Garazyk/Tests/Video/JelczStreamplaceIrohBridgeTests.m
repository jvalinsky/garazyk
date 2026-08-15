// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "Core/GZHTTPClient.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"
#import "Video/GZJelczPeerProviderIndex.h"
#import "Video/GZJelczStreamplaceIrohBridge.h"

@interface GZJelczStreamplaceIrohBridgeHTTPStub : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, copy, nullable) NSData *bodyToReturn;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, assign) NSUInteger requestCount;
@property (nonatomic, copy, nullable) NSURL *lastURL;
@property (nonatomic, copy, nullable) NSData *lastRequestBody;
@property (nonatomic, copy, nullable) NSString *lastAuthorization;
@property (nonatomic, strong, nullable) GZHTTPClientOptions *lastOptions;
@property (nonatomic, strong, nullable) NSError *requestErrorToReturn;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *subscribeResponseHeaders;
@property (nonatomic, assign) NSInteger attestationStatusCode;
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *requests;
@end

@implementation GZJelczStreamplaceIrohBridgeHTTPStub
- (instancetype)init {
    self = [super init];
    if (self) {
        _statusCode = 200;
        _attestationStatusCode = 204;
        _subscribeResponseHeaders = @{ @"X-Jelcz-Bridge-Session": @"bridge-session-1" };
        _requests = [NSMutableArray array];
    }
    return self;
}
- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(id)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    (void)options;
    self.requestCount += 1;
    self.lastURL = request.URL;
    self.lastRequestBody = request.HTTPBody;
    self.lastAuthorization = [request valueForHTTPHeaderField:@"Authorization"];
    self.lastOptions = options;
    [self.requests addObject:request];
    BOOL isAttestation = [request.URL.path isEqualToString:@"/v1/evidence/muxl-attestations"];
    NSInteger statusCode = isAttestation ? self.attestationStatusCode : self.statusCode;
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:statusCode
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:isAttestation ? @{} : self.subscribeResponseHeaders];
    }
    if (error && self.requestErrorToReturn) {
        *error = self.requestErrorToReturn;
    }
    return (isAttestation || self.requestErrorToReturn) ? nil : self.bodyToReturn;
}
@end

@interface JelczStreamplaceIrohBridgeTests : XCTestCase
@end

@implementation JelczStreamplaceIrohBridgeTests

- (GZJelczPeerProviderEntry *)allowedOriginAt:(NSDate *)updatedAt {
    GZJelczPeerProviderEntry *origin = [[GZJelczPeerProviderEntry alloc] init];
    origin.source = @"broadcast.origin";
    origin.streamerDID = @"did:plc:streamer";
    origin.serverDID = @"did:web:origin.example";
    origin.irohTicket = @"streamplace-node-ticket";
    origin.updatedAt = updatedAt;
    return origin;
}

- (NSData *)validSegment {
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

- (GZJelczStreamplaceIrohBridge *)bridgeWithStub:(GZJelczStreamplaceIrohBridgeHTTPStub *)stub {
    return [[GZJelczStreamplaceIrohBridge alloc] initWithHTTPClient:stub
                                                       bridgeBaseURL:@"http://127.0.0.1:17401"
                                                     capabilityToken:@"bridge-capability"
                                                            trustLAN:NO
                                                    allowedStreamers:[NSSet setWithObject:@"did:plc:streamer"]];
}

- (void)testDeniesBeforeDialWhenStreamerIsNotAllowed {
    GZJelczStreamplaceIrohBridgeHTTPStub *stub = [[GZJelczStreamplaceIrohBridgeHTTPStub alloc] init];
    GZJelczStreamplaceIrohBridge *bridge =
        [[GZJelczStreamplaceIrohBridge alloc] initWithHTTPClient:stub
                                                    bridgeBaseURL:@"http://127.0.0.1:17401"
                                                  capabilityToken:@"bridge-capability"
                                                         trustLAN:NO
                                                 allowedStreamers:[NSSet setWithObject:@"did:plc:other"]];
    NSError *error = nil;
    XCTAssertNil([bridge receiveSegmentFromOrigin:[self allowedOriginAt:[NSDate date]] now:[NSDate date] error:&error]);
    XCTAssertEqual(error.code, GZJelczStreamplaceIrohBridgeErrorDenied);
    XCTAssertEqual(stub.requestCount, 0u);
}

- (void)testRejectsStaleAndMalformedOriginsBeforeDial {
    GZJelczStreamplaceIrohBridgeHTTPStub *stub = [[GZJelczStreamplaceIrohBridgeHTTPStub alloc] init];
    GZJelczStreamplaceIrohBridge *bridge = [self bridgeWithStub:stub];
    NSDate *now = [NSDate date];
    NSError *error = nil;
    XCTAssertNil([bridge receiveSegmentFromOrigin:[self allowedOriginAt:[now dateByAddingTimeInterval:-301]] now:now error:&error]);
    XCTAssertEqual(error.code, GZJelczStreamplaceIrohBridgeErrorStaleOrigin);
    GZJelczPeerProviderEntry *malformed = [self allowedOriginAt:now];
    malformed.irohTicket = nil;
    XCTAssertNil([bridge receiveSegmentFromOrigin:malformed now:now error:&error]);
    XCTAssertEqual(error.code, GZJelczStreamplaceIrohBridgeErrorInvalidOrigin);
    XCTAssertEqual(stub.requestCount, 0u);
}

- (void)testRejectsOversizeAndCorruptMUXLResponses {
    GZJelczStreamplaceIrohBridgeHTTPStub *stub = [[GZJelczStreamplaceIrohBridgeHTTPStub alloc] init];
    GZJelczStreamplaceIrohBridge *bridge = [self bridgeWithStub:stub];
    bridge.maximumSegmentBytes = 4;
    stub.bodyToReturn = [self validSegment];
    NSError *error = nil;
    XCTAssertNil([bridge receiveSegmentFromOrigin:[self allowedOriginAt:[NSDate date]] now:[NSDate date] error:&error]);
    XCTAssertEqual(error.code, GZJelczStreamplaceIrohBridgeErrorBodyTooLarge);
    XCTAssertEqual(stub.requestCount, 1u);
    stub.requestErrorToReturn = [NSError errorWithDomain:GZHTTPClientErrorDomain
                                                     code:GZHTTPClientErrorResponseTooLarge
                                                 userInfo:nil];
    error = nil;
    XCTAssertNil([bridge receiveSegmentFromOrigin:[self allowedOriginAt:[NSDate date]] now:[NSDate date] error:&error]);
    XCTAssertEqual(error.code, GZJelczStreamplaceIrohBridgeErrorBodyTooLarge);
    XCTAssertEqual(stub.requestCount, 2u);
    stub.requestErrorToReturn = nil;
    bridge.maximumSegmentBytes = 1024 * 1024;
    NSData *valid = [self validSegment];
    XCTAssertNotNil(valid);
    if (!valid) return;
    stub.bodyToReturn = [valid subdataWithRange:NSMakeRange(0, valid.length - 1)];
    XCTAssertNil([bridge receiveSegmentFromOrigin:[self allowedOriginAt:[NSDate date]] now:[NSDate date] error:&error]);
    XCTAssertEqual(error.code, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL);
    XCTAssertEqual(stub.requestCount, 3u);
    XCTAssertEqualObjects(stub.requests.lastObject.URL.path, @"/v1/subscribe");
}

- (void)testValidatesExactResponseBeforeCapabilityProtectedAttestation {
    GZJelczStreamplaceIrohBridgeHTTPStub *stub = [[GZJelczStreamplaceIrohBridgeHTTPStub alloc] init];
    stub.bodyToReturn = [self validSegment];
    GZJelczStreamplaceIrohBridge *bridge = [self bridgeWithStub:stub];
    NSError *error = nil;
    GZJelczStreamplaceIrohBridgeEvidence *evidence = nil;
    NSData *received = [bridge receiveSegmentFromOrigin:[self allowedOriginAt:[NSDate date]]
                                                     now:[NSDate date]
                                                evidence:&evidence
                                                   error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(received, stub.bodyToReturn);
    XCTAssertEqual(stub.requestCount, 2u);
    NSURLRequest *subscription = stub.requests[0];
    NSURLRequest *attestation = stub.requests[1];
    XCTAssertEqualObjects(subscription.URL.path, @"/v1/subscribe");
    XCTAssertEqualObjects(attestation.URL.path, @"/v1/evidence/muxl-attestations");
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:subscription.HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(payload[@"streamer"], @"did:plc:streamer");
    XCTAssertEqualObjects(payload[@"irohTicket"], @"streamplace-node-ticket");
    XCTAssertEqualObjects(payload[@"consentAuthorized"], @YES);
    XCTAssertNil(payload[@"expectedNodeId"]);
    XCTAssertEqualObjects([subscription.HTTPBody length] > 0 ? @YES : @NO, @YES);
    XCTAssertEqualObjects([subscription.URL scheme], @"http");
    XCTAssertEqualObjects([attestation valueForHTTPHeaderField:@"Authorization"], @"Bearer bridge-capability");
    NSDictionary *attestationPayload =
        [NSJSONSerialization JSONObjectWithData:attestation.HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(attestationPayload[@"sessionId"], @"bridge-session-1");
    XCTAssertEqual([(NSNumber *)attestationPayload[@"contentBytes"] unsignedIntegerValue], received.length);
    XCTAssertEqualObjects(attestationPayload[@"muxlStructuralValidation"], @YES);
    XCTAssertTrue([attestationPayload[@"ticketFingerprint"] hasPrefix:@"sha256:"]);
    XCTAssertEqual([(NSString *)attestationPayload[@"ticketFingerprint"] length], 71u);
    XCTAssertNotEqualObjects(attestationPayload[@"ticketFingerprint"], @"streamplace-node-ticket");
    XCTAssertTrue([attestationPayload[@"contentSha256"] hasPrefix:@"sha256:"]);
    XCTAssertEqual([(NSString *)attestationPayload[@"contentSha256"] length], 71u);
    XCTAssertNotEqualObjects(attestationPayload[@"contentSha256"], attestationPayload[@"ticketFingerprint"]);
    XCTAssertEqualObjects(evidence.sessionID, @"bridge-session-1");
    XCTAssertEqual(evidence.contentBytes, received.length);
    XCTAssertEqualObjects(evidence.contentSHA256, attestationPayload[@"contentSha256"]);
    XCTAssertTrue(evidence.isStructurallyValid);
    XCTAssertEqual(stub.lastOptions.timeout, bridge.timeout);
    XCTAssertEqual(stub.lastOptions.maxResponseBytes, bridge.maximumSegmentBytes);
    XCTAssertTrue(stub.lastOptions.allowHTTP);
    XCTAssertTrue(stub.lastOptions.allowPrivateHosts);
    XCTAssertFalse(stub.lastOptions.followRedirects);
}

- (void)testMissingOrMismatchedBridgeSessionNeverAttests {
    GZJelczStreamplaceIrohBridgeHTTPStub *stub = [[GZJelczStreamplaceIrohBridgeHTTPStub alloc] init];
    stub.bodyToReturn = [self validSegment];
    stub.subscribeResponseHeaders = @{};
    GZJelczStreamplaceIrohBridge *bridge = [self bridgeWithStub:stub];
    NSError *error = nil;
    XCTAssertNil([bridge receiveSegmentFromOrigin:[self allowedOriginAt:[NSDate date]] now:[NSDate date] error:&error]);
    XCTAssertEqual(error.code, GZJelczStreamplaceIrohBridgeErrorMissingSession);
    XCTAssertEqual(stub.requestCount, 1u);

    stub.subscribeResponseHeaders = @{ @"X-Jelcz-Bridge-Session": @"expired-session" };
    stub.attestationStatusCode = 409;
    error = nil;
    XCTAssertNil([bridge receiveSegmentFromOrigin:[self allowedOriginAt:[NSDate date]] now:[NSDate date] error:&error]);
    XCTAssertEqual(error.code, GZJelczStreamplaceIrohBridgeErrorAttestationRejected);
    XCTAssertEqual(stub.requestCount, 3u);
    XCTAssertEqualObjects(stub.requests.lastObject.URL.path, @"/v1/evidence/muxl-attestations");
}

- (void)testDisabledPathAndNonlocalBridgeURL {
    XCTAssertFalse([GZJelczStreamplaceIrohBridge isEnabledInEnvironment:@{}]);
    NSDictionary *disabled = @{
        @"JELCZ_STREAMPLACE_IROH_BRIDGE": @"0",
        @"JELCZ_STREAMPLACE_IROH_BRIDGE_URL": @"http://127.0.0.1:17401",
    };
    XCTAssertFalse([GZJelczStreamplaceIrohBridge isEnabledInEnvironment:disabled]);
    NSDictionary *enabled = @{
        @"JELCZ_STREAMPLACE_IROH_BRIDGE": @"yes",
    };
    XCTAssertTrue([GZJelczStreamplaceIrohBridge isEnabledInEnvironment:enabled]);
    NSDictionary *nonlocal = @{
        @"JELCZ_STREAMPLACE_IROH_BRIDGE_URL": @"http://198.51.100.9:17401",
    };
    XCTAssertNil([GZJelczStreamplaceIrohBridge bridgeHTTPBaseURLFromEnvironment:nonlocal]);
    NSDictionary *privateLab = @{
        @"JELCZ_STREAMPLACE_IROH_BRIDGE_URL": @"http://streamplace-track-b-bridge:17353",
        @"JELCZ_STREAMPLACE_IROH_BRIDGE_TRUST_LAN": @"1",
    };
    XCTAssertEqualObjects(
        [GZJelczStreamplaceIrohBridge bridgeHTTPBaseURLFromEnvironment:privateLab],
        @"http://streamplace-track-b-bridge:17353");
    GZJelczStreamplaceIrohBridgeHTTPStub *stub = [[GZJelczStreamplaceIrohBridgeHTTPStub alloc] init];
    XCTAssertNotNil([[GZJelczStreamplaceIrohBridge alloc]
        initWithHTTPClient:stub
             bridgeBaseURL:@"http://streamplace-track-b-bridge:17353"
           capabilityToken:@"bridge-capability"
                  trustLAN:YES
          allowedStreamers:[NSSet set]]);
    XCTAssertNil([[GZJelczStreamplaceIrohBridge alloc]
        initWithHTTPClient:stub
             bridgeBaseURL:@"http://public.example:17353"
           capabilityToken:@"bridge-capability"
                  trustLAN:YES
          allowedStreamers:[NSSet set]]);
    XCTAssertNil([[GZJelczStreamplaceIrohBridge alloc] initWithHTTPClient:stub
                                                          bridgeBaseURL:@"http://127.0.0.1:17401"
                                                        capabilityToken:@"  "
                                                               trustLAN:NO
                                                       allowedStreamers:[NSSet set]]);
}

- (void)testBoundedByteLimitRejectsInvalidValues {
    XCTAssertEqual([GZJelczStreamplaceIrohBridge boundedByteLimitFromEnvironment:@{ @"limit": @"1024" }
                                                                         key:@"limit"
                                                                    fallback:512
                                                                    maximum:2048],
                   1024u);
    XCTAssertEqual([GZJelczStreamplaceIrohBridge boundedByteLimitFromEnvironment:@{ @"limit": @"-1" }
                                                                         key:@"limit"
                                                                    fallback:512
                                                                    maximum:2048],
                   512u);
    XCTAssertEqual([GZJelczStreamplaceIrohBridge boundedByteLimitFromEnvironment:@{ @"limit": @"2049" }
                                                                         key:@"limit"
                                                                    fallback:512
                                                                    maximum:2048],
                   512u);
}

@end
