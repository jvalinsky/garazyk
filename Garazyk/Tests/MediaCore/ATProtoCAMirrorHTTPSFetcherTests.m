// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoCAMirrorHTTPStubClient : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, copy, nullable) NSData *bodyToReturn;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, assign) NSUInteger requestCount;
@property (nonatomic, copy, nullable) NSURL *lastURL;
@end

@implementation ATProtoCAMirrorHTTPStubClient
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
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:self.statusCode
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:@{}];
    }
    if (self.statusCode != 200 || !self.bodyToReturn) {
        return nil;
    }
    return self.bodyToReturn;
}
@end

@interface ATProtoCAMirrorHTTPSequenceClient : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, copy) NSArray<NSNumber *> *statusCodes;
@property (nonatomic, copy) NSData *successBody;
@property (nonatomic, assign) NSUInteger requestCount;
@end

@implementation ATProtoCAMirrorHTTPSequenceClient
- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(id)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    (void)options;
    NSInteger status = 500;
    if (self.requestCount < self.statusCodes.count) {
        status = self.statusCodes[self.requestCount].integerValue;
    }
    self.requestCount += 1;
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:status
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:@{}];
    }
    if (status != 200) {
        return nil;
    }
    return self.successBody;
}
@end

@interface ATProtoCAMirrorHTTPSFetcherTests : XCTestCase
@end

@implementation ATProtoCAMirrorHTTPSFetcherTests

- (ATProtoCID *)sha256CIDForString:(NSString *)string {
    NSData *payload = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [ATProtoCAObjectStore cidForData:payload
                                    profile:ATProtoCAObjectDigestProfileSHA256
                                      error:nil];
}

- (void)testBuildsRASLURLFromHTTPSBase {
    ATProtoCID *cid = [self sha256CIDForString:@"x"];
    XCTAssertNotNil(cid);
    NSURL *url = [ATProtoCAMirrorHTTPSFetcher raslURLForCID:cid
                                             providerBaseURL:@"https://origin.example:8443/ignored"];
    NSString *expected =
        [NSString stringWithFormat:@"https://origin.example:8443/.well-known/rasl/%@", cid.stringValue];
    XCTAssertEqualObjects(url.absoluteString, expected);
}

- (void)testBuildsRASLURLFromBareHost {
    ATProtoCID *cid = [self sha256CIDForString:@"y"];
    NSURL *url = [ATProtoCAMirrorHTTPSFetcher raslURLForCID:cid providerBaseURL:@"mirror.example"];
    NSString *expected =
        [NSString stringWithFormat:@"https://mirror.example/.well-known/rasl/%@", cid.stringValue];
    XCTAssertEqualObjects(url.absoluteString, expected);
}

- (void)testFetchesFirstSuccessfulProvider {
    NSData *payload = [@"mirror-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload
                                               profile:ATProtoCAObjectDigestProfileSHA256
                                                 error:nil];
    ATProtoCAMirrorHTTPStubClient *stub = [[ATProtoCAMirrorHTTPStubClient alloc] init];
    stub.bodyToReturn = payload;
    ATProtoCAMirrorHTTPSFetcher *fetcher =
        [[ATProtoCAMirrorHTTPSFetcher alloc] initWithHTTPClient:stub];

    NSError *error = nil;
    NSData *got = [fetcher fetchObjectBytesForCID:cid
                                        providers:@[ @"https://a.example", @"https://b.example" ]
                                            error:&error];
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqual(stub.requestCount, (NSUInteger)1);
    XCTAssertTrue([stub.lastURL.path containsString:cid.stringValue]);
}

- (void)testSkipsFailedProviderThenSucceeds {
    NSData *payload = [@"second" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload
                                               profile:ATProtoCAObjectDigestProfileSHA256
                                                 error:nil];
    ATProtoCAMirrorHTTPSequenceClient *seq = [[ATProtoCAMirrorHTTPSequenceClient alloc] init];
    seq.statusCodes = @[ @404, @200 ];
    seq.successBody = payload;
    ATProtoCAMirrorHTTPSFetcher *fetcher =
        [[ATProtoCAMirrorHTTPSFetcher alloc] initWithHTTPClient:seq];

    NSError *error = nil;
    NSData *got = [fetcher fetchObjectBytesForCID:cid
                                        providers:@[ @"https://a.example", @"https://b.example" ]
                                            error:&error];
    XCTAssertEqualObjects(got, payload);
    XCTAssertEqual(seq.requestCount, (NSUInteger)2);
}

@end
