#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketHeartbeatPolicy.h"

@interface WebSocketHeartbeatPolicyTests : XCTestCase
@property (nonatomic, strong) WebSocketHeartbeatPolicy *policy;
@end

@implementation WebSocketHeartbeatPolicyTests

- (void)setUp {
    [super setUp];
    self.policy = [[WebSocketHeartbeatPolicy alloc] init];
    // Default: interval=30, timeout=10
}

- (void)tearDown {
    self.policy = nil;
    [super tearDown];
}

- (void)testInitialTickSendsPing {
    NSTimeInterval now = 100.0;
    WSHeartbeatAction action = [self.policy tick:now];
    XCTAssertEqual(action, WSHeartbeatActionSendPing, @"Should send ping immediately if never sent");
    
    [self.policy pingSent:now];
    
    action = [self.policy tick:now];
    XCTAssertEqual(action, WSHeartbeatActionNone, @"Should do nothing right after sending ping");
}

- (void)testTimeoutFiresIfNoPong {
    NSTimeInterval now = 100.0;
    [self.policy pingSent:now];
    
    // Move forward by 9 seconds (less than 10s timeout)
    WSHeartbeatAction action = [self.policy tick:now + 9.0];
    XCTAssertEqual(action, WSHeartbeatActionNone);
    
    // Move forward by 10 seconds (exactly timeout)
    action = [self.policy tick:now + 10.0];
    XCTAssertEqual(action, WSHeartbeatActionTimeout);
}

- (void)testPongResetsTimeout {
    NSTimeInterval now = 100.0;
    [self.policy pingSent:now];
    
    // Receive pong at 105.0
    [self.policy pongReceived:now + 5.0];
    
    // Check at 110.0 (would have been timeout without pong)
    WSHeartbeatAction action = [self.policy tick:now + 10.0];
    XCTAssertEqual(action, WSHeartbeatActionNone, @"Should not timeout because pong was received");
}

- (void)testNextPingIntervalSendsPingAfterInterval {
    NSTimeInterval now = 100.0;
    [self.policy pingSent:now];
    [self.policy pongReceived:now + 1.0];
    
    // Move forward by 29 seconds since ping
    WSHeartbeatAction action = [self.policy tick:now + 29.0];
    XCTAssertEqual(action, WSHeartbeatActionNone);
    
    // Move forward by 30 seconds since ping
    action = [self.policy tick:now + 30.0];
    XCTAssertEqual(action, WSHeartbeatActionSendPing);
}

- (void)testCustomIntervalAndTimeout {
    self.policy.heartbeatInterval = 5.0;
    self.policy.heartbeatTimeout = 2.0;
    
    NSTimeInterval now = 100.0;
    [self.policy pingSent:now];
    
    WSHeartbeatAction action = [self.policy tick:now + 2.0];
    XCTAssertEqual(action, WSHeartbeatActionTimeout);
    
    [self.policy pongReceived:now + 1.0];
    action = [self.policy tick:now + 5.0];
    XCTAssertEqual(action, WSHeartbeatActionSendPing);
}

@end
