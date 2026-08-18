// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayIngressConfiguration.h"
#import "Sync/Relay/RelayIngressPipeline.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Debug/GZLogger.h"

static void *RelayUpstreamManagerQueueKey = &RelayUpstreamManagerQueueKey;

@interface ATProtoRelayUpstreamManager () <RelayClientDelegate, RelayIngressBackpressureDelegate>

@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoRelayClient *> *upstreamClients;
@property (nonatomic, strong) NSMutableSet<NSString *> *connectedUpstreams;
@property (nonatomic, assign, readwrite) NSUInteger maxReconnectAttempts;
@property (nonatomic, assign, readwrite) NSTimeInterval baseReconnectInterval;
@property (nonatomic, assign, readwrite) BOOL autoReconnectEnabled;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *reconnectAttempts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *reconnectDelays;
// atomic: see the header for why this pointer is not queue-confined like
// upstreamClients below -- it is read on the WebSocket read thread inside
// -ingressGateForUpstream:'s block and must never block on _managerQueue.
@property (atomic, strong, readwrite, nullable) ATProtoRelayIngressPipeline *ingressPipeline;
@property (nonatomic, strong, nullable) ATProtoRelayIngressConfiguration *ingressConfiguration;
@property (nonatomic, assign) NSUInteger ingressGeneration;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *clientIngressGenerations;
@property (nonatomic, strong) NSMutableSet<NSString *> *backpressurePausedUpstreams;

// Host status tracking for getHostStatus endpoint
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *hostSeqs;           // url -> seq
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *hostAccountCounts; // url -> count
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *hostStatuses;      // url -> @ RelayHostStatus
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *hostEventCounts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *hostLastEventDates;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *hostConnectedDates;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *crawlStates;       // url -> @ RelayCrawlState
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *crawlGenerations;   // url -> generation
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *crawlRepoCounts;   // url -> inventory repo count
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *crawlErrors;        // url -> display-safe error
@property (nonatomic, strong) NSMutableSet<NSString *> *crawlRequestedURLSet;
@property (nonatomic, strong) NSMutableSet<NSString *> *inventoryRequestedUpstreams;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *crawlRequestedDates;
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;

@end

@implementation ATProtoRelayUpstreamManager {
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
        _hostEventCounts = [NSMutableDictionary dictionary];
        _hostLastEventDates = [NSMutableDictionary dictionary];
        _hostConnectedDates = [NSMutableDictionary dictionary];
        _crawlStates = [NSMutableDictionary dictionary];
        _crawlGenerations = [NSMutableDictionary dictionary];
        _crawlRepoCounts = [NSMutableDictionary dictionary];
        _crawlErrors = [NSMutableDictionary dictionary];
        _crawlRequestedURLSet = [NSMutableSet set];
        _inventoryRequestedUpstreams = [NSMutableSet set];
        _crawlRequestedDates = [NSMutableDictionary dictionary];
        _safeHTTPClient = [ATProtoSafeHTTPClient sharedClient];
        _clientIngressGenerations = [NSMutableDictionary dictionary];
        _backpressurePausedUpstreams = [NSMutableSet set];

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
        // ATProtoRelayClient.buildWebSocketURL converts http→ws, https→wss when connecting.
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

    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:httpURL];
    client.delegate = self;
    if (self.ingressPipeline) {
        client.reconnectUsesProcessedCursor = YES;
        client.ingressGate = [self ingressGateForUpstream:url];
    }
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
        ATProtoRelayClient *client = self.upstreamClients[url];
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
        for (ATProtoRelayClient *client in self.upstreamClients.allValues) {
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
        self.ingressGeneration++;
        for (NSString *url in self.upstreamClients) {
            [self connectToUpstream:url];
        }
    });
}

- (void)disconnectAll {
    dispatch_async(_managerQueue, ^{
        self.ingressGeneration++;
        for (ATProtoRelayClient *client in self.upstreamClients.allValues) {
            [client disconnect];
        }
    });
}

- (void)connectToUpstream:(NSString *)url {
    [self performSynchronouslyOnManagerQueue:^{
        ATProtoRelayClient *client = self.upstreamClients[url];
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
        ATProtoRelayClient *client = self.upstreamClients[url];
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
        for (ATProtoRelayClient *client in self.upstreamClients.allValues) {
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

#pragma mark - Bounded Ingress

- (void)configureBoundedIngressWithConfiguration:(ATProtoRelayIngressConfiguration *)configuration
                                        metrics:(ATProtoRelayMetrics *)metrics
                                   processBlock:(RelayIngressProcessBlock)processBlock {
    if (!configuration.boundedIngressEnabled) {
        self.ingressPipeline = nil;
        self.ingressConfiguration = configuration;
        return;
    }
    self.ingressConfiguration = configuration;
    RelayIngressProcessBlock userBlock = [processBlock copy];
    __weak typeof(self) weakSelf = self;
    self.ingressPipeline = [[ATProtoRelayIngressPipeline alloc]
        initWithConfiguration:configuration
                      metrics:metrics
                 processBlock:^(id event,
                                NSString *upstreamURL,
                                int64_t sequence,
                                RelayIngressProcessCompletion completion) {
        userBlock(event, upstreamURL, sequence, ^(RelayIngressReleaseReason reason) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && reason == RelayIngressReleaseReasonProcessed) {
                // This completion runs on RelayIngressPipeline's shard queue,
                // not _managerQueue -- upstreamClients is only ever mutated
                // on _managerQueue, so the read must go through it too.
                __block ATProtoRelayClient *acked = nil;
                [strongSelf performSynchronouslyOnManagerQueue:^{
                    acked = strongSelf.upstreamClients[upstreamURL];
                }];
                [acked acknowledgeProcessedSequence:sequence];
            }
            completion(reason);
        });
    }];
    self.ingressPipeline.backpressureDelegate = self;
    // configureBoundedIngressWithConfiguration:... is called from whatever
    // thread the owner sets bounded ingress up on, not necessarily
    // _managerQueue -- upstreamClients must only be touched on that queue.
    [self performSynchronouslyOnManagerQueue:^{
        for (NSString *url in self.upstreamClients) {
            ATProtoRelayClient *client = self.upstreamClients[url];
            client.reconnectUsesProcessedCursor = YES;
            client.ingressGate = [self ingressGateForUpstream:url];
        }
    }];
}

/*!
 Builds the synchronous ATProtoFirehoseIngressGate installed on the given
 upstream's ATProtoRelayClient (see ADR 0039). The block runs on the
 WebSocket read thread, computes the same encodedBytes/orderingKey/sequence
 that -submitEvent:fromClient: computes for the bounded path, and submits
 directly to self.ingressPipeline so admission and shard dispatch happen
 before any dispatch_async hop. Only Commit/Identity/Account/Sync events
 ever reach this block (Firehose only consults ingressGate for those
 kinds), so -submitEvent:fromClient: must not re-submit those same events
 once they reach the RelayClientDelegate chain -- see
 -eventKindIsGatedAtIngress:.
 */
- (ATProtoFirehoseIngressGate)ingressGateForUpstream:(NSString *)url {
    __weak typeof(self) weakSelf = self;
    NSString *upstreamURL = [url copy];
    return ^BOOL(id event, FirehoseEventKind kind) {
        (void)kind;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        ATProtoRelayIngressPipeline *pipeline = strongSelf.ingressPipeline;
        if (!pipeline) {
            // Bounded ingress was torn down after this gate was installed;
            // treat as if the gate itself were absent.
            return YES;
        }

        int64_t sequence = [strongSelf sequenceForEvent:event];
        uint64_t encodedBytes = [ATProtoRelayIngressPipeline encodedByteLengthForEvent:event];
        NSString *orderingKey = [ATProtoRelayIngressPipeline orderingKeyForEvent:event upstreamURL:upstreamURL];
        NSError *submitError = nil;
        BOOL accepted = [pipeline submitEvent:event
                                 encodedBytes:encodedBytes
                                  orderingKey:orderingKey
                                 fromUpstream:upstreamURL
                                     sequence:sequence
                                        error:&submitError];
        if (!accepted) {
            GZ_LOG_SYNC_WARN(@"RelayUpstreamManager: ingress gate refused event from %@: %@",
                             upstreamURL, submitError.localizedDescription ?: @"backlog full");
        }
        return accepted;
    };
}

/*!
 Whether -sendEventToSubscriptions:kind: gates this event's kind at the
 ATProtoFirehose layer (see ADR 0039). Commit/Identity/Account/Sync events
 that reach this manager's RelayClientDelegate callbacks were already
 admitted and shard-dispatched synchronously by the ingressGate block
 before delivery; -submitEvent:fromClient: must not submit them again.
 Raw and legacy dictionary-encoded events are never gated at the firehose
 layer and still take the bounded-submission path below.
 */
- (BOOL)eventKindIsGatedAtIngress:(id)event {
    return [event isKindOfClass:[ATProtoFirehoseCommitEvent class]] ||
        [event isKindOfClass:[ATProtoFirehoseIdentityEvent class]] ||
        [event isKindOfClass:[ATProtoFirehoseAccountEvent class]] ||
        [event isKindOfClass:[ATProtoFirehoseSyncEvent class]];
}

- (int64_t)sequenceForEvent:(id)event {
    if ([event isKindOfClass:[ATProtoFirehoseCommitEvent class]]) {
        return (int64_t)((ATProtoFirehoseCommitEvent *)event).seq;
    }
    if ([event isKindOfClass:[ATProtoFirehoseIdentityEvent class]]) {
        return (int64_t)((ATProtoFirehoseIdentityEvent *)event).seq;
    }
    if ([event isKindOfClass:[ATProtoFirehoseAccountEvent class]]) {
        return (int64_t)((ATProtoFirehoseAccountEvent *)event).seq;
    }
    if ([event isKindOfClass:[ATProtoFirehoseSyncEvent class]]) {
        return (int64_t)((ATProtoFirehoseSyncEvent *)event).seq;
    }
    if ([event isKindOfClass:[ATProtoFirehoseRawEvent class]]) {
        return [((ATProtoFirehoseRawEvent *)event).payload[@"seq"] longLongValue];
    }
    return 0;
}

- (void)submitEvent:(id)event fromClient:(ATProtoRelayClient *)client {
    NSString *url = [self urlForClient:client];
    if (!url) {
        return;
    }
    if (!self.ingressPipeline) {
        id<RelayUpstreamManagerDelegate> delegate = self.delegate;
        if (delegate) {
            [delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
        }
        return;
    }

    if ([self eventKindIsGatedAtIngress:event]) {
        // Admission and shard dispatch for this event already happened
        // synchronously in ATProtoFirehose's ingressGate (ADR 0039), before
        // this event was ever delivered through the RelayClientDelegate
        // chain that reached this method. Submitting again here would
        // double-admit and double-process the same event.
        return;
    }

    int64_t sequence = [self sequenceForEvent:event];
    uint64_t encodedBytes = [ATProtoRelayIngressPipeline encodedByteLengthForEvent:event];
    NSString *orderingKey = [ATProtoRelayIngressPipeline orderingKeyForEvent:event upstreamURL:url];
    NSError *submitError = nil;
    if ([self.ingressPipeline submitEvent:event
                             encodedBytes:encodedBytes
                              orderingKey:orderingKey
                             fromUpstream:url
                                 sequence:sequence
                                    error:&submitError]) {
        return;
    }

    GZ_LOG_SYNC_WARN(@"RelayUpstreamManager: rejected ingress event from %@: %@",
                     url, submitError.localizedDescription ?: @"backlog full");
}

#pragma mark - RelayIngressBackpressureDelegate

/*!
 Selective pause (F11 / R11): pauses the single connected, not-already-paused
 upstream currently holding the most in-flight backlog bytes, rather than
 every connected upstream. "Top-1" is deliberately the simplest defensible
 policy for this slice, not the most sophisticated one available -- see the
 design note in
 docs/plans/workstreams/17-zuk-relay-resource-bounds/phase-38-review-remediation.md
 for why, and for the Phase 42 hook (proportional/weighted selective
 pausing) if a single upstream proves insufficient to bring the backlog back
 under the low watermark under real load.

 -ingressPipeline's -inFlightByteCountByUpstream (backed by the same
 admitted-but-not-yet-released token tracking -noteUpstreamDisconnected:
 uses, F10) is the *current* in-flight backlog per upstream -- unlike a
 lifetime cumulative counter, it reflects who is contributing to the backlog
 right now. If that data is empty, or every connected-and-unpaused upstream
 shows zero in-flight bytes (e.g. the trip is driven by backlog whose
 admission accounting hasn't caught up, or some other edge case), this falls
 back to pausing everyone: a watermark trip must always result in some
 backpressure being applied.
 */
- (void)ingressPipelineDidRequestPause:(ATProtoRelayIngressPipeline *)pipeline {
    (void)pipeline;
    dispatch_async(_managerQueue, ^{
        NSDictionary<NSString *, NSNumber *> *inFlightByUpstream =
            self.ingressPipeline.inFlightByteCountByUpstream ?: @{};

        NSString *largestContributor = nil;
        uint64_t largestBytes = 0;
        for (NSString *url in [self.connectedUpstreams copy]) {
            if ([self.backpressurePausedUpstreams containsObject:url]) {
                continue;
            }
            uint64_t bytes = [inFlightByUpstream[url] unsignedLongLongValue];
            if (bytes > largestBytes) {
                largestBytes = bytes;
                largestContributor = url;
            }
        }

        NSSet<NSString *> *urlsToPause = largestContributor
            ? [NSSet setWithObject:largestContributor]
            : [self.connectedUpstreams copy];

        for (NSString *url in urlsToPause) {
            if ([self.backpressurePausedUpstreams containsObject:url]) {
                continue;
            }
            ATProtoRelayClient *client = self.upstreamClients[url];
            if (client && client.isConnected && !client.isReadingPaused) {
                [client pauseReading];
                [self.backpressurePausedUpstreams addObject:url];
                [[ATProtoRelayMetrics sharedMetrics] recordIngressUpstreamPause:url];
            }
        }
    });
}

- (void)ingressPipelineDidRequestResume:(ATProtoRelayIngressPipeline *)pipeline {
    (void)pipeline;
    dispatch_async(_managerQueue, ^{
        for (NSString *url in [self.backpressurePausedUpstreams copy]) {
            // Pause bookkeeping clears unconditionally: "is this url still
            // marked paused" is not generation-sensitive, only the act of
            // touching the underlying socket below is (F5). Skipping this on
            // a generation mismatch used to strand the url in the paused set
            // forever -- -ingressPipelineDidRequestPause: refuses to
            // re-track a url that is already present there, so a still-
            // connected client could never be paused or resumed again.
            [self.backpressurePausedUpstreams removeObject:url];

            NSNumber *generation = self.clientIngressGenerations[url];
            if (generation.unsignedIntegerValue != self.ingressGeneration) {
                // The connection this pause was recorded against may have
                // been superseded by a reconnect/reconfigure since; do not
                // manipulate whatever socket now lives at this url.
                continue;
            }
            ATProtoRelayClient *client = self.upstreamClients[url];
            if (client && client.isConnected && client.isReadingPaused) {
                [client resumeReading];
                [[ATProtoRelayMetrics sharedMetrics] recordIngressUpstreamResume:url];
            }
        }
    });
}

#pragma mark - RelayClientDelegate

- (void)recordEventKind:(NSString *)kind fromUpstream:(NSString *)url {
    dispatch_async(_managerQueue, ^{
        NSMutableDictionary<NSString *, NSNumber *> *counts = self.hostEventCounts[url];
        if (!counts) {
            counts = [NSMutableDictionary dictionary];
            self.hostEventCounts[url] = counts;
        }
        counts[kind] = @([counts[kind] unsignedLongLongValue] + 1);
        self.hostLastEventDates[url] = [NSDate date];
    });
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self recordEventKind:@"commit" fromUpstream:url];
    }
    [self submitEvent:event fromClient:client];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self recordEventKind:@"identity" fromUpstream:url];
    }
    [self submitEvent:event fromClient:client];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveAccountEvent:(ATProtoFirehoseAccountEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self recordEventKind:@"account" fromUpstream:url];
    }
    [self submitEvent:event fromClient:client];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveSyncEvent:(ATProtoFirehoseSyncEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self recordEventKind:@"sync" fromUpstream:url];
    }
    [self submitEvent:event fromClient:client];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveRawEvent:(ATProtoFirehoseRawEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self recordEventKind:@"raw" fromUpstream:url];
    }
    [self submitEvent:event fromClient:client];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveErrorEvent:(ATProtoFirehoseErrorEvent *)event {
    NSString *url = [self urlForClient:client];
    id<RelayUpstreamManagerDelegate> delegate = self.delegate;
    if (url) {
        [self recordEventKind:@"error" fromUpstream:url];
    }
    if (url && delegate) {
        [delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}

- (void)relayClientDidConnect:(ATProtoRelayClient *)client {
    NSString *url = [self urlForClient:client];
    if (url) {
        GZ_LOG_SYNC_INFO(@"RelayUpstreamManager: Client connected to %@", url);
        dispatch_async(_managerQueue, ^{
            [self.connectedUpstreams addObject:url];
            self.reconnectAttempts[url] = @0;
            self.reconnectDelays[url] = @(self.baseReconnectInterval);
            self.hostStatuses[url] = @(RelayHostStatusActive);
            self.hostConnectedDates[url] = [NSDate date];
            self.clientIngressGenerations[url] = @(self.ingressGeneration);
        });
        [[ATProtoRelayMetrics sharedMetrics] recordUpstreamConnected];
        id<RelayUpstreamManagerDelegate> delegate = self.delegate;
        if (delegate) {
            [delegate upstreamManager:self didConnectToUpstream:url];
        }
    }
}

- (void)relayClient:(ATProtoRelayClient *)client didDisconnectWithError:(NSError *)error {
    NSString *url = [self urlForClient:client];
    if (url) {
        dispatch_async(_managerQueue, ^{
            [self.connectedUpstreams removeObject:url];
            self.hostStatuses[url] = @(error ? RelayHostStatusError : RelayHostStatusDisconnected);
            [self.hostConnectedDates removeObjectForKey:url];
            [self.backpressurePausedUpstreams removeObject:url];
            [self.ingressPipeline noteUpstreamDisconnected:url];
        });
        [[ATProtoRelayMetrics sharedMetrics] recordUpstreamDisconnected];
        id<RelayUpstreamManagerDelegate> delegate = self.delegate;
        if (delegate) {
            [delegate upstreamManager:self didDisconnectFromUpstream:url error:error];
        }
        if (error) {
            [self scheduleReconnectForUpstream:url];
        }
    }
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveCursor:(int64_t)cursor {
    NSString *url = [self urlForClient:client];
    if (url) {
        dispatch_async(_managerQueue, ^{
            self.hostSeqs[url] = @(cursor);
        });
        [[ATProtoRelayMetrics sharedMetrics] recordSequence:cursor];
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

- (NSString *)urlForClient:(ATProtoRelayClient *)client {
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

- (uint64_t)eventCountForUpstream:(NSString *)url {
    __block uint64_t count = 0;
    [self performSynchronouslyOnManagerQueue:^{
        for (NSNumber *kindCount in self.hostEventCounts[url].allValues) {
            count += kindCount.unsignedLongLongValue;
        }
    }];
    return count;
}

- (NSDictionary<NSString *, NSNumber *> *)eventCountsByKindForUpstream:(NSString *)url {
    __block NSDictionary<NSString *, NSNumber *> *counts = nil;
    [self performSynchronouslyOnManagerQueue:^{
        counts = [self.hostEventCounts[url] copy] ?: @{};
    }];
    return counts;
}

- (NSDate *)lastEventAtForUpstream:(NSString *)url {
    __block NSDate *date = nil;
    [self performSynchronouslyOnManagerQueue:^{
        date = [self.hostLastEventDates[url] copy];
    }];
    return date;
}

- (NSDate *)connectedAtForUpstream:(NSString *)url {
    __block NSDate *date = nil;
    [self performSynchronouslyOnManagerQueue:^{
        date = [self.hostConnectedDates[url] copy];
    }];
    return date;
}

- (NSUInteger)reconnectAttemptsForUpstream:(NSString *)url {
    __block NSUInteger attempts = 0;
    [self performSynchronouslyOnManagerQueue:^{
        attempts = [self.reconnectAttempts[url] unsignedIntegerValue];
    }];
    return attempts;
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
