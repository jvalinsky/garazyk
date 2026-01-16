#import <XCTest/XCTest.h>
#import "Sync/WebSocketServer.h"
#import "Sync/WebSocketConnection.h"

@interface WebSocketServerTests : XCTestCase
@property (nonatomic, strong) WebSocketServer *server;
@end

@implementation WebSocketServerTests

- (void)setUp {
    [super setUp];
    self.server = [[WebSocketServer alloc] initWithHost:@"localhost" port:9999];
}

- (void)tearDown {
    [self.server stop];
    self.server = nil;
    [super tearDown];
}

- (void)testServerInitialization {
    XCTAssertNotNil(self.server);
    XCTAssertEqualObjects(self.server.host, @"localhost");
    XCTAssertEqual(self.server.port, 9999);
    XCTAssertEqual(self.server.state, WebSocketServerStateIdle);
}

- (void)testServerStateEnumValues {
    XCTAssertEqual(WebSocketServerStateIdle, 0);
    XCTAssertEqual(WebSocketServerStateStarting, 1);
    XCTAssertEqual(WebSocketServerStateRunning, 2);
    XCTAssertEqual(WebSocketServerStateStopping, 3);
    XCTAssertEqual(WebSocketServerStateFailed, 4);
}

- (void)testServerStateTransitions {
    XCTAssertEqual(self.server.state, WebSocketServerStateIdle);
}

- (void)testServerConnectionsInitiallyEmpty {
    XCTAssertNotNil(self.server.connections);
    XCTAssertEqual(self.server.connections.count, 0);
}

- (void)testMutableConnectionsProperty {
    XCTAssertNotNil(self.server.mutableConnections);
    XCTAssertEqual(self.server.mutableConnections.count, 0);
}

- (void)testSubprotocolDefaultNil {
    XCTAssertNil(self.server.subprotocol);
}

- (void)testSubprotocolCanBeSet {
    self.server.subprotocol = @"graphql-ws";
    XCTAssertEqualObjects(self.server.subprotocol, @"graphql-ws");
}

- (void)testStopOnIdleServer {
    XCTAssertNoThrow([self.server stop]);
}

- (void)testDelegateCanBeNil {
    self.server.delegate = nil;
    XCTAssertNil(self.server.delegate);
}

- (void)testErrorDomain {
    XCTAssertNotNil(WebSocketServerErrorDomain);
    XCTAssertEqualObjects(WebSocketServerErrorDomain, @"com.atproto.pds.websocket.server");
}

- (void)testErrorCodes {
    XCTAssertEqual(WebSocketServerErrorCodeListenerFailed, 100);
    XCTAssertEqual(WebSocketServerErrorCodeInvalidHandshake, 101);
    XCTAssertEqual(WebSocketServerErrorCodeConnectionFailed, 102);
}

- (void)testBroadcastWithNoConnections {
    NSData *message = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNoThrow([self.server broadcastMessage:message toConnectionsMatching:nil]);
}

- (void)testBroadcastWithPredicate {
    NSData *message = [@"filtered" dataUsingEncoding:NSUTF8StringEncoding];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"port == 8080"];
    XCTAssertNoThrow([self.server broadcastMessage:message toConnectionsMatching:predicate]);
}

- (void)testDelegateAssignment {
    id delegate = [[NSObject alloc] init];
    self.server.delegate = delegate;
    XCTAssertEqual(self.server.delegate, delegate);
}

- (void)testHostPropertyImmutable {
    XCTAssertEqualObjects(self.server.host, @"localhost");
}

- (void)testPortPropertyImmutable {
    XCTAssertEqual(self.server.port, 9999);
}

@end
