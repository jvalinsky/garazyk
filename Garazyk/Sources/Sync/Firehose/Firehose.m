// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Firehose/Firehose.h"
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Core/ATProtoDagCBOR.h"
#import "Sync/Relay/EventFormatter.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"

NSString * const FirehoseErrorDomain = @"com.atproto.pds.firehose";
NSInteger const FirehoseErrorCodeSubscriptionFailed = 6000;
NSInteger const FirehoseErrorCodeEventEncodingFailed = 6001;
NSInteger const FirehoseErrorCodeSubscriptionClosed = 6002;
NSString * const FirehoseCloseCodeKey = @"FirehoseCloseCode";
NSString * const FirehoseCloseReasonKey = @"FirehoseCloseReason";

BOOL FirehoseErrorIsBackpressureClose(NSError * _Nullable error) {
    if (!error) return NO;
    NSNumber *codeNumber = error.userInfo[FirehoseCloseCodeKey];
    if ([codeNumber isKindOfClass:[NSNumber class]]) {
        NSInteger code = codeNumber.integerValue;
        if (code == 1008 || code == 1009) return YES;
    }
    NSString *reason = error.userInfo[FirehoseCloseReasonKey];
    if (![reason isKindOfClass:[NSString class]]) {
        reason = error.localizedDescription;
    }
    if (![reason isKindOfClass:[NSString class]]) return NO;
    return [reason rangeOfString:@"ConsumerTooSlow" options:NSCaseInsensitiveSearch].location != NSNotFound
        || [reason rangeOfString:@"Outbound queue" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

@interface ATProtoFirehoseSubscription ()
@property (nonatomic, assign, readwrite) int64_t cursor;
@property (nonatomic, copy, readwrite, nullable) NSArray<NSString *> *collections;
@property (nonatomic, assign, readwrite) BOOL isActive;
@property (nonatomic, weak, readwrite, nullable) id<FirehoseSubscriptionDelegate> delegate;
@end

@interface ATProtoFirehose () <WebSocketConnectionDelegate>
@property (nonatomic, strong, readwrite) NSURL *serverURL;
@property (nonatomic, assign, readwrite) int64_t cursor;
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, strong, readwrite, nullable) ATProtoWebSocketConnection *connection;
@property (nonatomic, strong, readwrite) NSMutableSet<ATProtoFirehoseSubscription *> *subscriptions;
@property (nonatomic, strong, readwrite) ATProtoEventFormatter *eventFormatter;
@end

@implementation ATProtoFirehoseRawEvent
@end

@implementation ATProtoFirehose

- (instancetype)initWithServerURL:(NSURL *)serverURL {
    self = [super init];
    if (self) {
        _serverURL = serverURL;
        _isConnected = NO;
        _subscriptions = [NSMutableSet set];
        _eventFormatter = [[ATProtoEventFormatter alloc] init];
    }
    return self;
}

- (ATProtoFirehoseSubscription *)subscribeWithCursor:(int64_t)cursor
                                   collections:(nullable NSArray<NSString *> *)collections
                                     delegate:(nullable id<FirehoseSubscriptionDelegate>)delegate {
    self.cursor = cursor;
    ATProtoFirehoseSubscription *subscription = [[ATProtoFirehoseSubscription alloc] initWithCursor:cursor
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
    NSString *scheme = self.serverURL.scheme.lowercaseString ?: @"";
    BOOL secureTLS = [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"wss"];
    uint16_t port = portNum ? (uint16_t)[portNum intValue] : (secureTLS ? 443 : 80);
    NSString *path = @"/xrpc/com.atproto.sync.subscribeRepos";
    
    if (self.cursor > 0) {
        path = [path stringByAppendingFormat:@"?cursor=%lld", (long long)self.cursor];
    }

    GZ_LOG_SYNC_INFO(@"Firehose: Connecting to %@:%u%@ (scheme: %@)", host, port, path, self.serverURL.scheme);

    self.connection = [[ATProtoWebSocketConnection alloc] initWithHost:host
                                                          port:port
                                                          path:path
                                                     secureTLS:secureTLS];
    // Relays (e.g. bsky.network) reject handshakes that do not
    // negotiate the com.atproto.sync.subscribeRepos subprotocol.
    self.connection.subprotocol = @"com.atproto.sync.subscribeRepos";
    if (self.accessToken.length > 0) {
        self.connection.authorizationHeader =
            [@"Bearer " stringByAppendingString:self.accessToken];
    }
    // Set heartbeat so network partition is detected within ~5s
    // instead of relying on OS-level TCP keepalive (default 60-120s).
    self.connection.heartbeatInterval = 5.0;
    self.connection.heartbeatTimeout = 5.0;
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

- (void)suspendReading {
    [self.connection suspendReading];
}

- (void)resumeReading {
    [self.connection resumeReading];
}

- (NSTimeInterval)heartbeatTimeout {
    return self.connection.heartbeatTimeout;
}

- (void)setHeartbeatTimeout:(NSTimeInterval)heartbeatTimeout {
    self.connection.heartbeatTimeout = heartbeatTimeout;
}

- (void)sendEventToSubscriptions:(id)event kind:(FirehoseEventKind)kind {
    for (ATProtoFirehoseSubscription *subscription in self.subscriptions) {
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
    GZ_LOG_SYNC_DEBUG(@"Firehose received message of length %lu", (unsigned long)data.length);
    NSInteger op = 0;
    NSString *msgType = nil;
    NSError *error = nil;
    
    NSDictionary *payload = [self.eventFormatter decodeEventFromData:data op:&op msgType:&msgType error:&error];
#define GZ_SAFE_OBJ(x) ((x) == [NSNull null] ? nil : (x))

    if (!payload || error) {
        GZ_LOG_SYNC_ERROR(@"Failed to decode firehose frame: %@", error);
        return;
    }
    
    GZ_LOG_SYNC_DEBUG(@"Decoded firehose frame: op=%ld type=%@", (long)op, msgType);

    if (op == -1) { // Error frame
        ATProtoFirehoseErrorEvent *event = [[ATProtoFirehoseErrorEvent alloc] init];
        event.error = GZ_SAFE_OBJ(payload[@"error"]);
        event.message = GZ_SAFE_OBJ(payload[@"message"]);
        [self sendEventToSubscriptions:event kind:FirehoseEventKindError];
        return;
    }

    if ([msgType isEqualToString:@"#commit"]) {
        ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
        event.seq = [payload[@"seq"] longLongValue];
        event.rebase = [payload[@"rebase"] boolValue];
        event.tooBig = [payload[@"tooBig"] boolValue];
        event.repo = GZ_SAFE_OBJ(payload[@"repo"]);
        event.commit = GZ_SAFE_OBJ(payload[@"commit"]);
        event.rev = GZ_SAFE_OBJ(payload[@"rev"]);
        event.since = GZ_SAFE_OBJ(payload[@"since"]);
        event.blocks = GZ_SAFE_OBJ(payload[@"blocks"]);
        event.ops = GZ_SAFE_OBJ(payload[@"ops"]) ?: @[];
        event.blobs = GZ_SAFE_OBJ(payload[@"blobs"]) ?: @[];
        event.time = GZ_SAFE_OBJ(payload[@"time"]);
        event.prevData = GZ_SAFE_OBJ(payload[@"prevData"]);

        [self sendEventToSubscriptions:event kind:FirehoseEventKindCommit];

    } else if ([msgType isEqualToString:@"#identity"]) {
        ATProtoFirehoseIdentityEvent *event = [[ATProtoFirehoseIdentityEvent alloc] init];
        event.did = GZ_SAFE_OBJ(payload[@"did"]);
        event.seq = [payload[@"seq"] longLongValue];
        event.time = GZ_SAFE_OBJ(payload[@"time"]);
        event.handle = GZ_SAFE_OBJ(payload[@"handle"]);

        [self sendEventToSubscriptions:event kind:FirehoseEventKindIdentity];

    } else if ([msgType isEqualToString:@"#account"]) {
        ATProtoFirehoseAccountEvent *event = [[ATProtoFirehoseAccountEvent alloc] init];
        event.did = GZ_SAFE_OBJ(payload[@"did"]);
        event.seq = [payload[@"seq"] longLongValue];
        event.active = [payload[@"active"] boolValue];
        event.status = GZ_SAFE_OBJ(payload[@"status"]);
        event.time = GZ_SAFE_OBJ(payload[@"time"]);

        [self sendEventToSubscriptions:event kind:FirehoseEventKindAccount];

    } else if ([msgType isEqualToString:@"#sync"]) {
        ATProtoFirehoseSyncEvent *event = [[ATProtoFirehoseSyncEvent alloc] init];
        event.did = GZ_SAFE_OBJ(payload[@"did"]);
        event.seq = [payload[@"seq"] longLongValue];
        event.blocks = GZ_SAFE_OBJ(payload[@"blocks"]);
        event.rev = GZ_SAFE_OBJ(payload[@"rev"]);
        event.time = GZ_SAFE_OBJ(payload[@"time"]);

        [self sendEventToSubscriptions:event kind:FirehoseEventKindSync];

    } else if ([msgType isEqualToString:@"#info"]) {
        ATProtoFirehoseInfoEvent *event = [[ATProtoFirehoseInfoEvent alloc] init];
        event.kind = GZ_SAFE_OBJ(payload[@"kind"]) ?: GZ_SAFE_OBJ(payload[@"name"]);
        event.message = GZ_SAFE_OBJ(payload[@"message"]);

        [self sendEventToSubscriptions:event kind:FirehoseEventKindInfo];
    } else {
        ATProtoFirehoseRawEvent *event = [[ATProtoFirehoseRawEvent alloc] init];
        event.messageType = msgType ?: @"";
        event.frameData = [data copy];
        event.payload = payload;
        for (ATProtoFirehoseSubscription *subscription in self.subscriptions) {
            if (!subscription.isActive) continue;
            id<FirehoseSubscriptionDelegate> delegate = subscription.delegate;
            if ([delegate respondsToSelector:@selector(firehoseSubscription:didReceiveRawEvent:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [delegate firehoseSubscription:subscription didReceiveRawEvent:event];
                });
            }
        }
    }
}

- (void)notifyConnectionError:(NSError *)error {
    for (ATProtoFirehoseSubscription *subscription in self.subscriptions) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didCloseWithError:)]) {
                [subscription.delegate firehoseSubscription:subscription didCloseWithError:error];
            }
        });
    }
}

#pragma mark - WebSocketConnectionDelegate

- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection didReceiveMessage:(NSData *)message {
    [self handleMessage:message];
}

- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection didReceiveText:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    [self handleMessage:data];
}

- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason {
    self.isConnected = NO;

    for (ATProtoFirehoseSubscription *subscription in self.subscriptions) {
        NSError *error = nil;
        if (code != 1000) {
            NSString *safeReason = reason.length > 0 ? reason : @"Connection closed";
            error = [NSError errorWithDomain:FirehoseErrorDomain
                                        code:FirehoseErrorCodeSubscriptionClosed
                                    userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"WebSocket closed code=%ld reason=%@",
                                               (long)code, safeReason],
                FirehoseCloseCodeKey: @(code),
                FirehoseCloseReasonKey: safeReason,
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([subscription.delegate respondsToSelector:@selector(firehoseSubscription:didCloseWithError:)]) {
                [subscription.delegate firehoseSubscription:subscription didCloseWithError:error];
            }
        });
    }
}

- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection didFailWithError:(NSError *)error {
    [self notifyConnectionError:error];
}

- (void)webSocketConnectionStateDidChange:(ATProtoWebSocketConnection *)connection {
    GZ_LOG_DEBUG(@"Firehose: WebSocket state changed to %d", (int)connection.state);
    if (connection.state == WebSocketConnectionStateConnected) {
        self.isConnected = YES;

        for (ATProtoFirehoseSubscription *subscription in self.subscriptions) {
            dispatch_async(dispatch_get_main_queue(), ^{
                GZ_LOG_DEBUG(@"Firehose: Notifying subscription delegate of connect");
                if ([subscription.delegate respondsToSelector:@selector(firehoseSubscriptionDidConnect:)]) {
                    [subscription.delegate firehoseSubscriptionDidConnect:subscription];
                }
            });
        }
    }
}

@end

@implementation ATProtoFirehoseSubscription

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

@implementation ATProtoFirehoseCommitEvent
+ (instancetype)eventWithRepo:(NSString *)repo commit:(ATProtoCID *)commit ops:(NSArray<NSDictionary *> *)ops {
    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.repo = repo;
    event.commit = commit;
    event.ops = ops;
    return event;
}
@end

@implementation ATProtoFirehoseSyncEvent
+ (instancetype)eventWithDid:(NSString *)did
                         rev:(NSString *)rev
                      blocks:(NSData *)blocks {
    ATProtoFirehoseSyncEvent *event = [[ATProtoFirehoseSyncEvent alloc] init];
    event.did = did;
    event.rev = rev;
    event.blocks = blocks;
    return event;
}
@end

@implementation ATProtoFirehoseIdentityEvent
+ (instancetype)eventWithDid:(NSString *)did {
    ATProtoFirehoseIdentityEvent *event = [[ATProtoFirehoseIdentityEvent alloc] init];
    event.did = did;
    return event;
}
@end

@implementation ATProtoFirehoseAccountEvent
+ (instancetype)eventWithDid:(NSString *)did
                      active:(BOOL)active
                      status:(nullable NSString *)status {
    ATProtoFirehoseAccountEvent *event = [[ATProtoFirehoseAccountEvent alloc] init];
    event.did = did;
    event.active = active;
    event.status = status;
    return event;
}
@end

@implementation ATProtoFirehoseInfoEvent
+ (instancetype)eventWithKind:(NSString *)kind message:(NSString *)message {
    ATProtoFirehoseInfoEvent *event = [[ATProtoFirehoseInfoEvent alloc] init];
    event.kind = kind;
    event.message = message;
    return event;
}
@end

@implementation ATProtoFirehoseErrorEvent
+ (instancetype)eventWithMessage:(NSString *)message {
    return [self eventWithError:@"Error" message:message];
}
+ (instancetype)eventWithError:(NSString *)error message:(nullable NSString *)message {
    ATProtoFirehoseErrorEvent *event = [[ATProtoFirehoseErrorEvent alloc] init];
    event.error = error;
    event.message = message;
    return event;
}
@end
