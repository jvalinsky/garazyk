#import "Sync/Firehose/Firehose.h"
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Core/ATProtoDagCBOR.h"
#import "Sync/Relay/EventFormatter.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

NSString * const FirehoseErrorDomain = @"com.atproto.pds.firehose";
NSInteger const FirehoseErrorCodeSubscriptionFailed = 6000;
NSInteger const FirehoseErrorCodeEventEncodingFailed = 6001;
NSInteger const FirehoseErrorCodeSubscriptionClosed = 6002;

@interface FirehoseSubscription ()
@property (nonatomic, assign, readwrite) int64_t cursor;
@property (nonatomic, copy, readwrite, nullable) NSArray<NSString *> *collections;
@property (nonatomic, assign, readwrite) BOOL isActive;
@property (nonatomic, weak, readwrite, nullable) id<FirehoseSubscriptionDelegate> delegate;
@end

@interface Firehose () <WebSocketConnectionDelegate>
@property (nonatomic, strong, readwrite) NSURL *serverURL;
@property (nonatomic, assign, readwrite) int64_t cursor;
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, strong, readwrite, nullable) WebSocketConnection *connection;
@property (nonatomic, strong, readwrite) NSMutableSet<FirehoseSubscription *> *subscriptions;
@property (nonatomic, strong, readwrite) EventFormatter *eventFormatter;
@end

@implementation Firehose

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    self = [super init];
    if (self) {
        _serverURL = serverURL;
        _isConnected = NO;
        _subscriptions = [NSMutableSet set];
        _eventFormatter = [[EventFormatter alloc] init];
    }
    return self;
}

- (FirehoseSubscription *)subscribeWithCursor:(int64_t)cursor
                                   collections:(nullable NSArray<NSString *> *)collections
                                     delegate:(nullable id<FirehoseSubscriptionDelegate>)delegate {
    self.cursor = cursor;
    FirehoseSubscription *subscription = [[FirehoseSubscription alloc] initWithCursor:cursor
                                                                           collections:collections];
    subscription.delegate = delegate;

    [self.subscriptions addObject:subscription];

    if (self.isConnected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([subscription.delegate respondsToSelector:@selector(firehoseSubscriptionDidConnect:)]) {
                [subscription.delegate firehoseSubscriptionDidConnect:subscription];
            }
        });
    }

    return subscription;
}

- (void)connect {
    NSString *host = self.serverURL.host ?: @"localhost";
    NSNumber *portNum = self.serverURL.port;
    uint16_t port = portNum ? (uint16_t)[portNum intValue] : ([self.serverURL.scheme.lowercaseString isEqualToString:@"https"] ? 443 : 80);
    NSString *path = @"/xrpc/com.atproto.sync.subscribeRepos";
    
    if (self.cursor > 0) {
        path = [path stringByAppendingFormat:@"?cursor=%lld", (long long)self.cursor];
    }

    PDS_LOG_SYNC_INFO(@"Firehose: Connecting to %@:%u%@ (scheme: %@)", host, port, path, self.serverURL.scheme);

    self.connection = [[WebSocketConnection alloc] initWithHost:host port:port path:path];
    self.connection.delegate = self;

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

- (NSTimeInterval)heartbeatTimeout {
    return self.connection.heartbeatTimeout;
}

- (void)setHeartbeatTimeout:(NSTimeInterval)heartbeatTimeout {
    self.connection.heartbeatTimeout = heartbeatTimeout;
}

- (void)sendEventToSubscriptions:(id)event kind:(FirehoseEventKind)kind {
    for (FirehoseSubscription *subscription in self.subscriptions) {
        if (!subscription.isActive) continue;

        dispatch_async(dispatch_get_main_queue(), ^{
            switch (kind) {
                case FirehoseEventKindCommit:
                    if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didReceiveCommitEvent:)]) {
                        [subscription.delegate firehoseSubscription:subscription didReceiveCommitEvent:event];
                    }
                    break;
                case FirehoseEventKindIdentity:
                    if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didReceiveIdentityEvent:)]) {
                        [subscription.delegate firehoseSubscription:subscription didReceiveIdentityEvent:event];
                    }
                    break;
                case FirehoseEventKindAccount:
                    if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didReceiveAccountEvent:)]) {
                        [subscription.delegate firehoseSubscription:subscription didReceiveAccountEvent:event];
                    }
                    break;
                case FirehoseEventKindSync:
                    if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didReceiveSyncEvent:)]) {
                        [subscription.delegate firehoseSubscription:subscription didReceiveSyncEvent:event];
                    }
                    break;
                case FirehoseEventKindInfo:
                    if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didReceiveInfoEvent:)]) {
                        [subscription.delegate firehoseSubscription:subscription didReceiveInfoEvent:event];
                    }
                    break;
                case FirehoseEventKindError:
                    if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didReceiveErrorEvent:)]) {
                        [subscription.delegate firehoseSubscription:subscription didReceiveErrorEvent:event];
                    }
                    break;
            }
        });
    }
}

- (void)handleMessage:(NSData *)data {
    PDS_LOG_SYNC_DEBUG(@"Firehose received message of length %lu", (unsigned long)data.length);
    NSInteger op = 0;
    NSString *msgType = nil;
    NSError *error = nil;
    
    NSDictionary *payload = [self.eventFormatter decodeEventFromData:data op:&op msgType:&msgType error:&error];
    if (!payload || error) {
        PDS_LOG_SYNC_ERROR(@"Failed to decode firehose frame: %@", error);
        return;
    }
    
    PDS_LOG_SYNC_DEBUG(@"Decoded firehose frame: op=%ld type=%@", (long)op, msgType);

    if (op == -1) { // Error frame
        FirehoseErrorEvent *event = [[FirehoseErrorEvent alloc] init];
        event.error = payload[@"error"];
        event.message = payload[@"message"];
        [self sendEventToSubscriptions:event kind:FirehoseEventKindError];
        return;
    }

    if ([msgType isEqualToString:@"#commit"]) {
        FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
        event.seq = [payload[@"seq"] longLongValue];
        event.rebase = [payload[@"rebase"] boolValue];
        event.tooBig = [payload[@"tooBig"] boolValue];
        event.repo = payload[@"repo"];
        event.commit = payload[@"commit"];
        event.rev = payload[@"rev"];
        event.since = payload[@"since"];
        event.blocks = payload[@"blocks"];
        event.ops = payload[@"ops"] ?: @[];
        event.blobs = payload[@"blobs"] ?: @[];
        event.time = payload[@"time"];
        event.prevData = payload[@"prevData"];

        [self sendEventToSubscriptions:event kind:FirehoseEventKindCommit];

    } else if ([msgType isEqualToString:@"#identity"]) {
        FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
        event.did = payload[@"did"];
        event.seq = [payload[@"seq"] longLongValue];
        event.time = payload[@"time"];
        event.handle = payload[@"handle"];

        [self sendEventToSubscriptions:event kind:FirehoseEventKindIdentity];

    } else if ([msgType isEqualToString:@"#account"]) {
        FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
        event.did = payload[@"did"];
        event.seq = [payload[@"seq"] longLongValue];
        event.active = [payload[@"active"] boolValue];
        event.status = payload[@"status"];
        event.time = payload[@"time"];

        [self sendEventToSubscriptions:event kind:FirehoseEventKindAccount];

    } else if ([msgType isEqualToString:@"#sync"]) {
        FirehoseSyncEvent *event = [[FirehoseSyncEvent alloc] init];
        event.did = payload[@"did"];
        event.seq = [payload[@"seq"] longLongValue];
        event.blocks = payload[@"blocks"];
        event.rev = payload[@"rev"];
        event.time = payload[@"time"];

        [self sendEventToSubscriptions:event kind:FirehoseEventKindSync];

    } else if ([msgType isEqualToString:@"#info"]) {
        FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
        event.kind = payload[@"kind"];
        event.message = payload[@"message"];

        [self sendEventToSubscriptions:event kind:FirehoseEventKindInfo];
    }
}

- (void)notifyConnectionError:(NSError *)error {
    for (FirehoseSubscription *subscription in self.subscriptions) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didCloseWithError:)]) {
                [subscription.delegate firehoseSubscription:subscription didCloseWithError:error];
            }
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
            if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didCloseWithError:)]) {
                [subscription.delegate firehoseSubscription:subscription didCloseWithError:error];
            }
        });
    }
}

- (void)webSocketConnection:(WebSocketConnection *)connection didFailWithError:(NSError *)error {
    [self notifyConnectionError:error];
}

- (void)webSocketConnectionStateDidChange:(WebSocketConnection *)connection {
    PDS_LOG_DEBUG(@"Firehose: WebSocket state changed to %d", (int)connection.state);
    if (connection.state == WebSocketConnectionStateConnected) {
        self.isConnected = YES;

        for (FirehoseSubscription *subscription in self.subscriptions) {
            dispatch_async(dispatch_get_main_queue(), ^{
                PDS_LOG_DEBUG(@"Firehose: Notifying subscription delegate of connect");
                if ([subscription.delegate respondsToSelector:@selector(firehoseSubscriptionDidConnect:)]) {
                    [subscription.delegate firehoseSubscriptionDidConnect:subscription];
                }
            });
        }
    }
}

@end

@implementation FirehoseSubscription

- (instancetype)initWithCursor:(int64_t)cursor collections:(nullable NSArray<NSString *> *)collections {
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

@implementation FirehoseCommitEvent
+ (instancetype)eventWithRepo:(NSString *)repo commit:(CID *)commit ops:(NSArray<NSDictionary *> *)ops {
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = repo;
    event.commit = commit;
    event.ops = ops;
    return event;
}
@end

@implementation FirehoseSyncEvent
+ (instancetype)eventWithDid:(NSString *)did
                         rev:(NSString *)rev
                      blocks:(NSData *)blocks {
    FirehoseSyncEvent *event = [[FirehoseSyncEvent alloc] init];
    event.did = did;
    event.rev = rev;
    event.blocks = blocks;
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

@implementation FirehoseAccountEvent
+ (instancetype)eventWithDid:(NSString *)did
                      active:(BOOL)active
                      status:(nullable NSString *)status {
    FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
    event.did = did;
    event.active = active;
    event.status = status;
    return event;
}
@end

@implementation FirehoseInfoEvent
+ (instancetype)eventWithKind:(NSString *)kind message:(NSString *)message {
    FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
    event.kind = kind;
    event.message = message;
    return event;
}
@end

@implementation FirehoseErrorEvent
+ (instancetype)eventWithMessage:(NSString *)message {
    return [self eventWithError:@"Error" message:message];
}
+ (instancetype)eventWithError:(NSString *)error message:(nullable NSString *)message {
    FirehoseErrorEvent *event = [[FirehoseErrorEvent alloc] init];
    event.error = error;
    event.message = message;
    return event;
}
@end
