// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczStreamplaceBlobFetcher.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/CID.h"

@interface GZJelczStreamplaceHTTPStub : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, copy, nullable) NSData *bodyToReturn;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, assign) NSUInteger requestCount;
@property (nonatomic, copy, nullable) NSURL *lastURL;
@property (nonatomic, copy, nullable) NSDictionary *lastHeaders;
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *statusSequence;
@end

@implementation GZJelczStreamplaceHTTPStub
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
    self.requestCount += 1;
    self.lastURL = request.URL;
    self.lastHeaders = request.allHTTPHeaderFields;
    NSInteger status = self.statusCode;
    if (self.statusSequence.count > 0) {
        NSUInteger idx = self.requestCount - 1;
        if (idx < self.statusSequence.count) {
            status = self.statusSequence[idx].integerValue;
        }
    }
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:status
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:@{}];
    }
    if (status == 404) {
        return nil;
    }
    if (status != 200 && status != 206) {
        return nil;
    }
    return self.bodyToReturn;
}
@end

@interface JelczStreamplaceBlobFetcherTests : XCTestCase
@end

@implementation JelczStreamplaceBlobFetcherTests

- (ATProtoCID *)cidForPayload:(NSData *)payload {
    return [ATProtoCAObjectStore cidForData:payload
                                    profile:ATProtoCAObjectDigestProfileBLAKE3
                                      error:nil];
}

- (void)testBuildsGetVideoBlobURL {
    // Minimal MUXL-like ftyp header bytes for fixture identity.
    uint8_t ftyp[] = {
        0x00, 0x00, 0x00, 0x1c, 'f', 't', 'y', 'p',
        'm', 'u', 'x', 'l', 0x00, 0x00, 0x00, 0x00,
        'm', 'u', 'x', 'l', 'i', 's', 'o', 'm',
        'm', 'p', '4', '2'
    };
    NSData *payload = [NSData dataWithBytes:ftyp length:sizeof(ftyp)];
    ATProtoCID *cid = [self cidForPayload:payload];
    XCTAssertNotNil(cid);

    NSURL *url = [GZJelczStreamplaceBlobFetcher getVideoBlobURLForCID:cid
                                                      attributionDID:@"did:web:stream.place"
                                                     providerBaseURL:@"https://stream.place/ignored"];
    XCTAssertNotNil(url);
    XCTAssertEqualObjects(url.host, @"stream.place");
    XCTAssertTrue([url.path containsString:@"place.stream.playback.getVideoBlob"]);
    XCTAssertTrue([url.query containsString:@"did=did%3Aweb%3Astream.place"]);
    NSString *cidQuery = [NSString stringWithFormat:@"cid=%@", cid.stringValue];
    XCTAssertTrue([url.query containsString:cidQuery]);
}

- (void)testBlobNotFoundAdvancesProvider {
    uint8_t bytes[] = { 'm', 'u', 'x', 'l' };
    NSData *payload = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczStreamplaceHTTPStub *stub = [[GZJelczStreamplaceHTTPStub alloc] init];
    stub.statusSequence = @[ @404, @200 ];
    stub.bodyToReturn = payload;

    GZJelczStreamplaceBlobFetcher *fetcher =
        [[GZJelczStreamplaceBlobFetcher alloc] initWithHTTPClient:stub
                                                  attributionDID:@"did:plc:test"];
    NSError *error = nil;
    NSData *got = [fetcher fetchObjectBytesForCID:cid
                                        providers:@[ @"https://a.example", @"https://b.example" ]
                                            error:&error];
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqual(stub.requestCount, (NSUInteger)2);
    XCTAssertEqual(fetcher.blobNotFoundCount, (NSUInteger)1);
    XCTAssertEqual(fetcher.successCount, (NSUInteger)1);
    XCTAssertTrue([stub.lastURL.host isEqualToString:@"b.example"]);
}

- (void)testReturnsMUXLFixtureBody {
    uint8_t ftyp[] = {
        0x00, 0x00, 0x00, 0x1c, 'f', 't', 'y', 'p',
        'm', 'u', 'x', 'l', 0x00, 0x00, 0x00, 0x00,
        'm', 'u', 'x', 'l', 'i', 's', 'o', 'm',
        'm', 'p', '4', '2'
    };
    NSData *payload = [NSData dataWithBytes:ftyp length:sizeof(ftyp)];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczStreamplaceHTTPStub *stub = [[GZJelczStreamplaceHTTPStub alloc] init];
    stub.bodyToReturn = payload;

    GZJelczStreamplaceBlobFetcher *fetcher =
        [[GZJelczStreamplaceBlobFetcher alloc] initWithHTTPClient:stub
                                                  attributionDID:@"did:web:example.com"];
    NSError *error = nil;
    NSData *got = [fetcher fetchObjectBytesForCID:cid
                                        providers:@[ @"https://origin.example" ]
                                            error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(got, payload);
    XCTAssertTrue(got.length >= 8);
    XCTAssertEqual(((const char *)got.bytes)[4], 'f');
    XCTAssertEqual(((const char *)got.bytes)[5], 't');
    XCTAssertEqual(((const char *)got.bytes)[6], 'y');
    XCTAssertEqual(((const char *)got.bytes)[7], 'p');
}

- (void)testSendsRangeHeaderWhenRequested {
    uint8_t bytes[] = { 'm', 'u', 'x', 'l' };
    NSData *payload = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    ATProtoCID *cid = [self cidForPayload:payload];
    GZJelczStreamplaceHTTPStub *stub = [[GZJelczStreamplaceHTTPStub alloc] init];
    stub.statusCode = 206;
    stub.bodyToReturn = payload;
    GZJelczStreamplaceBlobFetcher *fetcher =
        [[GZJelczStreamplaceBlobFetcher alloc] initWithHTTPClient:stub
                                                  attributionDID:@"did:plc:r"];
    NSError *error = nil;
    NSData *got = [fetcher fetchObjectBytesForCID:cid
                                        providers:@[ @"https://origin.example" ]
                                      rangeHeader:@"bytes=0-3"
                                            error:&error];
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqualObjects(stub.lastHeaders[@"Range"], @"bytes=0-3");
}

@end
