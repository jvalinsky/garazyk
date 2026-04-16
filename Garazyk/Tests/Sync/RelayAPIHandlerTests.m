#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayAPIHandler.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface RelayAPIHandlerTests : XCTestCase
@property (nonatomic, strong) RelayAPIHandler *handler;
@property (nonatomic, strong) RelayMetrics *metrics;
@property (nonatomic, strong) RelayUpstreamManager *upstreamManager;
@end

@implementation RelayAPIHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [RelayAPIHandler sharedHandler];
    self.metrics = [[RelayMetrics alloc] init];
    self.upstreamManager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"test.pds.com"]];
}

- (void)tearDown {
    self.handler = nil;
    self.metrics = nil;
    self.upstreamManager = nil;
    [super tearDown];
}

- (HttpRequest *)requestWithPath:(NSString *)path {
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                   methodString:@"GET"
                                           path:path
                                    queryString:@""
                                    queryParams:@{}
                                        version:@"HTTP/1.1"
                                        headers:@{}
                                           body:[NSData data]
                                   remoteAddress:@"127.0.0.1"];
}

- (HttpResponse *)response {
    return [[HttpResponse alloc] init];
}

- (void)testSharedHandlerSingleton {
    RelayAPIHandler *handler1 = [RelayAPIHandler sharedHandler];
    RelayAPIHandler *handler2 = [RelayAPIHandler sharedHandler];
    
    XCTAssertEqual(handler1, handler2, @"Shared handler should return same instance");
}

- (void)testCanHandleRequestRelayMetrics {
    [self.handler setMetrics:self.metrics];
    
    HttpRequest *request = [self requestWithPath:@"/api/relay/metrics"];
    
    XCTAssertTrue([self.handler canHandleRequest:request], @"Should handle /api/relay/metrics");
}

- (void)testCanHandleRequestRelayUpstreams {
    [self.handler setUpstreamManager:self.upstreamManager];
    
    HttpRequest *request = [self requestWithPath:@"/api/relay/upstreams"];
    
    XCTAssertTrue([self.handler canHandleRequest:request], @"Should handle /api/relay/upstreams");
}

- (void)testCanHandleRequestRelayHealth {
    HttpRequest *request = [self requestWithPath:@"/api/relay/health"];
    
    XCTAssertTrue([self.handler canHandleRequest:request], @"Should handle /api/relay/health");
}

- (void)testCannotHandleOtherPaths {
    HttpRequest *request = [self requestWithPath:@"/xrpc/com.atproto.sync.subscribeRepos"];
    
    XCTAssertFalse([self.handler canHandleRequest:request], @"Should not handle non-relay paths");
}

- (void)testHandleMetricsRequest {
    [self.handler setMetrics:self.metrics];
    
    HttpRequest *request = [self requestWithPath:@"/api/relay/metrics"];
    HttpResponse *response = [self response];
    
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle metrics request without crash");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 OK");
    XCTAssertNotNil(response.body, @"Should have body");
}

- (void)testHandleUpstreamsRequest {
    [self.handler setUpstreamManager:self.upstreamManager];
    
    HttpRequest *request = [self requestWithPath:@"/api/relay/upstreams"];
    HttpResponse *response = [self response];
    
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle upstreams request without crash");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 OK");
    XCTAssertNotNil(response.body, @"Should have body");
}

- (void)testHandleHealthRequest {
    HttpRequest *request = [self requestWithPath:@"/api/relay/health"];
    HttpResponse *response = [self response];
    
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle health request without crash");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 OK");
    XCTAssertNotNil(response.body, @"Should have body");
}

- (void)testHandleMetricsWithNilMetrics {
    [self.handler setMetrics:nil];
    
    HttpRequest *request = [self requestWithPath:@"/api/relay/metrics"];
    HttpResponse *response = [self response];
    
    // Should handle gracefully without crash
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle nil metrics gracefully");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 even with nil metrics");
}

- (void)testHandleUpstreamsWithNilManager {
    [self.handler setUpstreamManager:nil];
    
    HttpRequest *request = [self requestWithPath:@"/api/relay/upstreams"];
    HttpResponse *response = [self response];
    
    // Should handle gracefully without crash
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle nil upstreamManager gracefully");
    XCTAssertEqual(response.statusCode, 200, @"Should return 200 even with nil upstreamManager");
}

- (void)testHandleUnknownRelayPath {
    HttpRequest *request = [self requestWithPath:@"/api/relay/unknown"];
    HttpResponse *response = [self response];
    
    XCTAssertNoThrow([self.handler handleRequest:request response:response], @"Should handle unknown path without crash");
    XCTAssertEqual(response.statusCode, 404, @"Should return 404 for unknown path");
}

- (void)testSetMetrics {
    RelayMetrics *newMetrics = [[RelayMetrics alloc] init];
    
    XCTAssertNoThrow([self.handler setMetrics:newMetrics], @"Should set metrics without crash");
}

- (void)testSetUpstreamManager {
    RelayUpstreamManager *newManager = [[RelayUpstreamManager alloc] initWithInitialURLs:@[@"new.pds.com"]];
    
    XCTAssertNoThrow([self.handler setUpstreamManager:newManager], @"Should set upstream manager without crash");
}

@end
