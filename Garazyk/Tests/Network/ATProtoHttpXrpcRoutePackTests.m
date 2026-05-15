// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/ATProtoHttpXrpcRoutePack.h"
#import "Network/XrpcHandler.h"

@interface HttpServer (ATProtoHttpXrpcRoutePackTesting)
- (HttpResponse *)dispatchRequest:(HttpRequest *)request;
- (nullable RequestHandler)handlerForRoute:(NSString *)path
                                    method:(NSString *)method
                                parameters:(NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)parameters;
@end

@interface ATProtoHttpXrpcRoutePackTests : XCTestCase
@property(nonatomic, strong) HttpServer *server;
@end

@implementation ATProtoHttpXrpcRoutePackTests

- (void)setUp {
    [super setUp];
    self.server = [HttpServer serverWithPort:0];
    [ATProtoHttpXrpcRoutePack registerRoutesWithServer:self.server
                                        dispatcher:[[XrpcDispatcher alloc] init]
                                       application:nil
                                        controller:nil
                             subscribeReposHandler:nil
                                    setCorsHeaders:^(HttpResponse *r, HttpRequest *req) {}];
}

- (void)tearDown {
    self.server = nil;
    [super tearDown];
}

- (void)testRegistersXRPCRootRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersXRPCMethodRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.repo.getRecord"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersXRPCWildcardRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.repo.getRecord"
                                                   method:@"*"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersOPTIONSForXRPCPrefix {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc"
                                                   method:@"OPTIONS"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersOPTIONSForXRPCNamedMethod {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/:method"
                                                   method:@"OPTIONS"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testOPTIONSReturns200 {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodOPTIONS
                                                  methodString:@"OPTIONS"
                                                          path:@"/xrpc"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, 200);
}

@end
