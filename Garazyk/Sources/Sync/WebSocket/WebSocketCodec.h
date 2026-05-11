// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WSCodecEventType) {
    WSCodecEventTextMessage,
    WSCodecEventBinaryMessage,
    WSCodecEventPing,
    WSCodecEventPong,
    WSCodecEventClose,
    WSCodecEventProtocolError
};

@interface WSCodecEvent : NSObject

@property (nonatomic, readonly) WSCodecEventType type;
@property (nonatomic, readonly, nullable) NSData *payload;
@property (nonatomic, readonly) NSInteger closeCode;
@property (nonatomic, readonly, nullable) NSString *closeReason;
@property (nonatomic, readonly, nullable) NSString *text;

- (instancetype)initWithType:(WSCodecEventType)type
                     payload:(nullable NSData *)payload
                   closeCode:(NSInteger)closeCode
                 closeReason:(nullable NSString *)closeReason
                        text:(nullable NSString *)text;

@end

@interface WebSocketCodec : NSObject

// Codec configuration
@property (nonatomic, assign) uint64_t maxFrameSize; // default 16MB

// Feed raw bytes in, get protocol events out
- (NSArray<WSCodecEvent *> *)feedData:(NSData *)data;

// Build outbound frames (no I/O, returns bytes to write)
- (NSData *)textFrame:(NSString *)text;
- (NSData *)binaryFrame:(NSData *)payload;
- (NSData *)pingFrame:(nullable NSData *)payload;
- (NSData *)pongFrame:(nullable NSData *)payload;
- (NSData *)closeFrame:(NSInteger)code reason:(nullable NSString *)reason;

@end

NS_ASSUME_NONNULL_END
