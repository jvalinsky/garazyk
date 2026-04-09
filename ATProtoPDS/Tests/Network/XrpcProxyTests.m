#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Auth/JWT.h"
#include <stdlib.h>

@interface XrpcProxyTests : XCTestCase
@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, strong) HttpServer *upstreamServer;
@property (nonatomic, copy, nullable) NSString *savedAppViewProxyURL;
@property (nonatomic, copy) NSString *testActorDid;
@property (nonatomic, copy) NSString *testAccessJwt;
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
    self.controller = self.application.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    self.dispatcher.jwtMinter = self.controller.jwtMinter;
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:self.application];

    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"proxytest@example.com"
                                                        password:@"password"
                                                          handle:@"proxytest.test"
                                                             did:nil
                                                           error:&error];
    XCTAssertNil(error, @"Account creation should succeed: %@", error);
    self.testActorDid = account[@"did"];
    XCTAssertNotNil(self.testActorDid, @"Account DID should be set");

    NSDictionary *session = [self.controller loginWithHandle:@"proxytest.test" password:@"password" error:&error];
    XCTAssertNil(error, @"Login should succeed: %@", error);
    self.testAccessJwt = session[@"accessJwt"];
    XCTAssertNotNil(self.testAccessJwt, @"Access JWT should be set");
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
    NSString *authValue = [NSString stringWithFormat:@"Bearer %@", self.testAccessJwt];
    NSDictionary *headers = @{
        @"authorization": authValue,
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
}

- (void)testUnknownAppBskyMethodFallsBackToConfiguredProxy {
    NSError *startError = nil;
    if (![self startUpstreamServerWithError:&startError]) {
        XCTSkip(@"Upstream listener unavailable in this environment: %@",
                startError.localizedDescription ?: @"unknown error");
        return;
    }

    NSString *proxyBase = [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)self.upstreamServer.port];
    self.dispatcher.proxyURL = [NSURL URLWithString:proxyBase];
    self.dispatcher.upstreamDID = @"did:web:test";

    NSString *methodId = @"app.bsky.unspecced.getThing";
    NSString *query = @"limit=5";
    NSString *authValue = [NSString stringWithFormat:@"Bearer %@", self.testAccessJwt];
    HttpResponse *response = [self dispatchRequestWithMethod:HttpMethodGET
                                             methodString:@"GET"
                                                     path:[NSString stringWithFormat:@"/xrpc/%@", methodId]
                                              queryString:query
                                              queryParams:@{ @"limit": @"5" }
                                                  headers:@{ @"authorization": authValue }
                                                     body:nil];

    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.body);

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertEqualObjects(json[@"proxied"], @YES);
    NSString *expectedPath = [NSString stringWithFormat:@"/xrpc/%@", methodId];
    XCTAssertEqualObjects(json[@"path"], expectedPath);
    XCTAssertEqualObjects(json[@"query"], query);
}

- (void)testKnownAppBskyMethodUsesLocalHandlerWhenNoExplicitProxyHeader {
    NSError *startError = nil;
    if (![self startUpstreamServerWithError:&startError]) {
        XCTSkip(@"Upstream listener unavailable in this environment: %@",
                startError.localizedDescription ?: @"unknown error");
        return;
    }

    NSString *proxyBase = [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)self.upstreamServer.port];
    self.dispatcher.proxyURL = [NSURL URLWithString:proxyBase];
    self.dispatcher.upstreamDID = @"did:web:test";

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

- (void)testAgeassuranceMethodsReturn501WithoutUpstream {
    NSArray *methods = @[
        @"app.bsky.ageassurance.getConfig",
        @"app.bsky.ageassurance.getState",
        @"app.bsky.contact.getSyncStatus"
    ];

    for (NSString *methodId in methods) {
        NSString *authValue = [NSString stringWithFormat:@"Bearer %@", self.testAccessJwt];
        HttpResponse *response = [self dispatchRequestWithMethod:HttpMethodGET
                                                 methodString:@"GET"
                                                         path:[NSString stringWithFormat:@"/xrpc/%@", methodId]
                                                  queryString:@""
                                                  queryParams:@{}
                                                      headers:@{@"authorization": authValue}
                                                         body:nil];

        XCTAssertEqual(response.statusCode, 501,
            @"%@ without upstream should return 501, got %ld",
            methodId, (long)response.statusCode);

        NSDictionary *json = response.body.length > 0
            ? [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil]
            : nil;
        XCTAssertEqualObjects(json[@"error"], @"NotSupported",
            @"%@ should return NotSupported error, got '%@'",
            methodId, json[@"error"]);
        XCTAssertNotNil(json[@"message"],
            @"%@ should have a message", methodId);
    }
}

- (void)testAgeassuranceMethodsProxyWhenUpstreamConfigured {
    NSError *startError = nil;
    if (![self startUpstreamServerWithError:&startError]) {
        XCTSkip(@"Upstream listener unavailable in this environment: %@",
                startError.localizedDescription ?: @"unknown error");
        return;
    }

    NSString *proxyBase = [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)self.upstreamServer.port];
    self.dispatcher.proxyURL = [NSURL URLWithString:proxyBase];
    self.dispatcher.upstreamDID = @"did:web:test";

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:@{} options:0 error:nil];
    NSString *authValue = [NSString stringWithFormat:@"Bearer %@", self.testAccessJwt];
    HttpResponse *response = [self dispatchRequestWithMethod:HttpMethodPOST
                                             methodString:@"POST"
                                                     path:@"/xrpc/app.bsky.ageassurance.begin"
                                              queryString:@""
                                              queryParams:@{}
                                                  headers:@{
                                                      @"authorization": authValue,
                                                      @"content-type": @"application/json"
                                                  }
                                                     body:bodyData];

    XCTAssertEqual(response.statusCode, 200,
        @"ageassurance.begin should be proxied successfully, got %ld",
        (long)response.statusCode);

    NSDictionary *json = response.body.length > 0
        ? [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil]
        : nil;
    XCTAssertEqualObjects(json[@"proxied"], @YES,
        @"Response should indicate proxied, got: %@", json);
}

- (void)testProxyTimeoutReturns504 {
    self.upstreamServer = [HttpServer serverWithPort:0];

    [self.upstreamServer setValue:^(HttpRequest *request, HttpResponse *response) {
        [NSThread sleepForTimeInterval:35.0];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"delayed": @YES}];
    } forKey:@"requestHandler"];

    NSError *startError = nil;
    if (![self.upstreamServer startWithError:&startError]) {
        XCTSkip(@"Upstream listener unavailable: %@", startError.localizedDescription ?: @"unknown");
        return;
    }

    NSString *proxyBase = [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)self.upstreamServer.port];
    self.dispatcher.proxyURL = [NSURL URLWithString:proxyBase];
    self.dispatcher.upstreamDID = @"did:web:test";

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:@{} options:0 error:nil];
    NSString *authValue = [NSString stringWithFormat:@"Bearer %@", self.testAccessJwt];
    HttpResponse *response = [self dispatchRequestWithMethod:HttpMethodPOST
                                             methodString:@"POST"
                                                     path:@"/xrpc/app.bsky.ageassurance.begin"
                                              queryString:@""
                                              queryParams:@{}
                                                  headers:@{
                                                      @"authorization": authValue,
                                                      @"content-type": @"application/json"
                                                  }
                                                     body:bodyData];

    XCTAssertEqual(response.statusCode, 504,
        @"Timed-out proxy request should return 504, got %ld",
        (long)response.statusCode);

    NSDictionary *json = response.body.length > 0
        ? [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil]
        : nil;
    XCTAssertEqualObjects(json[@"error"], @"UpstreamTimeout",
        @"Expected UpstreamTimeout error, got '%@'", json[@"error"]);
    XCTAssertTrue(
        [json[@"message"] isKindOfClass:[NSString class]] && ((NSString *)json[@"message"]).length > 0,
        @"Timeout response should have a non-empty message");
}

@end
