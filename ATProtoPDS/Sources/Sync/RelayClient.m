#import "Sync/RelayClient.h"
#import "Compat/PDSTypes.h"
#import "Sync/Firehose.h"
#import "Sync/WebSocketConnection.h"

NSString * const RelayClientErrorDomain = @"com.atproto.pds.relay.client";
NSInteger const RelayClientErrorCodeConnectionFailed = 4000;
NSInteger const RelayClientErrorCodeAuthenticationFailed = 4001;

@interface RelayClient () <FirehoseSubscriptionDelegate>

@property (nonatomic, strong, readwrite) NSURL *serverURL;
@property (nonatomic, copy, readwrite, nullable) NSString *accessToken;
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, assign, readwrite) NSTimeInterval reconnectInterval;
@property (nonatomic, assign, readwrite) NSInteger maxReconnectAttempts;
@property (nonatomic, assign, readwrite) NSInteger reconnectAttempts;
@property (nonatomic, strong, readwrite, nullable) Firehose *firehose;
@property (nonatomic, strong, readwrite, nullable) FirehoseSubscription *subscription;
@property (nonatomic, assign, readwrite) int64_t currentSeq;
@property (nonatomic, strong, readwrite) NSMutableDictionary<NSString *, NSNumber *> *cursorStorage;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, readwrite) dispatch_queue_t storageQueue;

@end

@implementation RelayClient

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
    }
    return self;
}

- (void)connect {
    self.reconnectAttempts = 0;
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

    self.firehose = [[Firehose alloc] initWithServerURL:wsURL];
    self.subscription = [self.firehose subscribeWithCursor:self.currentSeq
                                                collections:nil
                                                  delegate:self];
    [self.firehose connect];
}

- (NSURL *)buildWebSocketURL {
    NSString *scheme = @"wss";
    if ([self.serverURL.scheme.lowercaseString isEqualToString:@"https"]) {
        scheme = @"wss";
    }

    NSString *host = self.serverURL.host;
    uint16_t port = self.serverURL.port ? [self.serverURL.port intValue] : 443;

    NSString *path = @"/xrpc/com.atproto.sync.subscribeRepos";

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = scheme;
    components.host = host;
    components.port = @(port);
    components.path = path;

    if (self.currentSeq > 0) {
        components.query = [NSString stringWithFormat:@"cursor=%lld", self.currentSeq];
    }

    return components.URL;
}

- (void)disconnect {
    [self.subscription cancel];
    [self.firehose disconnect];
    self.firehose = nil;
    self.subscription = nil;
    self.isConnected = NO;
}

- (void)setAccessToken:(NSString *)accessToken {
    self.accessToken = [accessToken copy];

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
        self.cursorStorage[repo] = @(cursor);
    });
}

- (void)notifyDisconnectionWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate relayClient:self didDisconnectWithError:error];
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.isConnected) {
            [self establishConnection];
        }
    });
}

#pragma mark - FirehoseSubscriptionDelegate

- (void)firehoseSubscriptionDidConnect:(FirehoseSubscription *)subscription {
    self.isConnected = YES;
    self.reconnectAttempts = 0;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate relayClientDidConnect:self];
    });
}

- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    // Phase 5: Use seq as cursor per ATProto spec
    [self storeCursor:event.seq forRepo:event.repo];
    self.currentSeq = event.seq;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate relayClient:self didReceiveCommitEvent:event];
    });
}

- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveIdentityEvent:(FirehoseIdentityEvent *)event {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate relayClient:self didReceiveIdentityEvent:event];
    });
}

- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveErrorEvent:(FirehoseErrorEvent *)event {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate relayClient:self didReceiveErrorEvent:event];
    });
}

- (void)firehoseSubscription:(FirehoseSubscription *)subscription didCloseWithError:(NSError *)error {
    self.isConnected = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate relayClient:self didReceiveCursor:self.currentSeq];
    });

    if (error) {
        [self scheduleReconnect];
    }
}

@end
