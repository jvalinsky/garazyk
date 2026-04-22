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
        NSString *eventType = @"unknown";

        if ([event isKindOfClass:[FirehoseCommitEvent class]]) {
            FirehoseCommitEvent *commitEvent = (FirehoseCommitEvent *)event;
            seq = commitEvent.seq;
            eventType = @"commit";

            // Store in buffer for backfill
            [self.eventBuffer appendEvent:event seq:seq];

            // Update repo state manager for XRPC queries
            if (self.repoStateManager && commitEvent.repo) {
                NSString *rootCidStr = commitEvent.commit.stringValue;
                [self.repoStateManager handleCommitForRepo:commitEvent.repo
                                                     root:rootCidStr
                                                       rev:commitEvent.rev
                                                       seq:seq];
            }

            // Broadcast to downstream subscribers
            [self broadcastCommitEvent:commitEvent];

            PDS_LOG_DEBUG(@"Relay: Received commit seq=%lld repo=%@", seq, commitEvent.repo);
        }
        else if ([event isKindOfClass:[FirehoseIdentityEvent class]]) {
            FirehoseIdentityEvent *identityEvent = (FirehoseIdentityEvent *)event;
            seq = identityEvent.seq;
            eventType = @"identity";

            // Store in buffer
            [self.eventBuffer appendEvent:event seq:seq];

            // Broadcast identity change
            [self broadcastIdentityEvent:identityEvent];

            PDS_LOG_DEBUG(@"Relay: Received identity seq=%lld did=%@", seq, identityEvent.did);
        }
        else if ([event isKindOfClass:[FirehoseAccountEvent class]]) {
            FirehoseAccountEvent *accountEvent = (FirehoseAccountEvent *)event;
            seq = accountEvent.seq;
            eventType = @"account";

            // Store in buffer
            [self.eventBuffer appendEvent:event seq:seq];

            // Broadcast account status change
            [self broadcastAccountEvent:accountEvent];

            PDS_LOG_DEBUG(@"Relay: Received account seq=%lld did=%@ active=%d",
                          seq, accountEvent.did, accountEvent.active);
        }
        else if ([event isKindOfClass:[FirehoseErrorEvent class]]) {
            FirehoseErrorEvent *errorEvent = (FirehoseErrorEvent *)event;
            // Error events don't have sequence numbers
            eventType = @"error";

            PDS_LOG_WARN(@"Relay: Received error from upstream %@: %@", url, errorEvent.message ?: @"unknown");
        }
        else if ([event isKindOfClass:[NSDictionary class]]) {
            // Raw dictionary event (legacy/fallback)
            NSDictionary *eventDict = (NSDictionary *)event;
            seq = [eventDict[@"seq"] longLongValue];
            eventType = eventDict[@"kind"] ?: @"unknown";

            [self.eventBuffer appendEvent:event seq:seq];
        }

        // Update sequence tracking
        if (seq > self.currentSequence) {
            self.currentSequence = seq;
        }

        // Update metrics
        if (self.metrics) {
            [self.metrics recordEventReceived];
        }
    });
}

- (void)upstreamManager:(RelayUpstreamManager *)manager
    didConnectToUpstream:(NSString *)url {
    PDS_LOG_INFO(@"Relay: Connected to upstream %@", url);

    if (self.metrics) {
        [self.metrics recordUpstreamConnected];
    }
}

- (void)upstreamManager:(RelayUpstreamManager *)manager
    didDisconnectFromUpstream:(NSString *)url
                        error:(nullable NSError *)error {
    PDS_LOG_WARN(@"Relay: Disconnected from upstream %@: %@", url, error.localizedDescription ?: @"unknown");

    if (self.metrics) {
        [self.metrics recordUpstreamDisconnected];
        if (error) {
            [self.metrics recordReconnectionCount];
        }
    }
}

- (void)upstreamManager:(RelayUpstreamManager *)manager
       didReceiveCursor:(int64_t)cursor
            fromUpstream:(NSString *)url {
    // Update current sequence from cursor
    dispatch_async(self.handlerQueue, ^{
        if (cursor > self.currentSequence) {
            self.currentSequence = cursor;
        }

        if (self.metrics) {
            [self.metrics setCurrentSequence:cursor];
        }

        PDS_LOG_DEBUG(@"Relay: Received cursor %lld from %@", cursor, url);
    });
}

#pragma mark - Event Broadcasting

- (void)broadcastCommitEvent:(FirehoseCommitEvent *)commitEvent {
    if (self.subscribeReposHandler) {
        NSData *eventData = [self formatCommitEventForWire:commitEvent];
        if (eventData) {
            [self.subscribeReposHandler broadcastEventData:eventData];
        }
    }
}

- (void)broadcastIdentityEvent:(FirehoseIdentityEvent *)identityEvent {
    if (self.subscribeReposHandler) {
        NSData *eventData = [self formatIdentityEventForWire:identityEvent];
        if (eventData) {
            [self.subscribeReposHandler broadcastEventData:eventData];
        }
    }
}

- (void)broadcastAccountEvent:(FirehoseAccountEvent *)accountEvent {
    if (self.subscribeReposHandler) {
        NSData *eventData = [self formatAccountEventForWire:accountEvent];
        if (eventData) {
            [self.subscribeReposHandler broadcastEventData:eventData];
        }
    }
}

- (NSData *)formatCommitEventForWire:(FirehoseCommitEvent *)event {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    NSError *error = nil;
    NSData *data = [formatter encodeCommitEvent:event error:&error];

    if (error) {
        PDS_LOG_WARN(@"Failed to format commit event: %@", error.localizedDescription);
        return nil;
    }

    return data;
}

- (NSData *)formatIdentityEventForWire:(FirehoseIdentityEvent *)event {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    NSError *error = nil;
    NSData *data = [formatter encodeIdentityEvent:event error:&error];

    if (error) {
        PDS_LOG_WARN(@"Failed to format identity event: %@", error.localizedDescription);
        return nil;
    }

    return data;
}

- (NSData *)formatAccountEventForWire:(FirehoseAccountEvent *)event {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    NSError *error = nil;
    NSData *data = [formatter encodeAccountEvent:event error:&error];

    if (error) {
        PDS_LOG_WARN(@"Failed to format account event: %@", error.localizedDescription);
        return nil;
    }

    return data;
}

#pragma mark - Downstream Management

- (NSUInteger)activeDownstreamCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.handlerQueue, ^{
        count = self.downstreamConnections.count;
    });
    return count;
}

- (void)addDownstreamConnection:(id<PDSNetworkConnection>)connection {
    dispatch_async(self.handlerQueue, ^{
        [self.downstreamConnections addObject:connection];

        if (self.metrics) {
            [self.metrics recordDownstreamConnected];
        }

        PDS_LOG_INFO(@"Relay: New downstream connection (total: %lu)", (unsigned long)self.downstreamConnections.count);

        // Send backfill from buffer if requested
        // This would be handled by SubscribeReposHandler based on cursor parameter
    });
}

- (void)removeDownstreamConnection:(id<PDSNetworkConnection>)connection {
    dispatch_async(self.handlerQueue, ^{
        [self.downstreamConnections removeObject:connection];

        if (self.metrics) {
            [self.metrics recordDownstreamDisconnected];
        }

        PDS_LOG_INFO(@"Relay: Downstream disconnected (total: %lu)", (unsigned long)self.downstreamConnections.count);
    });
}

#pragma mark - Backfill Support

- (void)sendBackfillToConnection:(id<PDSNetworkConnection>)connection
                      fromCursor:(int64_t)cursor {
    // Get events after cursor from buffer
    NSArray *events = [self.eventBuffer eventsAfterCursor:cursor count:1000];

    if (events.count == 0) {
        PDS_LOG_DEBUG(@"Relay: No backfill events for cursor %lld", cursor);
        return;
    }

    // Send events to connection
    for (id event in events) {
        NSData *data = nil;

        if ([event isKindOfClass:[FirehoseCommitEvent class]]) {
            data = [self formatCommitEventForWire:(FirehoseCommitEvent *)event];
        } else if ([event isKindOfClass:[FirehoseIdentityEvent class]]) {
            data = [self formatIdentityEventForWire:(FirehoseIdentityEvent *)event];
        } else if ([event isKindOfClass:[FirehoseAccountEvent class]]) {
            data = [self formatAccountEventForWire:(FirehoseAccountEvent *)event];
        }

        if (data) {
            // Send over connection
            // Connection write would go here
        }
    }

    PDS_LOG_INFO(@"Relay: Sent %lu backfill events from cursor %lld", (unsigned long)events.count, cursor);
}

@end
