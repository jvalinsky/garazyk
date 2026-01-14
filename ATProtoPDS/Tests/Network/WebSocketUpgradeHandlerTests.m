#import <XCTest/XCTest.h>
#import "Network/WebSocketUpgradeHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface WebSocketUpgradeHandlerTests : XCTestCase
@end

@implementation WebSocketUpgradeHandlerTests

- (void)testValidWebSocketUpgradeRequest {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                methodString:@"GET"
                                                        path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      version:@"HTTP/1.1"
                                                      headers:@{
            @"Upgrade": @"websocket",
            @"Connection": @"Upgrade",
            @"Sec-WebSocket-Version": @"13",
            @"Sec-WebSocket-Key": @"dGhlIHNhbXBsZSBub25jZQ=="
        }
                                                         body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    BOOL shouldUpgrade = [handler handleUpgradeRequest:request response:response];

    XCTAssertTrue(shouldUpgrade);
    XCTAssertEqual(response.statusCode, 101);
    XCTAssertEqualObjects(response.statusMessage, @"Switching Protocols");
    XCTAssertEqualObjects([response.headers objectForKey:@"Upgrade"], @"websocket");
    XCTAssertEqualObjects([response.headers objectForKey:@"Connection"], @"Upgrade");
    XCTAssertNotNil([response.headers objectForKey:@"Sec-WebSocket-Accept"]);
}

- (void)testMissingUpgradeHeaderReturns426 {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                methodString:@"GET"
                                                        path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      version:@"HTTP/1.1"
                                                      headers:@{
            @"Connection": @"keep-alive",
            @"Sec-WebSocket-Version": @"13",
            @"Sec-WebSocket-Key": @"dGhlIHNhbXBsZSBub25jZQ=="
        }
                                                         body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    BOOL shouldUpgrade = [handler handleUpgradeRequest:request response:response];

    XCTAssertFalse(shouldUpgrade);
    XCTAssertEqual(response.statusCode, 426);
    XCTAssertFalse(response.keepAlive);
}

- (void)testNonGetRequestReturns405 {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                methodString:@"POST"
                                                        path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      version:@"HTTP/1.1"
                                                      headers:@{
            @"Upgrade": @"websocket",
            @"Connection": @"Upgrade",
            @"Sec-WebSocket-Version": @"13",
            @"Sec-WebSocket-Key": @"dGhlIHNhbXBsZSBub25jZQ=="
        }
                                                         body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    BOOL shouldUpgrade = [handler handleUpgradeRequest:request response:response];

    XCTAssertFalse(shouldUpgrade);
    XCTAssertEqual(response.statusCode, 405);
    XCTAssertFalse(response.keepAlive);
}

- (void)testInvalidWebSocketVersionReturns501 {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                methodString:@"GET"
                                                        path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      version:@"HTTP/1.1"
                                                      headers:@{
            @"Upgrade": @"websocket",
            @"Connection": @"Upgrade",
            @"Sec-WebSocket-Version": @"8",
            @"Sec-WebSocket-Key": @"dGhlIHNhbXBsZSBub25jZQ=="
        }
                                                         body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    BOOL shouldUpgrade = [handler handleUpgradeRequest:request response:response];

    XCTAssertFalse(shouldUpgrade);
    XCTAssertEqual(response.statusCode, 501);
}

- (void)testInvalidSecWebSocketKeyReturns400 {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                methodString:@"GET"
                                                        path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      version:@"HTTP/1.1"
                                                      headers:@{
            @"Upgrade": @"websocket",
            @"Connection": @"Upgrade",
            @"Sec-WebSocket-Version": @"13",
            @"Sec-WebSocket-Key": @"short"
        }
                                                         body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    BOOL shouldUpgrade = [handler handleUpgradeRequest:request response:response];

    XCTAssertFalse(shouldUpgrade);
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testNonSubscriptionPathNotUpgraded {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                methodString:@"GET"
                                                        path:@"/api/health"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      version:@"HTTP/1.1"
                                                      headers:@{
            @"Upgrade": @"websocket",
            @"Connection": @"Upgrade",
            @"Sec-WebSocket-Version": @"13",
            @"Sec-WebSocket-Key": @"dGhlIHNhbXBsZSBub25jZQ=="
        }
                                                         body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];

    HttpResponse *response = [[HttpResponse alloc] init];
    BOOL shouldUpgrade = [handler handleUpgradeRequest:request response:response];

    XCTAssertFalse(shouldUpgrade);
    XCTAssertNotEqual(response.statusCode, 101);
}

- (void)testComputeAcceptKeyIsCorrect {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    NSString *key = @"dGhlIHNhbXBsZSBub25jZQ==";
    NSString *acceptKey = [handler computeAcceptKey:key];

    XCTAssertNotNil(acceptKey);
    XCTAssertEqual(acceptKey.length, 28);

    XCTAssertEqualObjects(acceptKey, @"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
}

- (void)testIsWebSocketUpgradeRequestDetection {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    HttpRequest *wsRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                   queryString:@""
                                                    queryParams:@{}
                                                        version:@"HTTP/1.1"
                                                        headers:@{
              @"Upgrade": @"websocket",
              @"Connection": @"Upgrade"
          }
                                                             body:[NSData data]
                                                     remoteAddress:@"127.0.0.1"];

    HttpRequest *httpRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:@"/api/health"
                                                    queryString:@""
                                                     queryParams:@{}
                                                         version:@"HTTP/1.1"
                                                         headers:@{}
                                                            body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];

    XCTAssertTrue([handler isWebSocketUpgradeRequest:wsRequest]);
    XCTAssertFalse([handler isWebSocketUpgradeRequest:httpRequest]);
}

- (void)testSubscriptionPathPrefix {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    XCTAssertEqualObjects([handler subscriptionPathPrefix], @"/xrpc/");
}

- (void)testIsSubscriptionPath {
    WebSocketUpgradeHandler *handler = [[WebSocketUpgradeHandler alloc] init];

    XCTAssertTrue([handler isSubscriptionPath:@"/xrpc/com.atproto.sync.subscribeRepos"]);
    XCTAssertTrue([handler isSubscriptionPath:@"/xrpc/other.method"]);
    XCTAssertFalse([handler isSubscriptionPath:@"/api/health"]);
    XCTAssertFalse([handler isSubscriptionPath:@"/xrpc"]);  // No trailing slash
}

@end

NS_ASSUME_NONNULL_END
