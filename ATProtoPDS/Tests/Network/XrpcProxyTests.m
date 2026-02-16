#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#include <stdlib.h>

@interface XrpcProxyTests : XCTestCase
@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, strong) HttpServer *upstreamServer;
@property (nonatomic, copy, nullable) NSString *savedAppViewProxyURL;
@end

@implementation XrpcProxyTests

- (void)setUp {
    [super setUp];

    const char *savedValue = getenv("PDS_APPVIEW_URL");
    self.savedAppViewProxyURL = savedValue ? [NSString stringWithUTF8String:savedValue] : nil;

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    self.application = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:self.application];
}

- (void)tearDown {
    if (self.upstreamServer) {
        [self.upstreamServer stop];
        self.upstreamServer = nil;
    }

    if (self.savedAppViewProxyURL.length > 0) {
        setenv("PDS_APPVIEW_URL", self.savedAppViewProxyURL.UTF8String, 1);
    } else {
        unsetenv("PDS_APPVIEW_URL");
    }

    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (BOOL)startUpstreamServerWithError:(NSError **)error {
    self.upstreamServer = [HttpServer serverWithPort:0];

    __weak typeof(self) weakSelf = self;
    [self.upstreamServer setValue:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{ @"error": @"InternalServerError" }];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"proxied": @YES,
            @"method": request.methodString ?: @"",
            @"path": request.path ?: @"",
            @"query": request.queryString ?: @"",
            @"authorization": [request headerForKey:@"authorization"] ?: [NSNull null],
            @"hop": [request headerForKey:@"x-objpds-proxy-hop"] ?: [NSNull null]
        }];
    } forKey:@"requestHandler"];

    return [self.upstreamServer startWithError:error];
}

- (HttpResponse *)dispatchRequestWithMethod:(HttpMethod)method
                                methodString:(NSString *)methodString
                                        path:(NSString *)path
                                 queryString:(NSString *)queryString
                                 queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                     headers:(NSDictionary<NSString *, NSString *> *)headers
                                        body:(NSData *)body {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:method
                                                   methodString:methodString
                                                           path:path
                                                    queryString:queryString ?: @""
                                                    queryParams:queryParams ?: @{}
                                                        version:@"1.1"
                                                        headers:headers ?: @{}
                                                           body:body ?: [NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (void)testAtprotoProxyHeaderOverridesLocalHandler {
    NSError *startError = nil;
    if (![self startUpstreamServerWithError:&startError]) {
        XCTSkip(@"Upstream listener unavailable in this environment: %@",
                startError.localizedDescription ?: @"unknown error");
        return;
    }

    NSString *proxyBase = [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)self.upstreamServer.port];
    NSDictionary *headers = @{
        @"authorization": @"Bearer example-token",
        @"atproto-proxy": proxyBase
    };

    HttpResponse *response = [self dispatchRequestWithMethod:HttpMethodGET
                                                 methodString:@"GET"
                                                         path:@"/xrpc/com.atproto.server.describeServer"
                                                  queryString:@"from=proxy"
                                                  queryParams:@{ @"from": @"proxy" }
                                                      headers:headers
                                                         body:nil];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.body);

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertEqualObjects(json[@"proxied"], @YES);
    XCTAssertEqualObjects(json[@"path"], @"/xrpc/com.atproto.server.describeServer");
    XCTAssertEqualObjects(json[@"query"], @"from=proxy");
    XCTAssertEqualObjects(json[@"authorization"], @"Bearer example-token");
}

- (void)testUnknownAppBskyMethodFallsBackToConfiguredProxy {
    NSError *startError = nil;
    if (![self startUpstreamServerWithError:&startError]) {
        XCTSkip(@"Upstream listener unavailable in this environment: %@",
                startError.localizedDescription ?: @"unknown error");
        return;
    }

    NSString *proxyBase = [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)self.upstreamServer.port];
    setenv("PDS_APPVIEW_URL", proxyBase.UTF8String, 1);

    NSString *methodId = @"app.bsky.unspecced.getThing";
    NSString *query = @"limit=5";
    HttpResponse *response = [self dispatchRequestWithMethod:HttpMethodGET
                                                 methodString:@"GET"
                                                         path:[NSString stringWithFormat:@"/xrpc/%@", methodId]
                                                  queryString:query
                                                  queryParams:@{ @"limit": @"5" }
                                                      headers:@{ @"authorization": @"Bearer fallback-token" }
                                                         body:nil];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.body);

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertEqualObjects(json[@"proxied"], @YES);
    NSString *expectedPath = [NSString stringWithFormat:@"/xrpc/%@", methodId];
    XCTAssertEqualObjects(json[@"path"], expectedPath);
    XCTAssertEqualObjects(json[@"query"], query);
    XCTAssertEqualObjects(json[@"authorization"], @"Bearer fallback-token");
}

- (void)testKnownAppBskyMethodUsesLocalHandlerWhenNoExplicitProxyHeader {
    NSError *startError = nil;
    if (![self startUpstreamServerWithError:&startError]) {
        XCTSkip(@"Upstream listener unavailable in this environment: %@",
                startError.localizedDescription ?: @"unknown error");
        return;
    }

    NSString *proxyBase = [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)self.upstreamServer.port];
    setenv("PDS_APPVIEW_URL", proxyBase.UTF8String, 1);

    HttpResponse *response = [self dispatchRequestWithMethod:HttpMethodGET
                                                 methodString:@"GET"
                                                         path:@"/xrpc/app.bsky.actor.getProfile"
                                                  queryString:@""
                                                  queryParams:@{}
                                                      headers:@{}
                                                         body:nil];

    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    NSDictionary *json = response.body.length > 0
        ? [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil]
        : nil;
    XCTAssertEqualObjects(json[@"error"], @"InvalidRequest");
    XCTAssertNil(json[@"proxied"]);
}

@end
