// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketCodec.h"

@interface WebSocketCodecFragmentationTests : XCTestCase
@property (nonatomic, strong) ATProtoWebSocketCodec *codec;
@end

@implementation WebSocketCodecFragmentationTests

- (void)setUp {
    [super setUp];
    self.codec = [[ATProtoWebSocketCodec alloc] init];
    // These fixtures hand-build unmasked frames, simulating what a real
    // server legitimately sends. maskOutgoingFrames=YES puts the codec in
    // client role, which requires unmasked incoming frames per RFC 6455 §5.1.
    self.codec.maskOutgoingFrames = YES;
}

- (void)tearDown {
    self.codec = nil;
    [super tearDown];
}

- (void)testFragmentedTextFrame {
    // Opcode 1 (Text), FIN 0
    uint8_t frame1[] = {0x01, 0x02, 'H', 'e'};
    // Opcode 0 (Continuation), FIN 1
    uint8_t frame2[] = {0x80, 0x03, 'l', 'l', 'o'};
    
    NSArray<ATProtoWSCodecEvent *> *events1 = [self.codec feedData:[NSData dataWithBytes:frame1 length:sizeof(frame1)]];
    XCTAssertEqual(events1.count, 0, @"Should not emit event on incomplete fragment");
    
    NSArray<ATProtoWSCodecEvent *> *events2 = [self.codec feedData:[NSData dataWithBytes:frame2 length:sizeof(frame2)]];
    XCTAssertEqual(events2.count, 1, @"Should emit event after final fragment");
    XCTAssertEqual(events2.firstObject.type, WSCodecEventTextMessage);
    XCTAssertEqualObjects(events2.firstObject.text, @"Hello");
}

- (void)testFragmentedBinaryFrameWithMultipleContinuations {
    // Opcode 2 (Binary), FIN 0
    uint8_t frame1[] = {0x02, 0x01, 0x0A};
    // Opcode 0 (Cont), FIN 0
    uint8_t frame2[] = {0x00, 0x02, 0x0B, 0x0C};
    // Opcode 0 (Cont), FIN 1
    uint8_t frame3[] = {0x80, 0x01, 0x0D};
    
    [self.codec feedData:[NSData dataWithBytes:frame1 length:sizeof(frame1)]];
    [self.codec feedData:[NSData dataWithBytes:frame2 length:sizeof(frame2)]];
    NSArray<ATProtoWSCodecEvent *> *events3 = [self.codec feedData:[NSData dataWithBytes:frame3 length:sizeof(frame3)]];
    
    XCTAssertEqual(events3.count, 1);
    XCTAssertEqual(events3.firstObject.type, WSCodecEventBinaryMessage);
    
    uint8_t expected[] = {0x0A, 0x0B, 0x0C, 0x0D};
    NSData *expectedData = [NSData dataWithBytes:expected length:sizeof(expected)];
    XCTAssertEqualObjects(events3.firstObject.payload, expectedData);
}

- (void)testInterleavedControlFramesDuringFragmentation {
    // Opcode 1 (Text), FIN 0
    uint8_t frame1[] = {0x01, 0x02, 'H', 'i'};
    // Opcode 9 (Ping), FIN 1
    uint8_t ping[] = {0x89, 0x04, 'p', 'i', 'n', 'g'};
    // Opcode 0 (Cont), FIN 1
    uint8_t frame2[] = {0x80, 0x01, '!'};
    
    [self.codec feedData:[NSData dataWithBytes:frame1 length:sizeof(frame1)]];
    
    NSArray<ATProtoWSCodecEvent *> *pingEvents = [self.codec feedData:[NSData dataWithBytes:ping length:sizeof(ping)]];
    XCTAssertEqual(pingEvents.count, 1);
    XCTAssertEqual(pingEvents.firstObject.type, WSCodecEventPing, @"Control frame should be processed immediately");
    
    NSArray<ATProtoWSCodecEvent *> *events = [self.codec feedData:[NSData dataWithBytes:frame2 length:sizeof(frame2)]];
    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventTextMessage);
    XCTAssertEqualObjects(events.firstObject.text, @"Hi!");
}

@end
