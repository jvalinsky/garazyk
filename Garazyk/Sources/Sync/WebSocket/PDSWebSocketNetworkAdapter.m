// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSWebSocketNetworkAdapter.m

 @abstract Implementation of PDSWebSocketNetworkAdapter.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSWebSocketNetworkAdapter.h"
#import "WebSocketCodec.h"
#import "Network/ATProtoNetworkTransport.h"
#import "Compat/PDSTypes.h"

@interface PDSWebSocketNetworkAdapter ()
@property (nonatomic, strong) id<ATProtoNetworkConnection> connection;
@property (nonatomic, strong) WebSocketCodec *codec;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t eventQueue;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL isClosed;
@end

@implementation PDSWebSocketNetworkAdapter {
    PDSWebSocketTransportMessageHandler _messageHandler;
    PDSWebSocketTransportCloseHandler _closeHandler;
    PDSWebSocketTransportErrorHandler _errorHandler;
}

- (PDSWebSocketTransportMessageHandler)messageHandler {
    return _messageHandler;
}

- (void)setMessageHandler:(PDSWebSocketTransportMessageHandler)messageHandler {
    _messageHandler = [messageHandler copy];
}

- (PDSWebSocketTransportCloseHandler)closeHandler {
    return _closeHandler;
}

- (void)setCloseHandler:(PDSWebSocketTransportCloseHandler)closeHandler {
    _closeHandler = [closeHandler copy];
}

- (PDSWebSocketTransportErrorHandler)errorHandler {
    return _errorHandler;
}

- (void)setErrorHandler:(PDSWebSocketTransportErrorHandler)errorHandler {
    _errorHandler = [errorHandler copy];
}

- (instancetype)initWithConnection:(id<ATProtoNetworkConnection>)connection {
    self = [super init];
    if (self) {
        _connection = connection;
        _codec = [[WebSocketCodec alloc] init];
        _eventQueue = dispatch_queue_create("com.pds.websocket.adapter", DISPATCH_QUEUE_SERIAL);
        _isRunning = NO;
        _isClosed = NO;
    }
    return self;
}

- (void)start {
    dispatch_async(_eventQueue, ^{
        if (self.isRunning) return;
        self.isRunning = YES;

        // Begin receiving frames from the network
        [self _receiveNextFrame];
    });
}

- (void)_receiveNextFrame {
    // Request at least 2 bytes (minimum frame header), max 64KB
    __weak typeof(self) weakSelf = self;
    [self.connection receiveWithMinimumLength:2
                                maximumLength:65536
                                   completion:^(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            dispatch_async(strongSelf.eventQueue, ^{
                if (strongSelf.errorHandler) {
                    strongSelf.errorHandler(error);
                }
            });
            return;
        }

        if (isComplete) {
            dispatch_async(strongSelf.eventQueue, ^{
                strongSelf.isClosed = YES;
                if (strongSelf.closeHandler) {
                    strongSelf.closeHandler(1006, @"");  // 1006 = abnormal closure
                }
            });
            return;
        }

        // Feed data to codec and process events
        dispatch_async(strongSelf.eventQueue, ^{
            NSArray<WSCodecEvent *> *events = [strongSelf.codec feedData:data];
            for (WSCodecEvent *event in events) {
                [strongSelf _handleCodecEvent:event];
            }

            // Continue receiving
            if (strongSelf.isRunning && !strongSelf.isClosed) {
                [strongSelf _receiveNextFrame];
            }
        });
    }];
}

- (void)_handleCodecEvent:(WSCodecEvent *)event {
    switch (event.type) {
        case WSCodecEventTextMessage:
        case WSCodecEventBinaryMessage:
            // Deliver application message
            if (self.messageHandler && event.payload) {
                self.messageHandler(event.payload);
            }
            break;

        case WSCodecEventPing:
            // Auto-respond with pong
            {
                NSData *pongFrame = [self.codec pongFrame:event.payload];
                [self.connection sendData:pongFrame completion:^(NSError * _Nullable error) {
                    if (error && self.errorHandler) {
                        self.errorHandler(error);
                    }
                }];
            }
            break;

        case WSCodecEventPong:
            // Silently ignore pongs (application layer doesn't care)
            break;

        case WSCodecEventClose:
            self.isClosed = YES;
            if (self.closeHandler) {
                self.closeHandler(event.closeCode, event.closeReason ?: @"");
            }
            break;

        case WSCodecEventProtocolError:
            if (self.errorHandler) {
                NSError *error = [NSError errorWithDomain:@"WebSocketCodec"
                                                     code:-1
                                                 userInfo:@{NSLocalizedDescriptionKey: @"WebSocket protocol error"}];
                self.errorHandler(error);
            }
            break;
    }
}

- (void)sendMessage:(NSData *)data completion:(void (^)(NSError * _Nullable))completion {
    dispatch_async(_eventQueue, ^{
        if (self.isClosed) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"WebSocket" code:-1
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Connection closed"}];
                completion(error);
            }
            return;
        }

        NSData *frameData = [self.codec binaryFrame:data];
        [self.connection sendData:frameData completion:completion];
    });
}

- (void)closeWithCode:(NSInteger)code reason:(nullable NSString *)reason completion:(void (^)(NSError * _Nullable))completion {
    dispatch_async(_eventQueue, ^{
        if (self.isClosed) {
            if (completion) {
                completion(nil);
            }
            return;
        }

        self.isClosed = YES;
        NSData *closeFrame = [self.codec closeFrame:code reason:reason];
        [self.connection sendData:closeFrame completion:completion];
    });
}

@end
