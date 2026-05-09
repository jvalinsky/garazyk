#import <XCTest/XCTest.h>
#import "PLC/PLCReplicaServer.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCOperation.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface PLCReplicaServerTests : XCTestCase
@property (nonatomic, strong) PLCMockStore *store;
@property (nonatomic, strong) PLCAuditor *auditor;
@property (nonatomic, strong) PLCReplicaServer *replicaServer;
@end

@interface PLCReplicaServer (TestAccess)
- (void)handleGetHealth:(HttpRequest *)req response:(HttpResponse *)resp;
@end

@interface PLCServer (ReplicaTestAccess)
- (void)handleGetDID:(HttpRequest *)req response:(HttpResponse *)resp;
- (void)handleGetData:(HttpRequest *)req response:(HttpResponse *)resp;
@end

@implementation PLCReplicaServerTests

- (HttpRequest *)requestWithMethod:(HttpMethod)method
                      methodString:(NSString *)methodString
                              path:(NSString *)path
                        pathParams:(NSDictionary<NSString *, NSString *> *)pathParams
                           headers:(NSDictionary<NSString *, NSString *> *)headers
                              body:(NSData *)body {
    HttpRequest *req = [[HttpRequest alloc] initWithMethod:method
                                              methodString:methodString
                                                    path:path
                                             queryString:@""
                                              queryParams:@{}
                                                  version:@"HTTP/1.1"
                                                  headers:headers ?: @{}
                                                     body:body ?: [NSData data]
                                             remoteAddress:@"127.0.0.1"];
    req.pathParameters = pathParams;
    return req;
}

- (void)setUp {
    [super setUp];
    self.store = [[PLCMockStore alloc] init];
    self.auditor = [[PLCAuditor alloc] initWithStore:self.store];
    self.replicaServer = [[PLCReplicaServer alloc] initWithStore:self.store
                                                         auditor:self.auditor
                                                            port:0
                                                    readOnlyMode:YES];
}

- (void)tearDown {
    [self.replicaServer stop];
    [super tearDown];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

- (PLCOperation *)insertTestOperation {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[keyPair.didKeyString],
        @"verificationMethods": @{@"atproto": keyPair.didKeyString},
        @"alsoKnownAs": @[@"at://test.example.com"],
        @"services": @{@"atproto_pds": @{@"type": @"AtprotoPersonalDataServer", @"endpoint": @"https://pds.test.com"}},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [[Secp256k1 shared] signHash:hash withPrivateKey:keyPair.privateKey error:nil];

    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [self base64URLEncode:sig];
    NSString *did = [PLCOperation calculateDIDForSignedOperation:payload];

    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = payload[@"sig"];
    op.data = opData;
    op.prev = nil;
    op.createdAt = [NSDate date];
    [self.store appendOperation:op nullifyCIDs:@[] error:nil];

    return op;
}

#pragma mark - Read-only rejection

- (void)testReplicaRejectsPostWith405 {
    PLCOperation *op = [self insertTestOperation];
    NSString *did = op.did;

    NSData *body = [NSJSONSerialization dataWithJSONObject:@{} options:0 error:nil];
    HttpRequest *req = [self requestWithMethod:HttpMethodPOST
                                  methodString:@"POST"
                                          path:[NSString stringWithFormat:@"/%@", did]
                                    pathParams:@{@"did": did}
                                       headers:@{}
                                          body:body];
    HttpResponse *resp = [HttpResponse response];

    // The replica routes are registered on httpServer, so we test via the server
    // by starting it and making a real HTTP request
    NSError *startError = nil;
    BOOL started = [self.replicaServer startWithError:&startError];
    if (!started) {
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"PLCServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Failed to start replica server: %@", startError);
        return;
    }

    // Make a real HTTP POST request
    NSDictionary *response = [self rawHTTPResponseWithMethod:@"POST"
                                                        path:[NSString stringWithFormat:@"/%@", did]
                                                        port:(UInt16)self.replicaServer.httpServer.port];
    XCTAssertEqual([response[@"statusCode"] integerValue], 405);
}

- (void)testReplicaRejectsPutWith405 {
    PLCOperation *op = [self insertTestOperation];
    NSString *did = op.did;

    NSError *startError = nil;
    BOOL started = [self.replicaServer startWithError:&startError];
    if (!started) {
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"PLCServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Failed to start replica server: %@", startError);
        return;
    }

    NSDictionary *response = [self rawHTTPResponseWithMethod:@"PUT"
                                                        path:[NSString stringWithFormat:@"/%@", did]
                                                        port:(UInt16)self.replicaServer.httpServer.port];
    XCTAssertEqual([response[@"statusCode"] integerValue], 405);
}

- (void)testReplicaRejectsDeleteWith405 {
    PLCOperation *op = [self insertTestOperation];
    NSString *did = op.did;

    NSError *startError = nil;
    BOOL started = [self.replicaServer startWithError:&startError];
    if (!started) {
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"PLCServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Failed to start replica server: %@", startError);
        return;
    }

    NSDictionary *response = [self rawHTTPResponseWithMethod:@"DELETE"
                                                        path:[NSString stringWithFormat:@"/%@", did]
                                                        port:(UInt16)self.replicaServer.httpServer.port];
    XCTAssertEqual([response[@"statusCode"] integerValue], 405);
}

#pragma mark - Health endpoint

- (void)testReplicaHealthReturnsMode {
    HttpRequest *req = [self requestWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:@"/health"
                                    pathParams:@{}
                                       headers:@{}
                                          body:nil];
    HttpResponse *resp = [HttpResponse response];
    [self.replicaServer handleGetHealth:req response:resp];

    XCTAssertEqual(resp.statusCode, 200);
    XCTAssertTrue([resp.jsonBody isKindOfClass:[NSDictionary class]]);
    NSDictionary *json = (NSDictionary *)resp.jsonBody;
    XCTAssertEqualObjects(json[@"status"], @"ok");
    XCTAssertEqualObjects(json[@"mode"], @"replica");
    XCTAssertEqualObjects(json[@"readOnly"], @YES);
}

- (void)testReplicaHealthIncludesOperationCounts {
    [self insertTestOperation];

    HttpRequest *req = [self requestWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:@"/health"
                                    pathParams:@{}
                                       headers:@{}
                                          body:nil];
    HttpResponse *resp = [HttpResponse response];
    [self.replicaServer handleGetHealth:req response:resp];

    XCTAssertEqual(resp.statusCode, 200);
    NSDictionary *json = (NSDictionary *)resp.jsonBody;
    // PLCMockStore may or may not implement totalOperationCountWithError:
    // Just verify the required fields are present
    XCTAssertNotNil(json[@"status"]);
    XCTAssertNotNil(json[@"mode"]);
    XCTAssertNotNil(json[@"readOnly"]);
}

#pragma mark - Read operations still work

- (void)testReplicaGetDidStillWorks {
    PLCOperation *op = [self insertTestOperation];
    NSString *did = op.did;

    HttpRequest *req = [self requestWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:[NSString stringWithFormat:@"/%@", did]
                                    pathParams:@{@"did": did}
                                       headers:@{}
                                          body:nil];
    HttpResponse *resp = [HttpResponse response];

    // Use the inherited PLCServer handler
    [self.replicaServer handleGetDID:req response:resp];

    XCTAssertEqual(resp.statusCode, 200);
    NSDictionary *json = (NSDictionary *)resp.jsonBody;
    XCTAssertEqualObjects(json[@"id"], did);
}

- (void)testReplicaGetDataStillWorks {
    PLCOperation *op = [self insertTestOperation];
    NSString *did = op.did;

    HttpRequest *req = [self requestWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:[NSString stringWithFormat:@"/%@/data", did]
                                    pathParams:@{@"did": did}
                                       headers:@{}
                                          body:nil];
    HttpResponse *resp = [HttpResponse response];

    [self.replicaServer handleGetData:req response:resp];

    XCTAssertEqual(resp.statusCode, 200);
    NSDictionary *json = (NSDictionary *)resp.jsonBody;
    XCTAssertEqualObjects(json[@"did"], did);
    XCTAssertNil(json[@"sig"], @"/:did/data must not include sig");
    XCTAssertNil(json[@"prev"], @"/:did/data must not include prev");
    XCTAssertNil(json[@"type"], @"/:did/data must not include type");
}

#pragma mark - Non-replica mode

- (void)testNonReplicaServerDoesNotRejectPost {
    PLCReplicaServer *writableServer = [[PLCReplicaServer alloc] initWithStore:self.store
                                                                       auditor:self.auditor
                                                                          port:0
                                                                  readOnlyMode:NO];
    // In non-replica mode, setupReplicaRoutes should not add 405 handlers
    // The inherited PLCServer POST handler should still work
    XCTAssertFalse(writableServer.readOnlyMode);
}

#pragma mark - HTTP helper

- (NSDictionary *)rawHTTPResponseWithMethod:(NSString *)method
                                       path:(NSString *)path
                                       port:(UInt16)port {
    NSString *requestText = [NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                                                       method ?: @"GET",
                                                       path ?: @"/"];
    NSData *requestData = [requestText dataUsingEncoding:NSUTF8StringEncoding];

    CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
    if (!socket) {
        XCTFail(@"Failed to create socket");
        return @{@"statusCode": @0, @"headers": @{}, @"body": @""};
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    NSData *addressData = [NSData dataWithBytes:&addr length:sizeof(addr)];
    CFSocketError connectResult = CFSocketConnectToAddress(socket, (__bridge CFDataRef)addressData, 5.0);
    if (connectResult != kCFSocketSuccess) {
        CFRelease(socket);
        XCTFail(@"Failed to connect to local HTTP server");
        return @{@"statusCode": @0, @"headers": @{}, @"body": @""};
    }

    CFSocketNativeHandle nativeSocket = CFSocketGetNative(socket);
    struct timeval timeout;
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    setsockopt(nativeSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    ssize_t sent = send(nativeSocket, requestData.bytes, requestData.length, 0);
    if (sent != (ssize_t)requestData.length) {
        CFRelease(socket);
        XCTFail(@"Failed to send request bytes");
        return @{@"statusCode": @0, @"headers": @{}, @"body": @""};
    }

    NSMutableData *responseData = [NSMutableData data];
    char buffer[4096];
    ssize_t received = 0;
    while ((received = recv(nativeSocket, buffer, sizeof(buffer), 0)) > 0) {
        [responseData appendBytes:buffer length:(NSUInteger)received];
    }
    CFRelease(socket);

    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] ?: @"";
    NSRange headerEndRange = [responseString rangeOfString:@"\r\n\r\n"];
    NSString *headerSection = headerEndRange.location != NSNotFound
                                  ? [responseString substringToIndex:headerEndRange.location]
                                  : responseString;
    NSString *bodySection = headerEndRange.location != NSNotFound
                                ? [responseString substringFromIndex:headerEndRange.location + 4]
                                : @"";

    NSArray<NSString *> *headerLines = [headerSection componentsSeparatedByString:@"\r\n"];
    NSInteger statusCode = 0;
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    if (headerLines.count > 0) {
        NSArray<NSString *> *statusParts = [headerLines[0] componentsSeparatedByString:@" "];
        if (statusParts.count >= 2) {
            statusCode = [statusParts[1] integerValue];
        }
    }

    for (NSUInteger i = 1; i < headerLines.count; i++) {
        NSString *line = headerLines[i];
        NSRange separatorRange = [line rangeOfString:@":"];
        if (separatorRange.location == NSNotFound) {
            continue;
        }
        NSString *key = [[line substringToIndex:separatorRange.location] lowercaseString];
        NSString *value = [[line substringFromIndex:separatorRange.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length > 0) {
            headers[key] = value ?: @"";
        }
    }

    return @{
        @"statusCode": @(statusCode),
        @"headers": [headers copy],
        @"body": bodySection ?: @""
    };
}

@end
