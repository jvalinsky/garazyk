// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file JetstreamClient.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Sync/Jetstream/JetstreamClient.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"

// Jetstream event JSON keys.
static NSString * const kJetstreamKeyDid     = @"did";
static NSString * const kJetstreamKeyTimeUS  = @"time_us";
static NSString * const kJetstreamKeyKind    = @"kind";
static NSString * const kJetstreamKeyCommit  = @"commit";
static NSString * const kJetstreamKeyIdentity = @"identity";

// Commit sub-keys.
static NSString * const kJetstreamKeyRev        = @"rev";
static NSString * const kJetstreamKeyOperation  = @"operation";
static NSString * const kJetstreamKeyCollection = @"collection";
static NSString * const kJetstreamKeyRkey       = @"rkey";
static NSString * const kJetstreamKeyRecord     = @"record";
static NSString * const kJetstreamKeyCID        = @"cid";

// Identity sub-keys.
static NSString * const kJetstreamKeyHandle = @"handle";

@interface JetstreamClient () <NSURLSessionWebSocketDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionWebSocketTask *task;
@property (nonatomic, assign) BOOL shouldReconnect;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) NSArray<NSString *> *wantedCollections;
@property (nonatomic, assign) int64_t startingCursor;
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, assign, readwrite) int64_t currentCursor;
@property (nonatomic, assign, readwrite) BOOL isReadingPaused;
@end

@implementation JetstreamClient

- (instancetype)initWithJetstreamURL:(NSURL *)jetstreamURL
                  wantedCollections:(NSArray<NSString *> *)wantedCollections
                     startingCursor:(int64_t)startingCursor {
    self = [super init];
    if (!self) return nil;

    _wantedCollections = [wantedCollections copy] ?: @[];
    _startingCursor = startingCursor;
    _currentCursor = startingCursor;
    _isConnected = NO;
    _isReadingPaused = NO;
    _shouldReconnect = NO;

    // Build subscription URL with query params.
    NSURLComponents *components = [NSURLComponents componentsWithURL:jetstreamURL
                                             resolvingAgainstBaseURL:YES];
    NSString *existingPath = components.path ?: @"";
    if (![existingPath hasSuffix:@"/subscribe"]) {
        if ([existingPath hasSuffix:@"/"]) {
            components.path = [existingPath stringByAppendingString:@"subscribe"];
        } else {
            components.path = [existingPath stringByAppendingString:@"/subscribe"];
        }
    }
    NSMutableArray<NSURLQueryItem *> *queryItems = [components.queryItems mutableCopy] ?: [NSMutableArray array];

    for (NSString *collection in _wantedCollections) {
        if (collection.length > 0) {
            [queryItems addObject:[NSURLQueryItem queryItemWithName:@"wantedCollections"
                                                              value:collection]];
        }
    }
    components.queryItems = queryItems.count > 0 ? queryItems : nil;

    _subscriptionURL = [components URL];

    _queue = dispatch_queue_create("dev.garazyk.jetstream.client", DISPATCH_QUEUE_SERIAL);
    _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                             delegate:self
                                        delegateQueue:[[NSOperationQueue alloc] init]];

    return self;
}

- (void)dealloc {
    [self disconnect];
}

#pragma mark - Connection lifecycle

- (void)connect {
    if (_isConnected) return;
    _shouldReconnect = YES;

    dispatch_async(_queue, ^{
        [self _connectInternal];
    });
}

- (void)_connectInternal {
    if (_task) {
        [_task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
        _task = nil;
    }

    // Build URL with cursor if resuming.
    NSURL *url = _subscriptionURL;
    if (_currentCursor > 0) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url
                                                 resolvingAgainstBaseURL:YES];
        NSMutableArray<NSURLQueryItem *> *items = [components.queryItems mutableCopy] ?: [NSMutableArray array];
        // Remove any existing cursor param, then add the current one.
        [items filterUsingPredicate:[NSPredicate predicateWithFormat:@"name != %@", @"cursor"]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"cursor"
                                                     value:[NSString stringWithFormat:@"%lld", (long long)_currentCursor]]];
        components.queryItems = items;
        url = [components URL];
    }

    GZ_LOG_INFO(@"[JetstreamClient] Connecting to %@", url.absoluteString);
    _task = [_session webSocketTaskWithURL:url];
    [_task resume];
    [self _startReceiving];
}

- (void)disconnect {
    _shouldReconnect = NO;
    dispatch_async(_queue, ^{
        if (self->_task) {
            [self->_task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
            self->_task = nil;
        }
        self->_isConnected = NO;
    });
}

#pragma mark - Read loop

- (void)_startReceiving {
    if (!_task) return;
    __weak typeof(self) weakSelf = self;
    [_task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (error) {
            [self _handleReadError:error];
            return;
        }

        if (message.type == NSURLSessionWebSocketMessageTypeString) {
            [self _handleTextMessage:message.string];
        }
        // Data messages are not expected from Jetstream; ignore.

        if (self.isConnected && self.task) {
            [self _startReceiving]; // Continue the read loop.
        }
    }];
}

- (void)_handleReadError:(NSError *)error {
    GZ_LOG_WARN(@"[JetstreamClient] Read error: %@", error.localizedDescription);
    _isConnected = NO;
    _task = nil;

    id<JetstreamClientDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(jetstreamClient:didDisconnectWithError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate jetstreamClient:self didDisconnectWithError:error];
        });
    }

    if (_shouldReconnect) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), _queue, ^{
            if (self.shouldReconnect) {
                [self _connectInternal];
            }
        });
    }
}

#pragma mark - Message parsing

- (void)_handleTextMessage:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;

    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!json || ![json isKindOfClass:[NSDictionary class]]) {
        GZ_LOG_WARN(@"[JetstreamClient] Invalid JSON: %@", jsonError.localizedDescription);
        return;
    }

    NSDictionary *event = (NSDictionary *)json;
    NSNumber *timeUS = event[kJetstreamKeyTimeUS];
    if ([timeUS isKindOfClass:[NSNumber class]]) {
        _currentCursor = [timeUS longLongValue];
    }

    NSString *kind = event[kJetstreamKeyKind];
    NSString *did = event[kJetstreamKeyDid];

    if ([kind isEqualToString:@"commit"] && did) {
        [self _parseCommitEvent:event did:did];
    } else if ([kind isEqualToString:@"identity"] && did) {
        [self _parseIdentityEvent:event did:did];
    }

    // Notify delegate of cursor advancement.
    id<JetstreamClientDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(jetstreamClient:didReceiveCursor:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate jetstreamClient:self didReceiveCursor:self.currentCursor];
        });
    }
}

- (void)_parseCommitEvent:(NSDictionary *)event did:(NSString *)did {
    NSDictionary *commit = event[kJetstreamKeyCommit];
    if (![commit isKindOfClass:[NSDictionary class]]) return;

    NSString *rev = commit[kJetstreamKeyRev];
    NSString *operation = commit[kJetstreamKeyOperation] ?: @"create";
    NSString *collection = commit[kJetstreamKeyCollection] ?: @"";
    NSString *rkey = commit[kJetstreamKeyRkey] ?: @"";
    NSDictionary *record = commit[kJetstreamKeyRecord];
    NSString *cidStr = commit[kJetstreamKeyCID];

    if (!collection || !rev) return;

    // Normalise operation: Jetstream uses "create"/"update"/"delete".
    NSString *action = operation;
    if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
        // Keep as-is.
    } else if ([action isEqualToString:@"delete"]) {
        // Delete — no record needed.
        record = nil;
    }

    // Build a ATProtoFirehoseCommitEvent-compatible object.
    ATProtoFirehoseCommitEvent *commitEvent = [[ATProtoFirehoseCommitEvent alloc] init];
    commitEvent.seq = _currentCursor;
    commitEvent.repo = did;
    commitEvent.rev = rev;
    commitEvent.since = nil; // Jetstream doesn't expose since.
    commitEvent.blocks = nil; // No CAR blocks in Jetstream.
    commitEvent.time = event[kJetstreamKeyTimeUS] ? [NSString stringWithFormat:@"%@", event[kJetstreamKeyTimeUS]] : nil;

    if (cidStr && [cidStr isKindOfClass:[NSString class]]) {
        ATProtoCID *cid = [ATProtoCID cidWithString:cidStr];
        if (cid) commitEvent.commit = cid;
    }

    // Build a single op per Jetstream event.
    NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    NSMutableDictionary *op = [NSMutableDictionary dictionaryWithDictionary:@{
        @"action": action,
        @"path": path,
    }];
    if (record && [record isKindOfClass:[NSDictionary class]]) {
        op[@"record"] = record;
    }
    if (cidStr && [cidStr isKindOfClass:[NSString class]]) {
        op[@"cid"] = cidStr;
    }
    commitEvent.ops = @[op];

    id<JetstreamClientDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(jetstreamClient:didReceiveCommitEvent:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate jetstreamClient:self didReceiveCommitEvent:commitEvent];
        });
    }
}

- (void)_parseIdentityEvent:(NSDictionary *)event did:(NSString *)did {
    NSDictionary *identity = event[kJetstreamKeyIdentity];
    if (![identity isKindOfClass:[NSDictionary class]]) return;

    NSString *handle = identity[kJetstreamKeyHandle];

    ATProtoFirehoseIdentityEvent *identityEvent = [[ATProtoFirehoseIdentityEvent alloc] init];
    identityEvent.seq = _currentCursor;
    identityEvent.did = did;
    identityEvent.handle = handle;
    identityEvent.time = event[kJetstreamKeyTimeUS] ? [NSString stringWithFormat:@"%@", event[kJetstreamKeyTimeUS]] : nil;

    id<JetstreamClientDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(jetstreamClient:didReceiveIdentityEvent:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate jetstreamClient:self didReceiveIdentityEvent:identityEvent];
        });
    }
}

#pragma mark - NSURLSessionWebSocketDelegate

- (void)URLSession:(NSURLSession *)session
      webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
didOpenWithProtocol:(nullable NSString *)protocol {
    GZ_LOG_INFO(@"[JetstreamClient] Connected (protocol: %@)", protocol ?: @"none");
    _isConnected = YES;

    id<JetstreamClientDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(jetstreamClientDidConnect:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate jetstreamClientDidConnect:self];
        });
    }
}

- (void)URLSession:(NSURLSession *)session
      webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode
            reason:(nullable NSData *)reason {
    GZ_LOG_INFO(@"[JetstreamClient] Disconnected (code: %ld)", (long)closeCode);
    _isConnected = NO;
    _task = nil;

    id<JetstreamClientDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(jetstreamClient:didDisconnectWithError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate jetstreamClient:self didDisconnectWithError:nil];
        });
    }

    if (_shouldReconnect) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), _queue, ^{
            if (self.shouldReconnect) {
                [self _connectInternal];
            }
        });
    }
}

#pragma mark - Backpressure

- (void)pauseReading {
    if (!_task || _isReadingPaused) return;
    _isReadingPaused = YES;
    [_task suspend];
}

- (void)resumeReading {
    if (!_task || !_isReadingPaused) return;
    _isReadingPaused = NO;
    [_task resume];
    [self _startReceiving];
}

@end
