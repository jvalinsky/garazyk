// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/WebSocket/WebSocketProtocolSession.h"

@implementation ATProtoWSSessionAction
+ (instancetype)actionWithType:(WSSessionActionType)type data:(nullable id)data {
  ATProtoWSSessionAction *action = [[ATProtoWSSessionAction alloc] init];
  action.type = type;
  action.data = data;
  return action;
}
@end

@interface ATProtoWebSocketProtocolSession ()
@property(nonatomic, strong, readwrite) ATProtoWebSocketCodec *codec;
@property(nonatomic, strong, readwrite) ATProtoWebSocketHeartbeatPolicy *heartbeatPolicy;
@property(nonatomic, assign) BOOL isUnderBackpressure;
@end

@implementation ATProtoWebSocketProtocolSession

- (instancetype)init {
  self = [super init];
  if (self) {
    _codec = [[ATProtoWebSocketCodec alloc] init];
    _heartbeatPolicy = [[ATProtoWebSocketHeartbeatPolicy alloc] init];
    _maxOutboundQueueBytes = 10 * 1024 * 1024; // 10MB default
    _backpressureWarningThreshold = 0.7;
    _backpressureCriticalThreshold = 0.9;
    _isUnderBackpressure = NO;
  }
  return self;
}

- (NSArray<ATProtoWSSessionAction *> *)feedData:(NSData *)data {
  return [self feedData:data
             receivedAt:[[NSDate date] timeIntervalSince1970]];
}

- (NSArray<ATProtoWSSessionAction *> *)feedData:(NSData *)data
                              receivedAt:(NSTimeInterval)receivedAt {
  NSArray<ATProtoWSCodecEvent *> *codecEvents = [self.codec feedData:data];
  NSMutableArray<ATProtoWSSessionAction *> *actions = [NSMutableArray array];

  for (ATProtoWSCodecEvent *codecEvent in codecEvents) {
    switch (codecEvent.type) {
    case WSCodecEventTextMessage:
      [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeNotifyTextMessage data:codecEvent.text]];
      break;
    case WSCodecEventBinaryMessage:
      [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeNotifyBinaryMessage data:codecEvent.payload]];
      break;
    case WSCodecEventPing:
      [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeHandlePing data:codecEvent.payload]];
      break;
    case WSCodecEventPong: {
      [self.heartbeatPolicy pongReceived:receivedAt];
      [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeHandlePong data:codecEvent.payload]];
      break;
    }
    case WSCodecEventClose:
    case WSCodecEventProtocolError:
      [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeClose data:codecEvent]];
      break;
    }
  }

  return [actions copy];
}

- (NSArray<ATProtoWSSessionAction *> *)tick:(NSTimeInterval)now {
  NSMutableArray<ATProtoWSSessionAction *> *actions = [NSMutableArray array];
  WSHeartbeatAction heartbeatAction = [self.heartbeatPolicy tick:now];

  if (heartbeatAction == WSHeartbeatActionSendPing) {
    [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeSendPing data:nil]];
    [self.heartbeatPolicy pingSent:now];
  } else if (heartbeatAction == WSHeartbeatActionTimeout) {
    [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeHeartbeatTimeout data:nil]];
  }

  return [actions copy];
}

- (NSArray<ATProtoWSSessionAction *> *)didEnqueueFrameOfSize:(NSUInteger)size
                                     currentQueueSize:(NSUInteger)currentSize {
  NSMutableArray<ATProtoWSSessionAction *> *actions = [NSMutableArray array];
  double fillPercentage = (double)currentSize / (double)self.maxOutboundQueueBytes;

  if (fillPercentage >= self.backpressureCriticalThreshold) {
    [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeBackpressureCritical data:@(fillPercentage)]];
  } else if (fillPercentage >= self.backpressureWarningThreshold) {
    if (!self.isUnderBackpressure) {
      self.isUnderBackpressure = YES;
      [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeBackpressureWarning data:@(fillPercentage)]];
    }
  }

  return [actions copy];
}

- (NSArray<ATProtoWSSessionAction *> *)didDequeueFrameOfSize:(NSUInteger)size
                                     currentQueueSize:(NSUInteger)currentSize {
  NSMutableArray<ATProtoWSSessionAction *> *actions = [NSMutableArray array];
  double fillPercentage = (double)currentSize / (double)self.maxOutboundQueueBytes;

  if (self.isUnderBackpressure && fillPercentage < self.backpressureWarningThreshold) {
    self.isUnderBackpressure = NO;
    [actions addObject:[ATProtoWSSessionAction actionWithType:WSSessionActionTypeBackpressureCleared data:nil]];
  }

  return [actions copy];
}

@end
