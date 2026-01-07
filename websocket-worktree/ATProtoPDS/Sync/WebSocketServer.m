#import "WebSocketServer.h"
#import "WebSocketConnection.h"
#import <Network/Network.h>

NSString * const WebSocketServerErrorDomain = @"com.atproto.pds.websocket.server";
NSInteger const WebSocketServerErrorCodeListenerFailed = 1000;
NSInteger const WebSocketServerErrorCodeInvalidHandshake = 1001;
NSInteger const WebSocketServerErrorCodeConnectionFailed = 1002;

static const uint8_t WS_OPCODE_CONTINUE = 0x0;
static const uint8_t WS_OPCODE_TEXT = 0x1;
static const uint8_t WS_OPCODE_BINARY = 0x2;
static const uint8_t WS_OPCODE_CLOSE = 0x8;
static const uint8_t WS_OPCODE_PING = 0x9;
static const uint8_t WS_OPCODE_PONG = 0xA;

@interface WebSocketServer ()

@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign) WebSocketServerState state;
@property (nonatomic, weak, nullable) id<WebSocketServerDelegate> delegate;
@property (nonatomic, strong) NSMutableSet<WebSocketConnection *> *mutableConnections;
@property (nonatomic, copy, nullable) NSString *subprotocol;
@property (nonatomic, strong) nw_listener_t listener;
@property (nonatomic, strong) dispatch_queue_t listenerQueue;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, WebSocketConnection *> *connectionsByFileDescriptor;

@end

@implementation WebSocketServer

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _state = WebSocketServerStateIdle;
        _mutableConnections = [NSMutableSet set];
        _connectionsByFileDescriptor = [NSMutableDictionary dictionary];
        _listenerQueue = dispatch_queue_create("com.atproto.pds.websocket.listener", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSSet<WebSocketConnection *> *)connections {
    return [self.mutableConnections copy];
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

    nw_parameters_t parameters = nw_parameters_create();
    nw_parameters_set_include_local_to_remote_host_name(parameters, false);

    nw_listener_t listener = nw_listener_create(parameters, NULL);
    if (!listener) {
        self.state = WebSocketServerStateFailed;
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                         code:WebSocketServerErrorCodeListenerFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create listener"}];
        }
        return NO;
    }

    nw_listener_set_queue(listener, self.listenerQueue);

    nw_listener_state_t state = nw_listener_get_state(listener);
    if (state == nw_listener_state_failed) {
        self.state = WebSocketServerStateFailed;
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                         code:WebSocketServerErrorCodeListenerFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Listener state failed"}];
        }
        return NO;
    }

    self.listener = listener;
    self.state = WebSocketServerStateRunning;

    return YES;
}

- (void)stop {
    if (self.state == WebSocketServerStateIdle || self.state == WebSocketServerStateStopping) {
        return;
    }

    self.state = WebSocketServerStateStopping;

    for (WebSocketConnection *connection in [self.mutableConnections copy]) {
        [connection close];
    }

    [self.mutableConnections removeAllObjects];

    if (self.listener) {
        nw_listener_cancel(self.listener);
        self.listener = nil;
    }

    self.state = WebSocketServerStateIdle;
}

- (void)addConnection:(WebSocketConnection *)connection {
    [self.mutableConnections addObject:connection];
}

- (void)removeConnection:(WebSocketConnection *)connection {
    [self.mutableConnections removeObject:connection];
}

- (void)broadcastMessage:(NSData *)message toConnectionsMatching:(NSPredicate *)predicate {
    NSSet<WebSocketConnection *> *targets;
    if (predicate) {
        targets = [self.mutableConnections filteredSetUsingPredicate:predicate];
    } else {
        targets = [self.mutableConnections copy];
    }

    for (WebSocketConnection *connection in targets) {
        [connection sendMessage:message];
    }
}

- (void)setState:(WebSocketServerState)state {
    if (_state != state) {
        _state = state;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webSocketServer:self stateDidChange:state];
        });
    }
}

@end
