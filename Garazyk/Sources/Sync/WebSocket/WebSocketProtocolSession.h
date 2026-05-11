// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Sync/WebSocket/WebSocketCodec.h"
#import "Sync/WebSocket/WebSocketHeartbeatPolicy.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WSSessionActionType) {
  WSSessionActionTypeNotifyTextMessage,
  WSSessionActionTypeNotifyBinaryMessage,
  WSSessionActionTypeHandlePing,
  WSSessionActionTypeHandlePong,
  WSSessionActionTypeClose,
  WSSessionActionTypeSendPing,
  WSSessionActionTypeHeartbeatTimeout,
  WSSessionActionTypeBackpressureWarning,
  WSSessionActionTypeBackpressureCritical,
  WSSessionActionTypeBackpressureCleared
};

@interface WSSessionAction : NSObject
@property(nonatomic, assign) WSSessionActionType type;
@property(nonatomic, strong, nullable) id data;
+ (instancetype)actionWithType:(WSSessionActionType)type data:(nullable id)data;
@end

@interface WebSocketProtocolSession : NSObject

@property(nonatomic, readonly) WebSocketCodec *codec;
@property(nonatomic, readonly) WebSocketHeartbeatPolicy *heartbeatPolicy;

// Configuration
@property(nonatomic, assign) NSUInteger maxOutboundQueueBytes;
@property(nonatomic, assign) double backpressureWarningThreshold;
@property(nonatomic, assign) double backpressureCriticalThreshold;

- (NSArray<WSSessionAction *> *)feedData:(NSData *)data;
- (NSArray<WSSessionAction *> *)feedData:(NSData *)data
                              receivedAt:(NSTimeInterval)receivedAt;
- (NSArray<WSSessionAction *> *)tick:(NSTimeInterval)now;

// Tracking outbound state (input from driver)
- (NSArray<WSSessionAction *> *)didEnqueueFrameOfSize:(NSUInteger)size
                                     currentQueueSize:(NSUInteger)currentSize;
- (NSArray<WSSessionAction *> *)didDequeueFrameOfSize:(NSUInteger)size
                                     currentQueueSize:(NSUInteger)currentSize;

@end

NS_ASSUME_NONNULL_END
