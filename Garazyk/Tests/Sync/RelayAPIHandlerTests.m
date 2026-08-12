// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayAPIHandler.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface RelayAPIHandlerTests : XCTestCase
@property (nonatomic, strong) ATProtoRelayAPIHandler *handler;
@property (nonatomic, strong) ATProtoRelayMetrics *metrics;
@property (nonatomic, strong) ATProtoRelayUpstreamManager *upstreamManager;
@end

@implementation RelayAPIHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [ATProtoRelayAPIHandler sharedHandler];
    self.metrics = [[ATProtoRelayMetrics alloc] init];
    self.upstreamManager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
}

- (void)tearDown {
    self.handler = nil;
    self.metrics = nil;
    self.upstreamManager = nil;
    [super tearDown];
}

- (ATProtoHttpRequest *)requestWithPath:(NSString *)path {
    return [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                   methodString:@"GET"
                                           path:path
                                    queryString:@""
                                    queryParams:@{}
                                        version:@"HTTP/1.1"
                                        headers:@{}
                                           body:[NSData data]
                                   remoteAddress:@"127.0.0.1"];
}

- (ATProtoHttpResponse *)response {
    return [[ATProtoHttpResponse alloc] init];
}

- (void)testSharedHandlerSingleton {
    ATProtoRelayAPIHandler *handler1 = [ATProtoRelayAPIHandler sharedHandler];
    ATProtoRelayAPIHandler *handler2 = [ATProtoRelayAPIHandler sharedHandler];
    
    XCTAssertTrue(handler1 == handler2, @"Shared handler should return same instance");
}

- (void)testCanHandleRequestRelayMetrics {
    [self.handler setMetrics:self.metrics];
    
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/metrics"];
    
    XCTAssertTrue([self.handler canHandleRequest:request], @"Should handle /api/relay/metrics");
}

- (void)testCanHandleRequestRelayUpstreams {
    [self.handler setUpstreamManager:self.upstreamManager];
    
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/upstreams"];
    
    XCTAssertTrue([self.handler canHandleRequest:request], @"Should handle /api/relay/upstreams");
}

- (void)testCanHandleRequestRelayHealth {
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/health"];
    
    XCTAssertTrue([self.handler canHandleRequest:request], @"Should handle /api/relay/health");
}

- (void)testCannotHandleOtherPaths {
    ATProtoHttpRequest *request = [self requestWithPath:@"/xrpc/com.atproto.sync.subscribeRepos"];
    
    XCTAssertFalse([self.handler canHandleRequest:request], @"Should not handle non-relay paths");
}

- (void)testHandleMetricsRequest {
    [self.handler setMetrics:self.metrics];
    
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/metrics"];
    ATProtoHttpResponse *response = [self response];
    
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle metrics request without crash");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 OK");
    XCTAssertNotNil(response.body, @"Should have body");
}

- (void)testHandleUpstreamsRequest {
    [self.handler setUpstreamManager:self.upstreamManager];
    
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/upstreams"];
    ATProtoHttpResponse *response = [self response];
    
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle upstreams request without crash");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 OK");
    XCTAssertNotNil(response.body, @"Should have body");

    NSDictionary *body = response.jsonBody;
    NSArray *upstreams = body[@"upstreams"];
    XCTAssertEqual(upstreams.count, (NSUInteger)1);
    NSDictionary *upstream = upstreams.firstObject;
    XCTAssertEqualObjects(upstream[@"hostname"], @"test.pds.com");
    XCTAssertEqualObjects(upstream[@"crawlState"], @"not-requested");
    XCTAssertEqualObjects(upstream[@"crawlRequested"], @NO);
    XCTAssertEqualObjects(upstream[@"crawlRepoCount"], @0);
    XCTAssertEqualObjects(upstream[@"eventsReceived"], @0);
    XCTAssertEqualObjects(upstream[@"eventCounts"], @{});
    XCTAssertEqualObjects(upstream[@"reconnectAttempts"], @0);
}

- (void)testRequestCrawlMetadataAppearsInUpstreamList {
    ATProtoRelayAPIHandler *handler = [ATProtoRelayAPIHandler sharedHandler];
    ATProtoRelayUpstreamManager *manager = [[ATProtoRelayUpstreamManager alloc]
        initWithInitialURLs:@[@"https://requested.test/xrpc/com.atproto.sync.subscribeRepos"]];
    [handler setUpstreamManager:manager];

    [manager markCrawlRequestedForUpstream:@"https://requested.test/xrpc/com.atproto.sync.subscribeRepos"];
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/upstreams"];
    ATProtoHttpResponse *response = [self response];
    [handler handleRequest:request response:response];

    NSDictionary *upstream = [response.jsonBody[@"upstreams"] firstObject];
    XCTAssertEqualObjects(upstream[@"hostname"], @"requested.test");
    XCTAssertEqualObjects(upstream[@"crawlRequested"], @YES);
    XCTAssertEqualObjects(upstream[@"inventoryRequested"], @YES);
    XCTAssertEqualObjects(upstream[@"crawlState"], @"requested");
    XCTAssertNotNil(upstream[@"crawlRequestedAt"]);
}

- (void)testHandleHealthRequest {
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/health"];
    ATProtoHttpResponse *response = [self response];
    
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle health request without crash");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 OK");
    XCTAssertNotNil(response.body, @"Should have body");
}

- (void)testHandleMetricsWithNilMetrics {
    [self.handler setMetrics:nil];
    
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/metrics"];
    ATProtoHttpResponse *response = [self response];
    
    // Should handle gracefully without crash
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle nil metrics gracefully");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 even with nil metrics");
}

- (void)testHandleUpstreamsWithNilManager {
    [self.handler setUpstreamManager:nil];
    
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/upstreams"];
    ATProtoHttpResponse *response = [self response];
    
    // Should handle gracefully without crash
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle nil upstreamManager gracefully");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 even with nil upstreamManager");
}

- (void)testHandleUnknownRelayPath {
    ATProtoHttpRequest *request = [self requestWithPath:@"/api/relay/unknown"];
    ATProtoHttpResponse *response = [self response];
    
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle unknown path without crash");
    XCTAssertEqual(response.statusCode, 404, @"Should return 404 for unknown path");
}

- (void)testSetMetrics {
    ATProtoRelayMetrics *newMetrics = [[ATProtoRelayMetrics alloc] init];
    
    XCTAssertNoThrow([self.handler setMetrics:newMetrics], @"Should set metrics without crash");
}

- (void)testSetUpstreamManager {
    ATProtoRelayUpstreamManager *newManager = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[@"new.pds.com"]];
    
    XCTAssertNoThrow([self.handler setUpstreamManager:newManager], @"Should set upstream manager without crash");
}

@end
