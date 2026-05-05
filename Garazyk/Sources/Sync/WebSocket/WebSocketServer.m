#import "Sync/WebSocket/WebSocketServer.h"
#ifdef __APPLE__
#import "Network/PDSNetworkTransportMac.h"
#endif
#import "Compat/PDSTypes.h"
#import "Sync/WebSocket/WebSocketConnection.h"

NSString *const WebSocketServerErrorDomain = @"com.atproto.pds.websocket.server";
NSInteger const WebSocketServerErrorCodeListenerFailed = 1000;
NSInteger const WebSocketServerErrorCodeInvalidHandshake = 1001;
NSInteger const WebSocketServerErrorCodeConnectionFailed = 1002;

#if defined(__linux__) || defined(__GNUstep__)
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <netdb.h>

static inline int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static inline int set_reuseaddr(int fd) {
    int opt = 1;
    return setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
}

@interface WebSocketServer () <WebSocketConnectionDelegate>
@property(nonatomic, readwrite) uint16_t port;
@property(nonatomic, readwrite) WebSocketServerState state;
@property(nonatomic, assign) int serverSocket;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_source_t acceptSource;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t listenerQueue;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t connectionsQueue;
@property(nonatomic, strong) NSMutableSet<WebSocketConnection *> *mutableConnections;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_semaphore_t stopSemaphore;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_group_t taskGroup;
@end

@implementation WebSocketServer

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _state = WebSocketServerStateIdle;
        _serverSocket = -1;
        _mutableConnections = [NSMutableSet set];
        _connectionsQueue = dispatch_queue_create(
            "com.atproto.pds.websocket.connections", DISPATCH_QUEUE_CONCURRENT);
        _listenerQueue = dispatch_queue_create("com.atproto.pds.websocket.listener",
                                            DISPATCH_QUEUE_SERIAL);
        _stopSemaphore = dispatch_semaphore_create(0);
        _taskGroup = dispatch_group_create();
    }
    return self;
}

- (NSSet<WebSocketConnection *> *)connections {
    __block NSSet<WebSocketConnection *> *snapshot;
    dispatch_sync(self.connectionsQueue, ^{
        snapshot = [self.mutableConnections copy];
    });
    return snapshot;
}

- (BOOL)start:(NSError **)error {
    if (self.state != WebSocketServerStateIdle) {
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                       code:WebSocketServerErrorCodeListenerFailed
                                   userInfo:@{NSLocalizedDescriptionKey : @"Server is not idle"}];
        }
        return NO;
    }

    self.state = WebSocketServerStateStarting;

    struct addrinfo hints, *res, *res0;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_PASSIVE;

    NSString *portStr = [NSString stringWithFormat:@"%hu", self.port];
    int gai_err = getaddrinfo(NULL, portStr.UTF8String, &hints, &res0);
    if (gai_err != 0) {
        self.state = WebSocketServerStateFailed;
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                       code:WebSocketServerErrorCodeListenerFailed
                                   userInfo:@{NSLocalizedDescriptionKey :
                                             [NSString stringWithFormat:@"getaddrinfo: %s", gai_err] }];
        }
        return NO;
    }

    int srvfd = -1;
    for (res = res0; res; res = res->ai_next) {
        srvfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (srvfd < 0) continue;

        set_reuseaddr(srvfd);
        set_nonblocking(srvfd);

        if (bind(srvfd, res->ai_addr, res->ai_addrlen) == 0) break;

        close(srvfd);
        srvfd = -1;
    }
    freeaddrinfo(res0);

    if (srvfd < 0) {
        self.state = WebSocketServerStateFailed;
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                       code:WebSocketServerErrorCodeListenerFailed
                                   userInfo:@{NSLocalizedDescriptionKey : @"Failed to bind socket"}];
        }
        return NO;
    }

    if (listen(srvfd, 512) < 0) {
        close(srvfd);
        self.state = WebSocketServerStateFailed;
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                       code:WebSocketServerErrorCodeListenerFailed
                                   userInfo:@{NSLocalizedDescriptionKey : @"Failed to listen"}];
        }
        return NO;
    }

    struct sockaddr_in sin;
    socklen_t sinlen = sizeof(sin);
    if (getsockname(srvfd, (struct sockaddr *)&sin, &sinlen) == 0) {
        self.port = ntohs(sin.sin_port);
    }

    self.serverSocket = srvfd;
    self.state = WebSocketServerStateRunning;

    return YES;
}

- (void)stop {
    if (self.state == WebSocketServerStateIdle || self.state == WebSocketServerStateStopping) {
        return;
    }

    self.state = WebSocketServerStateStopping;

    __block NSSet<WebSocketConnection *> *connectionsSnapshot = nil;
    dispatch_barrier_sync(self.connectionsQueue, ^{
        connectionsSnapshot = [self.mutableConnections copy];
        [self.mutableConnections removeAllObjects];
    });

    for (WebSocketConnection *connection in connectionsSnapshot) {
        [connection close];
    }

    if (self.serverSocket >= 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
    }

    dispatch_group_wait(self.taskGroup, DISPATCH_TIME_FOREVER);
    self.state = WebSocketServerStateIdle;
}

- (void)addConnection:(WebSocketConnection *)connection {
    connection.delegate = self;
    dispatch_barrier_async(self.connectionsQueue, ^{
        [self.mutableConnections addObject:connection];
    });
}

- (void)removeConnection:(WebSocketConnection *)connection {
    dispatch_barrier_async(self.connectionsQueue, ^{
        [self.mutableConnections removeObject:connection];
    });
}

- (void)broadcastMessage:(NSData *)message toConnectionsMatching:(NSPredicate *)predicate {
    __block NSSet<WebSocketConnection *> *snapshot = nil;
    dispatch_sync(self.connectionsQueue, ^{
        snapshot = [self.mutableConnections copy];
    });

    NSSet<WebSocketConnection *> *targets =
        predicate ? [snapshot filteredSetUsingPredicate:predicate] : snapshot;

    for (WebSocketConnection *connection in targets) {
        [connection sendMessage:message];
    }
}

- (void)setState:(WebSocketServerState)state {
    if (_state != state) {
        _state = state;
        id<WebSocketServerDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(webSocketServer:stateDidChange:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate webSocketServer:self stateDidChange:state];
            });
        }
    }
}

- (void)webSocketConnection:(WebSocketConnection *)connection
           didCloseWithCode:(NSInteger)code
                     reason:(NSString *)reason {
    (void)code;
    (void)reason;
    [self removeConnection:connection];
    id<WebSocketServerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(webSocketServer:didCloseConnection:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate webSocketServer:self didCloseConnection:connection];
        });
    }
}

- (void)webSocketConnection:(WebSocketConnection *)connection
           didFailWithError:(NSError *)error {
    [self removeConnection:connection];
    id<WebSocketServerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(webSocketServer:didFailWithError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate webSocketServer:self didFailWithError:error];
        });
    }
}

@end

#else

#import <Network/Network.h>

@interface WebSocketServer () <WebSocketConnectionDelegate>
@property(nonatomic, readwrite) uint16_t port;
@property(nonatomic, readwrite) WebSocketServerState state;
@property(nonatomic, strong) nw_listener_t listener;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t listenerQueue;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t connectionsQueue;
@property(nonatomic, strong) NSMutableSet<WebSocketConnection *> *mutableConnections;
@property(nonatomic, PDS_GCD_STRONG) dispatch_semaphore_t stopSemaphore;
@property(nonatomic, PDS_GCD_STRONG) dispatch_group_t taskGroup;
@end

@implementation WebSocketServer

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _state = WebSocketServerStateIdle;
        _mutableConnections = [NSMutableSet set];
        _connectionsQueue = dispatch_queue_create("com.atproto.pds.websocket.connections", DISPATCH_QUEUE_CONCURRENT);
        _listenerQueue = dispatch_queue_create("com.atproto.pds.websocket.listener", DISPATCH_QUEUE_SERIAL);
        _stopSemaphore = dispatch_semaphore_create(0);
        _taskGroup = dispatch_group_create();
    }
    return self;
}

- (NSSet<WebSocketConnection *> *)connections {
    __block NSSet<WebSocketConnection *> *snapshot;
    dispatch_sync(self.connectionsQueue, ^{
        snapshot = [self.mutableConnections copy];
    });
    return snapshot;
}

- (BOOL)start:(NSError **)error {
    if (self.state != WebSocketServerStateIdle) {
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                       code:WebSocketServerErrorCodeListenerFailed
                                   userInfo:@{NSLocalizedDescriptionKey : @"Server is not idle"}];
        }
        return NO;
    }

    self.state = WebSocketServerStateStarting;

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_listener_t listener;
    NSString *portString = [NSString stringWithFormat:@"%hu", self.port];
    listener = nw_listener_create_with_port(portString.UTF8String, parameters);
    if (!listener) {
        self.state = WebSocketServerStateFailed;
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                       code:WebSocketServerErrorCodeListenerFailed
                                   userInfo:@{NSLocalizedDescriptionKey : @"Failed to create listener"}];
        }
        return NO;
    }

    nw_listener_set_queue(listener, self.listenerQueue);

    dispatch_semaphore_t readySemaphore = dispatch_semaphore_create(0);
    __weak typeof(self) weakSelf = self;
    __block BOOL startupSuccess = NO;
    __block NSError *startupError = nil;

    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, _Nullable nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        switch (state) {
        case nw_listener_state_ready:
            strongSelf.state = WebSocketServerStateRunning;
            strongSelf.port = nw_listener_get_port(listener);
            startupSuccess = YES;
            dispatch_semaphore_signal(readySemaphore);
            break;
        case nw_listener_state_failed:
            strongSelf.state = WebSocketServerStateFailed;
            if (error) {
                startupError = (__bridge_transfer NSError *)nw_error_copy_cf_error(error);
                if (strongSelf.delegate) {
                    [strongSelf.delegate webSocketServer:strongSelf didFailWithError:startupError];
                }
            }
            dispatch_semaphore_signal(strongSelf.stopSemaphore);
            dispatch_semaphore_signal(readySemaphore);
            break;
        case nw_listener_state_cancelled:
            strongSelf.state = WebSocketServerStateIdle;
            dispatch_semaphore_signal(strongSelf.stopSemaphore);
            break;
        default:
            break;
        }
    });

    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        PDSNetworkConnectionMac *adapter = [[PDSNetworkConnectionMac alloc] initWithConnection:connection];
        WebSocketConnection *webSocketConnection = [[WebSocketConnection alloc] initWithConnection:adapter];
        [strongSelf addConnection:webSocketConnection];
        webSocketConnection.delegate = strongSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(webSocketServer:didAcceptConnection:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate webSocketServer:strongSelf didAcceptConnection:webSocketConnection];
            });
        }
        [webSocketConnection start];
    });

    nw_listener_start(listener);

    if (dispatch_semaphore_wait(readySemaphore, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:WebSocketServerErrorDomain
                                       code:WebSocketServerErrorCodeListenerFailed
                                   userInfo:@{NSLocalizedDescriptionKey : @"Timed out waiting for WebSocket server to start"}];
        }
        nw_listener_cancel(listener);
        return NO;
    }

    if (!startupSuccess) {
        if (error) {
            *error = startupError ?: [NSError errorWithDomain:WebSocketServerErrorDomain
                                             code:WebSocketServerErrorCodeListenerFailed
                                         userInfo:@{NSLocalizedDescriptionKey : @"Failed to start WebSocket server"}];
        }
        return NO;
    }

    self.listener = listener;
    return YES;
}

- (void)stop {
    if (self.state == WebSocketServerStateIdle || self.state == WebSocketServerStateStopping) {
        return;
    }

    self.state = WebSocketServerStateStopping;

    __block NSSet<WebSocketConnection *> *connectionsSnapshot = nil;
    dispatch_barrier_sync(self.connectionsQueue, ^{
        connectionsSnapshot = [self.mutableConnections copy];
        [self.mutableConnections removeAllObjects];
    });

    for (WebSocketConnection *connection in connectionsSnapshot) {
        [connection close];
    }

    if (self.listener) {
        nw_listener_cancel(self.listener);
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC));
        dispatch_semaphore_wait(self.stopSemaphore, timeout);
        self.listener = nil;
    }

    dispatch_group_wait(self.taskGroup, DISPATCH_TIME_FOREVER);
    self.state = WebSocketServerStateIdle;
}

- (void)addConnection:(WebSocketConnection *)connection {
    connection.delegate = self;
    dispatch_barrier_async(self.connectionsQueue, ^{
        [self.mutableConnections addObject:connection];
    });
}

- (void)removeConnection:(WebSocketConnection *)connection {
    dispatch_barrier_async(self.connectionsQueue, ^{
        [self.mutableConnections removeObject:connection];
    });
}

- (void)broadcastMessage:(NSData *)message toConnectionsMatching:(NSPredicate *)predicate {
    __block NSSet<WebSocketConnection *> *snapshot = nil;
    dispatch_sync(self.connectionsQueue, ^{
        snapshot = [self.mutableConnections copy];
    });

    NSSet<WebSocketConnection *> *targets =
        predicate ? [snapshot filteredSetUsingPredicate:predicate] : snapshot;

    for (WebSocketConnection *connection in targets) {
        [connection sendMessage:message];
    }
}

- (void)setState:(WebSocketServerState)state {
    if (_state != state) {
        _state = state;
        id<WebSocketServerDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(webSocketServer:stateDidChange:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate webSocketServer:self stateDidChange:state];
            });
        }
    }
}

- (void)webSocketConnection:(WebSocketConnection *)connection
           didCloseWithCode:(NSInteger)code
                     reason:(NSString *)reason {
    (void)code;
    (void)reason;
    [self removeConnection:connection];
    id<WebSocketServerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(webSocketServer:didCloseConnection:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate webSocketServer:self didCloseConnection:connection];
        });
    }
}

- (void)webSocketConnection:(WebSocketConnection *)connection
           didFailWithError:(NSError *)error {
    [self removeConnection:connection];
    id<WebSocketServerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(webSocketServer:didFailWithError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate webSocketServer:self didFailWithError:error];
        });
    }
}

@end

#endif
