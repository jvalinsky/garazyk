// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Debug/GZLogger.h"

static void *RelayUpstreamManagerQueueKey = &RelayUpstreamManagerQueueKey;

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
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *crawlStates;       // url -> @ RelayCrawlState
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *crawlGenerations;   // url -> generation
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *crawlRepoCounts;   // url -> inventory repo count
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *crawlErrors;        // url -> display-safe error
@property (nonatomic, strong) NSMutableSet<NSString *> *crawlRequestedURLSet;
@property (nonatomic, strong) NSMutableSet<NSString *> *inventoryRequestedUpstreams;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *crawlRequestedDates;
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;

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
        dispatch_queue_set_specific(_managerQueue,
                                    RelayUpstreamManagerQueueKey,
                                    (__bridge void *)self,
                                    NULL);
        _maxReconnectAttempts = 10;
        _baseReconnectInterval = 5.0;
        _autoReconnectEnabled = YES;
        _isPaused = NO;
        _reconnectAttempts = [NSMutableDictionary dictionary];
        _reconnectDelays = [NSMutableDictionary dictionary];
        _hostSeqs = [NSMutableDictionary dictionary];
        _hostAccountCounts = [NSMutableDictionary dictionary];
        _hostStatuses = [NSMutableDictionary dictionary];
        _crawlStates = [NSMutableDictionary dictionary];
        _crawlGenerations = [NSMutableDictionary dictionary];
        _crawlRepoCounts = [NSMutableDictionary dictionary];
        _crawlErrors = [NSMutableDictionary dictionary];
        _crawlRequestedURLSet = [NSMutableSet set];
        _inventoryRequestedUpstreams = [NSMutableSet set];
        _crawlRequestedDates = [NSMutableDictionary dictionary];
        _safeHTTPClient = [ATProtoSafeHTTPClient sharedClient];

        for (NSString *url in urls) {
            [self createClientForUpstream:url];
        }
    }
    return self;
}

- (void)performSynchronouslyOnManagerQueue:(dispatch_block_t)block {
    if (dispatch_get_specific(RelayUpstreamManagerQueueKey) ==
        (__bridge void *)self) {
        block();
    } else {
        dispatch_sync(_managerQueue, block);
    }
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
    [self performSynchronouslyOnManagerQueue:^{
        result = [[self.connectedUpstreams allObjects]
            sortedArrayUsingSelector:@selector(compare:)];
    }];
    return result;
}

- (NSArray<NSString *> *)allUpstreams {
    __block NSArray *result;
    [self performSynchronouslyOnManagerQueue:^{
        result = [self.upstreamClients.allKeys sortedArrayUsingSelector:@selector(compare:)];
    }];
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
    [self performSynchronouslyOnManagerQueue:^{
        RelayClient *client = self.upstreamClients[url];
        if (client) {
            GZ_LOG_SYNC_INFO(@"RelayUpstreamManager: Connecting to %@", url);
            [client connect];
        } else {
            GZ_LOG_SYNC_ERROR(@"RelayUpstreamManager: No client found for %@", url);
        }
    }];
}

- (void)disconnectFromUpstream:(NSString *)url {
    [self performSynchronouslyOnManagerQueue:^{
        RelayClient *client = self.upstreamClients[url];
        if (client) {
            [client disconnect];
        }
    }];
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
    
    NSURL *baseURL = [NSURL URLWithString:urlString];
    NSURL *url = [NSURL URLWithString:@"/xrpc/com.atproto.server.describeServer" relativeToURL:baseURL].absoluteURL;
    if (!url) {
        completion(NO, [NSError errorWithDomain:@"com.atproto.relay.upstream" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid hostname"}]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 4.0;

    ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
    options.timeout = 4.0;
    options.maxResponseBytes = 64 * 1024;
    options.allowHTTP = [url.scheme.lowercaseString isEqualToString:@"http"];
    options.followRedirects = NO;

    [self.safeHTTPClient performSafeDataTaskWithRequest:request
                                               options:options
                                            completion:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            completion(NO, error);
            return;
        }

        if (response.statusCode == 200) {
            completion(YES, nil);
        } else {
            completion(NO, [NSError errorWithDomain:@"com.atproto.relay.upstream" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unexpected status code: %ld", (long)response.statusCode]}]);
        }
    }];
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
    __block BOOL connected = NO;
    [self performSynchronouslyOnManagerQueue:^{
        connected = self.connectedUpstreams.count > 0;
    }];
    return connected;
}

- (BOOL)isConnectedToUpstream:(NSString *)url {
    __block BOOL connected;
    [self performSynchronouslyOnManagerQueue:^{
        connected = [self.connectedUpstreams containsObject:url];
    }];
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

- (void)relayClient:(RelayClient *)client didReceiveAccountEvent:(FirehoseAccountEvent *)event {
    NSString *url = [self urlForClient:client];
    id<RelayUpstreamManagerDelegate> delegate = self.delegate;
    if (url && delegate) {
        [delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClient:(RelayClient *)client didReceiveSyncEvent:(FirehoseSyncEvent *)event {
    NSString *url = [self urlForClient:client];
    id<RelayUpstreamManagerDelegate> delegate = self.delegate;
    if (url && delegate) {
        [delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClient:(RelayClient *)client didReceiveRawEvent:(FirehoseRawEvent *)event {
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
        if (error) {
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
    dispatch_async(_managerQueue, ^{
        if (!self.autoReconnectEnabled || self.isPaused ||
            !self.upstreamClients[url]) {
            return;
        }
        NSNumber *attempts = self.reconnectAttempts[url] ?: @0;
        if (attempts.integerValue >= self.maxReconnectAttempts) {
            GZ_LOG_SYNC_WARN(@"Max reconnect attempts reached for upstream %@", url);
            return;
        }

        NSTimeInterval delay =
            self.reconnectDelays[url] != nil
                ? self.reconnectDelays[url].doubleValue
                : self.baseReconnectInterval;
        GZ_LOG_SYNC_INFO(@"Scheduling reconnect for %@ in %.1fs (attempt %ld)",
                         url, delay, (long)attempts.integerValue + 1);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay * NSEC_PER_SEC)),
                       self->_managerQueue, ^{
            if (!self.autoReconnectEnabled || self.isPaused ||
                !self.upstreamClients[url]) {
                return;
            }
            self.reconnectAttempts[url] = @(attempts.integerValue + 1);
            self.reconnectDelays[url] = @(MIN(delay * 1.5, 60.0));
            [self connectToUpstream:url];
        });
    });
}

#pragma mark - Helpers

- (NSString *)urlForClient:(RelayClient *)client {
    __block NSString *matchedURL = nil;
    [self performSynchronouslyOnManagerQueue:^{
        for (NSString *url in self.upstreamClients) {
            if (self.upstreamClients[url] == client) {
                matchedURL = url;
                break;
            }
        }
    }];
    return matchedURL;
}

#pragma mark - Status Tracking

- (int64_t)seqForUpstream:(NSString *)url {
    __block int64_t seq = 0;
    [self performSynchronouslyOnManagerQueue:^{
        seq = [self.hostSeqs[url] longLongValue];
    }];
    return seq;
}

- (NSUInteger)accountCountForUpstream:(NSString *)url {
    __block NSUInteger count = 0;
    [self performSynchronouslyOnManagerQueue:^{
        count = [self.hostAccountCounts[url] unsignedIntegerValue];
    }];
    return count;
}

- (void)setAccountCount:(NSUInteger)count forUpstream:(NSString *)url {
    dispatch_async(_managerQueue, ^{
        self.hostAccountCounts[url] = @(count);
    });
}

- (RelayHostStatus)statusForUpstream:(NSString *)url {
    __block RelayHostStatus status = RelayHostStatusDisconnected;
    [self performSynchronouslyOnManagerQueue:^{
        status = (RelayHostStatus)[self.hostStatuses[url] integerValue];
    }];
    return status;
}

#pragma mark - Repository Inventory Crawl State

- (void)markCrawlRequestedForUpstream:(NSString *)url {
    if (url.length == 0) return;
    [self performSynchronouslyOnManagerQueue:^{
        [self.crawlRequestedURLSet addObject:url];
        [self.inventoryRequestedUpstreams addObject:url];
        self.crawlRequestedDates[url] = [NSDate date];
        RelayCrawlState state = (RelayCrawlState)[self.crawlStates[url] integerValue];
        if (state != RelayCrawlStateCrawling && state != RelayCrawlStateComplete) {
            self.crawlStates[url] = @(RelayCrawlStateRequested);
        }
        [self.crawlErrors removeObjectForKey:url];
    }];
}

- (void)markInventoryRequestedForUpstream:(NSString *)url {
    if (url.length == 0) return;
    [self performSynchronouslyOnManagerQueue:^{
        [self.inventoryRequestedUpstreams addObject:url];
        if (![self.crawlStates[url] isEqual:@(RelayCrawlStateComplete)] &&
            ![self.crawlStates[url] isEqual:@(RelayCrawlStateCrawling)]) {
            self.crawlStates[url] = @(RelayCrawlStateRequested);
        }
    }];
}

- (NSUInteger)beginInventoryForUpstream:(NSString *)url {
    if (url.length == 0) return 0;
    __block NSUInteger generation = 0;
    [self performSynchronouslyOnManagerQueue:^{
        [self.inventoryRequestedUpstreams addObject:url];
        generation = [self.crawlGenerations[url] unsignedIntegerValue] + 1;
        self.crawlGenerations[url] = @(generation);
        self.crawlStates[url] = @(RelayCrawlStateCrawling);
        self.crawlRepoCounts[url] = @0;
        [self.crawlErrors removeObjectForKey:url];
    }];
    return generation;
}

- (void)recordInventoryPageForUpstream:(NSString *)url
                          generation:(NSUInteger)generation
                           repoCount:(NSUInteger)repoCount {
    if (url.length == 0) return;
    [self performSynchronouslyOnManagerQueue:^{
        if ([self.crawlGenerations[url] unsignedIntegerValue] != generation) return;
        NSUInteger currentCount = [self.crawlRepoCounts[url] unsignedIntegerValue];
        self.crawlRepoCounts[url] = @(currentCount + repoCount);
    }];
}

- (void)completeInventoryForUpstream:(NSString *)url
                         generation:(NSUInteger)generation
                          repoCount:(NSUInteger)repoCount {
    if (url.length == 0) return;
    [self performSynchronouslyOnManagerQueue:^{
        if ([self.crawlGenerations[url] unsignedIntegerValue] != generation) return;
        self.crawlStates[url] = @(RelayCrawlStateComplete);
        self.crawlRepoCounts[url] = @(repoCount);
        [self.crawlErrors removeObjectForKey:url];
    }];
}

- (void)failInventoryForUpstream:(NSString *)url
                     generation:(NSUInteger)generation
                           error:(NSString *)error {
    if (url.length == 0) return;
    [self performSynchronouslyOnManagerQueue:^{
        if ([self.crawlGenerations[url] unsignedIntegerValue] != generation) return;
        self.crawlStates[url] = @(RelayCrawlStateFailed);
        if (error.length > 0) {
            self.crawlErrors[url] = error;
        } else {
            [self.crawlErrors removeObjectForKey:url];
        }
    }];
}

- (NSArray<NSString *> *)crawlRequestedUpstreams {
    __block NSArray<NSString *> *urls = nil;
    [self performSynchronouslyOnManagerQueue:^{
        urls = [[self.crawlRequestedURLSet allObjects]
            sortedArrayUsingSelector:@selector(compare:)];
    }];
    return urls;
}

- (BOOL)crawlWasRequestedForUpstream:(NSString *)url {
    __block BOOL requested = NO;
    [self performSynchronouslyOnManagerQueue:^{
        requested = [self.crawlRequestedURLSet containsObject:url];
    }];
    return requested;
}

- (BOOL)inventoryWasRequestedForUpstream:(NSString *)url {
    __block BOOL requested = NO;
    [self performSynchronouslyOnManagerQueue:^{
        requested = [self.inventoryRequestedUpstreams containsObject:url];
    }];
    return requested;
}

- (NSDate *)crawlRequestedAtForUpstream:(NSString *)url {
    __block NSDate *date = nil;
    [self performSynchronouslyOnManagerQueue:^{
        date = [self.crawlRequestedDates[url] copy];
    }];
    return date;
}

- (NSUInteger)crawlGenerationForUpstream:(NSString *)url {
    __block NSUInteger generation = 0;
    [self performSynchronouslyOnManagerQueue:^{
        generation = [self.crawlGenerations[url] unsignedIntegerValue];
    }];
    return generation;
}

- (RelayCrawlState)crawlStateForUpstream:(NSString *)url {
    __block RelayCrawlState state = RelayCrawlStateNotRequested;
    [self performSynchronouslyOnManagerQueue:^{
        state = (RelayCrawlState)[self.crawlStates[url] integerValue];
    }];
    return state;
}

- (NSUInteger)crawlRepoCountForUpstream:(NSString *)url {
    __block NSUInteger count = 0;
    [self performSynchronouslyOnManagerQueue:^{
        count = [self.crawlRepoCounts[url] unsignedIntegerValue];
    }];
    return count;
}

- (NSString *)crawlErrorForUpstream:(NSString *)url {
    __block NSString *error = nil;
    [self performSynchronouslyOnManagerQueue:^{
        error = [self.crawlErrors[url] copy];
    }];
    return error;
}

@end
