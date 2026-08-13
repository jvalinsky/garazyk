// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczStreamplaceCompatServe.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Core/CID.h"

@interface JelczStreamplaceCompatServeTests : XCTestCase
@property (nonatomic, strong) NSString *storePath;
@property (nonatomic, strong) ATProtoCAObjectStore *store;
@property (nonatomic, strong) GZJelczStreamplaceCompatServe *serve;
@property (nonatomic, strong) ATProtoCID *cid;
@property (nonatomic, strong) NSData *payload;
@end

@implementation JelczStreamplaceCompatServeTests

- (void)setUp {
    [super setUp];
    self.storePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError *error = nil;
    self.store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.storePath error:&error];
    XCTAssertNotNil(self.store, @"%@", error);
    uint8_t bytes[] = {
        0x00, 0x00, 0x00, 0x1c, 'f', 't', 'y', 'p',
        'm', 'u', 'x', 'l', 0x00, 0x00, 0x00, 0x00,
        'm', 'u', 'x', 'l', 'i', 's', 'o', 'm',
        'm', 'p', '4', '2'
    };
    self.payload = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    self.cid = [self.store putData:self.payload
                       expectedCID:nil
                           profile:ATProtoCAObjectDigestProfileBLAKE3
                             error:&error];
    XCTAssertNotNil(self.cid, @"%@", error);
    self.serve = [[GZJelczStreamplaceCompatServe alloc] initWithObjectStore:self.store];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.storePath error:nil];
    [super tearDown];
}

- (ATProtoHttpRequest *)requestWithDID:(NSString *)did
                                   cid:(NSString *)cid
                                 range:(NSString *)range {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (range.length > 0) {
        headers[@"Range"] = range;
    }
    NSString *query = [NSString stringWithFormat:@"did=%@&cid=%@", did, cid];
    return [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                          methodString:@"GET"
                                                  path:@"/xrpc/place.stream.playback.getVideoBlob"
                                           queryString:query
                                           queryParams:@{@"did": did, @"cid": cid}
                                               version:@"HTTP/1.1"
                                               headers:headers
                                                  body:[NSData data]
                                         remoteAddress:@"127.0.0.1"];
}

- (void)testFullGetReturnsVerifiedBody {
    ATProtoHttpRequest *request = [self requestWithDID:@"did:plc:alice"
                                                   cid:self.cid.stringValue
                                                 range:nil];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    NSError *error = nil;
    XCTAssertTrue([self.serve handleRequest:request response:response error:&error], @"%@", error);
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.body, self.payload);
}

- (void)testRangedGet {
    ATProtoHttpRequest *request = [self requestWithDID:@"did:plc:alice"
                                                   cid:self.cid.stringValue
                                                 range:@"bytes=0-3"];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    XCTAssertTrue([self.serve handleRequest:request response:response error:nil]);
    XCTAssertEqual(response.statusCode, 206);
    XCTAssertEqual(response.body.length, 4u);
    XCTAssertEqualObjects(response.body, [self.payload subdataWithRange:NSMakeRange(0, 4)]);
}

- (void)testBlobNotFound {
    NSData *other = [@"other" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *missing = [ATProtoCAObjectStore cidForData:other
                                                   profile:ATProtoCAObjectDigestProfileBLAKE3
                                                     error:nil];
    ATProtoHttpRequest *request = [self requestWithDID:@"did:plc:alice"
                                                   cid:missing.stringValue
                                                 range:nil];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    XCTAssertFalse([self.serve handleRequest:request response:response error:nil]);
    XCTAssertEqual(response.statusCode, 404);
}

- (void)testOriginAttestation {
    NSDictionary *rec = [self.serve originAttestationForCIDString:self.cid.stringValue error:nil];
    XCTAssertEqualObjects(rec[@"blob"], self.cid.stringValue);
    XCTAssertEqualObjects(rec[@"size"], @(self.payload.length));
}

@end
