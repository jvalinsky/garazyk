// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayClient.h"
#import "Compat/PDSTypes.h"
#import "Sync/Firehose/Firehose.h"
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Debug/GZLogger.h"

NSString * const RelayClientErrorDomain = @"com.atproto.pds.relay.client";
NSInteger const RelayClientErrorCodeConnectionFailed = 4000;
NSInteger const RelayClientErrorCodeAuthenticationFailed = 4001;

static void *RelayClientSequenceQueueKey = &RelayClientSequenceQueueKey;

@interface ATProtoRelayClient () <FirehoseSubscriptionDelegate> {
    BOOL _readingPaused;
    BOOL _shouldReconnect;
    dispatch_queue_t _sequenceQueue;
    // Backing storage for currentSeq/lastReceivedSequence, declared
    // explicitly because both properties get fully custom (queue-confined)
    // getters and setters below, which suppresses ivar auto-synthesis.
    int64_t _currentSeq;
    int64_t _lastReceivedSequence;
}

@property (nonatomic, strong, readwrite) NSURL *serverURL;
@property (nonatomic, copy, readwrite, nullable) NSString *accessToken;
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, assign, readwrite) NSTimeInterval reconnectInterval;
@property (nonatomic, assign, readwrite) NSInteger maxReconnectAttempts;
@property (nonatomic, assign, readwrite) NSInteger reconnectAttempts;
@property (nonatomic, strong, readwrite, nullable) ATProtoFirehose *firehose;
@property (nonatomic, strong, readwrite, nullable) ATProtoFirehoseSubscription *subscription;
// currentSeq/lastReceivedSequence get custom accessors below that confine
// every read and write to _sequenceQueue (see F7): establishConnection and
// scheduleReconnect's dispatch_after touch these from _managerQueue and
// self.callbackQueue, noteIncomingSequence: touches them from the main
// queue (via ATProtoFirehose.sendEventToSubscriptions:), and
// acknowledgeProcessedSequence: touches them from RelayIngressPipeline's
// shard queues -- at least three distinct GCD queues doing unguarded
// read-modify-write on plain int64_t properties otherwise.
@property (nonatomic, assign, readwrite) int64_t currentSeq;
@property (nonatomic, assign, readwrite) int64_t lastReceivedSequence;
@property (nonatomic, strong, readwrite) NSMutableDictionary<NSString *, NSNumber *> *cursorStorage;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, readwrite) dispatch_queue_t storageQueue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, readwrite) dispatch_queue_t callbackQueue;

@end

@implementation ATProtoRelayClient

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    return [self initWithServerURL:serverURL accessToken:nil];
}

- (instancetype)initWithServerURL:(NSURL *)serverURL accessToken:(NSString *)accessToken {
    self = [super init];
    if (self) {
        _serverURL = serverURL;
        _accessToken = [accessToken copy];
        _isConnected = NO;
        _reconnectInterval = 5.0;
        _maxReconnectAttempts = 10;
        _reconnectAttempts = 0;
        _cursorStorage = [NSMutableDictionary dictionary];
        _storageQueue = dispatch_queue_create("com.atproto.pds.relay.storage", DISPATCH_QUEUE_SERIAL);
        _callbackQueue = dispatch_queue_create("com.atproto.pds.relay.callback", DISPATCH_QUEUE_SERIAL);
        _sequenceQueue = dispatch_queue_create("com.atproto.pds.relay.sequence", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_sequenceQueue,
                                    RelayClientSequenceQueueKey,
                                    (__bridge void *)self,
                                    NULL);
    }
    return self;
}

- (void)performOnSequenceQueue:(dispatch_block_t)block {
    if (dispatch_get_specific(RelayClientSequenceQueueKey) == (__bridge void *)self) {
        block();
    } else {
        dispatch_sync(_sequenceQueue, block);
    }
}

- (int64_t)currentSeq {
    __block int64_t value = 0;
    [self performOnSequenceQueue:^{
        value = self->_currentSeq;
    }];
    return value;
}

- (void)setCurrentSeq:(int64_t)currentSeq {
    [self performOnSequenceQueue:^{
        self->_currentSeq = currentSeq;
    }];
}

- (int64_t)lastReceivedSequence {
    __block int64_t value = 0;
    [self performOnSequenceQueue:^{
        value = self->_lastReceivedSequence;
    }];
    return value;
}

- (void)setLastReceivedSequence:(int64_t)lastReceivedSequence {
    [self performOnSequenceQueue:^{
        self->_lastReceivedSequence = lastReceivedSequence;
    }];
}

- (void)connect {
    self.reconnectAttempts = 0;
    _shouldReconnect = YES;
    [self establishConnection];
}

- (void)establishConnection {
    NSURL *wsURL = [self buildWebSocketURL];
    if (!wsURL) {
        NSError *error = [NSError errorWithDomain:RelayClientErrorDomain
                                             code:RelayClientErrorCodeConnectionFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to build WebSocket URL"}];
        [self notifyDisconnectionWithError:error];
        return;
    }

    // Reset the high-water mark to the reconnect cursor so frames the relay
    // replays from self.currentSeq are accepted by noteIncomingSequence:
    // instead of being dropped as duplicates of the pre-disconnect stream.
    self.lastReceivedSequence = self.currentSeq;

    self.firehose = [self configuredFirehoseForWebSocketURL:wsURL];
    self.subscription = [self.firehose subscribeWithCursor:self.currentSeq
                                                collections:nil
                                                  delegate:self];
    GZ_LOG_SYNC_INFO(@"RelayClient: Connecting to %@ (cursor=%lld)", wsURL, (long long)self.currentSeq);
    [self.firehose connect];
}

- (ATProtoFirehose *)configuredFirehoseForWebSocketURL:(NSURL *)webSocketURL {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:webSocketURL];
    firehose.accessToken = self.accessToken;
    firehose.ingressGate = self.ingressGate;
    return firehose;
}

- (NSURL *)buildWebSocketURL {
    NSString *inputScheme = self.serverURL.scheme.lowercaseString ?: @"";
    NSString *scheme = @"wss";
    if ([inputScheme isEqualToString:@"ws"] || [inputScheme isEqualToString:@"wss"]) {
        scheme = inputScheme;
    } else if ([inputScheme isEqualToString:@"http"]) {
        scheme = @"ws";
    } else if ([inputScheme isEqualToString:@"https"]) {
        scheme = @"wss";
    }

    NSString *host = self.serverURL.host;
    BOOL secureTLS = [scheme isEqualToString:@"wss"];
    uint16_t port = self.serverURL.port ? [self.serverURL.port intValue] : (secureTLS ? 443 : 80);

    NSString *path = @"/xrpc/com.atproto.sync.subscribeRepos";

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = scheme;
    components.host = host;
    components.port = @(port);
    components.path = path;

    if (self.currentSeq > 0) {
        components.query = [NSString stringWithFormat:@"cursor=%lld", (long long)self.currentSeq];
    }

    return components.URL;
}

- (void)disconnect {
    _readingPaused = NO;
    _shouldReconnect = NO;
    [self.subscription cancel];
    [self.firehose disconnect];
    self.firehose = nil;
    self.subscription = nil;
    self.isConnected = NO;
}

- (void)pauseReading {
    if (_readingPaused) return;
    _readingPaused = YES;
    [self.firehose suspendReading];
    GZ_LOG_SYNC_INFO(@"RelayClient: paused reading from %@", self.serverURL);
}

- (void)resumeReading {
    if (!_readingPaused) return;
    _readingPaused = NO;
    [self.firehose resumeReading];
    GZ_LOG_SYNC_INFO(@"RelayClient: resumed reading from %@", self.serverURL);
}

- (BOOL)isReadingPaused {
    return _readingPaused;
}

- (void)setAccessToken:(NSString *)accessToken {
    _accessToken = [accessToken copy];

    if (self.isConnected) {
        [self disconnect];
        [self connect];
    }
}

- (int64_t)getStoredCursorForRepo:(NSString *)repo {
    __block int64_t cursor = 0;
    dispatch_sync(self.storageQueue, ^{
        cursor = [self.cursorStorage[repo] longLongValue];
    });
    return cursor;
}

- (void)storeCursor:(int64_t)cursor forRepo:(NSString *)repo {
    dispatch_async(self.storageQueue, ^{
        NSNumber *storedCursor = self.cursorStorage[repo];
        if (!storedCursor || cursor > storedCursor.longLongValue) {
            self.cursorStorage[repo] = @(cursor);
        }
    });
}

- (BOOL)noteIncomingSequence:(int64_t)sequence {
    if (sequence <= 0) {
        return YES;
    }
    BOOL reconnectUsesProcessedCursor = self.reconnectUsesProcessedCursor;
    __block BOOL accepted = YES;
    // Single queue-confined block so the lastReceivedSequence
    // check-then-set is one atomic operation rather than two separate
    // get/set round trips that another queue could interleave between.
    [self performOnSequenceQueue:^{
        if (self->_lastReceivedSequence > 0 && sequence <= self->_lastReceivedSequence) {
            accepted = NO;
            return;
        }
        self->_lastReceivedSequence = sequence;
        if (!reconnectUsesProcessedCursor) {
            self->_currentSeq = sequence;
        }
    }];
    return accepted;
}

- (void)acknowledgeProcessedSequence:(int64_t)sequence {
    // Single queue-confined block: the "if greater, advance" check must be
    // atomic against concurrent calls from other RelayIngressPipeline shard
    // queues, not just individually torn-read-safe.
    [self performOnSequenceQueue:^{
        if (sequence > self->_currentSeq) {
            self->_currentSeq = sequence;
        }
    }];
}

- (void)notifyDisconnectionWithError:(NSError *)error {
    id<RelayClientDelegate> delegate = self.delegate;  // Capture strongly
    dispatch_async(self.callbackQueue, ^{
        if (delegate) {
            [delegate relayClient:self didDisconnectWithError:error];
        }
    });
}

- (void)scheduleReconnect {
    if (self.reconnectAttempts >= self.maxReconnectAttempts) {
        NSError *error = [NSError errorWithDomain:RelayClientErrorDomain
                                             code:RelayClientErrorCodeConnectionFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Max reconnect attempts reached"}];
        [self notifyDisconnectionWithError:error];
        return;
    }

    self.reconnectAttempts++;

    NSTimeInterval delay = self.reconnectInterval * pow(1.5, self.reconnectAttempts - 1);
    delay = MIN(delay, 60.0);

    GZ_LOG_SYNC_INFO(@"RelayClient: Scheduling reconnect to %@ (attempt=%ld/%ld, delay=%.1fs, cursor=%lld)",
                       self.serverURL, (long)self.reconnectAttempts, (long)self.maxReconnectAttempts,
                       delay, (long long)self.currentSeq);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self.callbackQueue, ^{
        if (self->_shouldReconnect && !self.isConnected) {
            [self establishConnection];
        }
    });
}

#pragma mark - FirehoseSubscriptionDelegate

- (void)firehoseSubscriptionDidConnect:(ATProtoFirehoseSubscription *)subscription {
    self.isConnected = YES;
    self.reconnectAttempts = 0;

    id<RelayClientDelegate> delegate = self.delegate;  // Capture strongly
    dispatch_async(self.callbackQueue, ^{
        if (delegate) {
            [delegate relayClientDidConnect:self];
        }
    });
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event {
    if (![self noteIncomingSequence:event.seq]) {
        GZ_LOG_SYNC_WARN(@"RelayClient: Dropping non-monotonic commit sequence %lld (received=%lld)",
                         (long long)event.seq, (long long)self.lastReceivedSequence);
        return;
    }

    [self storeCursor:event.seq forRepo:event.repo];

    id<RelayClientDelegate> delegate = self.delegate;  // Capture strongly
    dispatch_async(self.callbackQueue, ^{
        if (delegate) {
            [delegate relayClient:self didReceiveCommitEvent:event];
        }
    });
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event {
    if (![self noteIncomingSequence:event.seq]) {
        GZ_LOG_SYNC_WARN(@"RelayClient: Dropping non-monotonic identity sequence %lld (received=%lld)",
                         (long long)event.seq, (long long)self.lastReceivedSequence);
        return;
    }

    id<RelayClientDelegate> delegate = self.delegate;  // Capture strongly
    dispatch_async(self.callbackQueue, ^{
        if (delegate) {
            [delegate relayClient:self didReceiveIdentityEvent:event];
        }
    });
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveAccountEvent:(ATProtoFirehoseAccountEvent *)event {
    if (![self noteIncomingSequence:event.seq]) {
        GZ_LOG_SYNC_WARN(@"RelayClient: Dropping non-monotonic account sequence %lld (received=%lld)",
                         (long long)event.seq, (long long)self.lastReceivedSequence);
        return;
    }

    id<RelayClientDelegate> delegate = self.delegate;  // Capture strongly
    dispatch_async(self.callbackQueue, ^{
        if (delegate && [delegate respondsToSelector:@selector(relayClient:didReceiveAccountEvent:)]) {
            [delegate relayClient:self didReceiveAccountEvent:event];
        }
    });
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveSyncEvent:(ATProtoFirehoseSyncEvent *)event {
    if (![self noteIncomingSequence:event.seq]) {
        GZ_LOG_SYNC_WARN(@"RelayClient: Dropping non-monotonic sync sequence %lld (received=%lld)",
                         (long long)event.seq, (long long)self.lastReceivedSequence);
        return;
    }

    id<RelayClientDelegate> delegate = self.delegate;
    dispatch_async(self.callbackQueue, ^{
        if (delegate &&
            [delegate respondsToSelector:@selector(relayClient:didReceiveSyncEvent:)]) {
            [delegate relayClient:self didReceiveSyncEvent:event];
        }
    });
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveRawEvent:(ATProtoFirehoseRawEvent *)event {
    if (event.payload[@"seq"] != nil) {
        int64_t sequence = [event.payload[@"seq"] longLongValue];
        if (![self noteIncomingSequence:sequence]) {
            GZ_LOG_SYNC_WARN(@"RelayClient: Dropping non-monotonic raw sequence %lld (received=%lld)",
                             (long long)sequence, (long long)self.lastReceivedSequence);
            return;
        }
    }
    id<RelayClientDelegate> delegate = self.delegate;
    dispatch_async(self.callbackQueue, ^{
        if (delegate && [delegate respondsToSelector:@selector(relayClient:didReceiveRawEvent:)]) {
            [delegate relayClient:self didReceiveRawEvent:event];
        }
    });
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveErrorEvent:(ATProtoFirehoseErrorEvent *)event {
    GZ_LOG_SYNC_WARN(@"RelayClient: Received error from relay: error=%@ message=%@", event.error, event.message);

    id<RelayClientDelegate> delegate = self.delegate;  // Capture strongly
    dispatch_async(self.callbackQueue, ^{
        if (delegate) {
            [delegate relayClient:self didReceiveErrorEvent:event];
        }
    });
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didCloseWithError:(NSError *)error {
    self.isConnected = NO;

    NSNumber *closeCode = error.userInfo[FirehoseCloseCodeKey];
    NSString *closeReason = error.userInfo[FirehoseCloseReasonKey] ?: error.localizedDescription;
    BOOL backpressure = FirehoseErrorIsBackpressureClose(error);
    GZ_LOG_SYNC_WARN(@"RelayClient: Firehose closed from %@ (code=%@ reason=%@ backpressure=%@ currentSeq=%lld)",
                       self.serverURL,
                       closeCode ?: @"-",
                       closeReason ?: @"clean",
                       backpressure ? @"YES" : @"NO",
                       (long long)self.currentSeq);

    id<RelayClientDelegate> delegate = self.delegate;  // Capture strongly
    int64_t seq = self.currentSeq;  // Capture value
    dispatch_async(self.callbackQueue, ^{
        if (delegate) {
            [delegate relayClient:self didReceiveCursor:seq];
        }
    });

    if (_shouldReconnect) {
        [self scheduleReconnect];
    }
}

@end
