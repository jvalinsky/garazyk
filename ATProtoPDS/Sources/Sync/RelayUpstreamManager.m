#import "Sync/RelayUpstreamManager.h"
#import "Sync/RelayMetrics.h"

@interface RelayUpstreamManager () <RelayClientDelegate>

@property (nonatomic, strong) NSMutableDictionary<NSString *, RelayClient *> *upstreamClients;
@property (nonatomic, strong) NSMutableSet<NSString *> *connectedUpstreams;
@property (nonatomic) dispatch_queue_t managerQueue;
@property (nonatomic, assign, readwrite) NSUInteger maxReconnectAttempts;
@property (nonatomic, assign, readwrite) NSTimeInterval baseReconnectInterval;
@property (nonatomic, assign, readwrite) BOOL autoReconnectEnabled;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *reconnectAttempts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *reconnectDelays;

@end

@implementation RelayUpstreamManager

- (instancetype)initWithInitialURLs:(NSArray<NSString *> *)urls {
    self = [super init];
    if (self) {
        _upstreamClients = [NSMutableDictionary dictionary];
        _connectedUpstreams = [NSMutableSet set];
        self.managerQueue = dispatch_queue_create("com.atproto.relay.upstream", DISPATCH_QUEUE_SERIAL);
        _maxReconnectAttempts = 10;
        _baseReconnectInterval = 5.0;
        _autoReconnectEnabled = YES;
        _isPaused = NO;
        _reconnectAttempts = [NSMutableDictionary dictionary];
        _reconnectDelays = [NSMutableDictionary dictionary];

        for (NSString *url in urls) {
            [self createClientForUpstream:url];
        }
    }
    return self;
}

- (void)createClientForUpstream:(NSString *)url {
    NSURL *wsURL = [NSURL URLWithString:[NSString stringWithFormat:@"wss://%@/xrpc/com.atproto.sync.subscribeRepos", url]];
    RelayClient *client = [[RelayClient alloc] initWithServerURL:wsURL];
    client.delegate = self;
    self.upstreamClients[url] = client;
    self.reconnectAttempts[url] = @0;
    self.reconnectDelays[url] = @(self.baseReconnectInterval);
}

#pragma mark - Public Methods

- (void)addUpstream:(NSString *)url {
    dispatch_async(self.managerQueue, ^{
        if (!self.upstreamClients[url]) {
            [self createClientForUpstream:url];
            if (!self.isPaused) {
                [self connectToUpstream:url];
            }
        }
    });
}

- (void)removeUpstream:(NSString *)url {
    dispatch_async(self.managerQueue, ^{
        RelayClient *client = self.upstreamClients[url];
        if (client) {
            [client disconnect];
            [self.upstreamClients removeObjectForKey:url];
            [self.connectedUpstreams removeObject:url];
            [self.reconnectAttempts removeObjectForKey:url];
            [self.reconnectDelays removeObjectForKey:url];
        }
    });
}

- (void)removeAllUpstreams {
    dispatch_async(self.managerQueue, ^{
        for (RelayClient *client in self.upstreamClients.allValues) {
            [client disconnect];
        }
        [self.upstreamClients removeAllObjects];
        [self.connectedUpstreams removeAllObjects];
        [self.reconnectAttempts removeAllObjects];
        [self.reconnectDelays removeObjectForKey:@""];
    });
}

- (NSArray<NSString *> *)activeUpstreams {
    __block NSArray *result;
    dispatch_sync(self.managerQueue, ^{
        result = [self.connectedUpstreams allObjects];
    });
    return result;
}

- (NSArray<NSString *> *)allUpstreams {
    __block NSArray *result;
    dispatch_sync(self.managerQueue, ^{
        result = self.upstreamClients.allKeys;
    });
    return result;
}

- (void)connectAll {
    dispatch_async(self.managerQueue, ^{
        if (self.isPaused) return;
        for (NSString *url in self.upstreamClients) {
            [self connectToUpstream:url];
        }
    });
}

- (void)disconnectAll {
    dispatch_async(self.managerQueue, ^{
        for (RelayClient *client in self.upstreamClients.allValues) {
            [client disconnect];
        }
    });
}

- (void)connectToUpstream:(NSString *)url {
    if (self.isPaused) return;
    
    RelayClient *client = self.upstreamClients[url];
    if (client && !client.isConnected) {
        [client connect];
    }
}

- (void)disconnectFromUpstream:(NSString *)url {
    RelayClient *client = self.upstreamClients[url];
    if (client) {
        [client disconnect];
    }
}

- (void)pause {
    dispatch_async(self.managerQueue, ^{
        self.isPaused = YES;
        for (RelayClient *client in self.upstreamClients.allValues) {
            [client disconnect];
        }
    });
}

- (void)resume {
    dispatch_async(self.managerQueue, ^{
        self.isPaused = NO;
        for (NSString *url in self.upstreamClients) {
            [self connectToUpstream:url];
        }
    });
}

- (BOOL)isConnected {
    return self.connectedUpstreams.count > 0;
}

- (BOOL)isConnectedToUpstream:(NSString *)url {
    __block BOOL connected;
    dispatch_sync(self.managerQueue, ^{
        connected = [self.connectedUpstreams containsObject:url];
    });
    return connected;
}

#pragma mark - RelayClientDelegate

- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self.delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClient:(RelayClient *)client didReceiveIdentityEvent:(FirehoseIdentityEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self.delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClient:(RelayClient *)client didReceiveErrorEvent:(FirehoseErrorEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self.delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClientDidConnect:(RelayClient *)client {
    NSString *url = [self urlForClient:client];
    if (url) {
        dispatch_async(self.managerQueue, ^{
            [self.connectedUpstreams addObject:url];
            self.reconnectAttempts[url] = @0;
            self.reconnectDelays[url] = @(self.baseReconnectInterval);
        });
        [[RelayMetrics sharedMetrics] recordUpstreamConnected];
        [self.delegate upstreamManager:self didConnectToUpstream:url];
    }
}

- (void)relayClient:(RelayClient *)client didDisconnectWithError:(NSError *)error {
    NSString *url = [self urlForClient:client];
    if (url) {
        dispatch_async(self.managerQueue, ^{
            [self.connectedUpstreams removeObject:url];
        });
        [[RelayMetrics sharedMetrics] recordUpstreamDisconnected];
        [self.delegate upstreamManager:self didDisconnectFromUpstream:url error:error];
        
        if (self.autoReconnectEnabled && !self.isPaused) {
            [self scheduleReconnectForUpstream:url];
        }
    }
}

- (void)relayClient:(RelayClient *)client didReceiveCursor:(int64_t)cursor {
    NSString *url = [self urlForClient:client];
    if (url) {
        [[RelayMetrics sharedMetrics] recordSequence:cursor];
        [self.delegate upstreamManager:self didReceiveCursor:cursor fromUpstream:url];
    }
}

#pragma mark - Reconnection

- (void)scheduleReconnectForUpstream:(NSString *)url {
    NSNumber *attempts = self.reconnectAttempts[url];
    if (attempts.integerValue >= self.maxReconnectAttempts) {
        return;
    }
    
    self.reconnectAttempts[url] = @(attempts.integerValue + 1);
    [[RelayMetrics sharedMetrics] recordReconnectionCount];
    
    NSTimeInterval delay = self.reconnectDelays[url].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self.managerQueue, ^{
        if (!self.isPaused && ![self.connectedUpstreams containsObject:url]) {
            [self connectToUpstream:url];
        }
    });
    
    self.reconnectDelays[url] = @(delay * 2.0);
}

- (NSString *)urlForClient:(RelayClient *)client {
    for (NSString *url in self.upstreamClients) {
        if (self.upstreamClients[url] == client) {
            return url;
        }
    }
    return nil;
}

@end