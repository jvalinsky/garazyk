// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RelayXrpcRoutePack.h"
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Sync/Relay/RelayUpstreamManager.h"

@interface ATProtoHttpServer (RelayXrpcRoutePackTesting)
- (ATProtoHttpResponse *)dispatchRequest:(ATProtoHttpRequest *)request;
- (nullable RequestHandler)handlerForRoute:(NSString *)path
                                    method:(NSString *)method
                                parameters:(NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)parameters;
@end

@interface RelayXrpcRoutePackTests : XCTestCase
@property(nonatomic, strong) ATProtoHttpServer *server;
@property(nonatomic, strong) ATProtoRelayRepoStateManager *repoStateManager;
@property(nonatomic, strong) ATProtoRelayXrpcRoutePack *routePack;
@end

@implementation RelayXrpcRoutePackTests

- (void)setUp {
    [super setUp];
    self.server = [ATProtoHttpServer serverWithPort:0];
    self.repoStateManager = [[ATProtoRelayRepoStateManager alloc] init];
    self.routePack = [[ATProtoRelayXrpcRoutePack alloc] initWithRepoStateManager:self.repoStateManager
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
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.getHead"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetLatestCommitReturnsBadRequestWithoutDID {
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.getLatestCommit"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testListReposReturnsOKWithEmptyState {
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.listRepos"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testListReposRejectsLimitWithTrailingCharacters {
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.listRepos"
                                                   queryString:@"limit=10junk"
                                                    queryParams:@{@"limit": @"10junk"}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testListReposRejectsCursorWithTrailingCharacters {
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.listRepos"
                                                   queryString:@"cursor=1junk"
                                                    queryParams:@{@"cursor": @"1junk"}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [self.server dispatchRequest:request];
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (ATProtoHttpResponse *)getRepoStatusForDID:(NSString *)did {
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.getRepoStatus"
                                                   queryString:@""
                                                    queryParams:@{@"did": did}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    return [self.server dispatchRequest:request];
}

- (void)recordActiveRepo:(NSString *)did rev:(NSString *)rev {
    [self.repoStateManager handleCommitForRepo:did
                                          root:@"bafyreirepostatus"
                                           rev:rev
                                           seq:1];
}

- (void)testGetRepoStatusReturnsInactiveForUnknownRepo {
    NSString *did = @"did:plc:unknown";
    ATProtoHttpResponse *response = [self getRepoStatusForDID:did];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody, (@{
        @"did": did,
        @"active": @NO,
        @"status": @"desynchronized"
    }));
}

- (void)testGetRepoStatusReturnsActiveRepoRevision {
    NSString *did = @"did:plc:active";
    [self recordActiveRepo:did rev:@"3jzfcijpj2z2a"];

    ATProtoHttpResponse *response = [self getRepoStatusForDID:did];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody, (@{
        @"did": did,
        @"active": @YES,
        @"rev": @"3jzfcijpj2z2a"
    }));
}

- (void)testGetRepoStatusMapsInactiveStatesToLexiconKnownValues {
    NSString *did = @"did:plc:inactive";
    [self recordActiveRepo:did rev:@"3jzfcijpj2z2a"];
    NSArray<NSDictionary<NSString *, id> *> *states = @[
        @{@"state": @(RelayRepoStatusDesynchronized), @"status": @"desynchronized"},
        @{@"state": @(RelayRepoStatusThrottled), @"status": @"throttled"},
        @{@"state": @(RelayRepoStatusTombstoned), @"status": @"deleted"}
    ];

    for (NSDictionary<NSString *, id> *state in states) {
        [self.repoStateManager handleAccountEventForRepo:did
                                                   status:[state[@"state"] integerValue]];
        ATProtoHttpResponse *response = [self getRepoStatusForDID:did];

        XCTAssertEqual(response.statusCode, HttpStatusOK);
        XCTAssertEqualObjects(response.jsonBody, (@{
            @"did": did,
            @"active": @NO,
            @"status": state[@"status"]
        }));
    }
}

- (void)testGetRepoStatusOmitsStatusWhileSynchronizationIsInProgress {
    NSString *did = @"did:plc:in-progress";
    [self recordActiveRepo:did rev:@"3jzfcijpj2z2a"];
    [self.repoStateManager handleAccountEventForRepo:did
                                               status:RelayRepoStatusInProgress];

    ATProtoHttpResponse *response = [self getRepoStatusForDID:did];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody, (@{
        @"did": did,
        @"active": @NO
    }));
}

@end
