// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Sync/WebSocket/WebSocketCodec.h"
#import "Sync/WebSocket/WebSocketHeartbeatPolicy.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Actions emitted by a WebSocket protocol session for the transport driver.
 */
typedef NS_ENUM(NSInteger, WSSessionActionType) {
  /** Deliver a text message to the application. */
  WSSessionActionTypeNotifyTextMessage,
  /** Deliver a binary message to the application. */
  WSSessionActionTypeNotifyBinaryMessage,
  /** Reply to or otherwise process an inbound ping. */
  WSSessionActionTypeHandlePing,
  /** Process an inbound pong. */
  WSSessionActionTypeHandlePong,
  /** Close the WebSocket connection. */
  WSSessionActionTypeClose,
  /** Send a heartbeat ping. */
  WSSessionActionTypeSendPing,
  /** Close or fail the session because heartbeat liveness expired. */
  WSSessionActionTypeHeartbeatTimeout,
  /** Notify that outbound queue usage crossed the warning threshold. */
  WSSessionActionTypeBackpressureWarning,
  /** Notify that outbound queue usage crossed the critical threshold. */
  WSSessionActionTypeBackpressureCritical,
  /** Notify that outbound queue usage returned below pressure thresholds. */
  WSSessionActionTypeBackpressureCleared
};

/**
 * @abstract Driver action produced by WebSocketProtocolSession.
 */
@interface WSSessionAction : NSObject
/** Action kind. */
@property(nonatomic, assign) WSSessionActionType type;
/** Optional action payload, such as message bytes or close metadata. */
@property(nonatomic, strong, nullable) id data;
/** Creates an action with optional payload data. */
+ (instancetype)actionWithType:(WSSessionActionType)type data:(nullable id)data;
@end

/**
 * @abstract Coordinates WebSocket framing, heartbeat, and backpressure without owning socket I/O.
 */
@interface WebSocketProtocolSession : NSObject

/** Frame codec used to parse inbound bytes and build outbound frames. */
@property(nonatomic, readonly) WebSocketCodec *codec;
/** Heartbeat policy used to decide ping and timeout actions. */
@property(nonatomic, readonly) WebSocketHeartbeatPolicy *heartbeatPolicy;

/** Maximum outbound queue size before backpressure actions become critical. */
@property(nonatomic, assign) NSUInteger maxOutboundQueueBytes;
/** Fraction of maxOutboundQueueBytes that emits a warning. */
@property(nonatomic, assign) double backpressureWarningThreshold;
/** Fraction of maxOutboundQueueBytes that emits a critical warning. */
@property(nonatomic, assign) double backpressureCriticalThreshold;

/** Feeds inbound bytes using the current time for liveness bookkeeping. */
- (NSArray<WSSessionAction *> *)feedData:(NSData *)data;
/** Feeds inbound bytes and records the supplied receive timestamp. */
- (NSArray<WSSessionAction *> *)feedData:(NSData *)data
                              receivedAt:(NSTimeInterval)receivedAt;
/** Advances heartbeat and timeout state for the supplied timestamp. */
- (NSArray<WSSessionAction *> *)tick:(NSTimeInterval)now;

/** Records an outbound frame enqueue and emits any resulting backpressure action. */
- (NSArray<WSSessionAction *> *)didEnqueueFrameOfSize:(NSUInteger)size
                                     currentQueueSize:(NSUInteger)currentSize;
/** Records an outbound frame dequeue and emits any resulting pressure-clear action. */
- (NSArray<WSSessionAction *> *)didDequeueFrameOfSize:(NSUInteger)size
                                     currentQueueSize:(NSUInteger)currentSize;

@end

NS_ASSUME_NONNULL_END
