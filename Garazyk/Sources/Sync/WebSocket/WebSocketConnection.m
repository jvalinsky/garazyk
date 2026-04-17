#import "Sync/WebSocket/WebSocketConnection.h"
#import "Compat/PDSTypes.h"
#import "Network/PDSNetworkTransport.h"
#import "Network/HttpParsing.h"
#import "Sync/WebSocket/WebSocketCodec.h"
#import "Sync/WebSocket/WebSocketHeartbeatPolicy.h"
#import "Debug/PDSLogger.h"
#import "Metrics/PDSMetrics.h"
#import <CommonCrypto/CommonDigest.h>

static const NSUInteger WS_DEFAULT_MAX_QUEUE_BYTES = 10 * 1024 * 1024; // 10MB default

NSString *const WebSocketConnectionErrorDomain =
    @"com.atproto.pds.websocket.error";

NSInteger const WebSocketConnectionErrorCodeConnectionClosed = 2000;
NSInteger const WebSocketConnectionErrorCodeInvalidFrame = 2001;
NSInteger const WebSocketConnectionErrorCodeWriteFailed = 2002;

@interface WebSocketConnection ()

@property(nonatomic, assign, readwrite) WebSocketConnectionState state;
@property(nonatomic, copy, readwrite) NSString *queryString;
@property(nonatomic, copy, readwrite, nullable)
    NSDictionary<NSString *, id> *queryParams;

@property(nonatomic, strong) id<PDSNetworkConnection> connection;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_queue_t connectionQueue;
@property(nonatomic, strong) NSMutableData *writeBuffer;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t writeQueue;
@property(nonatomic, strong) NSMutableArray<NSData *> *messageQueue;
@property(nonatomic, assign) NSUInteger queuedSendBytes;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG, nullable)
    dispatch_source_t heartbeatTimer;

@property(nonatomic, strong) WebSocketCodec *codec;
@property(nonatomic, strong) WebSocketHeartbeatPolicy *heartbeatPolicy;
@property(nonatomic, assign) BOOL isUnderBackpressure;

@end

@implementation WebSocketConnection

- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                        path:(NSString *)path {
  self = [super init];
  if (self) {
    [self commonInit];
    _host = [host copy];
    _remoteAddress = [host copy];
    _port = port;
    _path = [path copy];
    _state = WebSocketConnectionStateConnecting;

    NSRange queryRange = [path rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
      _queryString = [path substringFromIndex:queryRange.location + 1];
      _queryParams = [HttpParsing parseQueryString:_queryString];
      _path = [path substringToIndex:queryRange.location];
    } else {
      _queryString = @"";
      _queryParams = nil;
    }
  }
  return self;
}

- (instancetype)initWithConnection:(id<PDSNetworkConnection>)connection {
  self = [super init];
  if (self) {
    [self commonInit];
    _connection = connection;
    _state = WebSocketConnectionStateConnected;
    _remoteAddress = [[connection remoteAddress] copy] ?: @"unknown";
    _host = _remoteAddress;
    _path = @"/";
    _queryString = @"";
  }
  return self;
}

- (void)commonInit {
  _identifier = [NSUUID UUID];
  _messageQueue = [NSMutableArray array];
  _queuedSendBytes = 0;
  _writeQueue = dispatch_queue_create("com.atproto.pds.websocket.write",
                                      DISPATCH_QUEUE_SERIAL);
  _connectionQueue = dispatch_queue_create(
      "com.atproto.pds.websocket.connection", DISPATCH_QUEUE_SERIAL);
  _codec = [[WebSocketCodec alloc] init];
  _heartbeatPolicy = [[WebSocketHeartbeatPolicy alloc] init];
  _maxOutboundQueueBytes = WS_DEFAULT_MAX_QUEUE_BYTES;
  _backpressureWarningThreshold = 0.7;
  _backpressureCriticalThreshold = 0.9;
}

- (NSTimeInterval)heartbeatInterval {
  return self.heartbeatPolicy.heartbeatInterval;
}

- (void)setHeartbeatInterval:(NSTimeInterval)interval {
  self.heartbeatPolicy.heartbeatInterval = interval;
}

- (NSTimeInterval)heartbeatTimeout {
  return self.heartbeatPolicy.heartbeatTimeout;
}

- (void)setHeartbeatTimeout:(NSTimeInterval)timeout {
  self.heartbeatPolicy.heartbeatTimeout = timeout;
}

- (void)start {
  __weak typeof(self) weakSelf = self;
  self.connection.stateChangedHandler =
      ^(PDSNetworkConnectionState state, NSError *_Nullable error) {
        [weakSelf handlePDSStateChange:state error:error];
      };

  [self.connection startWithQueue:self.connectionQueue];
  [self startReading];
  [self startHeartbeat];
}

- (void)startOnExistingTransport {
  if (!self.connection) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  void (^originalHandler)(PDSNetworkConnectionState, NSError *) =
      self.connection.stateChangedHandler;
  self.connection.stateChangedHandler =
      ^(PDSNetworkConnectionState state, NSError *_Nullable error) {
        if (originalHandler) {
          originalHandler(state, error);
        }
        [weakSelf handlePDSStateChange:state error:error];
      };
  [self startReading];
  [self startHeartbeat];
}

- (instancetype)init {
  return [self initWithHost:@"localhost" port:0 path:@"/"];
}

- (void)dealloc {
  [self stopHeartbeat];
  if (_connection) {
    [_connection cancel];
  }
}

- (BOOL)connect:(NSError **)error {
  if (self.state != WebSocketConnectionStateConnecting) {
    if (error) {
      *error =
          [NSError errorWithDomain:WebSocketConnectionErrorDomain
                              code:WebSocketConnectionErrorCodeConnectionClosed
                          userInfo:@{
                            NSLocalizedDescriptionKey :
                                @"Connection is not in connecting state"
                          }];
    }
    return NO;
  }

  self.connectionQueue = dispatch_queue_create(
      "com.atproto.pds.websocket.connection", DISPATCH_QUEUE_SERIAL);

  self.connection =
      [PDSNetworkTransportFactory createConnectionWithHost:self.host
                                                      port:self.port];

  [self setupInitialState];

  __weak typeof(self) weakSelf = self;
  self.connection.stateChangedHandler =
      ^(PDSNetworkConnectionState state, NSError *_Nullable error) {
        [weakSelf handlePDSStateChange:state error:error];
      };

  [self.connection startWithQueue:self.connectionQueue];

  return YES;
}

- (void)setupInitialState {
}

- (void)handlePDSStateChange:(PDSNetworkConnectionState)state
                       error:(NSError *_Nullable)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    switch (state) {
    case PDSNetworkConnectionStateReady: {
      self.state = WebSocketConnectionStateConnected;
      [self startReading];
      [self startHeartbeat];
      if ([self.delegate respondsToSelector:@selector(webSocketConnectionStateDidChange:)]) {
        [self.delegate webSocketConnectionStateDidChange:self];
      }
      break;
    }

    case PDSNetworkConnectionStateCancelled:
      self.state = WebSocketConnectionStateClosed;
      [self stopHeartbeat];
      [self notifyCloseWithCode:0 reason:@"Connection cancelled"];
      break;

    case PDSNetworkConnectionStateFailed:
      self.state = WebSocketConnectionStateClosed;
      [self stopHeartbeat];
      if (error) {
        [self notifyError:error];
      } else {
        [self
            notifyError:
                [NSError
                    errorWithDomain:WebSocketConnectionErrorDomain
                               code:WebSocketConnectionErrorCodeConnectionClosed
                           userInfo:@{
                             NSLocalizedDescriptionKey : @"Connection failed"
                           }]];
      }
      break;

    default:
      break;
    }
  });
}

- (void)startReading {
  __weak typeof(self) weakSelf = self;
  [self.connection
      receiveWithMinimumLength:1
                 maximumLength:UINT32_MAX
                    completion:^(NSData *_Nullable data, BOOL isComplete,
                                 NSError *_Nullable error) {
                      __strong typeof(weakSelf) strongSelf = weakSelf;
                      if (!strongSelf)
                        return;

                      if (data) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                          [strongSelf handleReceivedData:data];
                        });
                      }

                      if (error) {
                        return;
                      }

                      if (isComplete) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                          if (strongSelf.state !=
                              WebSocketConnectionStateClosed) {
                            strongSelf.state = WebSocketConnectionStateClosed;
                            [strongSelf
                                notifyCloseWithCode:1000
                                             reason:@"Connection closed"];
                          }
                        });
                        return;
                      }

                      [strongSelf startReading];
                    }];
}

- (void)handleReceivedData:(NSData *)data {
  NSArray<WSCodecEvent *> *events = [self.codec feedData:data];
  
  for (WSCodecEvent *event in events) {
    switch (event.type) {
      case WSCodecEventTextMessage:
        [self notifyTextMessage:event.text];
        break;
      case WSCodecEventBinaryMessage:
        [self notifyBinaryMessage:event.payload];
        break;
      case WSCodecEventPing:
        [self handlePingFrame:event.payload];
        break;
      case WSCodecEventPong:
        [self handlePongFrame:event.payload];
        break;
      case WSCodecEventClose:
        [self closeWithCode:event.closeCode reason:event.closeReason];
        break;
      case WSCodecEventProtocolError:
        [self closeWithCode:event.closeCode reason:event.closeReason];
        break;
    }
  }
}

- (void)handlePingFrame:(NSData *)payload {
  [self sendPong:payload];
}

- (void)handlePongFrame:(NSData *)payload {
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  [self.heartbeatPolicy pongReceived:now];
}

- (void)close {
  [self closeWithCode:1000 reason:@"Normal closure"];
}

- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
  if (self.state == WebSocketConnectionStateClosing ||
      self.state == WebSocketConnectionStateClosed) {
    return;
  }

  self.state = WebSocketConnectionStateClosing;
  self.closeCode = code;
  self.closeReason = reason;
  dispatch_async(self.writeQueue, ^{
    [self.messageQueue removeAllObjects];
    self.queuedSendBytes = 0;
  });

  NSData *frame = [self.codec closeFrame:code reason:reason];
  [self writeData:frame];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   if (self.state != WebSocketConnectionStateClosed) {
                     self.state = WebSocketConnectionStateClosed;
                     [self notifyCloseWithCode:code reason:reason];
                   }
                 });
}

- (void)sendMessage:(NSData *)data {
  [self sendFrame:[self.codec binaryFrame:data]];
}

- (void)sendText:(NSString *)text {
  [self sendFrame:[self.codec textFrame:text]];
}

- (void)sendPing:(NSData *)payload {
  [self sendFrame:[self.codec pingFrame:payload]];
}

- (void)sendPong:(NSData *)payload {
  [self sendFrame:[self.codec pongFrame:payload]];
}

- (void)sendFrame:(NSData *)frame {
  dispatch_async(self.writeQueue, ^{
    if (self.state == WebSocketConnectionStateClosing ||
        self.state == WebSocketConnectionStateClosed) {
      return;
    }

    NSUInteger newQueueSize = self.queuedSendBytes + frame.length;
    double fillPercentage = (double)newQueueSize / (double)self.maxOutboundQueueBytes;

    // Check critical threshold
    if (fillPercentage >= self.backpressureCriticalThreshold) {
      [self notifyBackpressureCritical:fillPercentage bytes:newQueueSize];
    }
    // Check warning threshold
    else if (fillPercentage >= self.backpressureWarningThreshold) {
      [self notifyBackpressureWarning:fillPercentage bytes:newQueueSize];
    }

    // Check overflow
    if (newQueueSize > self.maxOutboundQueueBytes) {
      [self notifyQueueOverflow:newQueueSize];
      [self.messageQueue removeAllObjects];
      self.queuedSendBytes = 0;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self closeWithCode:1009 reason:@"Outbound queue limit exceeded"];
      });
      return;
    }

    [self.messageQueue addObject:frame];
    self.queuedSendBytes += frame.length;
    if (self.messageQueue.count == 1) {
      [self flushWriteBuffer];
    }
  });
}

- (NSUInteger)pendingSendCount {
  __block NSUInteger count = 0;
  if (!self.writeQueue) {
    return 0;
  }

  dispatch_sync(self.writeQueue, ^{
    count = self.messageQueue.count;
  });
  return count;
}

- (NSUInteger)pendingSendBytes {
  __block NSUInteger bytes = 0;
  if (!self.writeQueue) {
    return 0;
  }

  dispatch_sync(self.writeQueue, ^{
    bytes = self.queuedSendBytes;
  });
  return bytes;
}

- (void)flushWriteBuffer {
  if (self.messageQueue.count == 0)
    return;

  NSData *message = self.messageQueue.firstObject;
  [self writeData:message];
}

- (void)writeData:(NSData *)data {
  __weak typeof(self) weakSelf = self;
  [self.connection sendData:data
                 completion:^(NSError *_Nullable error) {
                   __strong typeof(weakSelf) strongSelf = weakSelf;
                   if (!strongSelf)
                     return;

                   dispatch_async(strongSelf.writeQueue, ^{
                     if (strongSelf.messageQueue.count > 0) {
                       NSData *sentFrame = strongSelf.messageQueue.firstObject;
                       [strongSelf.messageQueue removeObjectAtIndex:0];
                       if (sentFrame.length >= strongSelf.queuedSendBytes) {
                         strongSelf.queuedSendBytes = 0;
                       } else {
                         strongSelf.queuedSendBytes -= sentFrame.length;
                       }
                     }

                     // Check if backpressure cleared
                     double fillPercentage = (double)strongSelf.queuedSendBytes /
                                            (double)strongSelf.maxOutboundQueueBytes;
                     if (strongSelf.isUnderBackpressure &&
                         fillPercentage < strongSelf.backpressureWarningThreshold) {
                       strongSelf.isUnderBackpressure = NO;
                       dispatch_async(dispatch_get_main_queue(), ^{
                         [strongSelf notifyBackpressureCleared];
                       });
                     }

                     [strongSelf flushWriteBuffer];
                   });

                   if (error) {
                     dispatch_async(dispatch_get_main_queue(), ^{
                       [strongSelf notifyError:error];
                     });
                   }
                 }];
}

- (void)startHeartbeat {
  [self stopHeartbeat];
  self.heartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                               dispatch_get_main_queue());
  // Tick more frequently to check the policy (e.g., every 1 second)
  dispatch_source_set_timer(
      self.heartbeatTimer,
      dispatch_walltime(NULL, 1 * NSEC_PER_SEC),
      1 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);

  __weak typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(self.heartbeatTimer, ^{
    [weakSelf tickHeartbeat];
  });
  dispatch_resume(self.heartbeatTimer);
}

- (void)stopHeartbeat {
  if (self.heartbeatTimer) {
    dispatch_source_cancel(self.heartbeatTimer);
    self.heartbeatTimer = nil;
  }
}

- (void)tickHeartbeat {
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  WSHeartbeatAction action = [self.heartbeatPolicy tick:now];
  
  if (action == WSHeartbeatActionSendPing) {
    [self sendPing:nil];
    [self.heartbeatPolicy pingSent:now];
  } else if (action == WSHeartbeatActionTimeout) {
    [self closeWithCode:1001 reason:@"Heartbeat timeout"];
  }
}

- (void)notifyTextMessage:(NSString *)text {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.delegate webSocketConnection:self didReceiveText:text];
  });
}

- (void)notifyBinaryMessage:(NSData *)data {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.delegate webSocketConnection:self didReceiveMessage:data];
  });
}

- (void)notifyCloseWithCode:(NSInteger)code reason:(NSString *)reason {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.delegate webSocketConnection:self
                      didCloseWithCode:code
                                reason:reason];
  });
}

- (void)notifyError:(NSError *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.delegate webSocketConnection:self didFailWithError:error];
  });
}

- (void)notifyBackpressureWarning:(double)fillPercentage bytes:(NSUInteger)bytes {
  if (self.isUnderBackpressure) return; // Already notified
  self.isUnderBackpressure = YES;
  PDS_LOG_SYNC_WARN(@"[%@] WebSocket backpressure warning: queue %.1f%% full (%lu/%lu bytes)",
                    self.remoteAddress, fillPercentage * 100,
                    bytes, self.maxOutboundQueueBytes);
  [[PDSMetrics sharedMetrics] recordWebSocketBackpressureWarning];
  [[PDSMetrics sharedMetrics] recordWebSocketBackpressureStateChange:YES];
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(webSocketConnection:didReachBackpressureWarning:queueBytes:)]) {
      [self.delegate webSocketConnection:self
              didReachBackpressureWarning:fillPercentage
                               queueBytes:bytes];
    }
  });
}

- (void)notifyBackpressureCritical:(double)fillPercentage bytes:(NSUInteger)bytes {
  PDS_LOG_SYNC_WARN(@"[%@] WebSocket backpressure critical: queue %.1f%% full (%lu/%lu bytes)",
                    self.remoteAddress, fillPercentage * 100,
                    bytes, self.maxOutboundQueueBytes);
  [[PDSMetrics sharedMetrics] recordWebSocketBackpressureCritical];
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(webSocketConnection:didReachBackpressureCritical:queueBytes:)]) {
      [self.delegate webSocketConnection:self
               didReachBackpressureCritical:fillPercentage
                                queueBytes:bytes];
    }
  });
}

- (void)notifyBackpressureCleared {
  PDS_LOG_SYNC_INFO(@"[%@] WebSocket backpressure cleared: queue now %.1f%% full (%lu/%lu bytes)",
                    self.remoteAddress, (double)self.queuedSendBytes / (double)self.maxOutboundQueueBytes * 100,
                    self.queuedSendBytes, self.maxOutboundQueueBytes);
  [[PDSMetrics sharedMetrics] recordWebSocketBackpressureStateChange:NO];
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(webSocketConnectionDidClearBackpressure:)]) {
      [self.delegate webSocketConnectionDidClearBackpressure:self];
    }
  });
}

- (void)notifyQueueOverflow:(NSUInteger)bytes {
  PDS_LOG_SYNC_ERROR(@"[%@] WebSocket queue overflow: %lu bytes exceeds limit %lu, closing connection",
                     self.remoteAddress, bytes, self.maxOutboundQueueBytes);
  [[PDSMetrics sharedMetrics] recordWebSocketQueueOverflowClosure];
  if (self.isUnderBackpressure) {
    [[PDSMetrics sharedMetrics] recordWebSocketBackpressureStateChange:NO];
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(webSocketConnection:willCloseForQueueOverflow:limit:)]) {
      [self.delegate webSocketConnection:self
         willCloseForQueueOverflow:bytes
                              limit:self.maxOutboundQueueBytes];
    }
  });
}

@end
