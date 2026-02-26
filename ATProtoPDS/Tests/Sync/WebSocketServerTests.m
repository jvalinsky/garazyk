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
- (void)setState:(WebSocketServerState)state;
@end

@interface TestWebSocketConnection : WebSocketConnection
@property (atomic, assign) NSUInteger sentMessageCount;
@property (nonatomic, assign) NSInteger tag;
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

@interface WebSocketServerDelegateSpy : NSObject <WebSocketServerDelegate>
@property (nonatomic, assign) WebSocketServerState lastState;
@property (nonatomic, assign) NSUInteger callbackCount;
@end

@implementation WebSocketServerDelegateSpy

- (void)webSocketServer:(WebSocketServer *)server stateDidChange:(WebSocketServerState)state {
    (void)server;
    self.lastState = state;
    self.callbackCount += 1;
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

- (void)testStopWhenAlreadyStoppingReturnsImmediately {
    [self.server setState:WebSocketServerStateStopping];
    XCTAssertNoThrow([self.server stop]);
    XCTAssertEqual(self.server.state, WebSocketServerStateStopping);
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

- (void)testStartFailsWhenServerNotIdle {
    [self.server setState:WebSocketServerStateRunning];
    NSError *error = nil;
    BOOL started = [self.server start:&error];
    XCTAssertFalse(started);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, WebSocketServerErrorDomain);
    XCTAssertEqual(error.code, WebSocketServerErrorCodeListenerFailed);
}

- (void)testBroadcastWithPredicate {
    TestWebSocketConnection *allowed = [[TestWebSocketConnection alloc] init];
    allowed.tag = 1;
    TestWebSocketConnection *blocked = [[TestWebSocketConnection alloc] init];
    blocked.tag = 0;
    [self.server addConnection:allowed];
    [self.server addConnection:blocked];

    NSData *message = [@"filtered" dataUsingEncoding:NSUTF8StringEncoding];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"tag == 1"];
    [self.server broadcastMessage:message toConnectionsMatching:predicate];

    XCTAssertEqual(allowed.sentMessageCount, (NSUInteger)1);
    XCTAssertEqual(blocked.sentMessageCount, (NSUInteger)0);
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

    // Deterministic precondition: a baseline broadcast should reach all existing connections.
    NSData *warmupPayload = [@"warmup" dataUsingEncoding:NSUTF8StringEncoding];
    [self.server broadcastMessage:warmupPayload toConnectionsMatching:nil];

    NSUInteger warmupSentTotal = 0;
    for (TestWebSocketConnection *connection in connections) {
        warmupSentTotal += connection.sentMessageCount;
    }
    XCTAssertGreaterThan(warmupSentTotal, 0u);

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
}

- (void)testStateSetterNotifiesDelegateOnChange {
    WebSocketServerDelegateSpy *spy = [[WebSocketServerDelegateSpy alloc] init];
    self.server.delegate = spy;

    [self.server setState:WebSocketServerStateRunning];
    // setState notifies asynchronously on main queue.
    for (NSUInteger i = 0; i < 50 && spy.callbackCount == 0; i++) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }

    XCTAssertEqual(spy.callbackCount, (NSUInteger)1);
    XCTAssertEqual(spy.lastState, WebSocketServerStateRunning);

    // Setting same state should not notify again.
    [self.server setState:WebSocketServerStateRunning];
    for (NSUInteger i = 0; i < 20; i++) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    XCTAssertEqual(spy.callbackCount, (NSUInteger)1);
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
