/*!
 @file PDSWebSocketServer.m

 @abstract Implementation of PDSWebSocketServer.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSWebSocketServer.h"
#import "PDSWebSocketNetworkAdapter.h"
#import "Network/PDSNetworkTransport.h"
#import "Compat/PDSTypes.h"

@interface PDSWebSocketServer ()
@property (nonatomic, strong, nullable) id<PDSNetworkListener> listener;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t eventQueue;
@property (nonatomic, assign) NSUInteger requestedPort;
@property (nonatomic, copy) PDSWebSocketListenerFactory listenerFactory;
@end

@implementation PDSWebSocketServer

- (instancetype)initWithPort:(NSUInteger)port {
    return [self initWithPort:port listenerFactory:^id<PDSNetworkListener> _Nullable(NSUInteger requestedPort) {
        return [PDSNetworkTransportFactory createListenerWithPort:requestedPort];
    }];
}

- (instancetype)initWithPort:(NSUInteger)port listenerFactory:(PDSWebSocketListenerFactory)listenerFactory {
    self = [super init];
    if (self) {
        _requestedPort = port;
        _listenerFactory = [listenerFactory copy];
        _eventQueue = dispatch_queue_create("com.pds.websocket.server", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSUInteger)port {
    __block NSUInteger result = 0;
    dispatch_sync(_eventQueue, ^{
        result = self.listener.port;
    });
    return result;
}

- (BOOL)startWithError:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;

    dispatch_sync(_eventQueue, ^{
        id<PDSNetworkListener> listener = self.listenerFactory ? self.listenerFactory(self.requestedPort) : nil;
        if (!listener) {
            blockError = [NSError errorWithDomain:@"PDSWebSocketServer"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create listener"}];
            return;
        }

        // Set up connection handler
        __weak typeof(self) weakSelf = self;
        listener.newConnectionHandler = ^(id<PDSNetworkConnection> connection) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            // Wrap the network connection in a WebSocket transport adapter
            PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:connection];
            [adapter start];

            // Invoke the connection handler
            dispatch_async(strongSelf.eventQueue, ^{
                if (strongSelf.connectionHandler) {
                    strongSelf.connectionHandler(adapter);
                }
            });
        };

        // Set up error handler
        listener.stateChangedHandler = ^(PDSNetworkListenerState state, NSError * _Nullable listenerError) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            if (state == PDSNetworkListenerStateFailed && listenerError && strongSelf.errorHandler) {
                dispatch_async(strongSelf.eventQueue, ^{
                    strongSelf.errorHandler(listenerError);
                });
            }
        };

        // Start the listener
        [listener startWithQueue:self.eventQueue];
        self.listener = listener;
        success = YES;
    });

    if (!success && error) {
        *error = blockError;
    }
    return success;
}

- (void)stop {
    dispatch_sync(_eventQueue, ^{
        if (self.listener) {
            [self.listener cancel];
            self.listener = nil;
        }
    });
}

- (void)delegateNewTransport:(id<PDSWebSocketTransport>)transport forPath:(NSString *)path {
    dispatch_async(_eventQueue, ^{
        if (self.connectionHandler) {
            self.connectionHandler(transport);
        }
    });
}

@end
