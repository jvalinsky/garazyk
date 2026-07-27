// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketCodec.h"

@interface WebSocketCodecTests : XCTestCase
// self.codec decodes: it is left in the default server role, requiring
// masked incoming frames, matching a real firehose server. self.peerCodec
// encodes frames as the client peer sending to it (maskOutgoingFrames=YES),
// so wire bytes fed into self.codec are always correctly masked.
@property (nonatomic, strong) WebSocketCodec *codec;
@property (nonatomic, strong) WebSocketCodec *peerCodec;
@end

@implementation WebSocketCodecTests

- (void)setUp {
    [super setUp];
    self.codec = [[WebSocketCodec alloc] init];
    self.peerCodec = [[WebSocketCodec alloc] init];
    self.peerCodec.maskOutgoingFrames = YES;
}

- (void)tearDown {
    self.codec = nil;
    self.peerCodec = nil;
    [super tearDown];
}

- (void)testTextFrame {
    NSData *frame = [self.peerCodec textFrame:@"Hello"];
    NSArray<WSCodecEvent *> *events = [self.codec feedData:frame];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventTextMessage);
    XCTAssertEqualObjects(events.firstObject.text, @"Hello");
}

- (void)testClientFrameIsMaskedAndRoundTrips {
    NSData *frame = [self.peerCodec textFrame:@"masked"];
    const uint8_t *bytes = frame.bytes;
    XCTAssertEqual(bytes[0], 0x81);
    XCTAssertEqual(bytes[1] & 0x80, 0x80);

    NSArray<WSCodecEvent *> *events = [self.codec feedData:frame];
    XCTAssertEqual(events.count, 1);
    XCTAssertEqualObjects(events.firstObject.text, @"masked");
}

- (void)testBinaryFrame {
    NSData *payload = [@"Binary" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *frame = [self.peerCodec binaryFrame:payload];
    NSArray<WSCodecEvent *> *events = [self.codec feedData:frame];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventBinaryMessage);
    XCTAssertEqualObjects(events.firstObject.payload, payload);
}

- (void)testPingPongFrames {
    NSData *payload = [@"ping" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *pingFrame = [self.peerCodec pingFrame:payload];
    NSData *pongFrame = [self.peerCodec pongFrame:payload];

    NSArray<WSCodecEvent *> *pingEvents = [self.codec feedData:pingFrame];
    XCTAssertEqual(pingEvents.count, 1);
    XCTAssertEqual(pingEvents.firstObject.type, WSCodecEventPing);
    XCTAssertEqualObjects(pingEvents.firstObject.payload, payload);

    NSArray<WSCodecEvent *> *pongEvents = [self.codec feedData:pongFrame];
    XCTAssertEqual(pongEvents.count, 1);
    XCTAssertEqual(pongEvents.firstObject.type, WSCodecEventPong);
    XCTAssertEqualObjects(pongEvents.firstObject.payload, payload);
}

- (void)testCloseFrame {
    NSData *closeFrame = [self.peerCodec closeFrame:1000 reason:@"Normal"];
    NSArray<WSCodecEvent *> *events = [self.codec feedData:closeFrame];

    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventClose);
    XCTAssertEqual(events.firstObject.closeCode, 1000);
    XCTAssertEqualObjects(events.firstObject.closeReason, @"Normal");
}

- (void)testPartialDelivery {
    NSData *frame = [self.peerCodec textFrame:@"Partial"];

    // Feed 1 byte at a time
    for (NSUInteger i = 0; i < frame.length; i++) {
        NSData *chunk = [frame subdataWithRange:NSMakeRange(i, 1)];
        NSArray<WSCodecEvent *> *events = [self.codec feedData:chunk];

        if (i < frame.length - 1) {
            XCTAssertEqual(events.count, 0, @"Should not emit event until frame is complete");
        } else {
            XCTAssertEqual(events.count, 1);
            XCTAssertEqualObjects(events.firstObject.text, @"Partial");
        }
    }
}

- (void)testOversizedFrameRejection {
    self.codec.maxFrameSize = 100; // Small max size

    // Create a frame larger than 100 bytes
    NSData *payload = [NSMutableData dataWithLength:150];
    NSData *frame = [self.peerCodec binaryFrame:payload];

    NSArray<WSCodecEvent *> *events = [self.codec feedData:frame];
    XCTAssertEqual(events.count, 1);
    XCTAssertEqual(events.firstObject.type, WSCodecEventProtocolError);
    XCTAssertEqual(events.firstObject.closeCode, 1009);
}

@end
