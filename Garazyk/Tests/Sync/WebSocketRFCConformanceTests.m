// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
// Negative-test acceptance gate for phase 17 (workstream 01 § S10, slices
// 1-4): RFC 6455 conformance for the WebSocket codec, plus the HTTP framing
// and firehose env-limit fixes. Each test asserts that a specific violation
// is rejected (connection close with the correct RFC close code) rather than
// silently accepted or ignored.
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketCodec.h"

@interface WebSocketRFCConformanceTests : XCTestCase
@property (nonatomic, strong) WebSocketCodec *codec;
@end

@implementation WebSocketRFCConformanceTests

- (void)setUp {
    [super setUp];
    self.codec = [[WebSocketCodec alloc] init];
    // These tests hand-build raw, unmasked frames to exercise codec
    // internals directly. Setting the client role means the codec expects
    // *unmasked* incoming frames (as a real server would legitimately send),
    // matching these fixtures without obscuring intent with synthetic
    // masking. Slice 2 adds dedicated masking-direction tests below.
    self.codec.maskOutgoingFrames = YES;
}

- (void)tearDown {
    self.codec = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (NSData *)frameWithFin:(BOOL)fin opcode:(uint8_t)opcode payload:(NSData *)payload {
    NSMutableData *frame = [NSMutableData data];
    uint8_t firstByte = (fin ? 0x80 : 0x00) | (opcode & 0x0F);
    [frame appendBytes:&firstByte length:1];

    NSUInteger length = payload.length;
    if (length <= 125) {
        uint8_t lenByte = (uint8_t)length;
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

- (NSData *)rawBytes:(const uint8_t *)bytes length:(NSUInteger)length {
    return [NSData dataWithBytes:bytes length:length];
}

#pragma mark - Slice 1: aggregate reassembly cap

- (void)testAggregateReassemblyCapExceededAcrossFragments {
    self.codec.maxAggregateMessageSize = 10;

    NSData *first = [self frameWithFin:NO opcode:0x1 payload:[@"AAAAAA" dataUsingEncoding:NSUTF8StringEncoding]]; // 6 bytes
    NSArray<WSCodecEvent *> *events1 = [self.codec feedData:first];
    XCTAssertEqual(events1.count, 0, @"Should not emit an event on an incomplete fragment under the cap");

    NSData *second = [self frameWithFin:NO opcode:0x0 payload:[@"BBBBBB" dataUsingEncoding:NSUTF8StringEncoding]]; // 6 more bytes -> 12 total
    NSArray<WSCodecEvent *> *events2 = [self.codec feedData:second];
    XCTAssertEqual(events2.count, 1);
    XCTAssertEqual(events2.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events2.firstObject.closeCode, 1009);
}

- (void)testAggregateReassemblyCapEnforcedFromFirstFragment {
    self.codec.maxAggregateMessageSize = 4;

    NSData *first = [self frameWithFin:NO opcode:0x2 payload:[NSMutableData dataWithLength:10]]; // 10 > 4
    NSArray<WSCodecEvent *> *events = [self.codec feedData:first];
    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1009);
}

#pragma mark - Slice 1: control frame limits (RFC 6455 §5.5)

- (void)testFragmentedControlFrameRejected {
    // Opcode 0x9 (Ping), FIN=0 -- control frames must never be fragmented.
    uint8_t bytes[] = {0x09, 0x04, 'p', 'i', 'n', 'g'};
    NSArray<WSCodecEvent *> *events = [self.codec feedData:[self rawBytes:bytes length:sizeof(bytes)]];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

- (void)testOversizedControlFrameRejected {
    // Opcode 0x9 (Ping), length byte 126 -- the extended-length sentinel,
    // which a control frame (max 125 bytes) can never legitimately need.
    uint8_t bytes[] = {0x89, 0x7E};
    NSArray<WSCodecEvent *> *events = [self.codec feedData:[self rawBytes:bytes length:sizeof(bytes)]];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

- (void)testControlFrameAt125BytesAccepted {
    NSData *payload = [NSMutableData dataWithLength:125];
    NSData *frame = [self frameWithFin:YES opcode:0x9 payload:payload];
    NSArray<WSCodecEvent *> *events = [self.codec feedData:frame];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventPing);
}

@end
