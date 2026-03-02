#import <XCTest/XCTest.h>
#import "Sync/WebSocketConnection.h"

@interface MockStateWebSocketDelegate : NSObject <WebSocketConnectionDelegate>
@property (nonatomic, assign) NSInteger lastCloseCode;
@property (nonatomic, strong) NSString *lastCloseReason;
@property (nonatomic, strong) XCTestExpectation *expectation;
@end

@implementation MockStateWebSocketDelegate
- (instancetype)init {
    self = [super init];
    if (self) {
        _lastCloseCode = -1;
    }
    return self;
}
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveMessage:(NSData *)data {}
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveText:(NSString *)text {}
- (void)webSocketConnection:(WebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason {
    self.lastCloseCode = code;
    self.lastCloseReason = reason;
    if (self.expectation) [self.expectation fulfill];
}
- (void)webSocketConnection:(WebSocketConnection *)connection didFailWithError:(NSError *)error {}
@end

@interface WebSocketConnection (StateTesting)
@property (nonatomic, assign, readwrite) WebSocketConnectionState state;
@property (nonatomic, assign) NSUInteger queuedSendBytes;
@property (nonatomic, strong) NSMutableArray<NSData *> *messageQueue;
- (void)startHeartbeat;
- (void)stopHeartbeat;
- (void)sendHeartbeat;
- (void)handlePongFrame:(NSData *)payload;
- (void)handleHeartbeatTimeout;
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;
- (void)sendFrame:(NSData *)frame;
@end

@interface WebSocketStateCharacterizationTests : XCTestCase
@property (nonatomic, strong) WebSocketConnection *connection;
@property (nonatomic, strong) MockStateWebSocketDelegate *delegate;
@end

@implementation WebSocketStateCharacterizationTests

- (void)setUp {
    [super setUp];
    self.connection = [[WebSocketConnection alloc] init];
    self.delegate = [[MockStateWebSocketDelegate alloc] init];
    self.connection.delegate = self.delegate;
}

- (void)tearDown {
    self.connection = nil;
    self.delegate = nil;
    [super tearDown];
}

// Since timers use dispatch_source, testing real timeouts requires waiting.
// We will test the direct handler methods instead to characterize the logic.

- (void)testHeartbeatTimeoutClosesConnection {
    [self.connection handleHeartbeatTimeout];
    // This calls closeWithCode:1001 reason:@"Heartbeat timeout"
    XCTAssertEqual(self.connection.closeCode, 1001);
    XCTAssertEqualObjects(self.connection.closeReason, @"Heartbeat timeout");
    XCTAssertEqual(self.connection.state, WebSocketConnectionStateClosing);
}

- (void)testStateTransitions {
    XCTAssertEqual(self.connection.state, WebSocketConnectionStateConnecting);
    
    // We mock connected state
    self.connection.state = WebSocketConnectionStateConnected;
    XCTAssertEqual(self.connection.state, WebSocketConnectionStateConnected);
    
    [self.connection closeWithCode:1000 reason:@"Normal"];
    XCTAssertEqual(self.connection.state, WebSocketConnectionStateClosing);
    
    // Test double close is idempotent
    [self.connection closeWithCode:1002 reason:@"Error"];
    XCTAssertEqual(self.connection.closeCode, 1000, @"Should keep original close code");
}

- (void)testOutboundQueueBackpressure {
    self.connection.state = WebSocketConnectionStateConnected;
    
    // Fill up the queue past WS_MAX_PENDING_SEND_BYTES (16MB)
    NSMutableData *largeFrame = [NSMutableData dataWithLength:10 * 1024 * 1024]; // 10MB
    [self.connection sendFrame:largeFrame];
    [self.connection sendFrame:largeFrame]; // This should trigger the backpressure (20MB > 16MB)
    
    // Backpressure logic in sendFrame: asynchronously cleans queue and calls closeWithCode:1009
    XCTestExpectation *exp = [self expectationWithDescription:@"Wait for write queue"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Just delay briefly to let the write queue run
        [NSThread sleepForTimeInterval:0.1];
        dispatch_async(dispatch_get_main_queue(), ^{
            [exp fulfill];
        });
    });
    
    [self waitForExpectations:@[exp] timeout:1.0];
    
    XCTAssertEqual(self.connection.closeCode, 1009);
    XCTAssertEqualObjects(self.connection.closeReason, @"Outbound queue limit exceeded");
}

- (void)testMissingPongTriggersTimeout {
    self.connection.state = WebSocketConnectionStateConnected;
    
    // sendHeartbeat sets waitingForPong = YES and starts timeout timer.
    // If called again while waitingForPong == YES, it closes connection.
    [self.connection sendHeartbeat];
    [self.connection sendHeartbeat]; // Should trigger timeout
    
    XCTAssertEqual(self.connection.closeCode, 1001);
    XCTAssertEqualObjects(self.connection.closeReason, @"Heartbeat timeout");
}

- (void)testPongResetsWaiting {
    self.connection.state = WebSocketConnectionStateConnected;
    
    [self.connection sendHeartbeat];
    [self.connection handlePongFrame:[NSData data]]; // Clears waitingForPong
    
    // Second heartbeat should not fail since waitingForPong was cleared
    [self.connection sendHeartbeat];
    
    XCTAssertNotEqual(self.connection.closeCode, 1001);
}

@end
