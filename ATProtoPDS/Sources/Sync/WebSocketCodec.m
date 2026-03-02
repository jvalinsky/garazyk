#import "Sync/WebSocketCodec.h"

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
@end

@implementation WebSocketCodec

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxFrameSize = 16 * 1024 * 1024; // 16MB default
        _readBuffer = [NSMutableData data];
    }
    return self;
}

- (NSArray<WSCodecEvent *> *)feedData:(NSData *)data {
    if (data.length > 0) {
        [self.readBuffer appendData:data];
    }

    NSMutableArray<WSCodecEvent *> *events = [NSMutableArray array];

    while (self.readBuffer.length >= 2) {
        const uint8_t *bytes = self.readBuffer.bytes;
        uint8_t firstByte = bytes[0];
        uint8_t secondByte = bytes[1];

        // BOOL fin = (firstByte & WS_FLAG_FIN) != 0;
        uint8_t opcode = firstByte & 0x0F;
        BOOL masked = (secondByte & WS_MASK) != 0;
        uint64_t payloadLength = secondByte & 0x7F;
        NSUInteger extendedLengthOffset = 0;

        if (payloadLength == 126) {
            if (self.readBuffer.length < 4) return events;
            payloadLength = (uint64_t)bytes[2] << 8 | bytes[3];
            extendedLengthOffset = 2;
        } else if (payloadLength == 127) {
            if (self.readBuffer.length < 10) return events;
            payloadLength = 0;
            for (int i = 0; i < 8; i++) {
                payloadLength = (payloadLength << 8) | bytes[2 + i];
            }
            extendedLengthOffset = 8;
        }

        if (payloadLength > self.maxFrameSize) {
            [events addObject:[[WSCodecEvent alloc] initWithType:WSCodecEventProtocolError
                                                         payload:nil
                                                       closeCode:1009
                                                     closeReason:@"Frame too large"
                                                            text:nil]];
            return events;
        }

        NSUInteger headerLength = 2 + extendedLengthOffset + (masked ? 4 : 0);
        NSUInteger maskOffset = 2 + extendedLengthOffset;
        NSUInteger dataOffset = headerLength;

        if (self.readBuffer.length < headerLength + payloadLength) {
            return events;
        }

        NSMutableData *payload = [NSMutableData dataWithCapacity:payloadLength];
        if (masked) {
            const uint8_t *maskBytes = bytes + maskOffset;
            for (NSUInteger i = 0; i < payloadLength; i++) {
                uint8_t maskedByte = bytes[dataOffset + i];
                uint8_t unmaskedByte = maskedByte ^ maskBytes[i % 4];
                [payload appendBytes:&unmaskedByte length:1];
            }
        } else {
            [payload appendBytes:bytes + dataOffset length:payloadLength];
        }

        [self.readBuffer replaceBytesInRange:NSMakeRange(0, headerLength + payloadLength)
                                   withBytes:NULL
                                      length:0];

        WSCodecEvent *event = [self eventForOpcode:opcode payload:payload];
        if (event) {
            [events addObject:event];
        }
        
        // Note: The original parser didn't fully handle FIN=0 logic natively in the parser. 
        // We preserve that behavior but emit the events. If it was FIN=0, the old parser just exited the loop 
        // without consuming more, or returned? Let's check original behavior.
        // Original: "if (!fin) { return; }" 
        // This was a bug in original parser (it would stop processing buffered data until more came in).
        // Let's drop the "return" so it keeps parsing if there are more frames in buffer, 
        // making the codec more correct.
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
        uint8_t secondByte = (uint8_t)length;
        [frame appendBytes:&secondByte length:1];
    } else if (length < 65536) {
        uint8_t secondByte = 126;
        uint8_t lengthBytes[2] = {(uint8_t)((length >> 8) & 0xFF),
                                  (uint8_t)(length & 0xFF)};
        [frame appendBytes:&secondByte length:1];
        [frame appendBytes:lengthBytes length:2];
    } else {
        uint8_t secondByte = 127;
        uint8_t lengthBytes[8];
        for (int i = 7; i >= 0; i--) {
            lengthBytes[i] = (uint8_t)(length & 0xFF);
            length >>= 8;
        }
        [frame appendBytes:&secondByte length:1];
        [frame appendBytes:lengthBytes length:8];
    }

    [frame appendData:payload];

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
