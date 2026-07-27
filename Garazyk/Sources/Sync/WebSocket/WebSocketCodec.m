// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/WebSocket/WebSocketCodec.h"
#include <string.h>

static const uint8_t WS_OPCODE_CONTINUE = 0x0;
static const uint8_t WS_OPCODE_TEXT = 0x1;
static const uint8_t WS_OPCODE_BINARY = 0x2;
static const uint8_t WS_OPCODE_CLOSE = 0x8;
static const uint8_t WS_OPCODE_PING = 0x9;
static const uint8_t WS_OPCODE_PONG = 0xA;
static const uint8_t WS_FLAG_FIN = 0x80;
static const uint8_t WS_MASK = 0x80;

@implementation WSCodecEvent

- (instancetype)initWithType:(WSCodecEventType)type
                     payload:(nullable NSData *)payload
                   closeCode:(NSInteger)closeCode
                 closeReason:(nullable NSString *)closeReason
                        text:(nullable NSString *)text {
    self = [super init];
    if (self) {
        _type = type;
        _payload = [payload copy];
        _closeCode = closeCode;
        _closeReason = [closeReason copy];
        _text = [text copy];
    }
    return self;
}

@end

@interface WebSocketCodec ()
@property (nonatomic, strong) NSMutableData *readBuffer;
@property (nonatomic, strong) NSMutableArray<NSData *> *fragments;
@property (nonatomic, assign) uint8_t fragmentOpcode;
@property (nonatomic, assign) uint64_t fragmentsTotalLength;
@property (nonatomic, assign) NSUInteger readOffset;
@end

@implementation WebSocketCodec

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxFrameSize = 16 * 1024 * 1024; // 16MB default
        _maxAggregateMessageSize = 16 * 1024 * 1024; // 16MB default
        _maskOutgoingFrames = NO;
        _readBuffer = [NSMutableData data];
        _fragments = [NSMutableArray array];
        _fragmentOpcode = 0;
        _fragmentsTotalLength = 0;
        _readOffset = 0;
    }
    return self;
}

- (BOOL)appendFragment:(NSData *)payload {
    uint64_t newTotal = self.fragmentsTotalLength + (uint64_t)payload.length;
    if (newTotal < self.fragmentsTotalLength || newTotal > self.maxAggregateMessageSize) {
        return NO;
    }
    self.fragmentsTotalLength = newTotal;
    [self.fragments addObject:payload];
    return YES;
}

- (WSCodecEvent *)protocolErrorEventWithCloseCode:(NSInteger)closeCode closeReason:(NSString *)closeReason {
    return [[WSCodecEvent alloc] initWithType:WSCodecEventProtocolError
                                       payload:nil
                                     closeCode:closeCode
                                   closeReason:closeReason
                                          text:nil];
}

- (void)resetConnectionState {
    [self.readBuffer setLength:0];
    self.readOffset = 0;
    [self.fragments removeAllObjects];
    self.fragmentOpcode = 0;
    self.fragmentsTotalLength = 0;
}

- (NSArray<WSCodecEvent *> *)feedData:(NSData *)data {
    if (data.length > 0) {
        [self.readBuffer appendData:data];
    }

    NSMutableArray<WSCodecEvent *> *events = [NSMutableArray array];
    NSUInteger offset = self.readOffset;

    while (self.readBuffer.length - offset >= 2) {
        const uint8_t *bytes = self.readBuffer.bytes + offset;
        uint8_t firstByte = bytes[0];
        uint8_t secondByte = bytes[1];

        BOOL fin = (firstByte & WS_FLAG_FIN) != 0;
        uint8_t opcode = firstByte & 0x0F;
        BOOL masked = (secondByte & WS_MASK) != 0;
        uint64_t payloadLength = secondByte & 0x7F;
        NSUInteger extendedLengthOffset = 0;

        if ((firstByte & 0x70) != 0) {
            // RFC 6455 §5.2: RSV1-RSV3 are reserved and MUST be 0 unless an
            // extension negotiated their use. This codec negotiates none.
            [events addObject:[self protocolErrorEventWithCloseCode:1002
                                                          closeReason:@"Reserved bits (RSV1-RSV3) must be zero"]];
            [self resetConnectionState];
            return events;
        }

        BOOL isKnownOpcode = (opcode == WS_OPCODE_CONTINUE || opcode == WS_OPCODE_TEXT ||
                               opcode == WS_OPCODE_BINARY || opcode == WS_OPCODE_CLOSE ||
                               opcode == WS_OPCODE_PING || opcode == WS_OPCODE_PONG);
        if (!isKnownOpcode) {
            // RFC 6455 §5.2: opcodes 0x3-0x7 and 0xB-0xF are reserved for
            // future use and MUST fail the connection if received.
            [events addObject:[self protocolErrorEventWithCloseCode:1002
                                                          closeReason:@"Reserved opcode"]];
            [self resetConnectionState];
            return events;
        }

        BOOL requiresMaskedIncoming = !self.maskOutgoingFrames;
        if (masked != requiresMaskedIncoming) {
            // RFC 6455 §5.1: a server MUST fail the connection on an
            // unmasked frame from a client, and a client MUST fail the
            // connection on a masked frame from a server. maskOutgoingFrames
            // records which side of that pairing this codec instance plays.
            NSString *reason = requiresMaskedIncoming ? @"Client frames must be masked"
                                                        : @"Server frames must not be masked";
            [events addObject:[self protocolErrorEventWithCloseCode:1002 closeReason:reason]];
            [self resetConnectionState];
            return events;
        }

        BOOL isControlFrame = opcode >= WS_OPCODE_CLOSE;
        if (isControlFrame && (!fin || payloadLength > 125)) {
            // RFC 6455 §5.5: control frames are never fragmented and carry
            // at most a 125-byte payload. A raw 7-bit length of 126/127 is
            // the extended-length sentinel, which a control frame can never
            // legitimately need.
            [events addObject:[self protocolErrorEventWithCloseCode:1002
                                                          closeReason:@"Control frame must not be fragmented or exceed 125 bytes"]];
            [self resetConnectionState];
            return events;
        }

        if (payloadLength == 126) {
            if (self.readBuffer.length - offset < 4) break;
            payloadLength = (uint64_t)bytes[2] << 8 | bytes[3];
            extendedLengthOffset = 2;
        } else if (payloadLength == 127) {
            if (self.readBuffer.length - offset < 10) break;
            payloadLength = 0;
            for (int i = 0; i < 8; i++) {
                payloadLength = (payloadLength << 8) | bytes[2 + i];
            }
            extendedLengthOffset = 8;
        }

        if (payloadLength > self.maxFrameSize) {
            [events addObject:[self protocolErrorEventWithCloseCode:1009
                                                          closeReason:@"Frame too large"]];
            [self resetConnectionState];
            return events;
        }

        NSUInteger headerLength = 2 + extendedLengthOffset + (masked ? 4 : 0);
        NSUInteger maskOffset = 2 + extendedLengthOffset;
        NSUInteger dataOffset = headerLength;

        // Guard the header+payload addition independently of maxFrameSize,
        // which is a public settable property: a caller could raise it high
        // enough that this sum wraps and the length check below passes
        // spuriously, reading past the buffer.
        uint64_t totalFrameLength = (uint64_t)headerLength + payloadLength;
        if (totalFrameLength < payloadLength) {
            [events addObject:[self protocolErrorEventWithCloseCode:1009
                                                          closeReason:@"Frame too large"]];
            [self resetConnectionState];
            return events;
        }

        if ((uint64_t)(self.readBuffer.length - offset) < totalFrameLength) {
            break;
        }

        NSUInteger payloadSize = (NSUInteger)payloadLength;
        NSMutableData *payload = [NSMutableData dataWithLength:payloadSize];
        if (payloadSize > 0) {
            uint8_t *payloadBytes = (uint8_t *)payload.mutableBytes;
            const uint8_t *sourceBytes = bytes + dataOffset;
            if (masked) {
                const uint8_t *maskBytes = bytes + maskOffset;
                for (NSUInteger i = 0; i < payloadSize; i++) {
                    payloadBytes[i] = sourceBytes[i] ^ maskBytes[i % 4];
                }
            } else {
                memcpy(payloadBytes, sourceBytes, payloadSize);
            }
        }

        offset += (NSUInteger)totalFrameLength;

        if (opcode >= WS_OPCODE_CLOSE) {
            // Control frames can be interleaved and are always complete
            WSCodecEvent *event = [self eventForOpcode:opcode payload:payload];
            if (event) {
                [events addObject:event];
            }
        } else {
            // Data or continuation frame
            if (opcode != WS_OPCODE_CONTINUE) {
                if (self.fragmentOpcode != 0) {
                    // RFC 6455 §5.4: a new data frame may not start while a
                    // fragmented message is still in progress.
                    [events addObject:[self protocolErrorEventWithCloseCode:1002
                                                                  closeReason:@"New data frame received while a fragmented message is in progress"]];
                    [self resetConnectionState];
                    return events;
                }
                if (!fin) {
                    self.fragmentOpcode = opcode;
                    self.fragmentsTotalLength = 0;
                    if (![self appendFragment:payload]) {
                        [events addObject:[self protocolErrorEventWithCloseCode:1009
                                                                      closeReason:@"Aggregate message size exceeds limit"]];
                        [self resetConnectionState];
                        return events;
                    }
                } else {
                    WSCodecEvent *event = [self eventForOpcode:opcode payload:payload];
                    if (event) {
                        [events addObject:event];
                    }
                }
            } else {
                if (self.fragmentOpcode == 0) {
                    // RFC 6455 §5.4: a continuation frame must not appear
                    // without a preceding non-FIN data frame to continue.
                    [events addObject:[self protocolErrorEventWithCloseCode:1002
                                                                  closeReason:@"Continuation frame with no preceding start frame"]];
                    [self resetConnectionState];
                    return events;
                }
                if (![self appendFragment:payload]) {
                    [events addObject:[self protocolErrorEventWithCloseCode:1009
                                                                  closeReason:@"Aggregate message size exceeds limit"]];
                    [self resetConnectionState];
                    return events;
                }
                if (fin) {
                    // Reassemble
                    NSUInteger totalLength = 0;
                    for (NSData *frag in self.fragments) {
                        totalLength += frag.length;
                    }
                    NSMutableData *reassembled = [NSMutableData dataWithCapacity:totalLength];
                    for (NSData *frag in self.fragments) {
                        [reassembled appendData:frag];
                    }
                    WSCodecEvent *event = [self eventForOpcode:self.fragmentOpcode payload:reassembled];
                    if (event) {
                        [events addObject:event];
                    }
                    [self.fragments removeAllObjects];
                    self.fragmentOpcode = 0;
                    self.fragmentsTotalLength = 0;
                }
            }
        }
    }

    if (offset == self.readBuffer.length) {
        [self.readBuffer setLength:0];
        self.readOffset = 0;
    } else if (offset > 0 && offset >= self.readBuffer.length / 2) {
        // Amortized compaction: only shift the residual tail down when the
        // consumed prefix is at least half the buffer, so a stream of small
        // frames doesn't pay an O(buffer) memmove on every read. Otherwise
        // just remember how far we've consumed and resume from there next
        // time -- the buffer keeps growing at the tail via appendData.
        [self.readBuffer replaceBytesInRange:NSMakeRange(0, offset) withBytes:NULL length:0];
        self.readOffset = 0;
    } else {
        self.readOffset = offset;
    }

    return events;
}

- (nullable WSCodecEvent *)eventForOpcode:(uint8_t)opcode payload:(NSData *)payload {
    switch (opcode) {
        case WS_OPCODE_TEXT: {
            NSString *text = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
            return [[WSCodecEvent alloc] initWithType:WSCodecEventTextMessage
                                              payload:nil
                                            closeCode:0
                                          closeReason:nil
                                                 text:text];
        }
        case WS_OPCODE_BINARY:
            return [[WSCodecEvent alloc] initWithType:WSCodecEventBinaryMessage
                                              payload:payload
                                            closeCode:0
                                          closeReason:nil
                                                 text:nil];
        case WS_OPCODE_CLOSE: {
            NSInteger code = 0;
            NSString *reason = @"";

            if (payload.length >= 2) {
                const unsigned char *payloadBytes = (const unsigned char *)payload.bytes;
                code = (NSInteger)payloadBytes[0] << 8 | (NSInteger)payloadBytes[1];
                if (payload.length > 2) {
                    NSUInteger reasonLength = payload.length - 2;
                    if (reasonLength > 1000) {
                        reasonLength = 1000;
                    }
                    reason = [[NSString alloc] initWithData:[payload subdataWithRange:NSMakeRange(2, reasonLength)]
                                                   encoding:NSUTF8StringEncoding];
                }
            }
            return [[WSCodecEvent alloc] initWithType:WSCodecEventClose
                                              payload:payload
                                            closeCode:code
                                          closeReason:reason
                                                 text:nil];
        }
        case WS_OPCODE_PING:
            return [[WSCodecEvent alloc] initWithType:WSCodecEventPing
                                              payload:payload
                                            closeCode:0
                                          closeReason:nil
                                                 text:nil];
        case WS_OPCODE_PONG:
            return [[WSCodecEvent alloc] initWithType:WSCodecEventPong
                                              payload:payload
                                            closeCode:0
                                          closeReason:nil
                                                 text:nil];
        default:
            return nil;
    }
}

- (NSData *)createFrameWithOpcode:(uint8_t)opcode payload:(NSData *)payload {
    NSMutableData *frame = [NSMutableData data];

    uint8_t firstByte = WS_FLAG_FIN | opcode;
    [frame appendBytes:&firstByte length:1];

    uint64_t length = payload.length;
    if (length < 126) {
        uint8_t secondByte = (uint8_t)length | (self.maskOutgoingFrames ? WS_MASK : 0);
        [frame appendBytes:&secondByte length:1];
    } else if (length < 65536) {
        uint8_t secondByte = 126 | (self.maskOutgoingFrames ? WS_MASK : 0);
        uint8_t lengthBytes[2] = {(uint8_t)((length >> 8) & 0xFF),
                                  (uint8_t)(length & 0xFF)};
        [frame appendBytes:&secondByte length:1];
        [frame appendBytes:lengthBytes length:2];
    } else {
        uint8_t secondByte = 127 | (self.maskOutgoingFrames ? WS_MASK : 0);
        uint8_t lengthBytes[8];
        for (int i = 7; i >= 0; i--) {
            lengthBytes[i] = (uint8_t)(length & 0xFF);
            length >>= 8;
        }
        [frame appendBytes:&secondByte length:1];
        [frame appendBytes:lengthBytes length:8];
    }

    if (self.maskOutgoingFrames) {
        uint8_t mask[4];
        arc4random_buf(mask, sizeof(mask));
        [frame appendBytes:mask length:sizeof(mask)];

        NSMutableData *maskedPayload = [NSMutableData dataWithLength:payload.length];
        const uint8_t *source = payload.bytes;
        uint8_t *destination = maskedPayload.mutableBytes;
        for (NSUInteger index = 0; index < payload.length; index++) {
            destination[index] = source[index] ^ mask[index % sizeof(mask)];
        }
        [frame appendData:maskedPayload];
    } else {
        [frame appendData:payload];
    }

    return frame;
}

- (NSData *)textFrame:(NSString *)text {
    NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
    return [self createFrameWithOpcode:WS_OPCODE_TEXT payload:textData];
}

- (NSData *)binaryFrame:(NSData *)payload {
    return [self createFrameWithOpcode:WS_OPCODE_BINARY payload:payload];
}

- (NSData *)pingFrame:(nullable NSData *)payload {
    return [self createFrameWithOpcode:WS_OPCODE_PING payload:payload ?: [NSData data]];
}

- (NSData *)pongFrame:(nullable NSData *)payload {
    return [self createFrameWithOpcode:WS_OPCODE_PONG payload:payload ?: [NSData data]];
}

- (NSData *)closeFrame:(NSInteger)code reason:(nullable NSString *)reason {
    NSMutableData *closeData = [NSMutableData dataWithCapacity:2 + (reason ? reason.length : 0)];
    uint8_t codeBytes[2] = {(uint8_t)((code >> 8) & 0xFF),
                            (uint8_t)(code & 0xFF)};
    [closeData appendBytes:codeBytes length:2];
    if (reason.length > 0) {
        [closeData appendData:[reason dataUsingEncoding:NSUTF8StringEncoding]];
    }

    return [self createFrameWithOpcode:WS_OPCODE_CLOSE payload:closeData];
}

@end
