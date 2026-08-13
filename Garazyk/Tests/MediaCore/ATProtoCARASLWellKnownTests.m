// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoCARASLWellKnown.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoCARASLWellKnownTests : XCTestCase
@property (nonatomic, copy) NSString *tempRoot;
@end

@implementation ATProtoCARASLWellKnownTests

- (void)setUp {
    [super setUp];
    self.tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"ca-rasl-%@", NSUUID.UUID.UUIDString]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempRoot error:nil];
    [super tearDown];
}

- (ATProtoHttpRequest *)requestForPath:(NSString *)path cidParam:(NSString *)cidParam {
    ATProtoHttpRequest *request =
        [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                       methodString:@"GET"
                                               path:path
                                        queryString:@""
                                         queryParams:@{}
                                             version:@"HTTP/1.1"
                                             headers:@{}
                                                body:[NSData data]
                                       remoteAddress:@"127.0.0.1"];
    if (cidParam.length > 0) {
        request.pathParameters = @{ @"cid": cidParam };
    }
    return request;
}

- (void)testServesBLAKE3Object {
    NSError *error = nil;
    ATProtoCAObjectStore *store =
        [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"vod-object" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [store putData:payload
                         expectedCID:nil
                             profile:ATProtoCAObjectDigestProfileBLAKE3
                               error:&error];
    XCTAssertNotNil(cid);

    ATProtoCARASLWellKnown *rasl = [[ATProtoCARASLWellKnown alloc] initWithObjectStore:store];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    ATProtoHttpRequest *request =
        [self requestForPath:[NSString stringWithFormat:@"/.well-known/rasl/%@", cid.stringValue]
                    cidParam:cid.stringValue];
    BOOL ok = [rasl handleRequest:request response:response includeBody:YES];
    XCTAssertTrue(ok);
    XCTAssertEqual(response.statusCode, (NSInteger)200);
    XCTAssertEqualObjects(response.body, payload);
}

- (void)testMissingObjectIs404 {
    NSError *error = nil;
    ATProtoCAObjectStore *store =
        [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    NSData *payload = [@"absent" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCAObjectStore cidForData:payload
                                               profile:ATProtoCAObjectDigestProfileBLAKE3
                                                 error:&error];
    ATProtoCARASLWellKnown *rasl = [[ATProtoCARASLWellKnown alloc] initWithObjectStore:store];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    ATProtoHttpRequest *request =
        [self requestForPath:[NSString stringWithFormat:@"/.well-known/rasl/%@", cid.stringValue]
                    cidParam:cid.stringValue];
    BOOL ok = [rasl handleRequest:request response:response includeBody:YES];
    XCTAssertFalse(ok);
    XCTAssertEqual(response.statusCode, (NSInteger)404);
}

- (void)testInvalidCIDIs400 {
    NSError *error = nil;
    ATProtoCAObjectStore *store =
        [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    ATProtoCARASLWellKnown *rasl = [[ATProtoCARASLWellKnown alloc] initWithObjectStore:store];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    ATProtoHttpRequest *request = [self requestForPath:@"/.well-known/rasl/not-a-cid"
                                              cidParam:@"not-a-cid"];
    BOOL ok = [rasl handleRequest:request response:response includeBody:YES];
    XCTAssertFalse(ok);
    XCTAssertEqual(response.statusCode, (NSInteger)400);
}

@end
