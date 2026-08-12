// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketConnection.h"

@interface ATProtoWebSocketConnection (Testing)
- (NSString *)handshakeRequestStringWithKey:(NSString *)key;
@end

@interface WebSocketConnectionTests : XCTestCase
@end

@implementation WebSocketConnectionTests

- (void)testInitWithPathWithoutQuery {
    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos"];
    
    XCTAssertEqualObjects(connection.host, @"localhost");
    XCTAssertEqual(connection.port, 8081);
    XCTAssertEqualObjects(connection.path, @"/xrpc/com.atproto.sync.subscribeRepos");
    XCTAssertEqualObjects(connection.queryString, @"");
    XCTAssertNil(connection.queryParams);
    XCTAssertFalse(connection.secureTLS);
}

- (void)testSecureConnectionPreservesTLSPolicy {
    ATProtoWebSocketConnection *connection =
        [[ATProtoWebSocketConnection alloc] initWithHost:@"selfhosted.social"
                                             port:443
                                             path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                        secureTLS:YES];

    XCTAssertTrue(connection.secureTLS);
}

- (void)testInitWithPathWithCursorQuery {
    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"localhost"
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
    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos?cursor=456&collections=app.bsky.feed.post"];
    
    XCTAssertNotNil(connection.queryParams);
    XCTAssertEqualObjects(connection.queryParams[@"cursor"], @"456");
    XCTAssertEqualObjects(connection.queryParams[@"collections"], @"app.bsky.feed.post");
}

- (void)testInitWithEncodedQueryParams {
    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos?cursor=789&name=hello%20world"];
    
    XCTAssertNotNil(connection.queryParams);
    XCTAssertEqualObjects(connection.queryParams[@"cursor"], @"789");
    XCTAssertEqualObjects(connection.queryParams[@"name"], @"hello world");
}

- (void)testInitWithRepeatedQueryParams {
    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos?cursor=100&collections=app.bsky.feed.post&collections=app.bsky.feed.deviate&collections=app.bsky.graph.listitem"];
    
    XCTAssertNotNil(connection.queryParams);
    XCTAssertEqualObjects(connection.queryParams[@"cursor"], @"100");
    NSArray<NSString *> *expectedCollections = @[@"app.bsky.feed.post", @"app.bsky.feed.deviate", @"app.bsky.graph.listitem"];
    XCTAssertEqualObjects(connection.queryParams[@"collections"], expectedCollections);
}

- (void)testInitWithSingleRepeatedQueryParam {
    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"localhost"
                                                                           port:8081
                                                                           path:@"/xrpc/com.atproto.sync.subscribeRepos?cursor=200&collections=app.bsky.feed.post"];
    
    XCTAssertNotNil(connection.queryParams);
    XCTAssertEqualObjects(connection.queryParams[@"cursor"], @"200");
    XCTAssertEqualObjects(connection.queryParams[@"collections"], @"app.bsky.feed.post");
}

- (void)testHandshakeOmitsDefaultTLSPortFromHost {
    ATProtoWebSocketConnection *connection =
        [[ATProtoWebSocketConnection alloc] initWithHost:@"northamerica.firehose.network"
                                             port:443
                                             path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                        secureTLS:YES];

    NSString *handshake = [connection handshakeRequestStringWithKey:@"dGVzdCBrZXk="];
    NSString *hostLine = [handshake componentsSeparatedByString:@"\r\n"][1];
    XCTAssertEqualObjects(hostLine, @"Host: northamerica.firehose.network");
}

- (void)testHandshakeOmitsDefaultPlaintextPortFromHost {
    ATProtoWebSocketConnection *connection =
        [[ATProtoWebSocketConnection alloc] initWithHost:@"localhost"
                                             port:80
                                             path:@"/xrpc/com.atproto.sync.subscribeRepos"];

    NSString *handshake = [connection handshakeRequestStringWithKey:@"dGVzdCBrZXk="];
    NSString *hostLine = [handshake componentsSeparatedByString:@"\r\n"][1];
    XCTAssertEqualObjects(hostLine, @"Host: localhost");
}

- (void)testHandshakeKeepsNonDefaultPortInHost {
    ATProtoWebSocketConnection *connection =
        [[ATProtoWebSocketConnection alloc] initWithHost:@"localhost"
                                             port:8081
                                             path:@"/xrpc/com.atproto.sync.subscribeRepos"];

    NSString *handshake = [connection handshakeRequestStringWithKey:@"dGVzdCBrZXk="];
    NSString *hostLine = [handshake componentsSeparatedByString:@"\r\n"][1];
    XCTAssertEqualObjects(hostLine, @"Host: localhost:8081");
}

@end
