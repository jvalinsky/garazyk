#import "Sync/WebSocket/WebSocketConnection.h"
#import "Compat/PDSTypes.h"
#import "Network/PDSNetworkTransport.h"
#import "Network/HttpParsing.h"
#import "Sync/WebSocket/WebSocketProtocolSession.h"
#import "Debug/PDSLogger.h"
#import "Metrics/PDSMetrics.h"
#import <CommonCrypto/CommonDigest.h>

static const NSUInteger WS_DEFAULT_MAX_QUEUE_BYTES = 10 * 1024 * 1024; // 10MB default

NSString *const WebSocketConnectionErrorDomain =
    @"com.atproto.pds.websocket.error";

NSInteger const WebSocketConnectionErrorCodeConnectionClosed = 2000;
NSInteger const WebSocketConnectionErrorCodeInvalidFrame = 2001;
NSInteger const WebSocketConnectionErrorCodeWriteFailed = 2002;

@interface WebSocketConnection () {
    NSString *_handshakeKey;
    BOOL _waitingForHandshakeResponse;
    BOOL _isReading;
}

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

@property(nonatomic, strong) WebSocketProtocolSession *session;

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
  _session = [[WebSocketProtocolSession alloc] init];
}

- (NSTimeInterval)heartbeatInterval {
  return self.session.heartbeatPolicy.heartbeatInterval;
}

- (void)setHeartbeatInterval:(NSTimeInterval)interval {
  self.session.heartbeatPolicy.heartbeatInterval = interval;
}

- (NSTimeInterval)heartbeatTimeout {
  return self.session.heartbeatPolicy.heartbeatTimeout;
}

- (void)setHeartbeatTimeout:(NSTimeInterval)timeout {
  self.session.heartbeatPolicy.heartbeatTimeout = timeout;
}

- (NSUInteger)maxOutboundQueueBytes {
  return self.session.maxOutboundQueueBytes;
}

- (void)setMaxOutboundQueueBytes:(NSUInteger)bytes {
  self.session.maxOutboundQueueBytes = bytes;
}

- (double)backpressureWarningThreshold {
  return self.session.backpressureWarningThreshold;
}

- (void)setBackpressureWarningThreshold:(double)threshold {
  self.session.backpressureWarningThreshold = threshold;
}

- (double)backpressureCriticalThreshold {
  return self.session.backpressureCriticalThreshold;
}

- (void)setBackpressureCriticalThreshold:(double)threshold {
  self.session.backpressureCriticalThreshold = threshold;
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

- (WebSocketHeartbeatPolicy *)heartbeatPolicy {
  return self.session.heartbeatPolicy;
}

- (void)waitForWriteQueue:(void (^)(void))completion {
    dispatch_async(self.writeQueue, completion);
}

- (void)handlePDSStateChange:(PDSNetworkConnectionState)state
                       error:(NSError *)error {

  PDS_LOG_SYNC_DEBUG(@"WebSocket connection %p state change: %ld", self, (long)state);
  dispatch_async(dispatch_get_main_queue(), ^{
    switch (state) {
    case PDSNetworkConnectionStateReady: {
      if (self.host && self.path) {
          [self sendHandshake];
      } else {
          self.state = WebSocketConnectionStateConnected;
          [self startReading];
          [self startHeartbeat];
          if ([self.delegate respondsToSelector:@selector(webSocketConnectionStateDidChange:)]) {
            [self.delegate webSocketConnectionStateDidChange:self];
          }
      }
      break;
    }

    case PDSNetworkConnectionStateWaiting:
      PDS_LOG_SYNC_DEBUG(@"WebSocket connection %p is waiting for network availability: %@", self, error.localizedDescription ?: @"no error");
      break;

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
  if (_isReading) return;
  _isReading = YES;

  __weak typeof(self) weakSelf = self;
  [self.connection
      receiveWithMinimumLength:1
                 maximumLength:UINT32_MAX
                    completion:^(NSData *_Nullable data, BOOL isComplete,
                                 NSError *_Nullable error) {
                      __strong typeof(weakSelf) strongSelf = weakSelf;
                      if (!strongSelf)
                        return;

                      strongSelf->_isReading = NO;

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

- (void)sendHandshake {
    uint8_t randomBytes[16];
    arc4random_buf(randomBytes, 16);
    NSData *keyData = [NSData dataWithBytes:randomBytes length:16];
    NSString *key = [keyData base64EncodedStringWithOptions:0];
    _handshakeKey = key;
    
    NSMutableString *handshake = [NSMutableString string];
    [handshake appendFormat:@"GET %@ HTTP/1.1\r\n", self.path];
    [handshake appendFormat:@"Host: %@:%u\r\n", self.host, self.port];
    [handshake appendString:@"Upgrade: websocket\r\n"];
    [handshake appendString:@"Connection: Upgrade\r\n"];
    [handshake appendFormat:@"Sec-WebSocket-Key: %@\r\n", key];
    [handshake appendString:@"Sec-WebSocket-Version: 13\r\n"];
    if (self.subprotocol) {
        [handshake appendFormat:@"Sec-WebSocket-Protocol: %@\r\n", self.subprotocol];
    }
    [handshake appendString:@"\r\n"];
    
    PDS_LOG_SYNC_DEBUG(@"WebSocket: Sending handshake to %@:%u", self.host, self.port);
    
    NSData *data = [handshake dataUsingEncoding:NSUTF8StringEncoding];
    [self writeData:data];
    
    // We expect a 101 response next.
    // For simplicity, we'll reuse handleReceivedData but we need to know we're waiting for a handshake.
    _waitingForHandshakeResponse = YES;
    [self startReading];
}

- (void)handleReceivedData:(NSData *)data {
    if (_waitingForHandshakeResponse) {
        [self handleHandshakeResponse:data];
        return;
    }
    
    PDS_LOG_SYNC_DEBUG(@"WebSocket received %lu bytes from wire", (unsigned long)data.length);
    NSArray<WSSessionAction *> *actions = [self.session
      feedData:data
      receivedAt:[[NSDate date] timeIntervalSince1970]];
    for (WSSessionAction *action in actions) {
        [self processAction:action];
    }
}

- (NSString *)computeAcceptKey:(NSString *)clientKey {
    static NSString * const GUID = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    NSString *input = [clientKey stringByAppendingString:GUID];
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, hash);
    
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA1_DIGEST_LENGTH];
    return [hashData base64EncodedStringWithOptions:0];
}

- (void)handleHandshakeResponse:(NSData *)data {
    // Very basic 101 parser
    NSString *resp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([resp hasPrefix:@"HTTP/1.1 101"] || [resp hasPrefix:@"HTTP/1.0 101"]) {
        // Verify Sec-WebSocket-Accept (M10)
        NSString *expectedAccept = [self computeAcceptKey:_handshakeKey];
        NSString *headerSearch = [NSString stringWithFormat:@"Sec-WebSocket-Accept: %@", expectedAccept];
        
        // Use a more robust check for the header (case-insensitive and handling different line endings)
        BOOL acceptMatched = NO;
        NSArray *lines = [resp componentsSeparatedByString:@"\r\n"];
        for (NSString *line in lines) {
            if ([line.lowercaseString hasPrefix:@"sec-websocket-accept:"]) {
                NSString *value = [[line substringFromIndex:21] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([value isEqualToString:expectedAccept]) {
                    acceptMatched = YES;
                    break;
                }
            }
        }
        
        if (!acceptMatched) {
            PDS_LOG_SYNC_ERROR(@"WebSocket: Handshake failed - Invalid Sec-WebSocket-Accept header");
            [self notifyError:[NSError errorWithDomain:WebSocketConnectionErrorDomain 
                                                  code:WebSocketConnectionErrorCodeConnectionClosed 
                                              userInfo:@{NSLocalizedDescriptionKey: @"WebSocket handshake failed: Invalid Accept key"}]];
            [self close];
            return;
        }

        PDS_LOG_SYNC_INFO(@"WebSocket: Handshake successful");
        _waitingForHandshakeResponse = NO;
        self.state = WebSocketConnectionStateConnected;
        [self startHeartbeat];
        if ([self.delegate respondsToSelector:@selector(webSocketConnectionStateDidChange:)]) {
            [self.delegate webSocketConnectionStateDidChange:self];
        }
        
        // If there was extra data after headers, feed it to session
        NSRange range = [resp rangeOfString:@"\r\n\r\n"];
        if (range.location != NSNotFound) {
            NSUInteger headerLen = range.location + 4;
            if (data.length > headerLen) {
                NSData *remaining = [data subdataWithRange:NSMakeRange(headerLen, data.length - headerLen)];
                [self handleReceivedData:remaining];
            }
        }
    } else {
        PDS_LOG_SYNC_ERROR(@"WebSocket: Handshake failed: %@", resp);
        [self notifyError:[NSError errorWithDomain:WebSocketConnectionErrorDomain 
                                              code:WebSocketConnectionErrorCodeConnectionClosed 
                                          userInfo:@{NSLocalizedDescriptionKey: @"WebSocket handshake failed"}]];
        [self close];
    }
}

- (void)processAction:(WSSessionAction *)action {
  switch (action.type) {
    case WSSessionActionTypeNotifyTextMessage:
      [self notifyTextMessage:(NSString *)action.data];
      break;
    case WSSessionActionTypeNotifyBinaryMessage:
      [self notifyBinaryMessage:(NSData *)action.data];
      break;
    case WSSessionActionTypeHandlePing:
      [self handlePingFrame:(NSData *)action.data];
      break;
    case WSSessionActionTypeHandlePong:
      [self handlePongFrame:(NSData *)action.data];
      break;
    case WSSessionActionTypeClose: {
      WSCodecEvent *event = (WSCodecEvent *)action.data;
      BOOL ackingOurClose = (self.state == WebSocketConnectionStateClosing);
      [self closeWithCode:event.closeCode reason:event.closeReason];
      if (ackingOurClose && self.state != WebSocketConnectionStateClosed) {
        self.state = WebSocketConnectionStateClosed;
        if (self.connection) {
          [self.connection cancel];
        }
        [self notifyCloseWithCode:event.closeCode reason:event.closeReason];
      }
      break;
    }
    case WSSessionActionTypeSendPing:
      [self sendPing:nil];
      break;
    case WSSessionActionTypeHeartbeatTimeout:
      [self closeWithCode:1001 reason:@"Heartbeat timeout"];
      break;
    case WSSessionActionTypeBackpressureWarning:
      [self notifyBackpressureWarning:[(NSNumber *)action.data doubleValue] bytes:self.queuedSendBytes];
      break;
    case WSSessionActionTypeBackpressureCritical:
      [self notifyBackpressureCritical:[(NSNumber *)action.data doubleValue] bytes:self.queuedSendBytes];
      break;
    case WSSessionActionTypeBackpressureCleared:
      [self notifyBackpressureCleared];
      break;
  }
}

- (void)handlePingFrame:(NSData *)payload {
  [self sendPong:payload];
}

- (void)handlePongFrame:(NSData *)payload {
  [self.heartbeatPolicy pongReceived:[[NSDate date] timeIntervalSince1970]];
}

- (void)close {
  [self closeWithCode:1000 reason:@"Normal closure"];
}

- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
  dispatch_async(self.writeQueue, ^{
    if (self.state == WebSocketConnectionStateClosing ||
        self.state == WebSocketConnectionStateClosed) {
      return;
    }

    self.state = WebSocketConnectionStateClosing;
    self.closeCode = code;
    self.closeReason = reason;

    [self.messageQueue removeAllObjects];
    self.queuedSendBytes = 0;

    NSData *frame = [self.session.codec closeFrame:code reason:reason];
    [self writeData:frame];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (self.state != WebSocketConnectionStateClosed) {
                       self.state = WebSocketConnectionStateClosed;
                       if (self.connection) {
                         [self.connection cancel];
                       }
                       [self notifyCloseWithCode:code reason:reason];
                     }
                   });
  });
}

- (void)sendMessage:(NSData *)data {
  [self sendFrame:[self.session.codec binaryFrame:data]];
}

- (void)sendText:(NSString *)text {
  [self sendFrame:[self.session.codec textFrame:text]];
}

- (void)sendPing:(NSData *)payload {
  [self sendFrame:[self.session.codec pingFrame:payload]];
}

- (void)sendPong:(NSData *)payload {
  [self sendFrame:[self.session.codec pongFrame:payload]];
}

- (void)sendFrame:(NSData *)frame {
  dispatch_async(self.writeQueue, ^{
    if (self.state == WebSocketConnectionStateClosing ||
        self.state == WebSocketConnectionStateClosed) {
      return;
    }

    NSUInteger newQueueSize = self.queuedSendBytes + frame.length;
    NSArray<WSSessionAction *> *actions = [self.session didEnqueueFrameOfSize:frame.length
                                                           currentQueueSize:newQueueSize];
    
    // Check overflow
    if (newQueueSize > self.session.maxOutboundQueueBytes) {
      [self notifyQueueOverflow:newQueueSize];
      [self.messageQueue removeAllObjects];
      self.queuedSendBytes = 0;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self closeWithCode:1009 reason:@"Outbound queue limit exceeded"];
      });
      return;
    }

    for (WSSessionAction *action in actions) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self processAction:action];
      });
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

                   if (error) {
                     dispatch_async(dispatch_get_main_queue(), ^{
                       [strongSelf notifyError:error];
                      [strongSelf closeWithCode:1011 reason:@"WebSocket write failed"];
                     });
                    return;
                   }

                  dispatch_async(strongSelf.writeQueue, ^{
                    if (strongSelf.messageQueue.count > 0) {
                      NSData *sentFrame = strongSelf.messageQueue.firstObject;
                      [strongSelf.messageQueue removeObjectAtIndex:0];
                      if (sentFrame.length >= strongSelf.queuedSendBytes) {
                        strongSelf.queuedSendBytes = 0;
                      } else {
                        strongSelf.queuedSendBytes -= sentFrame.length;
                      }

                      NSArray<WSSessionAction *> *actions =
                          [strongSelf.session
                              didDequeueFrameOfSize:sentFrame.length
                                   currentQueueSize:strongSelf.queuedSendBytes];
                      for (WSSessionAction *action in actions) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                          [strongSelf processAction:action];
                        });
                      }
                    }

                    [strongSelf flushWriteBuffer];
                  });
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
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSArray<WSSessionAction *> *actions = [self.session tick:now];
  for (WSSessionAction *action in actions) {
    [self processAction:action];
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
  PDS_LOG_SYNC_WARN(@"[%@] WebSocket backpressure warning: queue %.1f%% full (%lu/%lu bytes)",
                    self.remoteAddress, fillPercentage * 100,
                    bytes, self.session.maxOutboundQueueBytes);
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
                    bytes, self.session.maxOutboundQueueBytes);
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
                    self.remoteAddress, (double)self.queuedSendBytes / (double)self.session.maxOutboundQueueBytes * 100,
                    self.queuedSendBytes, self.session.maxOutboundQueueBytes);
  [[PDSMetrics sharedMetrics] recordWebSocketBackpressureStateChange:NO];
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(webSocketConnectionDidClearBackpressure:)]) {
      [self.delegate webSocketConnectionDidClearBackpressure:self];
    }
  });
}

- (void)notifyQueueOverflow:(NSUInteger)bytes {
  PDS_LOG_SYNC_ERROR(@"[%@] WebSocket queue overflow: %lu bytes exceeds limit %lu, closing connection",
                     self.remoteAddress, bytes, self.session.maxOutboundQueueBytes);
  [[PDSMetrics sharedMetrics] recordWebSocketQueueOverflowClosure];
  [[PDSMetrics sharedMetrics] recordWebSocketBackpressureStateChange:NO];
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(webSocketConnection:willCloseForQueueOverflow:limit:)]) {
      [self.delegate webSocketConnection:self
          willCloseForQueueOverflow:bytes
                               limit:self.session.maxOutboundQueueBytes];
    }
  });
}

@end


