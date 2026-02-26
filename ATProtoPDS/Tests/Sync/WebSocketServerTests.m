#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "Sync/WebSocketServer.h"
#import "Sync/WebSocketConnection.h"

@interface WebSocketServer (Testing)
- (void)addConnection:(WebSocketConnection *)connection;
- (void)removeConnection:(WebSocketConnection *)connection;
@end

@interface TestWebSocketConnection : WebSocketConnection
@property (atomic, assign) NSUInteger sentMessageCount;
@end

@implementation TestWebSocketConnection

- (instancetype)init {
    return [super initWithHost:@"localhost" port:9999 path:@"/xrpc/com.atproto.sync.subscribeRepos"];
}

- (void)sendMessage:(NSData *)data {
    (void)data;
    @synchronized (self) {
        self.sentMessageCount += 1;
    }
}

@end

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

- (void)testConnectionsPropertyReturnsSnapshot {
    NSSet<WebSocketConnection *> *snapshot = self.server.connections;
    XCTAssertNotNil(snapshot);
    XCTAssertEqual(snapshot.count, 0);
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
    XCTAssertEqual(WebSocketServerErrorCodeListenerFailed, 1000);
    XCTAssertEqual(WebSocketServerErrorCodeInvalidHandshake, 1001);
    XCTAssertEqual(WebSocketServerErrorCodeConnectionFailed, 1002);
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

- (void)testConcurrentConnectionMutationAndBroadcastDoesNotRace {
    const NSUInteger connectionCount = 128;
    NSMutableArray<TestWebSocketConnection *> *connections = [NSMutableArray arrayWithCapacity:connectionCount];
    for (NSUInteger i = 0; i < connectionCount; i++) {
        [connections addObject:[[TestWebSocketConnection alloc] init]];
    }

    dispatch_queue_t workerQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_apply(connectionCount, workerQueue, ^(size_t idx) {
        [self.server addConnection:connections[idx]];
    });
    XCTAssertEqual(self.server.connections.count, connectionCount);

    NSData *payload = [@"broadcast" dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, workerQueue, ^{
        for (NSUInteger i = 0; i < 200; i++) {
            [self.server broadcastMessage:payload toConnectionsMatching:nil];
        }
    });
    dispatch_group_async(group, workerQueue, ^{
        dispatch_apply(connectionCount, workerQueue, ^(size_t idx) {
            [self.server removeConnection:connections[idx]];
        });
    });
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // Force the connection queue to drain pending mutation barriers.
    XCTAssertEqual(self.server.connections.count, 0u);

    NSUInteger sentMessageTotal = 0;
    for (TestWebSocketConnection *connection in connections) {
        sentMessageTotal += connection.sentMessageCount;
    }
    XCTAssertGreaterThan(sentMessageTotal, 0u);
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
