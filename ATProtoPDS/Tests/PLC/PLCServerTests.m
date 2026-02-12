#import <XCTest/XCTest.h>
#import "PLC/PLCServer.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCOperation.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

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
    [super tearDown];
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

@end
