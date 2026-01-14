#import "Sync/WebSocketConnection.h"
#import "Network/PDSNetworkTransport.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const WebSocketConnectionErrorDomain = @"com.atproto.pds.websocket.connection";
NSInteger const WebSocketConnectionErrorCodeConnectionClosed = 2000;
NSInteger const WebSocketConnectionErrorCodeInvalidFrame = 2001;
NSInteger const WebSocketConnectionErrorCodeWriteFailed = 2002;

static const uint8_t WS_OPCODE_CONTINUE = 0x0;
static const uint8_t WS_OPCODE_TEXT = 0x1;
static const uint8_t WS_OPCODE_BINARY = 0x2;
static const uint8_t WS_OPCODE_CLOSE = 0x8;
static const uint8_t WS_OPCODE_PING = 0x9;
static const uint8_t WS_OPCODE_PONG = 0xA;
static const uint8_t WS_FLAG_FIN = 0x80;
static const uint8_t WS_MASK = 0x80;
static const uint64_t WS_MAX_FRAME_SIZE = 16 * 1024 * 1024;

@interface WebSocketConnection ()

@property (nonatomic, assign, readwrite) WebSocketConnectionState state;
@property (nonatomic, copy, readwrite) NSString *queryString;
@property (nonatomic, copy, readwrite, nullable) NSDictionary<NSString *, NSString *> *queryParams;

@property (nonatomic, strong) id<PDSNetworkConnection> connection;
@property (nonatomic, strong) dispatch_queue_t connectionQueue;
@property (nonatomic, strong) NSMutableData *readBuffer;
@property (nonatomic, strong) NSMutableData *writeBuffer;
@property (nonatomic, strong) dispatch_queue_t writeQueue;
@property (nonatomic, strong) NSMutableArray<NSData *> *messageQueue;
@property (nonatomic, strong, nullable) NSTimer *heartbeatTimer;
@property (nonatomic, strong, nullable) NSTimer *heartbeatTimeoutTimer;
@property (nonatomic, assign) BOOL waitingForPong;

@end

@implementation WebSocketConnection

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port path:(NSString *)path {
    self = [super init];
    if (self) {
        [self commonInit];
        _host = [host copy];
        _port = port;
        _path = [path copy];
        _state = WebSocketConnectionStateConnecting;

        NSRange queryRange = [path rangeOfString:@"?"];
        if (queryRange.location != NSNotFound) {
            _queryString = [path substringFromIndex:queryRange.location + 1];
            _queryParams = [self parseQueryParams:_queryString];
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
        _host = [connection remoteAddress] ?: @"unknown";
        _path = @"/";
        _queryString = @"";
    }
    return self;
}

- (void)commonInit {
    _identifier = [NSUUID UUID];
    _heartbeatInterval = 30.0;
    _heartbeatTimeout = 10.0;
    _readBuffer = [NSMutableData data];
    _messageQueue = [NSMutableArray array];
    _writeQueue = dispatch_queue_create("com.atproto.pds.websocket.write", DISPATCH_QUEUE_SERIAL);
    _connectionQueue = dispatch_queue_create("com.atproto.pds.websocket.connection", DISPATCH_QUEUE_SERIAL);
    _waitingForPong = NO;
}

- (void)start {
    __weak typeof(self) weakSelf = self;
    self.connection.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError * _Nullable error) {
        [weakSelf handlePDSStateChange:state error:error];
    };
    
    [self.connection startWithQueue:self.connectionQueue];
    [self startReading];
    [self startHeartbeat];
}

- (instancetype)init {
    return [self initWithHost:@"localhost" port:0 path:@"/"];
}

- (NSDictionary<NSString *, NSString *> *)parseQueryParams:(NSString *)queryString {
    if (queryString.length == 0) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    NSArray<NSString *> *pairs = [queryString componentsSeparatedByString:@"&"];

    for (NSString *pair in pairs) {
        NSArray<NSString *> *keyValue = [pair componentsSeparatedByString:@"="];
        if (keyValue.count == 2) {
            NSString *key = [keyValue[0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSString *value = [keyValue[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            if (key && value) {
                params[key] = value;
            }
        }
    }

    return params.count > 0 ? [params copy] : nil;
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
            *error = [NSError errorWithDomain:WebSocketConnectionErrorDomain
                                         code:WebSocketConnectionErrorCodeConnectionClosed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Connection is not in connecting state"}];
        }
        return NO;
    }

    self.connectionQueue = dispatch_queue_create("com.atproto.pds.websocket.connection", DISPATCH_QUEUE_SERIAL);

    self.connection = [PDSNetworkTransportFactory createConnectionWithHost:self.host port:self.port];

    [self setupInitialState];

    __weak typeof(self) weakSelf = self;
    self.connection.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError * _Nullable error) {
        [weakSelf handlePDSStateChange:state error:error];
    };

    [self.connection startWithQueue:self.connectionQueue];

    return YES;
}

- (void)setupInitialState {
}

- (void)handlePDSStateChange:(PDSNetworkConnectionState)state error:(NSError * _Nullable)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (state) {
            case PDSNetworkConnectionStateReady:
                self.state = WebSocketConnectionStateConnected;
                [self startReading];
                [self startHeartbeat];
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
                    [self notifyError:[NSError errorWithDomain:WebSocketConnectionErrorDomain
                                                           code:WebSocketConnectionErrorCodeConnectionClosed
                                                       userInfo:@{NSLocalizedDescriptionKey: @"Connection failed"}]];
                }
                break;

            default:
                break;
        }
    });
}

- (void)startReading {
    __weak typeof(self) weakSelf = self;
    [self.connection receiveWithMinimumLength:1 maximumLength:UINT32_MAX completion:^(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf handleReceivedData:data];
            });
        }

        if (!error) {
            [strongSelf startReading];
        }
    }];
}

- (void)handleReceivedData:(NSData *)data {
    [self.readBuffer appendData:data];

    while (self.readBuffer.length >= 2) {
        NSUInteger offset = 0;
        const uint8_t *bytes = self.readBuffer.bytes;
        uint8_t firstByte = bytes[0];
        uint8_t secondByte = bytes[1];

        BOOL fin = (firstByte & WS_FLAG_FIN) != 0;
        uint8_t opcode = firstByte & 0x0F;
        BOOL masked = (secondByte & WS_MASK) != 0;
        uint64_t payloadLength = secondByte & 0x7F;

        if (payloadLength == 126) {
            if (self.readBuffer.length < 4) return;
            payloadLength = (uint64_t)bytes[2] << 8 | bytes[3];
            offset += 2;
        } else if (payloadLength == 127) {
            if (self.readBuffer.length < 10) return;
            payloadLength = 0;
            for (int i = 0; i < 8; i++) {
                payloadLength = (payloadLength << 8) | bytes[2 + i];
            }
            offset += 8;
        }

        if (payloadLength > WS_MAX_FRAME_SIZE) {
            [self closeWithCode:1009 reason:@"Frame too large"];
            return;
        }

        NSUInteger headerLength = 2;
        if (masked) {
            headerLength += 4;
        }

        if (self.readBuffer.length < headerLength + payloadLength) {
            return;
        }

        NSMutableData *payload = [NSMutableData dataWithCapacity:payloadLength];
        NSUInteger dataOffset = headerLength;
        if (masked) {
            const uint8_t *maskBytes = bytes + 2;
            for (NSUInteger i = 0; i < payloadLength; i++) {
                uint8_t maskedByte = bytes[dataOffset + i];
                uint8_t unmaskedByte = maskedByte ^ maskBytes[i % 4];
                [payload appendBytes:&unmaskedByte length:1];
            }
        } else {
            [payload appendBytes:bytes + dataOffset length:payloadLength];
        }

        [self.readBuffer replaceBytesInRange:NSMakeRange(0, headerLength + payloadLength) withBytes:NULL length:0];

        [self handleFrameWithOpcode:opcode fin:fin payload:payload];

        if (!fin) {
            return;
        }
    }
}

- (void)handleFrameWithOpcode:(uint8_t)opcode fin:(BOOL)fin payload:(NSData *)payload {
    switch (opcode) {
        case WS_OPCODE_TEXT:
            [self notifyTextMessage:[[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding]];
            break;

        case WS_OPCODE_BINARY:
            [self notifyBinaryMessage:payload];
            break;

        case WS_OPCODE_CLOSE:
            [self handleCloseFrame:payload];
            break;

        case WS_OPCODE_PING:
            [self handlePingFrame:payload];
            break;

        case WS_OPCODE_PONG:
            [self handlePongFrame:payload];
            break;

        default:
            break;
    }
}

- (void)handleCloseFrame:(NSData *)payload {
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
            reason = [[NSString alloc] initWithData:[payload subdataWithRange:NSMakeRange(2, reasonLength)] encoding:NSUTF8StringEncoding];
        }
    }

    [self closeWithCode:code reason:reason];
}

- (void)handlePingFrame:(NSData *)payload {
    [self sendPong:payload];
}

- (void)handlePongFrame:(NSData *)payload {
    [self stopHeartbeatTimeout];
    self.waitingForPong = NO;
}

- (void)close {
    [self closeWithCode:1000 reason:@"Normal closure"];
}

- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
    if (self.state == WebSocketConnectionStateClosing || self.state == WebSocketConnectionStateClosed) {
        return;
    }

    self.state = WebSocketConnectionStateClosing;
    self.closeCode = code;
    self.closeReason = reason;

    NSMutableData *closeData = [NSMutableData dataWithCapacity:2 + reason.length];
    uint8_t codeBytes[2] = { (uint8_t)((code >> 8) & 0xFF), (uint8_t)(code & 0xFF) };
    [closeData appendBytes:codeBytes length:2];
    if (reason.length > 0) {
        [closeData appendData:[reason dataUsingEncoding:NSUTF8StringEncoding]];
    }

    NSData *frame = [self createFrameWithOpcode:WS_OPCODE_CLOSE payload:closeData];
    [self writeData:frame];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.state != WebSocketConnectionStateClosed) {
            self.state = WebSocketConnectionStateClosed;
            [self notifyCloseWithCode:code reason:reason];
        }
    });
}

- (void)sendMessage:(NSData *)data {
    [self sendFrame:[self createFrameWithOpcode:WS_OPCODE_BINARY payload:data]];
}

- (void)sendText:(NSString *)text {
    NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
    [self sendFrame:[self createFrameWithOpcode:WS_OPCODE_TEXT payload:textData]];
}

- (void)sendPing:(NSData *)payload {
    [self sendFrame:[self createFrameWithOpcode:WS_OPCODE_PING payload:payload ?: [NSData data]]];
}

- (void)sendPong:(NSData *)payload {
    [self sendFrame:[self createFrameWithOpcode:WS_OPCODE_PONG payload:payload ?: [NSData data]]];
}

- (void)sendFrame:(NSData *)frame {
    dispatch_async(self.writeQueue, ^{
        [self.messageQueue addObject:frame];
        if (self.messageQueue.count == 1) {
            [self flushWriteBuffer];
        }
    });
}

- (void)flushWriteBuffer {
    if (self.messageQueue.count == 0) return;

    NSData *message = self.messageQueue.firstObject;
    [self writeData:message];
}

- (void)writeData:(NSData *)data {
    __weak typeof(self) weakSelf = self;
    [self.connection sendData:data completion:^(NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        dispatch_async(strongSelf.writeQueue, ^{
            if (strongSelf.messageQueue.count > 0) {
                [strongSelf.messageQueue removeObjectAtIndex:0];
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
        uint8_t lengthBytes[2] = { (uint8_t)((length >> 8) & 0xFF), (uint8_t)(length & 0xFF) };
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

- (void)startHeartbeat {
    [self stopHeartbeat];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:self.heartbeatInterval
                                                            target:self
                                                          selector:@selector(sendHeartbeat)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)stopHeartbeat {
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = nil;
}

- (void)sendHeartbeat {
    if (self.waitingForPong) {
        [self closeWithCode:1001 reason:@"Heartbeat timeout"];
        return;
    }

    self.waitingForPong = YES;
    [self sendPing:nil];

    self.heartbeatTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:self.heartbeatTimeout
                                                                   target:self
                                                                 selector:@selector(handleHeartbeatTimeout)
                                                                 userInfo:nil
                                                                  repeats:NO];
}

- (void)stopHeartbeatTimeout {
    [self.heartbeatTimeoutTimer invalidate];
    self.heartbeatTimeoutTimer = nil;
}

- (void)handleHeartbeatTimeout {
    [self closeWithCode:1001 reason:@"Heartbeat timeout"];
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
        [self.delegate webSocketConnection:self didCloseWithCode:code reason:reason];
    });
}

- (void)notifyError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate webSocketConnection:self didFailWithError:error];
    });
}

@end
