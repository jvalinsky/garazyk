// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketProtocolSession.h"

@interface WebSocketProtocolSessionTests : XCTestCase
@property (nonatomic, strong) WebSocketProtocolSession *session;
@end

@implementation WebSocketProtocolSessionTests

- (void)setUp {
    [super setUp];
    self.session = [[WebSocketProtocolSession alloc] init];
    // These fixtures hand-build unmasked frames, simulating what a real
    // server legitimately sends. maskOutgoingFrames=YES puts the codec in
    // client role, which requires unmasked incoming frames per RFC 6455 §5.1.
    self.session.codec.maskOutgoingFrames = YES;
}

- (void)tearDown {
    self.session = nil;
    [super tearDown];
}

#pragma mark - Initial state

- (void)testInit_DefaultValues {
    XCTAssertNotNil(self.session.codec);
    XCTAssertNotNil(self.session.heartbeatPolicy);
    XCTAssertEqual(self.session.maxOutboundQueueBytes, (NSUInteger)(10 * 1024 * 1024));
    XCTAssertEqualWithAccuracy(self.session.backpressureWarningThreshold, 0.7, 0.001);
    XCTAssertEqualWithAccuracy(self.session.backpressureCriticalThreshold, 0.9, 0.001);
}

#pragma mark - feedData:

- (void)testFeedData_TextFrame_ReturnsNotifyTextAction {
    // Build a text frame: FIN=1, opcode=1 (text), payload="Hello"
    NSData *frame = [self.class textFrameWithPayload:@"Hello"];
    NSArray<WSSessionAction *> *actions = [self.session feedData:frame];

    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeNotifyTextMessage);
    XCTAssertEqualObjects(actions[0].data, @"Hello");
}

- (void)testFeedData_BinaryFrame_ReturnsNotifyBinaryAction {
    uint8_t bytes[] = {0x00, 0x01, 0x02, 0x03};
    NSData *payload = [NSData dataWithBytes:bytes length:4];
    NSData *frame = [self.class binaryFrameWithPayload:payload];
    NSArray<WSSessionAction *> *actions = [self.session feedData:frame];

    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeNotifyBinaryMessage);
    XCTAssertEqualObjects(actions[0].data, payload);
}

- (void)testFeedData_PingFrame_ReturnsHandlePingAction {
    NSData *frame = [self.class pingFrameWithPayload:[@"ping" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray<WSSessionAction *> *actions = [self.session feedData:frame];

    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeHandlePing);
}

- (void)testFeedData_PongFrame_ReturnsHandlePongAction {
    // Feed a ping first to set up heartbeat state, then a pong
    [self.session feedData:[self.class pingFrameWithPayload:nil]];
    NSData *pongFrame = [self.class pongFrameWithPayload:nil];
    NSArray<WSSessionAction *> *actions = [self.session feedData:pongFrame];

    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeHandlePong);
}

- (void)testFeedData_CloseFrame_ReturnsCloseAction {
    uint8_t closeBytes[] = {0x88, 0x02, 0x03, 0xE8}; // Close frame with status 1000
    NSData *frame = [NSData dataWithBytes:closeBytes length:4];
    NSArray<WSSessionAction *> *actions = [self.session feedData:frame];

    XCTAssertGreaterThanOrEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeClose);
}

- (void)testFeedData_EmptyData_ReturnsNoActions {
    NSArray<WSSessionAction *> *actions = [self.session feedData:[NSData data]];
    XCTAssertEqual(actions.count, (NSUInteger)0);
}

- (void)testFeedData_NilData_ReturnsNoActions {
    NSArray<WSSessionAction *> *actions = [self.session feedData:(NSData *)nil];
    XCTAssertEqual(actions.count, (NSUInteger)0);
}

- (void)testFeedData_MultipleFrames_ReturnsMultipleActions {
    // Send two text frames
    NSData *frame1 = [self.class textFrameWithPayload:@"First"];
    NSData *frame2 = [self.class textFrameWithPayload:@"Second"];
    NSMutableData *combined = [NSMutableData data];
    [combined appendData:frame1];
    [combined appendData:frame2];

    NSArray<WSSessionAction *> *actions = [self.session feedData:combined];
    XCTAssertEqual(actions.count, (NSUInteger)2);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeNotifyTextMessage);
    XCTAssertEqualObjects(actions[0].data, @"First");
    XCTAssertEqual(actions[1].type, WSSessionActionTypeNotifyTextMessage);
    XCTAssertEqualObjects(actions[1].data, @"Second");
}

#pragma mark - tick:

- (void)testTick_FirstCallSendsPing {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSArray<WSSessionAction *> *actions = [self.session tick:now];
    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeSendPing);
}

- (void)testTick_ImmediatelyAfterPing_NoAction {
    NSTimeInterval now = 1000.0;
    [self.session tick:now]; // First tick → sends ping

    NSArray<WSSessionAction *> *actions = [self.session tick:now + 1.0];
    // Within 30s interval, so no ping
    for (WSSessionAction *action in actions) {
        XCTAssertNotEqual(action.type, WSSessionActionTypeSendPing);
    }
}

#pragma mark - didEnqueueFrameOfSize:currentQueueSize:

- (void)testEnqueue_BelowWarning_NoAction {
    NSUInteger maxQueue = self.session.maxOutboundQueueBytes;
    // Fill to 50% (below 70% warning threshold)
    NSUInteger size = maxQueue / 2;
    NSArray<WSSessionAction *> *actions = [self.session didEnqueueFrameOfSize:size currentQueueSize:size];

    XCTAssertEqual(actions.count, (NSUInteger)0);
}

- (void)testEnqueue_AtWarning_EmitsWarningOnce {
    NSUInteger maxQueue = self.session.maxOutboundQueueBytes;
    NSUInteger warningSize = (NSUInteger)((double)maxQueue * 0.75); // 75% > 70% warning

    NSArray<WSSessionAction *> *actions = [self.session didEnqueueFrameOfSize:warningSize currentQueueSize:warningSize];
    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeBackpressureWarning);
}

- (void)testEnqueue_WarningOnlyFiresOnce {
    NSUInteger maxQueue = self.session.maxOutboundQueueBytes;
    NSUInteger warningSize = (NSUInteger)((double)maxQueue * 0.75);

    // First enqueue at warning level → emits warning
    NSArray<WSSessionAction *> *actions1 = [self.session didEnqueueFrameOfSize:warningSize currentQueueSize:warningSize];
    XCTAssertEqual(actions1.count, (NSUInteger)1);

    // Second enqueue still at warning level → no repeat
    NSArray<WSSessionAction *> *actions2 = [self.session didEnqueueFrameOfSize:1 currentQueueSize:warningSize + 1];
    for (WSSessionAction *action in actions2) {
        XCTAssertNotEqual(action.type, WSSessionActionTypeBackpressureWarning);
    }
}

- (void)testEnqueue_AtCritical_EmitsCritical {
    NSUInteger maxQueue = self.session.maxOutboundQueueBytes;
    NSUInteger criticalSize = (NSUInteger)((double)maxQueue * 0.95); // 95% > 90% critical

    NSArray<WSSessionAction *> *actions = [self.session didEnqueueFrameOfSize:criticalSize currentQueueSize:criticalSize];
    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeBackpressureCritical);

    // Verify fill percentage in data
    double fillPct = [actions[0].data doubleValue];
    XCTAssertEqualWithAccuracy(fillPct, 0.95, 0.01);
}

- (void)testEnqueue_WarningThenCritical_EmitsBoth {
    NSUInteger maxQueue = self.session.maxOutboundQueueBytes;
    NSUInteger warningSize = (NSUInteger)((double)maxQueue * 0.75);
    NSUInteger criticalSize = (NSUInteger)((double)maxQueue * 0.95);

    // New session (isUnderBackpressure = NO, no warning emitted yet)
    WebSocketProtocolSession *freshSession = [[WebSocketProtocolSession alloc] init];

    // Enqueue at warning
    NSArray<WSSessionAction *> *warnActions = [freshSession didEnqueueFrameOfSize:warningSize currentQueueSize:warningSize];
    XCTAssertEqual(warnActions.count, (NSUInteger)1);
    XCTAssertEqual(warnActions[0].type, WSSessionActionTypeBackpressureWarning);

    // Enqueue at critical
    NSArray<WSSessionAction *> *critActions = [freshSession didEnqueueFrameOfSize:1 currentQueueSize:criticalSize];
    XCTAssertGreaterThanOrEqual(critActions.count, (NSUInteger)1);
    XCTAssertEqual(critActions[0].type, WSSessionActionTypeBackpressureCritical);
}

#pragma mark - didDequeueFrameOfSize:currentQueueSize:

- (void)testDequeue_NotUnderBackpressure_NoAction {
    NSArray<WSSessionAction *> *actions = [self.session didDequeueFrameOfSize:100 currentQueueSize:50];
    XCTAssertEqual(actions.count, (NSUInteger)0);
}

- (void)testDequeue_ClearsBackpressureWhenBelowThreshold {
    NSUInteger maxQueue = self.session.maxOutboundQueueBytes;
    NSUInteger warningSize = (NSUInteger)((double)maxQueue * 0.75);

    // Enter warning state
    [self.session didEnqueueFrameOfSize:warningSize currentQueueSize:warningSize];

    // Dequeue below threshold
    NSUInteger clearSize = (NSUInteger)((double)maxQueue * 0.4);
    NSArray<WSSessionAction *> *actions = [self.session didDequeueFrameOfSize:(warningSize - clearSize) currentQueueSize:clearSize];
    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeBackpressureCleared);
}

- (void)testDequeue_ClearOnlyFiresOnce {
    NSUInteger maxQueue = self.session.maxOutboundQueueBytes;
    NSUInteger warningSize = (NSUInteger)((double)maxQueue * 0.75);

    // Enter warning
    [self.session didEnqueueFrameOfSize:warningSize currentQueueSize:warningSize];

    // Clear
    [self.session didDequeueFrameOfSize:(warningSize - 1) currentQueueSize:1];

    // Another dequeue (already cleared) → no action
    NSArray<WSSessionAction *> *actions = [self.session didDequeueFrameOfSize:1 currentQueueSize:0];
    XCTAssertEqual(actions.count, (NSUInteger)0);
}

#pragma mark - Custom threshold configuration

- (void)testCustomThresholds {
    self.session.maxOutboundQueueBytes = 1000;
    self.session.backpressureWarningThreshold = 0.5;
    self.session.backpressureCriticalThreshold = 0.8;

    // 40% → below warning
    NSArray<WSSessionAction *> *actions = [self.session didEnqueueFrameOfSize:400 currentQueueSize:400];
    XCTAssertEqual(actions.count, (NSUInteger)0);

    // 60% → warning
    actions = [self.session didEnqueueFrameOfSize:200 currentQueueSize:600];
    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeBackpressureWarning);

    // 85% → critical
    actions = [self.session didEnqueueFrameOfSize:250 currentQueueSize:850];
    // Already under backpressure, so only critical
    XCTAssertEqual(actions[0].type, WSSessionActionTypeBackpressureCritical);
}

#pragma mark - feedData with receivedAt:

- (void)testFeedDataWithReceivedAt_TextFrame_ReturnsNotifyText {
    NSData *frame = [self.class textFrameWithPayload:@"Timed"];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSArray<WSSessionAction *> *actions = [self.session feedData:frame receivedAt:now];
    XCTAssertEqual(actions.count, (NSUInteger)1);
    XCTAssertEqual(actions[0].type, WSSessionActionTypeNotifyTextMessage);
    XCTAssertEqualObjects(actions[0].data, @"Timed");
}

#pragma mark - Helper methods

+ (NSData *)textFrameWithPayload:(NSString *)payload {
    return [self.class frameWithOpcode:0x1 payload:[payload dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSData *)binaryFrameWithPayload:(NSData *)payload {
    return [self.class frameWithOpcode:0x2 payload:payload];
}

+ (NSData *)pingFrameWithPayload:(nullable NSData *)payload {
    return [self.class frameWithOpcode:0x9 payload:payload ?: [NSData data]];
}

+ (NSData *)pongFrameWithPayload:(nullable NSData *)payload {
    return [self.class frameWithOpcode:0xA payload:payload ?: [NSData data]];
}

+ (NSData *)frameWithOpcode:(uint8_t)opcode payload:(NSData *)payload {
    NSMutableData *frame = [NSMutableData data];
    uint8_t firstByte = 0x80 | (opcode & 0x0F); // FIN=1
    [frame appendBytes:&firstByte length:1];

    NSUInteger length = payload.length;
    if (length <= 125) {
        uint8_t lenByte = length;
        [frame appendBytes:&lenByte length:1];
    } else if (length <= UINT16_MAX) {
        uint8_t lenByte = 126;
        [frame appendBytes:&lenByte length:1];
        uint16_t netLen = CFSwapInt16HostToBig((uint16_t)length);
        [frame appendBytes:&netLen length:2];
    } else {
        uint8_t lenByte = 127;
        [frame appendBytes:&lenByte length:1];
        uint64_t netLen = CFSwapInt64HostToBig(length);
        [frame appendBytes:&netLen length:8];
    }

    [frame appendData:payload];
    return frame;
}

@end
