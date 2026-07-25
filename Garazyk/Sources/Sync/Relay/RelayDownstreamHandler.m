// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayDownstreamHandler.m

 @abstract Implementation of relay downstream event handling.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import "Sync/Relay/RelayDownstreamHandler.h"
#import "Sync/Relay/RelayEventBuffer.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Sync/Firehose/Firehose.h"
#import "Sync/Relay/EventFormatter.h"
#import "Core/CID.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"

static const NSUInteger kRelayInventoryPageLimit = 1000;
static const NSUInteger kRelayInventoryMaximumPages = 10000;

@interface RelayDownstreamHandler ()
@property (nonatomic, strong) RelayEventBuffer *eventBuffer;
@property (nonatomic, strong) SubscribeReposHandler *subscribeReposHandler;
@property (nonatomic, assign) int64_t currentSequence;
@property (nonatomic, strong) NSMutableArray<id<ATProtoNetworkConnection>> *downstreamConnections;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t handlerQueue;
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;
@property (nonatomic, strong) NSMutableSet<NSString *> *bootstrappingUpstreams;
@end

@implementation RelayDownstreamHandler

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

#pragma mark - Initialization

- (instancetype)initWithEventBuffer:(RelayEventBuffer *)buffer
               subscribeReposHandler:(SubscribeReposHandler *)handler {
    self = [super init];
    if (self) {
        _eventBuffer = buffer;
        _subscribeReposHandler = handler;
        if (_subscribeReposHandler && !_subscribeReposHandler.eventBuffer) {
            _subscribeReposHandler.eventBuffer = buffer;
        }
        _metrics = nil;
        _currentSequence = 0;
        _downstreamConnections = [NSMutableArray array];
        _handlerQueue = dispatch_queue_create("com.atproto.relay.downstream", DISPATCH_QUEUE_SERIAL);
        _safeHTTPClient = [ATProtoSafeHTTPClient sharedClient];
        _bootstrappingUpstreams = [NSMutableSet set];
        GZ_LOG_SYNC_INFO(@"RelayDownstreamHandler initialized %p", self);
    }
    return self;
}


#pragma mark - RelayUpstreamManagerDelegate

- (void)upstreamManager:(RelayUpstreamManager *)manager
         didReceiveEvent:(id)event
           fromUpstream:(NSString *)url {
    GZ_LOG_SYNC_INFO(@"RelayDownstreamHandler: Received event from %@", url);
    // Process on handler queue for thread safety
    dispatch_async(self.handlerQueue, ^{
        // Extract sequence number and event type
        int64_t seq = 0;

        GZ_LOG_SYNC_INFO(@"RelayDownstreamHandler: Received event of class %@", NSStringFromClass([event class]));
        if ([event isKindOfClass:[FirehoseCommitEvent class]]) {
            FirehoseCommitEvent *commitEvent = (FirehoseCommitEvent *)event;

            NSString *rootCID = commitEvent.commit.stringValue;
            if (self.repoStateManager && commitEvent.repo.length > 0 && rootCID.length > 0) {
                [self.repoStateManager handleCommitForRepo:commitEvent.repo
                                                      root:rootCID
                                                        rev:commitEvent.rev ?: @""
                                                        seq:(int64_t)commitEvent.seq];
            }
            
            // Just broadcast. Re-sequencing happens in SubscribeReposHandler/Session.
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastCommitEvent:commitEvent];
                seq = (int64_t)commitEvent.seq;
            } else if (self.eventBuffer) {
                seq = (int64_t)commitEvent.seq;
                [self.eventBuffer appendEvent:commitEvent seq:seq];
            }

            GZ_LOG_DEBUG(@"Relay: Received and broadcast commit seq=%lld repo=%@", seq, commitEvent.repo);
        }
        else if ([event isKindOfClass:[FirehoseIdentityEvent class]]) {
            FirehoseIdentityEvent *identityEvent = (FirehoseIdentityEvent *)event;
            
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastIdentityChange:identityEvent.did handle:identityEvent.handle];
                seq = (int64_t)identityEvent.seq;
            } else if (self.eventBuffer) {
                seq = (int64_t)identityEvent.seq;
                [self.eventBuffer appendEvent:identityEvent seq:seq];
            }

            GZ_LOG_DEBUG(@"Relay: Received and broadcast identity seq=%lld did=%@", seq, identityEvent.did);
        }
        else if ([event isKindOfClass:[FirehoseAccountEvent class]]) {
            FirehoseAccountEvent *accountEvent = (FirehoseAccountEvent *)event;
            
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastAccountStatus:accountEvent.did active:accountEvent.active status:accountEvent.status];
                seq = (int64_t)accountEvent.seq;
            } else if (self.eventBuffer) {
                seq = (int64_t)accountEvent.seq;
                [self.eventBuffer appendEvent:accountEvent seq:seq];
            }

            GZ_LOG_DEBUG(@"Relay: Received and broadcast account seq=%lld did=%@", seq, accountEvent.did);
        }
        else if ([event isKindOfClass:[FirehoseErrorEvent class]]) {
            FirehoseErrorEvent *errorEvent = (FirehoseErrorEvent *)event;
            GZ_LOG_WARN(@"Relay: Received error from upstream %@: %@", url, errorEvent.message ?: @"unknown");
        }
        else if ([event isKindOfClass:[NSDictionary class]]) {
            // Raw dictionary event (legacy/fallback)
            NSDictionary *eventDict = (NSDictionary *)event;
            seq = [eventDict[@"seq"] longLongValue];
            [self.eventBuffer appendEvent:eventDict seq:seq];
            
            if (self.subscribeReposHandler) {
                // If it's a dict, we just broadcast as raw data (legacy path)
                NSData *data = [NSJSONSerialization dataWithJSONObject:eventDict options:0 error:nil];
                if (data) {
                    [self.subscribeReposHandler broadcastEventData:data];
                }
            }
        }
    });
}


- (void)upstreamManager:(RelayUpstreamManager *)manager
    didConnectToUpstream:(NSString *)url {
    GZ_LOG_SYNC_INFO(@"RelayDownstreamHandler: Connected to upstream %@", url);
    dispatch_async(self.handlerQueue, ^{
        if (!self.repoStateManager || url.length == 0 || [self.bootstrappingUpstreams containsObject:url]) {
            return;
        }
        [self.bootstrappingUpstreams addObject:url];
        [self fetchRepoInventoryFromUpstream:url cursor:nil pageNumber:1 seenCursors:[NSMutableSet set]];
    });
}

- (void)upstreamManager:(RelayUpstreamManager *)manager
    didDisconnectFromUpstream:(NSString *)url
                        error:(nullable NSError *)error {
    GZ_LOG_SYNC_WARN(@"RelayDownstreamHandler: Disconnected from upstream %@ (error: %@)", 
                 url, error.localizedDescription ?: @"none");
}

- (void)upstreamManager:(RelayUpstreamManager *)manager
        didReceiveCursor:(int64_t)cursor
             fromUpstream:(NSString *)url {
    GZ_LOG_SYNC_INFO(@"RelayDownstreamHandler: Received cursor %lld from upstream %@", (long long)cursor, url);
    // We don't necessarily update our local sequence based on upstream cursor
}

#pragma mark - Downstream Management

- (NSUInteger)activeDownstreamCount {
    if (self.subscribeReposHandler) {
        return self.subscribeReposHandler.attachedConnections.count;
    }
    return 0;
}

#pragma mark - Repository Inventory Bootstrap

- (nullable NSURL *)repoInventoryURLForUpstream:(NSString *)upstreamURL
                                          cursor:(nullable NSString *)cursor {
    NSURLComponents *components = [NSURLComponents componentsWithString:upstreamURL];
    NSString *scheme = components.scheme.lowercaseString;
    if ([scheme isEqualToString:@"wss"]) {
        components.scheme = @"https";
    } else if ([scheme isEqualToString:@"ws"]) {
        components.scheme = @"http";
    }

    if (components.host.length == 0 || components.scheme.length == 0) {
        return nil;
    }

    components.path = @"/xrpc/com.atproto.sync.listRepos";
    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithObject:
        [NSURLQueryItem queryItemWithName:@"limit"
                                     value:[NSString stringWithFormat:@"%lu", (unsigned long)kRelayInventoryPageLimit]]];
    if (cursor.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"cursor" value:cursor]];
    }
    components.queryItems = queryItems;
    return components.URL;
}

- (void)fetchRepoInventoryFromUpstream:(NSString *)upstreamURL
                                cursor:(nullable NSString *)cursor
                            pageNumber:(NSUInteger)pageNumber
                           seenCursors:(NSMutableSet<NSString *> *)seenCursors {
    NSURL *inventoryURL = [self repoInventoryURLForUpstream:upstreamURL cursor:cursor];
    if (!inventoryURL) {
        GZ_LOG_SYNC_WARN(@"Relay inventory: invalid upstream URL %@", upstreamURL);
        [self.bootstrappingUpstreams removeObject:upstreamURL];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:inventoryURL];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 15.0;

    ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
    options.timeout = 15.0;
    options.maxResponseBytes = 2 * 1024 * 1024;
    options.allowHTTP = [inventoryURL.scheme.lowercaseString isEqualToString:@"http"];
    options.followRedirects = NO;

    __weak typeof(self) weakSelf = self;
    [self.safeHTTPClient performSafeDataTaskWithRequest:request
                                                options:options
                                             completion:^(NSData * _Nullable data,
                                                          NSHTTPURLResponse * _Nullable response,
                                                          NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        dispatch_async(strongSelf.handlerQueue, ^{
            if (error || response.statusCode != 200 || data.length == 0) {
                GZ_LOG_SYNC_WARN(@"Relay inventory: failed to fetch %@ (status=%ld, error=%@)",
                                 inventoryURL.absoluteString,
                                 (long)response.statusCode,
                                 error.localizedDescription ?: @"none");
                [strongSelf.bootstrappingUpstreams removeObject:upstreamURL];
                return;
            }

            NSError *parseError = nil;
            id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            if (![decoded isKindOfClass:[NSDictionary class]]) {
                GZ_LOG_SYNC_WARN(@"Relay inventory: invalid response from %@: %@",
                                 inventoryURL.absoluteString,
                                 parseError.localizedDescription ?: @"expected JSON object");
                [strongSelf.bootstrappingUpstreams removeObject:upstreamURL];
                return;
            }

            NSDictionary *inventory = (NSDictionary *)decoded;
            NSUInteger applied = [strongSelf applyRepoInventoryPage:inventory];
            NSString *nextCursor = [inventory[@"cursor"] isKindOfClass:[NSString class]] ? inventory[@"cursor"] : nil;
            if (nextCursor.length == 0) {
                GZ_LOG_SYNC_INFO(@"Relay inventory: completed %@ after %lu page(s)",
                                 upstreamURL,
                                 (unsigned long)pageNumber);
                [strongSelf.bootstrappingUpstreams removeObject:upstreamURL];
                return;
            }

            if (pageNumber >= kRelayInventoryMaximumPages || [seenCursors containsObject:nextCursor]) {
                GZ_LOG_SYNC_WARN(@"Relay inventory: stopped %@ at page %lu due to invalid pagination",
                                 upstreamURL,
                                 (unsigned long)pageNumber);
                [strongSelf.bootstrappingUpstreams removeObject:upstreamURL];
                return;
            }

            [seenCursors addObject:nextCursor];
            GZ_LOG_SYNC_INFO(@"Relay inventory: loaded %lu repo(s) from %@ page %lu",
                             (unsigned long)applied,
                             upstreamURL,
                             (unsigned long)pageNumber);
            [strongSelf fetchRepoInventoryFromUpstream:upstreamURL
                                                cursor:nextCursor
                                            pageNumber:pageNumber + 1
                                           seenCursors:seenCursors];
        });
    }];
}

- (NSUInteger)applyRepoInventoryPage:(NSDictionary *)inventory {
    NSArray *repos = [inventory[@"repos"] isKindOfClass:[NSArray class]] ? inventory[@"repos"] : nil;
    if (!repos || !self.repoStateManager) {
        return 0;
    }

    NSUInteger applied = 0;
    for (id item in repos) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSDictionary *repo = (NSDictionary *)item;
        NSString *did = [repo[@"did"] isKindOfClass:[NSString class]] ? repo[@"did"] : nil;
        NSString *head = [repo[@"head"] isKindOfClass:[NSString class]] ? repo[@"head"] : nil;
        NSString *rev = [repo[@"rev"] isKindOfClass:[NSString class]] ? repo[@"rev"] : @"";
        if (did.length == 0 || head.length == 0) {
            continue;
        }

        [self.repoStateManager handleCommitForRepo:did root:head rev:rev seq:0];
        NSNumber *active = [repo[@"active"] isKindOfClass:[NSNumber class]] ? repo[@"active"] : nil;
        if (active && !active.boolValue) {
            [self.repoStateManager handleAccountEventForRepo:did status:RelayRepoStatusDesynchronized];
        }
        applied++;
    }
    return applied;
}

@end
