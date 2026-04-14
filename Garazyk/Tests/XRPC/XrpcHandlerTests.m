#import <XCTest/XCTest.h>
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface XrpcHandlerTests : XCTestCase
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@end

@implementation XrpcHandlerTests

- (void)setUp {
    [super setUp];
    self.dispatcher = [[XrpcDispatcher alloc] init];
}

- (void)tearDown {
    self.dispatcher = nil;
    [super tearDown];
}

#ifndef GNUSTEP
- (void)testMethodRegistrationAndDispatchReturnsSuccess {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Method handler called"];
    
    [self.dispatcher registerMethod:@"test.method" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"result": @"success"}];
        [expectation fulfill];
    }];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/test.method"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    [self.dispatcher handleRequest:request response:response];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"result"], @"success");
}
#endif

- (void)testUnrecognizedMethodReturns404 {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/unknown.method"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    [self.dispatcher handleRequest:request response:response];
    
    XCTAssertEqual(response.statusCode, HttpStatusNotFound, @"Should return 404 for unknown methods");
}

#ifndef GNUSTEP
- (void)testPathParametersOverrideMethodParsing {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Path parameter handler called"];

    [self.dispatcher registerMethod:@"test.method" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"result": @"path-params"}];
        [expectation fulfill];
    }];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/ignored.method"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                remoteAddress:@"127.0.0.1"];
    request.pathParameters = @{@"method": @"test.method"};
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.dispatcher handleRequest:request response:response];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"result"], @"path-params");
}
#endif

#ifndef GNUSTEP
- (void)testRegisterComAtprotoSyncSubscribeReposMapsToMethodAndReturnsSuccess {
    XCTestExpectation *expectation = [self expectationWithDescription:@"subscribeRepos handler called"];

    [self.dispatcher registerComAtprotoSyncSubscribeRepos:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"ok": @YES}];
        [expectation fulfill];
    }];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.dispatcher handleRequest:request response:response];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"ok"], @YES);
}
#endif

#ifndef GNUSTEP
- (void)testRegisterComAtprotoServerDeleteSessionMapsToMethodAndReturnsSuccess {
    XCTestExpectation *expectation = [self expectationWithDescription:@"deleteSession handler called"];

    [self.dispatcher registerComAtprotoServerDeleteSession:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"ok": @YES}];
        [expectation fulfill];
    }];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/xrpc/com.atproto.server.deleteSession"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.dispatcher handleRequest:request response:response];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"ok"], @YES);
}
#endif

#ifndef GNUSTEP
- (void)testRegisterComAtprotoSyncGetRecordMapsToMethodAndReturnsSuccess {
    XCTestExpectation *expectation = [self expectationWithDescription:@"getRecord handler called"];

    [self.dispatcher registerComAtprotoSyncGetRecord:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"ok": @YES}];
        [expectation fulfill];
    }];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.getRecord"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];

    [self.dispatcher handleRequest:request response:response];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"ok"], @YES);
}
#endif

@end
