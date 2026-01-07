#import "Firehose.h"
#import "WebSocketConnection.h"
#import "EventFormatter.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const FirehoseErrorDomain = @"com.atproto.pds.firehose";
NSInteger const FirehoseErrorCodeSubscriptionFailed = 3000;
NSInteger const FirehoseErrorCodeEventEncodingFailed = 3001;
NSInteger const FirehoseErrorCodeSubscriptionClosed = 3002;

@implementation FirehoseCommitEvent

+ (instancetype)eventWithRepo:(NSString *)repo commit:(NSString *)commit ops:(NSArray<NSDictionary *> *)ops {
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = repo;
    event.commit = commit;
    event.ops = ops;
    return event;
}

@end

@implementation FirehoseIdentityEvent

+ (instancetype)eventWithDid:(NSString *)did {
    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
    event.did = did;
    return event;
}

@end

@implementation FirehoseErrorEvent

+ (instancetype)eventWithMessage:(NSString *)message {
    FirehoseErrorEvent *event = [[FirehoseErrorEvent alloc] init];
    event.message = message;
    return event;
}

@end

@interface FirehoseSubscription ()

@property (nonatomic, copy, nullable) NSString *cursor;
@property (nonatomic, copy, nullable) NSArray<NSString *> *collections;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, weak, nullable) id<FirehoseSubscriptionDelegate> delegate;
@property (nonatomic, weak, nullable) Firehose *firehose;

@end

@implementation FirehoseSubscription

- (instancetype)initWithCursor:(NSString *)cursor collections:(NSArray<NSString *> *)collections {
    self = [super init];
    if (self) {
        _cursor = cursor;
        _collections = collections;
        _isActive = YES;
    }
    return self;
}

- (void)cancel {
    self.isActive = NO;
}

@end

@interface Firehose () <WebSocketConnectionDelegate>

@property (nonatomic, strong) NSURL *serverURL;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, weak, nullable) id<FirehoseSubscriptionDelegate> delegate;
@property (nonatomic, strong) WebSocketConnection *connection;
@property (nonatomic, strong) NSMutableSet<FirehoseSubscription *> *subscriptions;
@property (nonatomic, strong) EventFormatter *eventFormatter;
@property (nonatomic, strong) NSMutableDictionary<NSString *, FirehoseSubscription *> *subscriptionsByCursor;

@end

@implementation Firehose

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    self = [super init];
    if (self) {
        _serverURL = serverURL;
        _isConnected = NO;
        _subscriptions = [NSMutableSet set];
        _subscriptionsByCursor = [NSMutableDictionary dictionary];
        _eventFormatter = [[EventFormatter alloc] init];
    }
    return self;
}

- (FirehoseSubscription *)subscribeWithCursor:(NSString *)cursor
                                   collections:(NSArray<NSString *> *)collections
                                     delegate:(id<FirehoseSubscriptionDelegate>)delegate {
    FirehoseSubscription *subscription = [[FirehoseSubscription alloc] initWithCursor:cursor
                                                                           collections:collections];
    subscription.delegate = delegate;
    subscription.firehose = self;

    [self.subscriptions addObject:subscription];

    if (cursor) {
        self.subscriptionsByCursor[cursor] = subscription;
    }

    if (self.isConnected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [subscription.delegate firehoseSubscriptionDidConnect:subscription];
        });
    }

    return subscription;
}

- (void)connect {
    NSString *host = self.serverURL.host ?: @"bsky.social";
    uint16_t port = self.serverURL.port ?: (self.serverURL.scheme.lowercaseString.https ? 443 : 80);
    NSString *path = [NSString stringWithFormat:@"/xrpc/com.atproto.server.subscribeRepos"];

    BOOL useTLS = [self.serverURL.scheme.lowercaseString isEqualToString:@"wss"] ||
                  [self.serverURL.scheme.lowercaseString isEqualToString:@"https"];

    NSString *effectiveHost = useTLS ? host : host;
    uint16_t effectivePort = useTLS ? 443 : port;

    self.connection = [[WebSocketConnection alloc] initWithHost:effectiveHost
                                                           port:effectivePort
                                                           path:path];
    self.connection.delegate = self;

    NSMutableArray<NSString *> *queryParams = [NSMutableArray array];
    for (FirehoseSubscription *subscription in self.subscriptions) {
        if (subscription.cursor) {
            NSString *escapedCursor = [subscription.cursor stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            [queryParams addObject:[NSString stringWithFormat:@"cursor=%@", escapedCursor]];
        }
        if (subscription.collections.count > 0) {
            NSString *collectionsStr = [subscription.collections componentsJoinedByString:@","];
            NSString *escapedCollections = [collectionsStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            [queryParams addObject:[NSString stringWithFormat:@"collections=%@", escapedCollections]];
        }
        break;
    }

    NSError *error = nil;
    [self.connection connect:&error];

    if (error) {
        [self notifyConnectionError:error];
    }
}

- (void)disconnect {
    [self.connection close];
    self.connection = nil;
    self.isConnected = NO;
}

- (void)sendEventToSubscriptions:(id)event kind:(FirehoseEventKind)kind {
    for (FirehoseSubscription *subscription in self.subscriptions) {
        if (!subscription.isActive) continue;

        dispatch_async(dispatch_get_main_queue(), ^{
            switch (kind) {
                case FirehoseEventKindCommit:
                    [subscription.delegate firehoseSubscription:subscription didReceiveCommitEvent:event];
                    break;
                case FirehoseEventKindIdentity:
                    [subscription.delegate firehoseSubscription:subscription didReceiveIdentityEvent:event];
                    break;
                case FirehoseEventKindError:
                    [subscription.delegate firehoseSubscription:subscription didReceiveErrorEvent:event];
                    break;
            }
        });
    }
}

- (void)handleMessage:(NSData *)data {
    NSError *error = nil;
    id message = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (error || ![message isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSString *kind = message[@"kind"];

    if ([kind isEqualToString:@"commit"]) {
        NSArray *ops = message[@"ops"];
        NSArray *blobs = message[@"blobs"];

        FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
        event.repo = message[@"repo"];
        event.commit = message[@"commit"];
        event.previous = message[@"previous"];
        event.ops = ops ?: @[];
        event.blobs = blobs;

        [self sendEventToSubscriptions:event kind:FirehoseEventKindCommit];

    } else if ([kind isEqualToString:@"identity"]) {
        FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
        event.did = message[@"did"];

        [self sendEventToSubscriptions:event kind:FirehoseEventKindIdentity];

    } else if ([kind isEqualToString:@"error"]) {
        FirehoseErrorEvent *event = [[FirehoseErrorEvent alloc] init];
        event.message = message[@"message"];

        [self sendEventToSubscriptions:event kind:FirehoseEventKindError];
    }
}

- (void)notifyConnectionError:(NSError *)error {
    for (FirehoseSubscription *subscription in self.subscriptions) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [subscription.delegate firehoseSubscription:subscription didCloseWithError:error];
        });
    }
}

#pragma mark - WebSocketConnectionDelegate

- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveMessage:(NSData *)message {
    [self handleMessage:message];
}

- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveText:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    [self handleMessage:data];
}

- (void)webSocketConnection:(WebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason {
    self.isConnected = NO;

    for (FirehoseSubscription *subscription in self.subscriptions) {
        NSError *error = nil;
        if (code != 1000) {
            error = [NSError errorWithDomain:FirehoseErrorDomain
                                        code:FirehoseErrorCodeSubscriptionClosed
                                    userInfo:@{NSLocalizedDescriptionKey: reason ?: @"Connection closed"}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [subscription.delegate firehoseSubscription:subscription didCloseWithError:error];
        });
    }
}

- (void)webSocketConnection:(WebSocketConnection *)connection didFailWithError:(NSError *)error {
    [self notifyConnectionError:error];
}

- (void)webSocketConnectionStateDidChange:(WebSocketConnection *)connection {
    if (connection.state == WebSocketConnectionStateConnected) {
        self.isConnected = YES;

        for (FirehoseSubscription *subscription in self.subscriptions) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [subscription.delegate firehoseSubscriptionDidConnect:subscription];
            });
        }
    }
}

@end
