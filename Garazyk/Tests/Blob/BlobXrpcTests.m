// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Auth/Crypto/JWT.h"
#import "Core/CID.h"

@interface BlobXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *did;
@end

@implementation BlobXrpcTests

- (void)setUp {
    [super setUp];
    
    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.controller = [[PDSController alloc] initWithDirectory:self.tempURL.path serviceMaxSize:10 userDatabaseSize:10];
    
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher controller:self.controller];
    
    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"blobtest@example.com" password:@"password" handle:@"blobtest.bsky.social" did:nil error:&error];
    XCTAssertNil(error, @"Account creation failed");
    self.did = account[@"did"];
}

- (void)tearDown {
    [self.controller stopServer];
    self.dispatcher = nil;
    self.controller = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (nullable NSString *)uploadBlobAndReturnCIDForData:(NSData *)blobData
                                             mimeType:(NSString *)mimeType
                                                error:(NSError **)error {
    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social"
                                                     password:@"password"
                                                        error:error];
    if (!session) {
        return nil;
    }

    NSString *accessJwt = session[@"accessJwt"];
    HttpRequest *uploadRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                         methodString:@"POST"
                                                                 path:@"/xrpc/com.atproto.repo.uploadBlob"
                                                          queryString:@""
                                                          queryParams:@{}
                                                              version:@"1.1"
                                                              headers:@{
                                                                  @"content-type": mimeType ?: @"application/octet-stream",
                                                                  @"authorization": [NSString stringWithFormat:@"Bearer %@", accessJwt]
                                                              }
                                                                 body:blobData
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *uploadResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:uploadRequest response:uploadResponse];
    if (uploadResponse.statusCode != 200) {
        return nil;
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:uploadResponse.body options:0 error:error];
    return json[@"blob"][@"ref"][@"$link"];
}

- (BOOL)referenceBlobWithCID:(NSString *)cid error:(NSError **)error {
    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social"
                                                     password:@"password"
                                                        error:error];
    if (!session) return NO;

    NSDictionary *body = @{
        @"repo": self.did,
        @"collection": @"app.bsky.feed.post",
        @"rkey": [[NSUUID UUID] UUIDString],
        @"validate": @NO,
        @"record": @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"references an uploaded blob",
            @"embed": @{
                @"$type": @"blob",
                @"ref": @{ @"$link": cid }
            }
        }
    };
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
    if (!bodyData) return NO;

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                   methodString:@"POST"
                                                           path:@"/xrpc/com.atproto.repo.createRecord"
                                                    queryString:@""
                                                    queryParams:@{}
                                                        version:@"1.1"
                                                        headers:@{
        @"content-type": @"application/json",
        @"authorization": [NSString stringWithFormat:@"Bearer %@", session[@"accessJwt"]]
    }
                                                           body:bodyData
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    if (response.statusCode == HttpStatusOK) return YES;

    if (error) {
        *error = [NSError errorWithDomain:@"BlobXrpcTests"
                                     code:response.statusCode
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create blob reference record"}];
    }
    return NO;
}

- (void)testUploadBlobEndpointSuccess {
    NSError *error = nil;
    NSString *blobContent = @"Hello XRPC Blob";
    NSData *blobData = [blobContent dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social" password:@"password" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(session, @"Session should not be nil");
    NSString *accessJwt = session[@"accessJwt"];
    // DEBUG: Verify token manually
    XCTAssertNotNil(accessJwt, @"Access JWT should not be nil");
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/com.atproto.repo.uploadBlob"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"content-type": @"text/plain", @"authorization": [NSString stringWithFormat:@"Bearer %@", accessJwt]}
                                                          body:blobData
                                                    remoteAddress:@"127.0.0.1"];
    

    
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 OK");
    XCTAssertNotNil(response.body);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:&error];
    XCTAssertNil(error);
    
    NSDictionary *blob = json[@"blob"];
    XCTAssertNotNil(blob, @"Response should contain blob object");
    XCTAssertEqualObjects(blob[@"mimeType"], @"text/plain", @"MimeType should match");
    XCTAssertEqual([blob[@"size"] integerValue], blobData.length, @"Size should match");
    XCTAssertNotNil(blob[@"ref"][@"$link"], @"Blob should have CID link");
}

- (void)testUploadBlobWithoutAuth {
    NSString *blobContent = @"Unauthorized Blob";
    NSData *blobData = [blobContent dataUsingEncoding:NSUTF8StringEncoding];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/com.atproto.repo.uploadBlob"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"content-type": @"text/plain"} // No Authorization
                                                          body:blobData
                                                    remoteAddress:@"127.0.0.1"];
    
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, 401, @"Should return 401 Unauthorized");
}

- (void)testUploadBlobWithInvalidMimeType {
    NSError *error = nil;
    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social" password:@"password" error:&error];
    XCTAssertNil(error);
    NSString *accessJwt = session[@"accessJwt"];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/com.atproto.repo.uploadBlob"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"content-type": @"application/x-msdownload", @"authorization": [NSString stringWithFormat:@"Bearer %@", accessJwt]}
                                                          body:[@"fake-exe" dataUsingEncoding:NSUTF8StringEncoding]
                                                    remoteAddress:@"127.0.0.1"];
    
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, 415, @"Should return 415 (Unsupported Media Type) for invalid mime type");
}

- (void)testUploadBlobTooLarge {
    NSError *error = nil;
    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social" password:@"password" error:&error];
    XCTAssertNil(error);
    NSString *accessJwt = session[@"accessJwt"];
    
    // Create large data exceeding the MIME category limit (5MB for application/octet-stream)
    NSMutableData *largeData = [NSMutableData dataWithLength:6 * 1024 * 1024];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/com.atproto.repo.uploadBlob"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"content-type": @"application/octet-stream", @"authorization": [NSString stringWithFormat:@"Bearer %@", accessJwt]}
                                                          body:largeData
                                                    remoteAddress:@"127.0.0.1"];
    
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, 400, @"Should return 400 (or 413) for blob too large");
}

- (void)testUploadVideoBlobAllowsEmbedVideoSize {
    NSError *error = nil;
    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social" password:@"password" error:&error];
    XCTAssertNil(error);
    NSString *accessJwt = session[@"accessJwt"];

    NSMutableData *videoData = [NSMutableData dataWithLength:2 * 1024 * 1024];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/com.atproto.repo.uploadBlob"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"content-type": @"video/mp4", @"authorization": [NSString stringWithFormat:@"Bearer %@", accessJwt]}
                                                          body:videoData
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 200, @"Video blobs up to app.bsky.embed.video maxSize should upload");
}

- (void)testGetBlob {
    NSError *error = nil;
    // 1. Upload a blob initially
    NSString *blobContent = @"Retrievable Blob Content";
    NSData *blobData = [blobContent dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social" password:@"password" error:&error];
    XCTAssertNil(error);
    NSString *accessJwt = session[@"accessJwt"];
    
    HttpRequest *uploadRequest = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                       methodString:@"POST"
                                                               path:@"/xrpc/com.atproto.repo.uploadBlob"
                                                        queryString:@""
                                                        queryParams:@{}
                                                            version:@"1.1"
                                                            headers:@{@"content-type": @"text/plain", @"authorization": [NSString stringWithFormat:@"Bearer %@", accessJwt]}
                                                               body:blobData
                                                         remoteAddress:@"127.0.0.1"];
    
    HttpResponse *uploadResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:uploadRequest response:uploadResponse];
    XCTAssertEqual(uploadResponse.statusCode, 200);
    
    NSDictionary *uploadJson = [NSJSONSerialization JSONObjectWithData:uploadResponse.body options:0 error:nil];
    NSString *cid = uploadJson[@"blob"][@"ref"][@"$link"];
    XCTAssertNotNil(cid);
    XCTAssertTrue([self referenceBlobWithCID:cid error:&error], @"%@", error);
    
    // 2. Retrieve the blob
    // Query params: did, cid
    NSDictionary *queryParams = @{@"did": self.did, @"cid": cid};
    
    HttpRequest *getRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                     methodString:@"GET"
                                                             path:@"/xrpc/com.atproto.sync.getBlob"
                                                      queryString:[NSString stringWithFormat:@"did=%@&cid=%@", self.did, cid]
                                                      queryParams:queryParams
                                                          version:@"1.1"
                                                          headers:@{} // No auth required for getBlob? Usually public if repo is public, but let's check spec. Sync endpoints are usually public.
                                                             body:[NSData data]
                                                       remoteAddress:@"127.0.0.1"];
    
    HttpResponse *getResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:getRequest response:getResponse];
    
    XCTAssertEqual(getResponse.statusCode, 200, @"Should return 200 OK for getBlob");
    XCTAssertEqualObjects(getResponse.body, blobData, @"Retrieved data should match uploaded data");
    XCTAssertEqualObjects(getResponse.contentType, @"text/plain", @"Content-Type should match");
}

- (void)testTemporaryBlobIsNotRetrievable {
    NSError *error = nil;
    NSString *cid = [self uploadBlobAndReturnCIDForData:[@"Temporary Blob Content" dataUsingEncoding:NSUTF8StringEncoding]
                                                mimeType:@"text/plain"
                                                   error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cid);

    HttpRequest *getRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                     methodString:@"GET"
                                                             path:@"/xrpc/com.atproto.sync.getBlob"
                                                      queryString:[NSString stringWithFormat:@"did=%@&cid=%@", self.did, cid]
                                                      queryParams:@{ @"did": self.did, @"cid": cid }
                                                          version:@"1.1"
                                                          headers:@{}
                                                             body:[NSData data]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *getResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:getRequest response:getResponse];

    XCTAssertEqual(getResponse.statusCode, HttpStatusNotFound);
}

- (void)testGetBlobNotFound {
    ATProtoCID *missingCID = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:[@"missing blob" dataUsingEncoding:NSUTF8StringEncoding]]
                                   codec:0x55];
    XCTAssertNotNil(missingCID);
    NSDictionary *queryParams = @{@"did": self.did, @"cid": missingCID.stringValue};
    
    HttpRequest *getRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                     methodString:@"GET"
                                                             path:@"/xrpc/com.atproto.sync.getBlob"
                                                      queryString:[NSString stringWithFormat:@"did=%@&cid=%@", self.did, queryParams[@"cid"]]
                                                      queryParams:queryParams
                                                          version:@"1.1"
                                                          headers:@{}
                                                             body:[NSData data]
                                                       remoteAddress:@"127.0.0.1"];
    
    HttpResponse *getResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:getRequest response:getResponse];
    
    XCTAssertEqual(getResponse.statusCode, 404, @"Should return 404 for non-existent blob");
}

- (void)testGetBlobRangeReturnsPartialContentWithStreamingProducer {
    NSError *error = nil;
    NSData *blobData = [@"RangeBlobPayload" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self uploadBlobAndReturnCIDForData:blobData mimeType:@"text/plain" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cid);
    if (!cid) {
        return;
    }
    XCTAssertTrue([self referenceBlobWithCID:cid error:&error], @"%@", error);

    HttpRequest *getRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                     methodString:@"GET"
                                                             path:@"/xrpc/com.atproto.sync.getBlob"
                                                      queryString:[NSString stringWithFormat:@"did=%@&cid=%@", self.did, cid]
                                                      queryParams:@{@"did": self.did, @"cid": cid}
                                                          version:@"1.1"
                                                          headers:@{@"range": @"bytes=0-4"}
                                                             body:[NSData data]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *getResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:getRequest response:getResponse];

    XCTAssertEqual(getResponse.statusCode, (HttpStatusCode)206);
    XCTAssertEqualObjects([getResponse headerForKey:@"Accept-Ranges"], @"bytes");
    NSString *expectedContentRange = [NSString stringWithFormat:@"bytes 0-4/%lu",
                                      (unsigned long)blobData.length];
    XCTAssertEqualObjects([getResponse headerForKey:@"Content-Range"],
                          expectedContentRange);
    XCTAssertNotNil(getResponse.bodyChunkProducer);
    XCTAssertEqualObjects(getResponse.body, [blobData subdataWithRange:NSMakeRange(0, 5)]);
}

- (void)testGetBlobRangeUnsatisfiableReturns416 {
    NSError *error = nil;
    NSData *blobData = [@"TinyBlob" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self uploadBlobAndReturnCIDForData:blobData mimeType:@"text/plain" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cid);
    if (!cid) {
        return;
    }
    XCTAssertTrue([self referenceBlobWithCID:cid error:&error], @"%@", error);

    HttpRequest *getRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                     methodString:@"GET"
                                                             path:@"/xrpc/com.atproto.sync.getBlob"
                                                      queryString:[NSString stringWithFormat:@"did=%@&cid=%@", self.did, cid]
                                                      queryParams:@{@"did": self.did, @"cid": cid}
                                                          version:@"1.1"
                                                          headers:@{@"range": @"bytes=999-1000"}
                                                             body:[NSData data]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *getResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:getRequest response:getResponse];

    XCTAssertEqual(getResponse.statusCode, (HttpStatusCode)416);
    NSString *expectedContentRange = [NSString stringWithFormat:@"bytes */%lu",
                                      (unsigned long)blobData.length];
    XCTAssertEqualObjects([getResponse headerForKey:@"Content-Range"],
                          expectedContentRange);
}

- (void)testRepoGetBlobRangeReturnsPartialContent {
    NSError *error = nil;
    NSData *blobData = [@"RepoRangeBlobPayload" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self uploadBlobAndReturnCIDForData:blobData mimeType:@"text/plain" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cid);
    if (!cid) {
        return;
    }
    XCTAssertTrue([self referenceBlobWithCID:cid error:&error], @"%@", error);

    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social"
                                                    password:@"password"
                                                       error:&error];
    XCTAssertNil(error);
    NSString *accessJwt = session[@"accessJwt"];

    // Test Range request on repo.getBlob
    HttpRequest *getRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                     methodString:@"GET"
                                                             path:@"/xrpc/com.atproto.repo.getBlob"
                                                      queryString:[NSString stringWithFormat:@"did=%@&cid=%@", self.did, cid]
                                                      queryParams:@{@"did": self.did, @"cid": cid}
                                                          version:@"1.1"
                                                          headers:@{
        @"range": @"bytes=0-3",
        @"authorization": [NSString stringWithFormat:@"Bearer %@", accessJwt]
    }
                                                             body:[NSData data]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *getResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:getRequest response:getResponse];

    XCTAssertEqual(getResponse.statusCode, (HttpStatusCode)206);
    XCTAssertEqualObjects([getResponse headerForKey:@"Accept-Ranges"], @"bytes");
    NSString *expectedContentRange = [NSString stringWithFormat:@"bytes 0-3/%lu",
                                      (unsigned long)blobData.length];
    XCTAssertEqualObjects([getResponse headerForKey:@"Content-Range"],
                          expectedContentRange);
    XCTAssertEqualObjects(getResponse.body, [blobData subdataWithRange:NSMakeRange(0, 4)]);
}

- (void)testRepoGetBlobRangeUnsatisfiableReturns416 {
    NSError *error = nil;
    NSData *blobData = [@"Tiny" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self uploadBlobAndReturnCIDForData:blobData mimeType:@"text/plain" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cid);
    if (!cid) {
        return;
    }
    XCTAssertTrue([self referenceBlobWithCID:cid error:&error], @"%@", error);

    NSDictionary *session = [self.controller loginWithHandle:@"blobtest.bsky.social"
                                                    password:@"password"
                                                       error:&error];
    XCTAssertNil(error);
    NSString *accessJwt = session[@"accessJwt"];

    // Test unsatisfiable Range request on repo.getBlob
    HttpRequest *getRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                     methodString:@"GET"
                                                             path:@"/xrpc/com.atproto.repo.getBlob"
                                                      queryString:[NSString stringWithFormat:@"did=%@&cid=%@", self.did, cid]
                                                      queryParams:@{@"did": self.did, @"cid": cid}
                                                          version:@"1.1"
                                                          headers:@{
        @"range": @"bytes=999-1000",
        @"authorization": [NSString stringWithFormat:@"Bearer %@", accessJwt]
    }
                                                             body:[NSData data]
                                                       remoteAddress:@"127.0.0.1"];
    HttpResponse *getResponse = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:getRequest response:getResponse];

    XCTAssertEqual(getResponse.statusCode, (HttpStatusCode)416);
    NSString *expectedContentRange = [NSString stringWithFormat:@"bytes */%lu",
                                      (unsigned long)blobData.length];
    XCTAssertEqualObjects([getResponse headerForKey:@"Content-Range"],
                          expectedContentRange);
}

@end
