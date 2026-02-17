#import "Sync/SubscribeReposHandler.h"
#import "Compat/PDSTypes.h"
#import "Sync/WebSocketServer.h"
#import "Sync/WebSocketConnection.h"
#import "App/PDSController.h"
#import "App/Services/PDSRecordService.h"
#import "Sync/EventFormatter.h"
#import "Sync/Firehose.h"
#import "Network/HttpRequest.h"
#import "Repository/RepoCommit.h"
#import "Core/TID.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"

NSString * const SubscribeReposHandlerErrorDomain = @"com.atproto.pds.subscribeRepos";
NSInteger const SubscribeReposHandlerErrorCodeConnectionFailed = 3000;

static const NSUInteger kSubscribeReposReplayBatchSize = 100;
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;
static const NSUInteger kSubscribeReposMaxPendingSendsDefault = 512;
static NSString * const kSubscribeReposErrorFutureCursor = @"FutureCursor";
static NSString * const kSubscribeReposErrorConsumerTooSlow = @"ConsumerTooSlow";
static NSString * const kSubscribeReposErrorInvalidCursor = @"InvalidCursor";

@interface SubscribeReposHandler () <WebSocketServerDelegate, WebSocketConnectionDelegate>

@property (nonatomic, strong) WebSocketServer *webSocketServer;
@property (nonatomic, strong) EventFormatter *eventFormatter;
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t eventQueue;
@property (nonatomic, assign) NSUInteger sequenceNumber;
@property (nonatomic, assign) BOOL sequenceInitialized;
@property (nonatomic, assign) BOOL stopping;
@property (nonatomic, strong) NSMutableSet<WebSocketConnection *> *attachedConnections;
@property (nonatomic, assign) NSUInteger maxReplayEventsPerConnection;
@property (nonatomic, assign) NSUInteger maxPendingSendsPerConnection;

- (void)ensureSequenceInitialized;
- (BOOL)parseCursorString:(nullable NSString *)cursor outValue:(NSUInteger *)outValue;
- (void)sendErrorFrameWithCode:(NSString *)code message:(NSString *)message toConnection:(WebSocketConnection *)connection;
- (void)detachConnection:(WebSocketConnection *)connection;
- (BOOL)sendEventData:(NSData *)eventData toConnectionWithBackpressureCheck:(WebSocketConnection *)connection;

@end

@implementation SubscribeReposHandler

static void *kSubscribeReposEventQueueKey = &kSubscribeReposEventQueueKey;

- (instancetype)initWithController:(PDSController *)controller {
    self = [super init];
    if (self) {
        _controller = controller;
        _eventFormatter = [[EventFormatter alloc] init];
        _eventQueue = dispatch_queue_create("com.atproto.pds.subscribeRepos.events", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_eventQueue, kSubscribeReposEventQueueKey, kSubscribeReposEventQueueKey, NULL);
        _sequenceNumber = 0;
        _sequenceInitialized = NO;
        _stopping = NO;
        _attachedConnections = [NSMutableSet set];
        _maxReplayEventsPerConnection = kSubscribeReposMaxReplayEventsDefault;
        _maxPendingSendsPerConnection = kSubscribeReposMaxPendingSendsDefault;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRecordChange:)
                                                     name:PDSRecordDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error {
    PDS_LOG_SYNC_INFO(@"Starting subscribeRepos WebSocket handler on port %d", port);

    [self ensureSequenceInitialized];

    self.webSocketServer = [[WebSocketServer alloc] initWithHost:@"localhost" port:port];
    self.webSocketServer.delegate = self;
    self.webSocketServer.subprotocol = @"com.atproto.sync.subscribeRepos";

    if (![self.webSocketServer start:error]) {
        PDS_LOG_SYNC_ERROR(@"Failed to start WebSocket server: %@", *error);
        return NO;
    }

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandlerDidStart:)]) {
        [self.delegate subscribeReposHandlerDidStart:self];
    }

    PDS_LOG_SYNC_INFO(@"SubscribeRepos WebSocket handler started successfully");
    return YES;
}

- (void)stop {
    PDS_LOG_SYNC_INFO(@"Stopping subscribeRepos WebSocket handler");

    self.stopping = YES;
    if (dispatch_get_specific(kSubscribeReposEventQueueKey) == NULL) {
        dispatch_sync(self.eventQueue, ^{
        });
    }

    NSSet<WebSocketConnection *> *attachedSnapshot = nil;
    @synchronized (self.attachedConnections) {
        attachedSnapshot = [self.attachedConnections copy];
        [self.attachedConnections removeAllObjects];
    }
    for (WebSocketConnection *connection in attachedSnapshot) {
        [connection close];
    }

    [self.webSocketServer stop];
    self.webSocketServer = nil;

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandlerDidStop:)]) {
        [self.delegate subscribeReposHandlerDidStop:self];
    }

    PDS_LOG_SYNC_INFO(@"SubscribeRepos WebSocket handler stopped");
}

- (void)acceptUpgradedConnection:(id<PDSNetworkConnection>)connection request:(HttpRequest *)request {
    [self ensureSequenceInitialized];

    WebSocketConnection *webSocketConnection = [[WebSocketConnection alloc] initWithConnection:connection];
    webSocketConnection.delegate = self;
    @synchronized (self.attachedConnections) {
        [self.attachedConnections addObject:webSocketConnection];
    }

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didAcceptConnection:)]) {
        [self.delegate subscribeReposHandler:self didAcceptConnection:webSocketConnection];
    }

    [webSocketConnection startOnExistingTransport];
    [self sendInitialRepositoryStateToConnection:webSocketConnection cursor:[request queryParamForKey:@"cursor"]];
}

#pragma mark - WebSocketServerDelegate

- (void)webSocketServer:(WebSocketServer *)server didAcceptConnection:(WebSocketConnection *)connection {
    PDS_LOG_SYNC_INFO(@"Accepted new WebSocket connection for subscribeRepos");

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didAcceptConnection:)]) {
        [self.delegate subscribeReposHandler:self didAcceptConnection:connection];
    }

    [self sendInitialRepositoryStateToConnection:connection cursor:nil];
}

- (void)webSocketServer:(WebSocketServer *)server didCloseConnection:(WebSocketConnection *)connection {
    PDS_LOG_SYNC_INFO(@"Closed WebSocket connection for subscribeRepos");

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didCloseConnection:)]) {
        [self.delegate subscribeReposHandler:self didCloseConnection:connection];
    }
}

- (void)webSocketServer:(WebSocketServer *)server didFailWithError:(NSError *)error {
    PDS_LOG_SYNC_ERROR(@"WebSocket server failed: %@", error);
}

- (void)webSocketServer:(WebSocketServer *)server stateDidChange:(WebSocketServerState)state {
    PDS_LOG_SYNC_INFO(@"WebSocket server state changed to: %ld", (long)state);
}

#pragma mark - WebSocketConnectionDelegate

- (void)webSocketConnection:(WebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason {
    PDS_LOG_SYNC_INFO(@"Main-port WebSocket connection closed (code=%ld, reason=%@)", (long)code, reason ?: @"");
    [self detachConnection:connection];
    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didCloseConnection:)]) {
        [self.delegate subscribeReposHandler:self didCloseConnection:connection];
    }
}

- (void)webSocketConnection:(WebSocketConnection *)connection didFailWithError:(NSError *)error {
    PDS_LOG_SYNC_ERROR(@"Main-port WebSocket connection failed: %@", error);
    [self detachConnection:connection];
    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didCloseConnection:)]) {
        [self.delegate subscribeReposHandler:self didCloseConnection:connection];
    }
}

#pragma mark - Record Change Notification

- (void)handleRecordChange:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSString *did = info[@"did"];
    NSString *collection = info[@"collection"];
    NSString *rkey = info[@"rkey"];
    NSString *action = info[@"action"];

    if (!did || !collection || !rkey) return;

    NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    NSDictionary *op = @{
        @"action": action ?: @"create",
        @"path": path,
        @"cid": [NSNull null]
    };

    RepoCommit *commit = [RepoCommit createCommitWithDid:did
                                                    data:nil
                                                     rev:[[TID tid] stringValue]
                                                   prev:nil];

    [self broadcastRepositoryCommit:commit forRepo:did ops:@[op] blobs:@[]];
}

#pragma mark - Event Broadcasting

- (void)broadcastRepositoryCommit:(RepoCommit *)commit
                          forRepo:(NSString *)repoDid
                              ops:(NSArray<NSDictionary *> *)ops
                            blobs:(NSArray<CID *> *)blobs {
    if (self.stopping) {
        return;
    }
    dispatch_async(self.eventQueue, ^{
        [self ensureSequenceInitialized];
        self.sequenceNumber++;

        FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
        event.repo = repoDid;
        event.commit = [commit.computeCID stringValue];
        event.previous = [commit.prevCID stringValue];
        event.ops = ops;
        event.blobs = [blobs valueForKey:@"stringValue"];

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeCommitEvent:event error:&error];

        if (!eventData) {
            PDS_LOG_SYNC_ERROR(@"Failed to encode commit event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.controller.serviceDatabases persistEvent:self.sequenceNumber type:@"commit" data:eventData error:&persistError]) {
            PDS_LOG_SYNC_ERROR(@"Failed to persist commit event: %@", persistError);
        }

        [self broadcastEventData:eventData];
        PDS_LOG_SYNC_INFO(@"Broadcast commit event for repo %@, seq %lu", repoDid, (unsigned long)self.sequenceNumber);
    });
}

- (void)broadcastIdentityChange:(NSString *)did handle:(nullable NSString *)handle {
    if (self.stopping) {
        return;
    }
    dispatch_async(self.eventQueue, ^{
        [self ensureSequenceInitialized];
        self.sequenceNumber++;

        FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
        event.did = did;
        event.handle = handle;

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeIdentityEvent:event error:&error];

        if (!eventData) {
            PDS_LOG_SYNC_ERROR(@"Failed to encode identity event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.controller.serviceDatabases persistEvent:self.sequenceNumber type:@"identity" data:eventData error:&persistError]) {
            PDS_LOG_SYNC_ERROR(@"Failed to persist identity event: %@", persistError);
        }

        [self broadcastEventData:eventData];
        PDS_LOG_SYNC_INFO(@"Broadcast identity event for DID %@, seq %lu", did, (unsigned long)self.sequenceNumber);
    });
}

- (void)broadcastAccountTakedown:(NSString *)did {
    if (self.stopping) {
        return;
    }
    dispatch_async(self.eventQueue, ^{
        [self ensureSequenceInitialized];
        self.sequenceNumber++;

        FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
        event.did = did;
        event.active = NO;
        event.status = @"takendown";
        event.time = [[NSDate date] description];

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeAccountEvent:event error:&error];

        if (!eventData) {
            PDS_LOG_SYNC_ERROR(@"Failed to encode account event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.controller.serviceDatabases persistEvent:self.sequenceNumber type:@"account" data:eventData error:&persistError]) {
            PDS_LOG_SYNC_ERROR(@"Failed to persist account event: %@", persistError);
        }

        [self broadcastEventData:eventData];
        PDS_LOG_SYNC_INFO(@"Broadcast account takedown event for DID %@, seq %lu", did, (unsigned long)self.sequenceNumber);
    });
}

- (void)broadcastInfo:(NSString *)kind message:(NSString *)message {
    if (self.stopping) {
        return;
    }
    dispatch_async(self.eventQueue, ^{
        [self ensureSequenceInitialized];
        self.sequenceNumber++;

        FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
        event.kind = kind;
        event.message = message;

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeInfoEvent:event error:&error];

        if (!eventData) {
            PDS_LOG_SYNC_ERROR(@"Failed to encode info event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.controller.serviceDatabases persistEvent:self.sequenceNumber type:@"info" data:eventData error:&persistError]) {
            PDS_LOG_SYNC_ERROR(@"Failed to persist info event: %@", persistError);
        }

        [self broadcastEventData:eventData];
        PDS_LOG_SYNC_INFO(@"Broadcast info event (%@), seq %lu", kind, (unsigned long)self.sequenceNumber);
    });
}

#pragma mark - Private Methods

- (void)broadcastEventData:(NSData *)eventData {
    [self.webSocketServer broadcastMessage:eventData toConnectionsMatching:nil];
    NSSet<WebSocketConnection *> *attachedSnapshot = nil;
    @synchronized (self.attachedConnections) {
        attachedSnapshot = [self.attachedConnections copy];
    }
    for (WebSocketConnection *connection in attachedSnapshot) {
        [self sendEventData:eventData toConnectionWithBackpressureCheck:connection];
    }
}

- (void)sendInitialRepositoryStateToConnection:(WebSocketConnection *)connection cursor:(nullable NSString *)cursor {
    PDS_LOG_SYNC_INFO(@"Sending initial repository state to new connection");

    if (!cursor) {
        id cursorParam = connection.queryParams[@"cursor"];
        if ([cursorParam isKindOfClass:[NSString class]]) {
            cursor = cursorParam;
        } else if ([cursorParam isKindOfClass:[NSArray class]] && [(NSArray *)cursorParam count] > 0) {
            id firstValue = [(NSArray *)cursorParam firstObject];
            if ([firstValue isKindOfClass:[NSString class]]) {
                cursor = firstValue;
            }
        }
    }

    __block BOOL hasCursor = (cursor.length > 0);
    __block NSUInteger parsedCursor = 0;
    __block BOOL cursorValid = YES;
    if (hasCursor) {
        cursorValid = [self parseCursorString:cursor outValue:&parsedCursor];
        if (cursorValid) {
            PDS_LOG_SYNC_INFO(@"Client requested resumption from cursor %@ (seq %lu)", cursor, (unsigned long)parsedCursor);
        }
    }

    dispatch_async(self.eventQueue, ^{
        [self ensureSequenceInitialized];

        if (hasCursor && !cursorValid) {
            [self sendErrorFrameWithCode:kSubscribeReposErrorInvalidCursor
                                 message:@"cursor must be a non-negative integer"
                            toConnection:connection];
            [self detachConnection:connection];
            [connection closeWithCode:1008 reason:kSubscribeReposErrorInvalidCursor];
            return;
        }

        if (hasCursor && parsedCursor > self.sequenceNumber) {
            [self sendErrorFrameWithCode:kSubscribeReposErrorFutureCursor
                                 message:@"requested cursor is ahead of server sequence"
                            toConnection:connection];
            [self detachConnection:connection];
            [connection closeWithCode:1008 reason:kSubscribeReposErrorFutureCursor];
            return;
        }

        NSUInteger cursorSeq = hasCursor ? parsedCursor : 0;
        if (cursorSeq == 0) {
            NSError *error = nil;
            NSArray<PDSDatabaseRepo *> *repos = [self.controller.userDatabasePool getAllReposWithError:&error];

            if (error) {
                PDS_LOG_SYNC_ERROR(@"Failed to get all repos: %@", error);
                [self sendInfoEvent:@"OutdatedCursor" message:@"Unable to retrieve repository state" toConnection:connection];
                return;
            }

            for (PDSDatabaseRepo *repo in repos) {
                if (repo.rootCid.length > 0) {
                    NSData *rootCidData = repo.rootCid;
                    CID *cid = [CID cidFromBytes:rootCidData];
                    NSString *cidString = cid ? [cid stringValue] : [rootCidData base64EncodedStringWithOptions:0];

                    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
                    event.did = repo.ownerDid;

                    NSError *encodeError = nil;
                    NSData *eventData = [self.eventFormatter encodeIdentityEvent:event error:&encodeError];

                    if (eventData) {
                        if (![self sendEventData:eventData toConnectionWithBackpressureCheck:connection]) {
                            return;
                        }
                        PDS_LOG_SYNC_DEBUG(@"Sent identity event for repo %@ (root: %@)", repo.ownerDid, cidString);
                    } else {
                        PDS_LOG_SYNC_ERROR(@"Failed to encode identity event for repo %@: %@", repo.ownerDid, encodeError);
                    }
                }
            }
            PDS_LOG_SYNC_INFO(@"Completed sending initial state for %lu repos to new connection", (unsigned long)repos.count);
        }

        if (cursorSeq > 0) {
            NSUInteger backlog = self.sequenceNumber - cursorSeq;
            if (backlog > self.maxReplayEventsPerConnection) {
                [self sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
                                     message:@"cursor backlog exceeds replay window"
                                toConnection:connection];
                [self detachConnection:connection];
                [connection closeWithCode:1008 reason:kSubscribeReposErrorConsumerTooSlow];
                return;
            }
            [self replayEventsAfterCursor:cursorSeq toConnection:connection];
        }
    });
}

- (void)replayEventsAfterCursor:(NSUInteger)cursor toConnection:(WebSocketConnection *)connection {
    PDS_LOG_SYNC_INFO(@"Replaying events after cursor %lu", (unsigned long)cursor);
    [self ensureSequenceInitialized];
    
    NSUInteger fetchCursor = cursor;
    NSUInteger replayedCount = 0;
    BOOL hasMore = YES;
    
    while (hasMore) {
        NSError *error = nil;
        NSArray *events = [self.controller.serviceDatabases getEventsSince:fetchCursor limit:kSubscribeReposReplayBatchSize error:&error];
        if (error || !events) {
            PDS_LOG_SYNC_ERROR(@"Failed to fetch events for replay: %@", error);
            break;
        }
        
        if (events.count == 0) {
            hasMore = NO;
            break;
        }
        
        for (NSDictionary *event in events) {
            NSNumber *seq = event[@"seq"];
            NSData *data = event[@"data"];

            replayedCount++;
            if (replayedCount > self.maxReplayEventsPerConnection) {
                [self sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
                                     message:@"replay window exceeded while backfilling"
                                toConnection:connection];
                [self detachConnection:connection];
                [connection closeWithCode:1008 reason:kSubscribeReposErrorConsumerTooSlow];
                return;
            }

            if (![self sendEventData:data toConnectionWithBackpressureCheck:connection]) {
                return;
            }
            fetchCursor = [seq unsignedIntegerValue];
        }
        
        if (events.count < kSubscribeReposReplayBatchSize) {
            hasMore = NO;
        }
        
        if (fetchCursor >= self.sequenceNumber) {
            hasMore = NO;
        }
    }
    
    PDS_LOG_SYNC_INFO(@"Replay completed. Last cursor: %lu", (unsigned long)fetchCursor);
}

- (void)sendInfoEvent:(NSString *)kind message:(NSString *)message toConnection:(WebSocketConnection *)connection {
    FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
    event.kind = kind;
    event.message = message;

    NSError *error = nil;
    NSData *eventData = [self.eventFormatter encodeInfoEvent:event error:&error];

    if (eventData) {
        [connection sendMessage:eventData];
        PDS_LOG_SYNC_DEBUG(@"Sent info event (%@) to connection", kind);
    } else {
        PDS_LOG_SYNC_ERROR(@"Failed to encode info event: %@", error);
    }
}

- (BOOL)parseCursorString:(nullable NSString *)cursor outValue:(NSUInteger *)outValue {
    if (cursor.length == 0) {
        if (outValue) *outValue = 0;
        return YES;
    }

    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([cursor rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return NO;
    }

    NSScanner *scanner = [NSScanner scannerWithString:cursor];
    unsigned long long parsed = 0;
    if (![scanner scanUnsignedLongLong:&parsed] || ![scanner isAtEnd]) {
        return NO;
    }
    if (parsed > (unsigned long long)NSUIntegerMax) {
        return NO;
    }

    if (outValue) *outValue = (NSUInteger)parsed;
    return YES;
}

- (void)sendErrorFrameWithCode:(NSString *)code message:(NSString *)message toConnection:(WebSocketConnection *)connection {
    FirehoseErrorEvent *event = [FirehoseErrorEvent eventWithError:code message:message];
    NSError *error = nil;
    NSData *eventData = [self.eventFormatter encodeErrorEvent:event error:&error];
    if (eventData) {
        [connection sendMessage:eventData];
    } else {
        PDS_LOG_SYNC_ERROR(@"Failed to encode error event (%@): %@", code, error);
    }
}

- (void)detachConnection:(WebSocketConnection *)connection {
    @synchronized (self.attachedConnections) {
        [self.attachedConnections removeObject:connection];
    }
}

- (BOOL)sendEventData:(NSData *)eventData toConnectionWithBackpressureCheck:(WebSocketConnection *)connection {
    if (!eventData || !connection) {
        return NO;
    }

    if (connection.pendingSendCount >= self.maxPendingSendsPerConnection) {
        [self sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
                             message:@"connection output queue exceeded server limit"
                        toConnection:connection];
        [self detachConnection:connection];
        [connection closeWithCode:1008 reason:kSubscribeReposErrorConsumerTooSlow];
        return NO;
    }

    [connection sendMessage:eventData];
    return YES;
}

- (void)ensureSequenceInitialized {
    @synchronized (self) {
        if (self.sequenceInitialized) {
            return;
        }

        NSError *dbError = nil;
        int64_t maxSequence = [self.controller.serviceDatabases getMaxEventSequence:&dbError];
        if (dbError) {
            PDS_LOG_SYNC_ERROR(@"Failed to get max event sequence: %@", dbError);
            return;
        }

        self.sequenceNumber = (NSUInteger)MAX((int64_t)0, maxSequence);
        self.sequenceInitialized = YES;
        PDS_LOG_SYNC_INFO(@"Initialized sequence number to %lu", (unsigned long)self.sequenceNumber);
    }
}

@end
