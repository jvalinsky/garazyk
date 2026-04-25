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
#import "Debug/PDSLogger.h"

@interface RelayDownstreamHandler ()
@property (nonatomic, strong) RelayEventBuffer *eventBuffer;
@property (nonatomic, strong) SubscribeReposHandler *subscribeReposHandler;
@property (nonatomic, assign) int64_t currentSequence;
@property (nonatomic, strong) NSMutableArray<id<PDSNetworkConnection>> *downstreamConnections;
@property (nonatomic, strong) dispatch_queue_t handlerQueue;
@end

@implementation RelayDownstreamHandler

#pragma mark - Initialization

- (instancetype)initWithEventBuffer:(RelayEventBuffer *)buffer
               subscribeReposHandler:(SubscribeReposHandler *)handler {
    self = [super init];
    if (self) {
        _eventBuffer = buffer;
        _subscribeReposHandler = handler;
        _metrics = nil;
        _currentSequence = 0;
        _downstreamConnections = [NSMutableArray array];
        _handlerQueue = dispatch_queue_create("com.atproto.relay.downstream", DISPATCH_QUEUE_SERIAL);
        PDS_LOG_SYNC_INFO(@"RelayDownstreamHandler initialized %p", self);
    }
    return self;
}


#pragma mark - RelayUpstreamManagerDelegate

- (void)upstreamManager:(RelayUpstreamManager *)manager
         didReceiveEvent:(id)event
           fromUpstream:(NSString *)url {
    PDS_LOG_SYNC_INFO(@"RelayDownstreamHandler: Received event from %@", url);
    // Process on handler queue for thread safety
    dispatch_async(self.handlerQueue, ^{
        // Extract sequence number and event type
        int64_t seq = 0;

        if ([event isKindOfClass:[FirehoseCommitEvent class]]) {
            FirehoseCommitEvent *commitEvent = (FirehoseCommitEvent *)event;
            
            // Just broadcast. Re-sequencing happens in SubscribeReposHandler/Session.
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastCommitEvent:commitEvent];
                seq = (int64_t)commitEvent.seq;
            }

            [self.eventBuffer appendEvent:commitEvent seq:seq];
            PDS_LOG_DEBUG(@"Relay: Received and broadcast commit seq=%lld repo=%@", seq, commitEvent.repo);
        }
        else if ([event isKindOfClass:[FirehoseIdentityEvent class]]) {
            FirehoseIdentityEvent *identityEvent = (FirehoseIdentityEvent *)event;
            
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastIdentityChange:identityEvent.did handle:identityEvent.handle];
                seq = (int64_t)identityEvent.seq;
            }

            [self.eventBuffer appendEvent:identityEvent seq:seq];
            PDS_LOG_DEBUG(@"Relay: Received and broadcast identity seq=%lld did=%@", seq, identityEvent.did);
        }
        else if ([event isKindOfClass:[FirehoseAccountEvent class]]) {
            FirehoseAccountEvent *accountEvent = (FirehoseAccountEvent *)event;
            
            if (self.subscribeReposHandler) {
                [self.subscribeReposHandler broadcastAccountStatus:accountEvent.did active:accountEvent.active status:accountEvent.status];
                seq = (int64_t)accountEvent.seq;
            }

            [self.eventBuffer appendEvent:accountEvent seq:seq];
            PDS_LOG_DEBUG(@"Relay: Received and broadcast account seq=%lld did=%@", seq, accountEvent.did);
        }
        else if ([event isKindOfClass:[FirehoseErrorEvent class]]) {
            FirehoseErrorEvent *errorEvent = (FirehoseErrorEvent *)event;
            PDS_LOG_WARN(@"Relay: Received error from upstream %@: %@", url, errorEvent.message ?: @"unknown");
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
    PDS_LOG_SYNC_INFO(@"RelayDownstreamHandler: Connected to upstream %@", url);
}

- (void)upstreamManager:(RelayUpstreamManager *)manager
    didDisconnectFromUpstream:(NSString *)url
                        error:(nullable NSError *)error {
    PDS_LOG_SYNC_WARN(@"RelayDownstreamHandler: Disconnected from upstream %@ (error: %@)", 
                 url, error.localizedDescription ?: @"none");
}

- (void)upstreamManager:(RelayUpstreamManager *)manager
        didReceiveCursor:(int64_t)cursor
             fromUpstream:(NSString *)url {
    PDS_LOG_SYNC_INFO(@"RelayDownstreamHandler: Received cursor %lld from upstream %@", cursor, url);
    // We don't necessarily update our local sequence based on upstream cursor
}

#pragma mark - Downstream Management

- (NSUInteger)activeDownstreamCount {
    if (self.subscribeReposHandler) {
        return self.subscribeReposHandler.attachedConnections.count;
    }
    return 0;
}

#pragma mark - Internal Helpers (REPLACED BY SubscribeReposHandler re-sequencing)

- (void)broadcastCommitEvent:(FirehoseCommitEvent *)commitEvent {
    // Deprecated - use subscribeReposHandler directly to ensure sequencing
}

- (void)broadcastIdentityEvent:(FirehoseIdentityEvent *)identityEvent {
    // Deprecated
}

- (void)broadcastAccountEvent:(FirehoseAccountEvent *)accountEvent {
    // Deprecated
}

- (NSData *)formatCommitEventForWire:(FirehoseCommitEvent *)event {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    NSError *error = nil;
    NSData *data = [formatter encodeCommitEvent:event error:&error];
    return data;
}

- (NSData *)formatIdentityEventForWire:(FirehoseIdentityEvent *)event {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    NSError *error = nil;
    NSData *data = [formatter encodeIdentityEvent:event error:&error];
    return data;
}

- (NSData *)formatAccountEventForWire:(FirehoseAccountEvent *)event {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    NSError *error = nil;
    NSData *data = [formatter encodeAccountEvent:event error:&error];
    return data;
}

@end
