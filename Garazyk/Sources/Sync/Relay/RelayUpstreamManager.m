// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Debug/GZLogger.h"

@interface RelayUpstreamManager () <RelayClientDelegate>

@property (nonatomic, strong) NSMutableDictionary<NSString *, RelayClient *> *upstreamClients;
@property (nonatomic, strong) NSMutableSet<NSString *> *connectedUpstreams;
@property (nonatomic, assign, readwrite) NSUInteger maxReconnectAttempts;
@property (nonatomic, assign, readwrite) NSTimeInterval baseReconnectInterval;
@property (nonatomic, assign, readwrite) BOOL autoReconnectEnabled;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *reconnectAttempts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *reconnectDelays;

// Host status tracking for getHostStatus endpoint
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *hostSeqs;           // url -> seq
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *hostAccountCounts; // url -> count
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *hostStatuses;      // url -> @ RelayHostStatus

@end

@implementation RelayUpstreamManager {
    dispatch_queue_t _managerQueue;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithInitialURLs:(NSArray<NSString *> *)urls {
    self = [super init];
    if (self) {
        _upstreamClients = [NSMutableDictionary dictionary];
        _connectedUpstreams = [NSMutableSet set];
        _managerQueue = dispatch_queue_create("com.atproto.relay.upstream", DISPATCH_QUEUE_SERIAL);
        _maxReconnectAttempts = 10;
        _baseReconnectInterval = 5.0;
        _autoReconnectEnabled = YES;
        _isPaused = NO;
        _reconnectAttempts = [NSMutableDictionary dictionary];
        _reconnectDelays = [NSMutableDictionary dictionary];
        _hostSeqs = [NSMutableDictionary dictionary];
        _hostAccountCounts = [NSMutableDictionary dictionary];
        _hostStatuses = [NSMutableDictionary dictionary];

        for (NSString *url in urls) {
            [self createClientForUpstream:url];
        }
    }
    return self;
}

- (void)createClientForUpstream:(NSString *)url {
    NSString *urlString = url;
    if (![urlString containsString:@"://"]) {
        // Bare hostname — add http/https scheme
        if ([urlString hasPrefix:@"localhost:"] || [urlString hasPrefix:@"127.0.0.1:"]) {
            urlString = [NSString stringWithFormat:@"http://%@", urlString];
        } else {
            urlString = [NSString stringWithFormat:@"https://%@", urlString];
        }
    } else {
        // Normalize WebSocket schemes to HTTP so NSURL can parse them.
        // RelayClient.buildWebSocketURL converts http→ws, https→wss when connecting.
        if ([urlString hasPrefix:@"ws://"]) {
            urlString = [NSString stringWithFormat:@"http://%@", [urlString substringFromIndex:5]];
        } else if ([urlString hasPrefix:@"wss://"]) {
            urlString = [NSString stringWithFormat:@"https://%@", [urlString substringFromIndex:6]];
        }
    }

    NSURL *httpURL = [NSURL URLWithString:urlString];
    if (!httpURL) {
        GZ_LOG_ERROR_C(@"Relay", @"Invalid upstream URL: %@", url);
        return;
    }

    NSString *scheme = httpURL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        GZ_LOG_ERROR_C(@"Relay", @"Invalid upstream URL scheme: %@ (original: %@)", scheme, url);
        return;
    }

    RelayClient *client = [[RelayClient alloc] initWithServerURL:httpURL];
    client.delegate = self;
    self.upstreamClients[url] = client;
    self.reconnectAttempts[url] = @0;
    self.reconnectDelays[url] = @(self.baseReconnectInterval);
}

#pragma mark - Public Methods

- (void)addUpstream:(NSString *)url {
    dispatch_async(_managerQueue, ^{
        if (!self.upstreamClients[url]) {
            [self createClientForUpstream:url];
            if (!self.isPaused) {
                [self connectToUpstream:url];
            }
        }
    });
}

- (void)removeUpstream:(NSString *)url {
    dispatch_async(_managerQueue, ^{
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
    dispatch_async(_managerQueue, ^{
        for (RelayClient *client in self.upstreamClients.allValues) {
            [client disconnect];
        }
        [self.upstreamClients removeAllObjects];
        [self.connectedUpstreams removeAllObjects];
        [self.reconnectAttempts removeAllObjects];
        [self.reconnectDelays removeAllObjects];
    });
}

- (NSArray<NSString *> *)activeUpstreams {
    __block NSArray *result;
    dispatch_sync(_managerQueue, ^{
        result = [self.connectedUpstreams allObjects];
    });
    return result;
}

- (NSArray<NSString *> *)allUpstreams {
    __block NSArray *result;
    dispatch_sync(_managerQueue, ^{
        result = self.upstreamClients.allKeys;
    });
    return result;
}

- (void)connectAll {
    dispatch_async(_managerQueue, ^{
        if (self.isPaused) return;
        for (NSString *url in self.upstreamClients) {
            [self connectToUpstream:url];
        }
    });
}

- (void)disconnectAll {
    dispatch_async(_managerQueue, ^{
        for (RelayClient *client in self.upstreamClients.allValues) {
            [client disconnect];
        }
    });
}

- (void)connectToUpstream:(NSString *)url {
    RelayClient *client = self.upstreamClients[url];
    if (client) {
        GZ_LOG_SYNC_INFO(@"RelayUpstreamManager: Connecting to %@", url);
        [client connect];
    } else {
        GZ_LOG_SYNC_ERROR(@"RelayUpstreamManager: No client found for %@", url);
    }
}

- (void)disconnectFromUpstream:(NSString *)url {
    RelayClient *client = self.upstreamClients[url];
    if (client) {
        [client disconnect];
    }
}

- (void)validateHost:(NSString *)hostname completion:(void (^)(BOOL reachable, NSError * _Nullable error))completion {
    NSString *urlString = hostname;
    if (![urlString containsString:@"://"]) {
        if ([hostname hasPrefix:@"localhost:"] || [hostname hasPrefix:@"127.0.0.1:"]) {
            urlString = [NSString stringWithFormat:@"http://%@", hostname];
        } else {
            urlString = [NSString stringWithFormat:@"https://%@", hostname];
        }
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.describeServer", urlString]];
    if (!url) {
        completion(NO, [NSError errorWithDomain:@"com.atproto.relay.upstream" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid hostname"}]);
        return;
    }
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 200) {
            completion(YES, nil);
        } else {
            completion(NO, [NSError errorWithDomain:@"com.atproto.relay.upstream" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unexpected status code: %ld", (long)httpResponse.statusCode]}]);
        }
    }];
    [task resume];
}

- (void)pause {
    dispatch_async(_managerQueue, ^{
        self.isPaused = YES;
        for (RelayClient *client in self.upstreamClients.allValues) {
            [client disconnect];
        }
    });
}

- (void)resume {
    dispatch_async(_managerQueue, ^{
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
    dispatch_sync(_managerQueue, ^{
        connected = [self.connectedUpstreams containsObject:url];
    });
    return connected;
}

#pragma mark - RelayClientDelegate

- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    NSString *url = [self urlForClient:client];
    id<RelayUpstreamManagerDelegate> delegate = self.delegate;
    if (url && delegate) {
        [delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClient:(RelayClient *)client didReceiveIdentityEvent:(FirehoseIdentityEvent *)event {
    NSString *url = [self urlForClient:client];
    id<RelayUpstreamManagerDelegate> delegate = self.delegate;
    if (url && delegate) {
        [delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClient:(RelayClient *)client didReceiveErrorEvent:(FirehoseErrorEvent *)event {
    NSString *url = [self urlForClient:client];
    id<RelayUpstreamManagerDelegate> delegate = self.delegate;
    if (url && delegate) {
        [delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClientDidConnect:(RelayClient *)client {
    NSString *url = [self urlForClient:client];
    if (url) {
        GZ_LOG_SYNC_INFO(@"RelayUpstreamManager: Client connected to %@", url);
        dispatch_async(_managerQueue, ^{
            [self.connectedUpstreams addObject:url];
            self.reconnectAttempts[url] = @0;
            self.reconnectDelays[url] = @(self.baseReconnectInterval);
            self.hostStatuses[url] = @(RelayHostStatusActive);
        });
        [[RelayMetrics sharedMetrics] recordUpstreamConnected];
        id<RelayUpstreamManagerDelegate> delegate = self.delegate;
        if (delegate) {
            [delegate upstreamManager:self didConnectToUpstream:url];
        }
    }
}

- (void)relayClient:(RelayClient *)client didDisconnectWithError:(NSError *)error {
    NSString *url = [self urlForClient:client];
    if (url) {
        dispatch_async(_managerQueue, ^{
            [self.connectedUpstreams removeObject:url];
            self.hostStatuses[url] = @(error ? RelayHostStatusError : RelayHostStatusDisconnected);
        });
        [[RelayMetrics sharedMetrics] recordUpstreamDisconnected];
        id<RelayUpstreamManagerDelegate> delegate = self.delegate;
        if (delegate) {
            [delegate upstreamManager:self didDisconnectFromUpstream:url error:error];
        }
        if (self.autoReconnectEnabled && !self.isPaused) {
            [self scheduleReconnectForUpstream:url];
        }
    }
}

- (void)relayClient:(RelayClient *)client didReceiveCursor:(int64_t)cursor {
    NSString *url = [self urlForClient:client];
    if (url) {
        dispatch_async(_managerQueue, ^{
            self.hostSeqs[url] = @(cursor);
        });
        [[RelayMetrics sharedMetrics] recordSequence:cursor];
        id<RelayUpstreamManagerDelegate> delegate = self.delegate;
        if (delegate) {
            [delegate upstreamManager:self didReceiveCursor:cursor fromUpstream:url];
        }
    }
}

#pragma mark - Reconnection

- (void)scheduleReconnectForUpstream:(NSString *)url {
    NSNumber *attempts = self.reconnectAttempts[url];
    if (attempts.integerValue >= self.maxReconnectAttempts) {
        GZ_LOG_SYNC_WARN(@"Max reconnect attempts reached for upstream %@", url);
        return;
    }

    NSTimeInterval delay = [self.reconnectDelays[url] doubleValue];
    GZ_LOG_SYNC_INFO(@"Scheduling reconnect for %@ in %.1fs (attempt %ld)", url, delay, (long)attempts.integerValue + 1);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _managerQueue, ^{
        self.reconnectAttempts[url] = @(attempts.integerValue + 1);
        double nextDelay = MIN(delay * 1.5, 60.0);
        self.reconnectDelays[url] = @(nextDelay);
        [self connectToUpstream:url];
    });
}

#pragma mark - Helpers

- (NSString *)urlForClient:(RelayClient *)client {
    for (NSString *url in self.upstreamClients) {
        if (self.upstreamClients[url] == client) {
            return url;
        }
    }
    return nil;
}

#pragma mark - Status Tracking

- (int64_t)seqForUpstream:(NSString *)url {
    __block int64_t seq = 0;
    dispatch_sync(_managerQueue, ^{
        seq = [self.hostSeqs[url] longLongValue];
    });
    return seq;
}

- (NSUInteger)accountCountForUpstream:(NSString *)url {
    __block NSUInteger count = 0;
    dispatch_sync(_managerQueue, ^{
        count = [self.hostAccountCounts[url] unsignedIntegerValue];
    });
    return count;
}

- (void)setAccountCount:(NSUInteger)count forUpstream:(NSString *)url {
    dispatch_async(_managerQueue, ^{
        self.hostAccountCounts[url] = @(count);
    });
}

- (RelayHostStatus)statusForUpstream:(NSString *)url {
    __block RelayHostStatus status = RelayHostStatusDisconnected;
    dispatch_sync(_managerQueue, ^{
        status = (RelayHostStatus)[self.hostStatuses[url] integerValue];
    });
    return status;
}

@end
