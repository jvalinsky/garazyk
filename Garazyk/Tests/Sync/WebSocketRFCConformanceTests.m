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

- (NSData *)maskedFrameWithFin:(BOOL)fin opcode:(uint8_t)opcode payload:(NSData *)payload {
    NSMutableData *frame = [NSMutableData data];
    uint8_t firstByte = (fin ? 0x80 : 0x00) | (opcode & 0x0F);
    [frame appendBytes:&firstByte length:1];

    NSUInteger length = payload.length;
    uint8_t maskKey[4] = {0x11, 0x22, 0x33, 0x44};
    if (length <= 125) {
        uint8_t lenByte = (uint8_t)(length | 0x80);
        [frame appendBytes:&lenByte length:1];
    } else if (length <= UINT16_MAX) {
        uint8_t lenByte = 126 | 0x80;
        [frame appendBytes:&lenByte length:1];
        uint16_t netLen = CFSwapInt16HostToBig((uint16_t)length);
        [frame appendBytes:&netLen length:2];
    } else {
        uint8_t lenByte = 127 | 0x80;
        [frame appendBytes:&lenByte length:1];
        uint64_t netLen = CFSwapInt64HostToBig(length);
        [frame appendBytes:&netLen length:8];
    }
    [frame appendBytes:maskKey length:sizeof(maskKey)];

    const uint8_t *source = payload.bytes;
    for (NSUInteger i = 0; i < length; i++) {
        uint8_t maskedByte = source[i] ^ maskKey[i % 4];
        [frame appendBytes:&maskedByte length:1];
    }
    return frame;
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

#pragma mark - Slice 2: masking direction (RFC 6455 §5.1)

- (void)testUnmaskedClientFrameRejectedByServer {
    WebSocketCodec *serverCodec = [[WebSocketCodec alloc] init]; // default: server role
    NSData *frame = [self frameWithFin:YES opcode:0x1 payload:[@"hi" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray<WSCodecEvent *> *events = [serverCodec feedData:frame];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

- (void)testMaskedServerFrameRejectedByClient {
    // self.codec is client role (maskOutgoingFrames=YES in setUp), so a
    // masked incoming frame simulates a non-conformant/malicious server.
    NSData *frame = [self maskedFrameWithFin:YES opcode:0x1 payload:[@"hi" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray<WSCodecEvent *> *events = [self.codec feedData:frame];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

#pragma mark - Slice 2: reserved opcodes and RSV bits (RFC 6455 §5.2)

- (void)testReservedOpcodesRejected {
    uint8_t reservedOpcodes[] = {0x3, 0x4, 0x5, 0x6, 0x7, 0xB, 0xC, 0xD, 0xE, 0xF};
    for (NSUInteger i = 0; i < sizeof(reservedOpcodes); i++) {
        WebSocketCodec *codec = [[WebSocketCodec alloc] init];
        codec.maskOutgoingFrames = YES;
        NSData *frame = [self frameWithFin:YES opcode:reservedOpcodes[i] payload:[NSData data]];
        NSArray<WSCodecEvent *> *events = [codec feedData:frame];

        XCTAssertEqual(events.count, (NSUInteger)1, @"opcode 0x%X should be rejected", reservedOpcodes[i]);
        XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError, @"opcode 0x%X should be rejected", reservedOpcodes[i]);
        XCTAssertEqual(events.firstObject.closeCode, 1002, @"opcode 0x%X should be rejected", reservedOpcodes[i]);
    }
}

- (void)testRSV1BitRejected {
    uint8_t bytes[] = {0xC1, 0x00}; // FIN=1, RSV1=1, opcode=1 (text), len=0
    NSArray<WSCodecEvent *> *events = [self.codec feedData:[self rawBytes:bytes length:sizeof(bytes)]];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

- (void)testRSV2AndRSV3BitsRejected {
    uint8_t bytes[] = {0xB1, 0x00}; // FIN=1, RSV2=1, RSV3=1, opcode=1
    NSArray<WSCodecEvent *> *events = [self.codec feedData:[self rawBytes:bytes length:sizeof(bytes)]];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

#pragma mark - Slice 2: fragmentation state machine (RFC 6455 §5.4)

- (void)testContinuationWithNoPrecedingStartRejected {
    NSData *frame = [self frameWithFin:YES opcode:0x0 payload:[@"orphan" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray<WSCodecEvent *> *events = [self.codec feedData:frame];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

- (void)testNewDataFrameWhileFragmentInProgressRejected {
    NSData *start = [self frameWithFin:NO opcode:0x1 payload:[@"He" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray<WSCodecEvent *> *startEvents = [self.codec feedData:start];
    XCTAssertEqual(startEvents.count, 0);

    // A second non-FIN data frame (not CONTINUE) while the first message's
    // fragmentation is still in progress must fail the connection rather
    // than silently overwrite fragmentOpcode and merge payloads.
    NSData *second = [self frameWithFin:NO opcode:0x2 payload:[@"Bi" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray<WSCodecEvent *> *events = [self.codec feedData:second];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

- (void)testCompleteDataFrameWhileFragmentInProgressRejected {
    NSData *start = [self frameWithFin:NO opcode:0x1 payload:[@"He" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray<WSCodecEvent *> *startEvents = [self.codec feedData:start];
    XCTAssertEqual(startEvents.count, 0);

    // A complete (FIN=1) new data frame while a fragmented message is
    // unfinished is equally invalid, not only a fragmented one.
    NSData *second = [self frameWithFin:YES opcode:0x2 payload:[@"Bi" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray<WSCodecEvent *> *events = [self.codec feedData:second];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1002);
}

@end
