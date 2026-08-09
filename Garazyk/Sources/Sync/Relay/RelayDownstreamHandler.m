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
#import "Sync/Relay/RelayEventValidator.h"
#import "Sync/Firehose/Firehose.h"
#import "Sync/Relay/EventFormatter.h"
#import "Core/CID.h"
#import "Repository/CAR.h"
#import "Repository/RepoCommit.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"

static const NSUInteger kRelayInventoryPageLimit = 1000;
static const NSUInteger kRelayInventoryMaximumPages = 10000;
static const NSUInteger kRelayMaximumConcurrentRecoveries = 4;

@interface RelayDownstreamHandler ()
@property (nonatomic, strong) RelayEventBuffer *eventBuffer;
@property (nonatomic, strong) SubscribeReposHandler *subscribeReposHandler;
@property (nonatomic, assign) int64_t currentSequence;
@property (nonatomic, strong) NSMutableArray<id<ATProtoNetworkConnection>> *downstreamConnections;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t handlerQueue;
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;
@property (nonatomic, strong) NSMutableSet<NSString *> *bootstrappingUpstreams;
@property (nonatomic, strong) NSMutableSet<NSString *> *recoveringRepos;
- (nullable ATProtoRepoCommit *)validatedCommitForEvent:(FirehoseCommitEvent *)event
                                           error:(NSError **)error;
- (nullable ATProtoRepoCommit *)validatedCommitForSyncEvent:(FirehoseSyncEvent *)event
                                           commitCID:(ATProtoCID * _Nullable * _Nonnull)commitCID
                                               error:(NSError **)error;
- (void)recoverRepo:(NSString *)repoDID
       fromUpstream:(NSString *)upstreamURL
           sequence:(int64_t)sequence;
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
        _recoveringRepos = [NSMutableSet set];
        _chainValidationMode = RelayValidationModeLogOnly;
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
        [self.metrics recordEventReceived];

        GZ_LOG_SYNC_INFO(@"RelayDownstreamHandler: Received event of class %@", NSStringFromClass([event class]));
        if ([event isKindOfClass:[FirehoseCommitEvent class]]) {
            FirehoseCommitEvent *commitEvent = (FirehoseCommitEvent *)event;

            if (self.eventValidator) {
                RelayValidationOutcome *outcome = [self.eventValidator validateCommitEvent:commitEvent];
                if (![self.eventValidator shouldForwardEvent:outcome]) {
                    GZ_LOG_SYNC_WARN(@"Relay: Dropping commit seq=%lld repo=%@ (validation: %d %@)",
                                     (long long)commitEvent.seq, commitEvent.repo,
                                     (int)outcome.result, outcome.errorMessage ?: @"");
                    return;
                }
            }

            if (![self verifyChainForCommitEvent:commitEvent]) {
                GZ_LOG_SYNC_WARN(@"Relay: Not forwarding commit seq=%lld repo=%@ (continuity policy)",
                                 (long long)commitEvent.seq, commitEvent.repo);
                if ([self.repoStateManager statusForRepo:commitEvent.repo] ==
                    RelayRepoStatusDesynchronized) {
                    [self recoverRepo:commitEvent.repo
                         fromUpstream:url
                             sequence:(int64_t)commitEvent.seq];
                }
                return;
            }

            // Just broadcast. Re-sequencing happens in SubscribeReposHandler/Session.
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastCommitEvent:commitEvent];
                seq = (int64_t)commitEvent.seq;
            } else if (self.eventBuffer) {
                seq = (int64_t)commitEvent.seq;
                [self.eventBuffer appendEvent:commitEvent seq:seq];
            }
            [self.metrics recordEventForwarded];
            [self.metrics recordSequence:seq];

            GZ_LOG_DEBUG(@"Relay: Received and broadcast commit seq=%lld repo=%@", seq, commitEvent.repo);
        }
        else if ([event isKindOfClass:[FirehoseSyncEvent class]]) {
            FirehoseSyncEvent *syncEvent = (FirehoseSyncEvent *)event;
            NSError *syncError = nil;
            ATProtoCID *commitCID = nil;
            ATProtoRepoCommit *commit =
                [self validatedCommitForSyncEvent:syncEvent
                                       commitCID:&commitCID
                                           error:&syncError];
            if (!commit) {
                GZ_LOG_SYNC_WARN(@"Relay: Dropping invalid sync seq=%lld did=%@: %@",
                                 (long long)syncEvent.seq, syncEvent.did,
                                 syncError.localizedDescription ?: @"unknown");
                [self.metrics recordEventInvalidated:@"sync-envelope"];
                [self.metrics recordEventDropped];
                return;
            }

            [self.repoStateManager handleCommitForRepo:syncEvent.did
                                             commitCID:commitCID.stringValue
                                               dataCID:commit.dataCID.stringValue
                                                   rev:syncEvent.rev ?: @""
                                                   seq:(int64_t)syncEvent.seq];
            [self.metrics recordSyncReset];
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastSyncEvent:syncEvent];
            } else if (self.eventBuffer) {
                [self.eventBuffer appendEvent:syncEvent seq:(int64_t)syncEvent.seq];
            }
            [self.metrics recordEventForwarded];
            [self.metrics recordSequence:(int64_t)syncEvent.seq];
            GZ_LOG_SYNC_INFO(@"Relay: Applied and broadcast sync seq=%lld did=%@",
                             (long long)syncEvent.seq, syncEvent.did);
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
        else if ([event isKindOfClass:[FirehoseRawEvent class]]) {
            FirehoseRawEvent *rawEvent = (FirehoseRawEvent *)event;
            int64_t rawSequence = [rawEvent.payload[@"seq"] longLongValue];
            if (self.eventBuffer && rawSequence > 0) {
                [self.eventBuffer appendEvent:rawEvent.frameData seq:rawSequence];
            }
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastEventData:rawEvent.frameData];
            }
            GZ_LOG_SYNC_INFO(@"Relay: Forwarded unknown firehose event type %@ byte-for-byte", rawEvent.messageType);
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

#pragma mark - Chain Verification

- (nullable ATProtoRepoCommit *)validatedCommitForSyncEvent:(FirehoseSyncEvent *)event
                                           commitCID:(ATProtoCID * _Nullable * _Nonnull)commitCID
                                               error:(NSError **)error {
    ATProtoCARReader *reader = [ATProtoCARReader readFromData:event.blocks error:error];
    if (!reader || !reader.rootCID) {
        return nil;
    }
    ATProtoCARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    if (!commitBlock) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"sync CAR does not contain its root commit block"}];
        }
        return nil;
    }
    ATProtoCID *computedCID = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:commitBlock.data]
                                    codec:0x71];
    if (!computedCID || ![computedCID isEqual:reader.rootCID]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:9
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"sync commit block does not hash to its CAR root"}];
        }
        return nil;
    }
    ATProtoRepoCommit *commit = [ATProtoRepoCommit fromSignedBlockData:commitBlock.data
                                                   error:error];
    if (!commit) {
        return nil;
    }
    if (![commit.did isEqualToString:event.did] ||
        ![commit.rev isEqualToString:event.rev] ||
        commit.dataCID.stringValue.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"sync event fields do not match its signed commit"}];
        }
        return nil;
    }
    *commitCID = reader.rootCID;
    return commit;
}

- (nullable ATProtoRepoCommit *)validatedCommitForEvent:(FirehoseCommitEvent *)event
                                           error:(NSError **)error {
    if (!event.commit || event.blocks.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"commit event is missing its commit CID or CAR blocks"}];
        }
        return nil;
    }

    ATProtoCARReader *reader = [ATProtoCARReader readFromData:event.blocks error:error];
    if (!reader) {
        return nil;
    }
    if (![reader.rootCID isEqual:event.commit]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"firehose commit CID does not match the CAR root"}];
        }
        return nil;
    }

    ATProtoCARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    if (!commitBlock) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"CAR does not contain its root commit block"}];
        }
        return nil;
    }

    ATProtoCID *computedCID = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:commitBlock.data]
                                    codec:0x71];
    if (!computedCID || ![computedCID isEqual:event.commit]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"root commit block bytes do not hash to the advertised CID"}];
        }
        return nil;
    }

    ATProtoRepoCommit *commit = [ATProtoRepoCommit fromSignedBlockData:commitBlock.data
                                                   error:error];
    if (!commit) {
        return nil;
    }
    if (![commit.did isEqualToString:event.repo]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"signed commit DID does not match the firehose repo"}];
        }
        return nil;
    }
    if (![commit.rev isEqualToString:event.rev]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"signed commit revision does not match the firehose revision"}];
        }
        return nil;
    }
    if (!commit.dataCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.relay.continuity"
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"signed commit is missing its MST data root"}];
        }
        return nil;
    }
    return commit;
}

- (BOOL)verifyChainForCommitEvent:(FirehoseCommitEvent *)event {
    if (!self.repoStateManager || event.repo.length == 0) {
        return YES;
    }

    NSError *parseError = nil;
    ATProtoRepoCommit *commit = [self validatedCommitForEvent:event error:&parseError];
    if (!commit) {
        GZ_LOG_SYNC_WARN(@"Relay continuity: invalid commit envelope seq=%lld repo=%@: %@",
                         (long long)event.seq, event.repo,
                         parseError.localizedDescription ?: @"unknown error");
        [self.metrics recordMSTValidationFailure];
        [self.metrics recordContinuityFailure];
        [self.metrics recordEventInvalidated:@"commit-envelope"];
        if (self.chainValidationMode == RelayValidationModeStrict) {
            [self.metrics recordEventDropped];
            return NO;
        }
        return YES;
    }

    RelayRepoAdvanceResult result =
        [self.repoStateManager advanceRepo:event.repo
                                     since:event.since
                                  prevData:event.prevData.stringValue
                                 commitCID:event.commit.stringValue
                                   dataCID:commit.dataCID.stringValue
                                       rev:event.rev ?: @""
                                       seq:(int64_t)event.seq];

    switch (result) {
        case RelayRepoAdvanceResultStale:
            GZ_LOG_SYNC_WARN(@"Relay continuity: ignoring stale commit seq=%lld repo=%@ rev=%@",
                             (long long)event.seq, event.repo, event.rev);
            return NO;

        case RelayRepoAdvanceResultSinceMismatch:
        case RelayRepoAdvanceResultPrevDataMismatch: {
            NSString *reason =
                (result == RelayRepoAdvanceResultSinceMismatch)
                    ? @"since-mismatch"
                    : @"prev-data-mismatch";
            GZ_LOG_SYNC_WARN(
                @"Relay continuity: %@ seq=%lld repo=%@ since=%@ storedRev=%@ "
                 "prevData=%@ storedData=%@",
                reason, (long long)event.seq, event.repo, event.since,
                [self.repoStateManager revForRepo:event.repo],
                event.prevData.stringValue,
                [self.repoStateManager dataCIDForRepo:event.repo]);
            [self.metrics recordMSTValidationFailure];
            [self.metrics recordContinuityFailure];
            [self.metrics recordEventInvalidated:reason];
            if (self.chainValidationMode == RelayValidationModeStrict) {
                [self.metrics recordEventDropped];
                return NO;
            }

            [self.repoStateManager handleCommitForRepo:event.repo
                                             commitCID:event.commit.stringValue
                                               dataCID:commit.dataCID.stringValue
                                                   rev:event.rev ?: @""
                                                   seq:(int64_t)event.seq];
            return YES;
        }

        case RelayRepoAdvanceResultBaselineEstablished:
            [self.metrics recordContinuityBaseline];
            GZ_LOG_SYNC_INFO(@"Relay continuity: established data-root baseline seq=%lld repo=%@",
                             (long long)event.seq, event.repo);
            break;

        case RelayRepoAdvanceResultUnverifiableAdvanced:
            [self.metrics recordContinuityBaseline];
            GZ_LOG_SYNC_WARN(@"Relay continuity: missing since/prevData seq=%lld repo=%@; advanced baseline",
                             (long long)event.seq, event.repo);
            break;

        case RelayRepoAdvanceResultAdvanced:
            [self.metrics recordMSTValidationSuccess];
            [self.metrics recordContinuityVerified];
            break;
    }
    return YES;
}

#pragma mark - Continuity Recovery

- (void)recoverRepo:(NSString *)repoDID
       fromUpstream:(NSString *)upstreamURL
           sequence:(int64_t)sequence {
    if (repoDID.length == 0 || upstreamURL.length == 0 ||
        [self.recoveringRepos containsObject:repoDID]) {
        return;
    }
    if (self.recoveringRepos.count >= kRelayMaximumConcurrentRecoveries) {
        GZ_LOG_SYNC_WARN(@"Relay recovery: throttling getRepo for %@", repoDID);
        [self.repoStateManager handleAccountEventForRepo:repoDID
                                                   status:RelayRepoStatusThrottled];
        return;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:upstreamURL];
    NSString *scheme = components.scheme.lowercaseString;
    if ([scheme isEqualToString:@"wss"]) {
        components.scheme = @"https";
    } else if ([scheme isEqualToString:@"ws"]) {
        components.scheme = @"http";
    }
    components.path = @"/xrpc/com.atproto.sync.getRepo";
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"did" value:repoDID]
    ];
    NSURL *repoURL = components.URL;
    if (!repoURL) {
        GZ_LOG_SYNC_WARN(@"Relay recovery: invalid upstream URL %@", upstreamURL);
        return;
    }

    [self.recoveringRepos addObject:repoDID];
    [self.repoStateManager handleAccountEventForRepo:repoDID
                                               status:RelayRepoStatusInProgress];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:repoURL];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 60.0;

    ATProtoSafeHTTPClientOptions *options =
        [ATProtoSafeHTTPClientOptions defaultOptions];
    options.timeout = 60.0;
    options.maxResponseBytes = 64 * 1024 * 1024;
    options.allowHTTP = [repoURL.scheme.lowercaseString isEqualToString:@"http"];
    options.followRedirects = NO;

    __weak typeof(self) weakSelf = self;
    [self.safeHTTPClient
        performSafeDataTaskWithRequest:request
                               options:options
                            completion:^(NSData * _Nullable data,
                                         NSHTTPURLResponse * _Nullable response,
                                         NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        dispatch_async(strongSelf.handlerQueue, ^{
            [strongSelf.recoveringRepos removeObject:repoDID];
            if (error || response.statusCode != 200 || data.length == 0) {
                GZ_LOG_SYNC_WARN(
                    @"Relay recovery: getRepo failed did=%@ upstream=%@ status=%ld error=%@",
                    repoDID, upstreamURL, (long)response.statusCode,
                    error.localizedDescription ?: @"none");
                [strongSelf.repoStateManager
                    handleAccountEventForRepo:repoDID
                                       status:RelayRepoStatusThrottled];
                return;
            }

            NSError *carError = nil;
            ATProtoCARReader *reader = [ATProtoCARReader readFromData:data error:&carError];
            ATProtoCARBlock *rootBlock =
                reader.rootCID ? [reader blockWithCID:reader.rootCID] : nil;
            ATProtoRepoCommit *commit =
                rootBlock
                    ? [ATProtoRepoCommit fromSignedBlockData:rootBlock.data
                                                error:&carError]
                    : nil;
            if (!commit || ![commit.did isEqualToString:repoDID] ||
                commit.rev.length == 0 || commit.dataCID.stringValue.length == 0) {
                GZ_LOG_SYNC_WARN(@"Relay recovery: invalid getRepo CAR did=%@: %@",
                                 repoDID,
                                 carError.localizedDescription ?: @"commit mismatch");
                [strongSelf.repoStateManager
                    handleAccountEventForRepo:repoDID
                                       status:RelayRepoStatusThrottled];
                return;
            }

            FirehoseSyncEvent *syncEvent =
                [FirehoseSyncEvent eventWithDid:repoDID
                                            rev:commit.rev
                                         blocks:data];
            syncEvent.seq = sequence;
            syncEvent.time =
                [[[NSISO8601DateFormatter alloc] init] stringFromDate:[NSDate date]];

            ATProtoCID *commitCID = nil;
            NSError *syncError = nil;
            ATProtoRepoCommit *validated =
                [strongSelf validatedCommitForSyncEvent:syncEvent
                                              commitCID:&commitCID
                                                  error:&syncError];
            if (!validated) {
                GZ_LOG_SYNC_WARN(@"Relay recovery: rejected getRepo CAR did=%@: %@",
                                 repoDID,
                                 syncError.localizedDescription ?: @"unknown");
                [strongSelf.repoStateManager
                    handleAccountEventForRepo:repoDID
                                       status:RelayRepoStatusThrottled];
                return;
            }

            [strongSelf.repoStateManager handleCommitForRepo:repoDID
                                                    commitCID:commitCID.stringValue
                                                      dataCID:validated.dataCID.stringValue
                                                          rev:validated.rev
                                                          seq:sequence];
            [strongSelf.metrics recordSyncReset];
            if (strongSelf.subscribeReposHandler) {
                [strongSelf.subscribeReposHandler broadcastSyncEvent:syncEvent];
            } else if (strongSelf.eventBuffer) {
                [strongSelf.eventBuffer appendEvent:syncEvent seq:sequence];
            }
            [strongSelf.metrics recordEventForwarded];
            [strongSelf.metrics recordSequence:sequence];
            GZ_LOG_SYNC_INFO(@"Relay recovery: applied getRepo sync did=%@ rev=%@",
                             repoDID, validated.rev);
        });
    }];
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

        NSNumber *active = [repo[@"active"] isKindOfClass:[NSNumber class]] ? repo[@"active"] : nil;
        [self.repoStateManager observeInventoryForRepo:did
                                            commitCID:head
                                                  rev:rev
                                               active:active ? active.boolValue : YES];
        applied++;
    }
    return applied;
}

@end
