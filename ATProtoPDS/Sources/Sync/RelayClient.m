#import "Sync/RelayClient.h"
#import "Sync/Firehose.h"
#import "Sync/WebSocketConnection.h"

NSString * const RelayClientErrorDomain = @"com.atproto.pds.relay.client";
NSInteger const RelayClientErrorCodeConnectionFailed = 4000;
NSInteger const RelayClientErrorCodeAuthenticationFailed = 4001;

@interface RelayClient () <FirehoseSubscriptionDelegate>

@property (nonatomic, strong, readwrite) NSURL *serverURL;
@property (nonatomic, copy, readwrite, nullable) NSString *accessToken;
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, weak, readwrite, nullable) id<RelayClientDelegate> delegate;
@property (nonatomic, copy, readwrite, nullable) NSString *currentCursor;
@property (nonatomic, assign, readwrite) NSTimeInterval reconnectInterval;
@property (nonatomic, assign, readwrite) NSInteger maxReconnectAttempts;
@property (nonatomic, assign, readwrite) NSInteger reconnectAttempts;
@property (nonatomic, strong, readwrite, nullable) Firehose *firehose;
@property (nonatomic, strong, readwrite, nullable) FirehoseSubscription *subscription;
@property (nonatomic, strong, readwrite) NSMutableDictionary<NSString *, NSString *> *cursorStorage;
#if defined(__linux__) || defined(__GNUstep__)
@property (nonatomic, assign, readwrite) dispatch_queue_t storageQueue;
#else
@property (nonatomic, strong, readwrite) dispatch_queue_t storageQueue;
#endif

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
    self.subscription = [self.firehose subscribeWithCursor:self.currentCursor
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

    NSString *path = @"/xrpc/com.atproto.server.subscribeRepos";

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = scheme;
    components.host = host;
    components.port = @(port);
    components.path = path;

    if (self.currentCursor) {
        NSString *encodedCursor = [self.currentCursor stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        components.query = [NSString stringWithFormat:@"cursor=%@", encodedCursor];
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

- (NSString *)getStoredCursorForRepo:(NSString *)repo {
    __block NSString *cursor = nil;
    dispatch_sync(self.storageQueue, ^{
        cursor = self.cursorStorage[repo];
    });
    return cursor;
}

- (void)storeCursor:(NSString *)cursor forRepo:(NSString *)repo {
    dispatch_async(self.storageQueue, ^{
        self.cursorStorage[repo] = cursor;
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
    [self storeCursor:event.commit forRepo:event.repo];
    self.currentCursor = event.commit;

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
        [self.delegate relayClient:self didReceiveCursor:self.currentCursor ?: @""];
    });

    if (error) {
        [self scheduleReconnect];
    }
}

@end
