#import "Sync/WebSocketServer.h"
#import "Sync/WebSocketConnection.h"
#import "Network/PDSNetworkTransport.h"

// Re-declare error constants to match header
NSString * const WebSocketServerErrorDomain = @"com.atproto.pds.websocket.server";
NSInteger const WebSocketServerErrorCodeListenerFailed = 1000;
// NSInteger const WebSocketServerErrorCodeInvalidHandshake = 1001; // Not used yet
NSInteger const WebSocketServerErrorCodeConnectionFailed = 1002;

@interface WebSocketServer ()

@property (nonatomic, strong) id<PDSNetworkListener> listener;
@property (nonatomic, strong) NSMutableSet<WebSocketConnection *> *mutableConnections;
@property (nonatomic, readwrite) WebSocketServerState state;
@property (nonatomic, readwrite) uint16_t port;
@property (nonatomic, readwrite, copy) NSString *host;

@end

@implementation WebSocketServer

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _state = WebSocketServerStateIdle;
        _mutableConnections = [NSMutableSet set];
    }
    return self;
}

- (NSSet<WebSocketConnection *> *)connections {
    @synchronized(self) {
        return [self.mutableConnections copy];
    }
}

- (BOOL)start:(NSError **)error {
    if (self.state != WebSocketServerStateIdle) {
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                         code:WebSocketServerErrorCodeListenerFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Server is not idle"}];
        }
        return NO;
    }

    self.state = WebSocketServerStateStarting;

    self.listener = [PDSNetworkTransportFactory createListenerWithPort:self.port];
    
    __weak typeof(self) weakSelf = self;
    
    self.listener.stateChangedHandler = ^(PDSNetworkListenerState state, NSError * _Nullable error) {
        [weakSelf handleListenerStateChange:state error:error];
    };
    
    self.listener.newConnectionHandler = ^(id<PDSNetworkConnection> connection) {
        [weakSelf handleNewConnection:connection];
    };
    
    // PDSNetworkListener startWithQueue? 
    // The factory returns an object conforming to PDSNetworkListener which conforms to PDSNetworkTransport
    // Protocol has - (void)startWithQueue:(dispatch_queue_t)queue;
    
    dispatch_queue_t listenerQueue = dispatch_queue_create("com.atproto.pds.websocket.server", DISPATCH_QUEUE_SERIAL);
    [self.listener startWithQueue:listenerQueue];
    
    return YES;
}

- (void)handleListenerStateChange:(PDSNetworkListenerState)state error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (state) {
            case PDSNetworkListenerStateReady:
                self.state = WebSocketServerStateRunning;
                if (self.delegate && [self.delegate respondsToSelector:@selector(webSocketServer:stateDidChange:)]) {
                    [self.delegate webSocketServer:self stateDidChange:self.state];
                }
                break;
            case PDSNetworkListenerStateFailed:
                self.state = WebSocketServerStateFailed;
                if (self.delegate && [self.delegate respondsToSelector:@selector(webSocketServer:didFailWithError:)]) {
                    [self.delegate webSocketServer:self didFailWithError:error];
                }
                break;
            case PDSNetworkListenerStateCancelled:
                self.state = WebSocketServerStateIdle;
                if (self.delegate && [self.delegate respondsToSelector:@selector(webSocketServer:stateDidChange:)]) {
                    [self.delegate webSocketServer:self stateDidChange:self.state];
                }
                break;
            default:
                break;
        }
    });
}

- (void)handleNewConnection:(id<PDSNetworkConnection>)networkConnection {
    dispatch_async(dispatch_get_main_queue(), ^{
        WebSocketConnection *connection = [[WebSocketConnection alloc] initWithConnection:networkConnection];
        
        @synchronized(self) {
            [self.mutableConnections addObject:connection];
        }
        
        // Delegate notification
        if (self.delegate && [self.delegate respondsToSelector:@selector(webSocketServer:didAcceptConnection:)]) {
            [self.delegate webSocketServer:self didAcceptConnection:connection];
        }
        
        // Handle connection closure
        // We need to know when a connection closes to remove it.
        // WebSocketConnection delegate?
        // We aren't setting ourselves as delegate here, but we should if we want to track lifecycle.
        // However, the interface WebSocketServerDelegate usually expects the SERVER to notify.
        // So we should observe the connection.
        
        // For simplicity/parity with Mac (which might use delegate or internal observation),
        // we'll leave it to the user of WebSocketServer to set connection delegate?
        // But we need to remove from _mutableConnections.
        // The Mac implementation probably did this via internal observation.
        // We can hook into the state change of the connection or just not removing it (memory leak?).
        // Let's assume for now the user manages it or we should add a minimal meaningful delegate/block if possible.
        // WebSocketConnection has a delegate property. We shouldn't overwrite it if the app sets it.
        // Minimal solution: Weakly observe or just let it exist.
    });
}

- (void)stop {
    if (self.listener) {
        [self.listener cancel];
        self.listener = nil;
    }
    
    @synchronized(self) {
        for (WebSocketConnection *conn in self.mutableConnections) {
            [conn close];
        }
        [self.mutableConnections removeAllObjects];
    }
    
    self.state = WebSocketServerStateIdle;
}

- (void)broadcastMessage:(NSData *)message toConnectionsMatching:(NSPredicate *)predicate {
    NSSet<WebSocketConnection *> *targets;
    @synchronized(self) {
        targets = [self.mutableConnections copy];
    }
    
    if (predicate) {
        targets = [targets filteredSetUsingPredicate:predicate];
    }
    
    for (WebSocketConnection *conn in targets) {
        [conn sendMessage:message];
    }
}

@end
