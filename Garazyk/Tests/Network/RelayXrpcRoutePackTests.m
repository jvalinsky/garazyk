// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RelayXrpcRoutePack.h"
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Sync/Relay/RelayUpstreamManager.h"

@interface HttpServer (RelayXrpcRoutePackTesting)
- (HttpResponse *)dispatchRequest:(HttpRequest *)request;
- (nullable RequestHandler)handlerForRoute:(NSString *)path
                                    method:(NSString *)method
                                parameters:(NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)parameters;
@end

@interface RelayXrpcRoutePackTests : XCTestCase
@property(nonatomic, strong) HttpServer *server;
@property(nonatomic, strong) RelayRepoStateManager *repoStateManager;
@property(nonatomic, strong) RelayXrpcRoutePack *routePack;
@end

@implementation RelayXrpcRoutePackTests

- (void)setUp {
    [super setUp];
    self.server = [HttpServer serverWithPort:0];
    self.repoStateManager = [[RelayRepoStateManager alloc] init];
    self.routePack = [[RelayXrpcRoutePack alloc] initWithRepoStateManager:self.repoStateManager
                                                   subscribeReposHandler:nil];
    [self.routePack registerRoutesWithServer:self.server];
}

- (void)tearDown {
    self.server = nil;
    self.repoStateManager = nil;
    self.routePack = nil;
    [super tearDown];
}

- (void)testRegistersListReposRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.sync.listRepos"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersGetHeadRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.sync.getHead"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersGetLatestCommitRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.sync.getLatestCommit"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersGetRepoStatusRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.sync.getRepoStatus"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersGetHostStatusRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.sync.getHostStatus"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersListHostsRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.sync.listHosts"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersRequestCrawlRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.sync.requestCrawl"
                                                   method:@"POST"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersAdminRequestCrawlRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/admin/pds/requestCrawl"
                                                   method:@"POST"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testRegistersGetRepoRoute {
    RequestHandler handler = [self.server handlerForRoute:@"/xrpc/com.atproto.sync.getRepo"
                                                   method:@"GET"
                                               parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testGetHeadReturnsBadRequestWithoutDID {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.getHead"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetLatestCommitReturnsBadRequestWithoutDID {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.getLatestCommit"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testListReposReturnsOKWithEmptyState {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.listRepos"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testGetRepoStatusReturnsActiveFalseForUnknownRepo {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.getRepoStatus"
                                                   queryString:@"did=did%3Aplc%3Aunknown"
                                                    queryParams:@{@"did": @"did:plc:unknown"}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"active"], @NO);
    XCTAssertEqualObjects(response.jsonBody[@"did"], @"did:plc:unknown");
}

@end
