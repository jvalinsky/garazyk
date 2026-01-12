#import <XCTest/XCTest.h>
#import "Sync/WebSocketConnection.h"

@interface WebSocketConnectionTests : XCTestCase
@end

@implementation WebSocketConnectionTests

- (void)testInitWithPathWithoutQuery {
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos"];
    
    XCTAssertEqualObjects(connection.host, @"localhost");
    XCTAssertEqual(connection.port, 8081);
    XCTAssertEqualObjects(connection.path, @"/xrpc/com.atproto.sync.subscribeRepos");
    XCTAssertEqualObjects(connection.queryString, @"");
    XCTAssertNil(connection.queryParams);
}

- (void)testInitWithPathWithCursorQuery {
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos?cursor=123"];
    
    XCTAssertEqualObjects(connection.host, @"localhost");
    XCTAssertEqual(connection.port, 8081);
    XCTAssertEqualObjects(connection.path, @"/xrpc/com.atproto.sync.subscribeRepos");
    XCTAssertEqualObjects(connection.queryString, @"cursor=123");
    XCTAssertNotNil(connection.queryParams);
    XCTAssertEqualObjects(connection.queryParams[@"cursor"], @"123");
}

- (void)testInitWithPathWithMultipleQueryParams {
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos?cursor=456&collections=app.bsky.feed.post"];
    
    XCTAssertNotNil(connection.queryParams);
    XCTAssertEqualObjects(connection.queryParams[@"cursor"], @"456");
    XCTAssertEqualObjects(connection.queryParams[@"collections"], @"app.bsky.feed.post");
}

- (void)testInitWithEncodedQueryParams {
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos?cursor=789&name=hello%20world"];
    
    XCTAssertNotNil(connection.queryParams);
    XCTAssertEqualObjects(connection.queryParams[@"cursor"], @"789");
    XCTAssertEqualObjects(connection.queryParams[@"name"], @"hello world");
}

@end
