// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Event types emitted by the WebSocket frame codec.
 */
typedef NS_ENUM(NSInteger, WSCodecEventType) {
    /** A complete UTF-8 text message was received. */
    WSCodecEventTextMessage,
    /** A complete binary message was received. */
    WSCodecEventBinaryMessage,
    /** A ping control frame was received. */
    WSCodecEventPing,
    /** A pong control frame was received. */
    WSCodecEventPong,
    /** A close control frame was received. */
    WSCodecEventClose,
    /** Invalid WebSocket framing or payload data was received. */
    WSCodecEventProtocolError
};

/**
 * @abstract Parsed WebSocket protocol event produced by WebSocketCodec.
 */
@interface WSCodecEvent : NSObject

/** Event kind. */
@property (nonatomic, readonly) WSCodecEventType type;
/** Binary payload for message or control events. */
@property (nonatomic, readonly, nullable) NSData *payload;
/** Close status code for close events. */
@property (nonatomic, readonly) NSInteger closeCode;
/** Close reason for close events. */
@property (nonatomic, readonly, nullable) NSString *closeReason;
/** Decoded text for text-message events. */
@property (nonatomic, readonly, nullable) NSString *text;

/**
 * @abstract Initializes a parsed codec event.
 */
- (instancetype)initWithType:(WSCodecEventType)type
                     payload:(nullable NSData *)payload
                   closeCode:(NSInteger)closeCode
                 closeReason:(nullable NSString *)closeReason
                        text:(nullable NSString *)text;

@end

/**
 * @abstract Sans-I/O WebSocket frame encoder and decoder.
 * @discussion The codec accepts raw bytes and emits protocol events. It does not own socket I/O.
 */
@interface WebSocketCodec : NSObject

/** Maximum accepted frame payload size in bytes. Defaults to 16 MB. */
@property (nonatomic, assign) uint64_t maxFrameSize; // default 16MB

/**
 * @abstract Parses inbound bytes into zero or more WebSocket events.
 * @param data Raw bytes read from the transport.
 * @return Parsed events, including protocol errors when framing is invalid.
 */
- (NSArray<WSCodecEvent *> *)feedData:(NSData *)data;

/** Builds a text message frame for outbound transport. */
- (NSData *)textFrame:(NSString *)text;
/** Builds a binary message frame for outbound transport. */
- (NSData *)binaryFrame:(NSData *)payload;
/** Builds a ping control frame for outbound transport. */
- (NSData *)pingFrame:(nullable NSData *)payload;
/** Builds a pong control frame for outbound transport. */
- (NSData *)pongFrame:(nullable NSData *)payload;
/** Builds a close control frame for outbound transport. */
- (NSData *)closeFrame:(NSInteger)code reason:(nullable NSString *)reason;

@end

NS_ASSUME_NONNULL_END
