#import "Sync/WebSocket/WebSocketProtocolSession.h"

@implementation WSSessionAction
+ (instancetype)actionWithType:(WSSessionActionType)type data:(nullable id)data {
  WSSessionAction *action = [[WSSessionAction alloc] init];
  action.type = type;
  action.data = data;
  return action;
}
@end

@interface WebSocketProtocolSession ()
@property(nonatomic, strong, readwrite) WebSocketCodec *codec;
@property(nonatomic, strong, readwrite) WebSocketHeartbeatPolicy *heartbeatPolicy;
@property(nonatomic, assign) BOOL isUnderBackpressure;
@end

@implementation WebSocketProtocolSession

- (instancetype)init {
  self = [super init];
  if (self) {
    _codec = [[WebSocketCodec alloc] init];
    _heartbeatPolicy = [[WebSocketHeartbeatPolicy alloc] init];
    _maxOutboundQueueBytes = 10 * 1024 * 1024; // 10MB default
    _backpressureWarningThreshold = 0.7;
    _backpressureCriticalThreshold = 0.9;
    _isUnderBackpressure = NO;
  }
  return self;
}

- (NSArray<WSSessionAction *> *)feedData:(NSData *)data {
  return [self feedData:data
             receivedAt:[NSDate timeIntervalSinceReferenceDate]];
}

- (NSArray<WSSessionAction *> *)feedData:(NSData *)data
                              receivedAt:(NSTimeInterval)receivedAt {
  NSArray<WSCodecEvent *> *codecEvents = [self.codec feedData:data];
  NSMutableArray<WSSessionAction *> *actions = [NSMutableArray array];

  for (WSCodecEvent *codecEvent in codecEvents) {
    switch (codecEvent.type) {
    case WSCodecEventTextMessage:
      [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeNotifyTextMessage data:codecEvent.text]];
      break;
    case WSCodecEventBinaryMessage:
      [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeNotifyBinaryMessage data:codecEvent.payload]];
      break;
    case WSCodecEventPing:
      [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeHandlePing data:codecEvent.payload]];
      break;
    case WSCodecEventPong: {
      [self.heartbeatPolicy pongReceived:receivedAt];
      [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeHandlePong data:codecEvent.payload]];
      break;
    }
    case WSCodecEventClose:
    case WSCodecEventProtocolError:
      [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeClose data:codecEvent]];
      break;
    }
  }

  return [actions copy];
}

- (NSArray<WSSessionAction *> *)tick:(NSTimeInterval)now {
  NSMutableArray<WSSessionAction *> *actions = [NSMutableArray array];
  WSHeartbeatAction heartbeatAction = [self.heartbeatPolicy tick:now];

  if (heartbeatAction == WSHeartbeatActionSendPing) {
    [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeSendPing data:nil]];
    [self.heartbeatPolicy pingSent:now];
  } else if (heartbeatAction == WSHeartbeatActionTimeout) {
    [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeHeartbeatTimeout data:nil]];
  }

  return [actions copy];
}

- (NSArray<WSSessionAction *> *)didEnqueueFrameOfSize:(NSUInteger)size
                                     currentQueueSize:(NSUInteger)currentSize {
  NSMutableArray<WSSessionAction *> *actions = [NSMutableArray array];
  double fillPercentage = (double)currentSize / (double)self.maxOutboundQueueBytes;

  if (fillPercentage >= self.backpressureCriticalThreshold) {
    [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeBackpressureCritical data:@(fillPercentage)]];
  } else if (fillPercentage >= self.backpressureWarningThreshold) {
    if (!self.isUnderBackpressure) {
      self.isUnderBackpressure = YES;
      [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeBackpressureWarning data:@(fillPercentage)]];
    }
  }

  return [actions copy];
}

- (NSArray<WSSessionAction *> *)didDequeueFrameOfSize:(NSUInteger)size
                                     currentQueueSize:(NSUInteger)currentSize {
  NSMutableArray<WSSessionAction *> *actions = [NSMutableArray array];
  double fillPercentage = (double)currentSize / (double)self.maxOutboundQueueBytes;

  if (self.isUnderBackpressure && fillPercentage < self.backpressureWarningThreshold) {
    self.isUnderBackpressure = NO;
    [actions addObject:[WSSessionAction actionWithType:WSSessionActionTypeBackpressureCleared data:nil]];
  }

  return [actions copy];
}

@end
