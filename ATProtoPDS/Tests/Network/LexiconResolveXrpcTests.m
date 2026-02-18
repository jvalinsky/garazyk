#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "App/PDSApplication.h"
#import "Core/CID.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcMethodRegistry.h"

@interface LexiconResolveXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@end

@implementation LexiconResolveXrpcTests

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.controller = app.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:app];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (HttpResponse *)sendResolveRequestWithQueryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                        queryString:(NSString *)queryString {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.lexicon.resolveLexicon"
                                                   queryString:queryString ?: @""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (void)testResolveLexiconMissingNSIDReturnsBadRequest {
    HttpResponse *response = [self sendResolveRequestWithQueryParams:@{} queryString:@""];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testResolveLexiconInvalidNSIDReturnsBadRequest {
    HttpResponse *response = [self sendResolveRequestWithQueryParams:@{@"nsid": @"bad nsid"}
                                                         queryString:@"nsid=bad%20nsid"];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testResolveLexiconUnknownNSIDReturnsNotFound {
    NSString *nsid = @"com.example.does.notExist";
    HttpResponse *response = [self sendResolveRequestWithQueryParams:@{@"nsid": nsid}
                                                         queryString:[NSString stringWithFormat:@"nsid=%@", nsid]];
    XCTAssertEqual(response.statusCode, 404);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"LexiconNotFound");
}

- (void)testResolveLexiconKnownNSIDReturnsSchemaCIDAndURI {
    NSString *nsid = @"com.atproto.server.describeServer";
    HttpResponse *response = [self sendResolveRequestWithQueryParams:@{@"nsid": nsid}
                                                         queryString:[NSString stringWithFormat:@"nsid=%@", nsid]];
    XCTAssertEqual(response.statusCode, 200);

    NSDictionary *body = response.jsonBody;
    XCTAssertTrue([body isKindOfClass:[NSDictionary class]]);

    NSString *uri = body[@"uri"];
    NSString *cidString = body[@"cid"];
    NSDictionary *schema = body[@"schema"];
    NSString *expectedSuffix = [NSString stringWithFormat:@"/com.atproto.lexicon.schema/%@", nsid];

    XCTAssertTrue([uri hasPrefix:@"at://did:web:"]);
    XCTAssertTrue([uri hasSuffix:expectedSuffix]);
    XCTAssertNotNil([CID cidFromString:cidString]);
    XCTAssertTrue([schema isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(schema[@"id"], nsid);
}

@end
