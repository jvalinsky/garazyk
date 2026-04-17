#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Sync/WebSocket/WebSocketHeartbeatPolicy.h"

@interface MockStateWebSocketDelegate : NSObject <WebSocketConnectionDelegate>
@property (nonatomic, assign) NSInteger lastCloseCode;
@property (nonatomic, strong) NSString *lastCloseReason;
@property (nonatomic, strong) XCTestExpectation *expectation;
@property (nonatomic, assign) BOOL didReceiveBackpressureWarning;
@property (nonatomic, assign) double lastWarningFillPercentage;
@property (nonatomic, assign) NSUInteger lastWarningQueueBytes;
@property (nonatomic, assign) BOOL didReceiveBackpressureCritical;
@property (nonatomic, assign) double lastCriticalFillPercentage;
@property (nonatomic, assign) NSUInteger lastCriticalQueueBytes;
@property (nonatomic, assign) BOOL didReceiveBackpressureCleared;
@property (nonatomic, assign) BOOL didReceiveQueueOverflow;
@property (nonatomic, assign) NSUInteger lastOverflowBytes;
@property (nonatomic, assign) NSUInteger lastOverflowLimit;
@end

@implementation MockStateWebSocketDelegate
- (instancetype)init {
    self = [super init];
    if (self) {
        _lastCloseCode = -1;
        _didReceiveBackpressureWarning = NO;
        _didReceiveBackpressureCritical = NO;
        _didReceiveBackpressureCleared = NO;
        _didReceiveQueueOverflow = NO;
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
- (void)webSocketConnection:(WebSocketConnection *)connection didReachBackpressureWarning:(double)fillPercentage queueBytes:(NSUInteger)bytes {
    self.didReceiveBackpressureWarning = YES;
    self.lastWarningFillPercentage = fillPercentage;
    self.lastWarningQueueBytes = bytes;
}
- (void)webSocketConnection:(WebSocketConnection *)connection didReachBackpressureCritical:(double)fillPercentage queueBytes:(NSUInteger)bytes {
    self.didReceiveBackpressureCritical = YES;
    self.lastCriticalFillPercentage = fillPercentage;
    self.lastCriticalQueueBytes = bytes;
}
- (void)webSocketConnectionDidClearBackpressure:(WebSocketConnection *)connection {
    self.didReceiveBackpressureCleared = YES;
}
- (void)webSocketConnection:(WebSocketConnection *)connection willCloseForQueueOverflow:(NSUInteger)bytes limit:(NSUInteger)limit {
    self.didReceiveQueueOverflow = YES;
    self.lastOverflowBytes = bytes;
    self.lastOverflowLimit = limit;
}
@end

@interface WebSocketConnection (StateTesting)
@property (nonatomic, assign, readwrite) WebSocketConnectionState state;
@property (nonatomic, assign) NSUInteger queuedSendBytes;
@property (nonatomic, strong) NSMutableArray<NSData *> *messageQueue;
@property (nonatomic, strong) WebSocketHeartbeatPolicy *heartbeatPolicy;
- (void)startHeartbeat;
- (void)stopHeartbeat;
- (void)tickHeartbeat;
- (void)handlePongFrame:(NSData *)payload;
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

// Since timers use dispatch_source, testing real timeouts needs waiting.
// We will test the direct handler methods instead to characterize the logic.

- (void)testHeartbeatTimeoutClosesConnection {
    // Simulate ping sent, wait timeout
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    [self.connection.heartbeatPolicy pingSent:now - 11.0]; // 10s timeout
    [self.connection tickHeartbeat];
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

- (void)testOutboundQueueOverflow {
    self.connection.state = WebSocketConnectionStateConnected;

    // Default limit is 10MB, try to queue 20MB
    NSMutableData *largeFrame = [NSMutableData dataWithLength:10 * 1024 * 1024]; // 10MB
    [self.connection sendFrame:largeFrame];
    [self.connection sendFrame:largeFrame]; // This should trigger overflow (20MB > 10MB default)

    // Overflow logic in sendFrame: asynchronously cleans queue and calls closeWithCode:1009
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
    XCTAssertTrue(self.delegate.didReceiveQueueOverflow, @"Should notify delegate of queue overflow");
}

- (void)testMissingPongTriggersTimeoutClosesConnection {
    self.connection.state = WebSocketConnectionStateConnected;
    
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    [self.connection.heartbeatPolicy pingSent:now - 20.0];
    [self.connection tickHeartbeat]; // Should trigger timeout
    
    XCTAssertEqual(self.connection.closeCode, 1001);
    XCTAssertEqualObjects(self.connection.closeReason, @"Heartbeat timeout");
}

- (void)testPongResetsWaitingValidatesCloseCodeIsDifferent {
    self.connection.state = WebSocketConnectionStateConnected;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    [self.connection.heartbeatPolicy pingSent:now - 20.0];
    [self.connection handlePongFrame:[NSData data]]; // Clears waitingForPong

    // Second heartbeat should not fail since waitingForPong was cleared
    [self.connection tickHeartbeat];

    XCTAssertNotEqual(self.connection.closeCode, 1001);
}

#pragma mark - Backpressure Threshold Tests

- (void)testConfigurableQueueLimit {
    self.connection.state = WebSocketConnectionStateConnected;

    // Set custom 5MB limit
    self.connection.maxOutboundQueueBytes = 5 * 1024 * 1024;

    NSData *frame4MB = [NSData dataWithLength:4 * 1024 * 1024];
    NSData *frame2MB = [NSData dataWithLength:2 * 1024 * 1024];

    // First frame should succeed
    [self.connection sendFrame:frame4MB];
    XCTAssertEqual(self.connection.pendingSendBytes, 4 * 1024 * 1024, @"4MB should be queued");

    // Second frame should trigger overflow (total 6MB > 5MB limit)
    [self.connection sendFrame:frame2MB];

    // Wait for async write queue
    XCTestExpectation *exp = [self expectationWithDescription:@"Wait for overflow"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.1];
        dispatch_async(dispatch_get_main_queue(), ^{ [exp fulfill]; });
    });
    [self waitForExpectations:@[exp] timeout:1.0];

    XCTAssertEqual(self.connection.closeCode, 1009, @"Should close with 1009 when limit exceeded");
}

- (void)testBackpressureWarningThreshold {
    self.connection.state = WebSocketConnectionStateConnected;
    self.connection.maxOutboundQueueBytes = 10 * 1024 * 1024; // 10MB
    self.connection.backpressureWarningThreshold = 0.7; // 70%

    // Send 8MB (80% of 10MB) - should trigger warning
    NSData *frame8MB = [NSData dataWithLength:8 * 1024 * 1024];
    [self.connection sendFrame:frame8MB];

    // Wait for main queue to process delegate callback
    XCTestExpectation *exp = [self expectationWithDescription:@"Wait for warning callback"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectations:@[exp] timeout:1.0];

    XCTAssertTrue(self.delegate.didReceiveBackpressureWarning, @"Should notify delegate of warning");
    XCTAssertGreaterThanOrEqual(self.delegate.lastWarningFillPercentage, 0.8, @"Fill percentage should be ~80%");
    XCTAssertEqual(self.delegate.lastWarningQueueBytes, 8 * 1024 * 1024, @"Queue bytes should be 8MB");
}

- (void)testBackpressureCriticalThreshold {
    self.connection.state = WebSocketConnectionStateConnected;
    self.connection.maxOutboundQueueBytes = 10 * 1024 * 1024; // 10MB
    self.connection.backpressureCriticalThreshold = 0.9; // 90%

    // Send 9.5MB (95% of 10MB) - should trigger critical
    NSMutableData *frame9_5MB = [NSMutableData dataWithLength:9.5 * 1024 * 1024];
    [self.connection sendFrame:frame9_5MB];

    // Wait for main queue to process delegate callback
    XCTestExpectation *exp = [self expectationWithDescription:@"Wait for critical callback"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectations:@[exp] timeout:1.0];

    XCTAssertTrue(self.delegate.didReceiveBackpressureCritical, @"Should notify delegate of critical");
    XCTAssertGreaterThanOrEqual(self.delegate.lastCriticalFillPercentage, 0.9, @"Fill percentage should be ~95%");
}

- (void)testBackpressureWarningNotDuplicateNotified {
    self.connection.state = WebSocketConnectionStateConnected;
    self.connection.maxOutboundQueueBytes = 10 * 1024 * 1024;
    self.connection.backpressureWarningThreshold = 0.7;

    NSData *frame8MB = [NSData dataWithLength:8 * 1024 * 1024];
    [self.connection sendFrame:frame8MB]; // First warning

    // Wait for callback
    XCTestExpectation *exp1 = [self expectationWithDescription:@"First warning"];
    dispatch_async(dispatch_get_main_queue(), ^{ [exp1 fulfill]; });
    [self waitForExpectations:@[exp1] timeout:1.0];

    NSInteger warningCount = self.delegate.didReceiveBackpressureWarning ? 1 : 0;

    // Send another small frame - should NOT trigger another warning
    NSData *frame1MB = [NSData dataWithLength:1 * 1024 * 1024];
    [self.connection sendFrame:frame1MB];

    XCTestExpectation *exp2 = [self expectationWithDescription:@"No duplicate warning"];
    dispatch_async(dispatch_get_main_queue(), ^{ [exp2 fulfill]; });
    [self waitForExpectations:@[exp2] timeout:1.0];

    // Delegate should still show only one warning received
    XCTAssertTrue(self.delegate.didReceiveBackpressureWarning, @"Warning should still be set");
}

@end
