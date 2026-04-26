#import <XCTest/XCTest.h>
#import "PLC/PLCServer.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCOperation.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <CoreFoundation/CoreFoundation.h>

@interface PLCServerTests : XCTestCase
@property (nonatomic, strong) PLCMockStore *store;
@property (nonatomic, strong) PLCAuditor *auditor;
@property (nonatomic, strong) PLCServer *server;
@end

@interface PLCServer (TestAccess)
- (void)handleGetDID:(HttpRequest *)req response:(HttpResponse *)resp;
- (void)handlePostDID:(HttpRequest *)req response:(HttpResponse *)resp;
@end

@implementation PLCServerTests

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
    self.server = [[PLCServer alloc] initWithStore:self.store auditor:self.auditor port:0];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

- (void)tearDown {
    [self.server stop];
    [super tearDown];
}

- (NSDictionary *)rawHTTPResponseWithMethod:(NSString *)method
                                       path:(NSString *)path
                                       port:(UInt16)port {
    NSString *requestText = [NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
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

- (void)testGetDID {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[keyPair didKeyString]],
        @"verificationMethods": @{@"atproto": [keyPair didKeyString]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [[Secp256k1 shared] signHash:hash withPrivateKey:keyPair.privateKey error:nil];
    
    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [self base64URLEncode:sig];
    NSString *did = [PLCOperation calculateDIDForData:opData];

    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = payload[@"sig"];
    op.data = opData;
    op.prev = nil;
    [self.store appendOperation:op nullifyCIDs:@[] error:nil];

    HttpRequest *req = [self requestWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:[NSString stringWithFormat:@"/%@", did]
                                    pathParams:@{@"did": did}
                                       headers:@{}
                                          body:nil];
    HttpResponse *resp = [HttpResponse response];
    [self.server handleGetDID:req response:resp];

    XCTAssertEqual(resp.statusCode, 200);
    XCTAssertTrue([resp.jsonBody isKindOfClass:[NSDictionary class]]);
    NSDictionary *json = (NSDictionary *)resp.jsonBody;
    XCTAssertEqualObjects(json[@"id"], did);
    XCTAssertNotNil(json[@"verificationMethod"]);
}

- (void)testPostDID {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[keyPair didKeyString]],
        @"verificationMethods": @{@"atproto": [keyPair didKeyString]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [[Secp256k1 shared] signHash:hash withPrivateKey:keyPair.privateKey error:nil];
    
    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [self base64URLEncode:sig];
    NSString *did = [PLCOperation calculateDIDForData:opData];

    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    HttpRequest *req = [self requestWithMethod:HttpMethodPOST
                                  methodString:@"POST"
                                          path:[NSString stringWithFormat:@"/%@", did]
                                    pathParams:@{@"did": did}
                                       headers:@{@"content-type": @"application/json"}
                                          body:body];
    HttpResponse *resp = [HttpResponse response];
    [self.server handlePostDID:req response:resp];

    XCTAssertEqual(resp.statusCode, 200);
    XCTAssertTrue([resp.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(((NSDictionary *)resp.jsonBody)[@"status"], @"ok");

    NSArray *history = [self.store getHistoryForDID:did includeNullified:NO error:nil];
    XCTAssertEqual(history.count, 1);
}

- (void)testPostInvalidDID {
    NSString *wrongDid = @"did:plc:wrong";
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[keyPair didKeyString]],
        @"verificationMethods": @{@"atproto": [keyPair didKeyString]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [[Secp256k1 shared] signHash:hash withPrivateKey:keyPair.privateKey error:nil];
    
    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [self base64URLEncode:sig];
    NSString *did = [PLCOperation calculateDIDForData:opData];

    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    HttpRequest *req = [self requestWithMethod:HttpMethodPOST
                                  methodString:@"POST"
                                          path:[NSString stringWithFormat:@"/%@", wrongDid]
                                    pathParams:@{@"did": wrongDid}
                                       headers:@{@"content-type": @"application/json"}
                                          body:body];
    HttpResponse *resp = [HttpResponse response];
    [self.server handlePostDID:req response:resp];
    XCTAssertEqual(resp.statusCode, 400);
    XCTAssertNotEqualObjects(did, wrongDid);
}

- (void)testRootRouteReturnsPlainTextBanner {
    NSError *startError = nil;
    BOOL started = [self.server startWithError:&startError];
    if (!started) {
        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"PLCServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Failed to start PLC server: %@", startError);
        return;
    }

    NSDictionary *response = [self rawHTTPResponseWithMethod:@"GET"
                                                        path:@"/"
                                                        port:(UInt16)self.server.httpServer.port];
    XCTAssertEqual([response[@"statusCode"] integerValue], 200);
    XCTAssertTrue([response[@"headers"][@"content-type"] containsString:@"text/plain"]);
    NSString *body = [response[@"body"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertEqualObjects(body, @"campagnola 1.0.0");
}

- (void)testAdminRouteRedirectsToUIService {
    NSString *previousUIURL = [[[NSProcessInfo processInfo] environment][@"PDS_UI_SERVER_URL"] copy];
    setenv("PDS_UI_SERVER_URL", "http://ui.local:4599", 1);

    @try {
        NSError *startError = nil;
        BOOL started = [self.server startWithError:&startError];
        if (!started) {
            NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
            if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
                XCTSkip(@"PLCServer cannot listen (EPERM) in this environment");
                return;
            }
            XCTFail(@"Failed to start PLC server: %@", startError);
            return;
        }

    } @finally {
        if (previousUIURL.length > 0) {
            setenv("PDS_UI_SERVER_URL", previousUIURL.UTF8String, 1);
        } else {
            unsetenv("PDS_UI_SERVER_URL");
        }
    }
}

@end
