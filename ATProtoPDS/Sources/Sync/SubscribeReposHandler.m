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
#import "Repository/CAR.h"
#import "Debug/PDSLogger.h"
#import "Database/ActorStore/ActorStore.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Repository/CBOR.h"

NSString * const SubscribeReposHandlerErrorDomain = @"com.atproto.pds.subscribeRepos";
NSInteger const SubscribeReposHandlerErrorCodeConnectionFailed = 3000;

static const NSUInteger kSubscribeReposReplayBatchSize = 100;
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;
static const NSUInteger kSubscribeReposMaxPendingSendsDefault = 512;
static const NSUInteger kSubscribeReposMaxPendingBytesDefault = 16 * 1024 * 1024; // 16MB
static NSString * const kSubscribeReposErrorFutureCursor = @"FutureCursor";
static NSString * const kSubscribeReposErrorConsumerTooSlow = @"ConsumerTooSlow";
static NSString * const kSubscribeReposErrorInvalidCursor = @"InvalidCursor";

@interface SubscribeReposHandler () <WebSocketServerDelegate, WebSocketConnectionDelegate>

@property (nonatomic, strong) WebSocketServer *webSocketServer;
@property (nonatomic, strong) EventFormatter *eventFormatter;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) PDSDatabasePool *userDatabasePool;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t eventQueue;
@property (nonatomic, assign) NSUInteger sequenceNumber;
@property (nonatomic, assign) BOOL sequenceInitialized;
@property (nonatomic, assign) BOOL stopping;
@property (nonatomic, strong) NSMutableSet<WebSocketConnection *> *attachedConnections;
@property (nonatomic, assign) NSUInteger maxReplayEventsPerConnection;
@property (nonatomic, assign) NSUInteger maxPendingSendsPerConnection;
@property (nonatomic, assign) NSUInteger maxPendingBytesPerConnection;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *lastCommitRevByDID;

- (void)ensureSequenceInitialized;
- (BOOL)parseCursorString:(nullable NSString *)cursor outValue:(NSUInteger *)outValue;
- (void)sendErrorFrameWithCode:(NSString *)code message:(NSString *)message toConnection:(WebSocketConnection *)connection;
- (void)detachConnection:(WebSocketConnection *)connection;
- (BOOL)sendEventData:(NSData *)eventData toConnectionWithBackpressureCheck:(WebSocketConnection *)connection;
+ (NSString *)rfc3339Timestamp;
- (NSData *)buildCARBlocksForCommit:(RepoCommit *)commit ops:(NSArray<NSDictionary *> *)ops;
- (nullable CID *)extractCIDFromCBORTag:(CBORValue *)tagValue;
- (NSUInteger)addMSTNodeBlocksForRootCID:(CID *)rootCID did:(NSString *)repoDid toWriter:(CARWriter *)writer;

@end

@implementation SubscribeReposHandler

static void *kSubscribeReposEventQueueKey = &kSubscribeReposEventQueueKey;

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases 
                        userDatabasePool:(nullable PDSDatabasePool *)userDatabasePool {
    self = [super init];
    if (self) {
        _serviceDatabases = serviceDatabases;
        _userDatabasePool = userDatabasePool;
        _eventFormatter = [[EventFormatter alloc] init];
        _eventQueue = dispatch_queue_create("com.atproto.pds.subscribeRepos.events", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_eventQueue, kSubscribeReposEventQueueKey, kSubscribeReposEventQueueKey, NULL);
        _sequenceNumber = 0;
        _sequenceInitialized = NO;
        _stopping = NO;
        _attachedConnections = [NSMutableSet set];
        _maxReplayEventsPerConnection = kSubscribeReposMaxReplayEventsDefault;
        _maxPendingSendsPerConnection = kSubscribeReposMaxPendingSendsDefault;
        _maxPendingBytesPerConnection = kSubscribeReposMaxPendingBytesDefault;
        _lastCommitRevByDID = [NSMutableDictionary dictionary];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRecordChange:)
                                                     name:PDSRecordDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    return [self initWithServiceDatabases:serviceDatabases userDatabasePool:nil];
}

- (instancetype)initWithController:(PDSController *)controller {
    return [self initWithServiceDatabases:controller.serviceDatabases userDatabasePool:controller.userDatabasePool];
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

    @synchronized (self.attachedConnections) {
        [self.attachedConnections addObject:connection];
    }

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didAcceptConnection:)]) {
        [self.delegate subscribeReposHandler:self didAcceptConnection:connection];
    }

    [self sendInitialRepositoryStateToConnection:connection cursor:nil];
}

- (void)webSocketServer:(WebSocketServer *)server didCloseConnection:(WebSocketConnection *)connection {
    PDS_LOG_SYNC_INFO(@"Closed WebSocket connection for subscribeRepos");
    [self detachConnection:connection];

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

    NSString *cidStr = info[@"cid"];
    // NSString *prevStr = info[@"prev"]; // Unused with new logic
    NSString *commitStr = info[@"commit"]; // This is the signed Commit CID
    // NSString *revStr = info[@"rev"];    // We get rev from the loaded commit
    id recordCBORValue = info[@"recordCBOR"];
    NSData *recordCBOR = ([recordCBORValue isKindOfClass:[NSData class]]) ? recordCBORValue : nil;

    CID *opCID = (cidStr && ![cidStr isKindOfClass:[NSNull class]]) ? [CID cidFromString:cidStr] : nil;
    CID *commitCID = (commitStr && ![commitStr isKindOfClass:[NSNull class]]) ? [CID cidFromString:commitStr] : nil;

    NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    NSMutableDictionary *op = [@{
        @"action": action ?: @"create",
        @"path": path,
        @"cid": opCID ?: [NSNull null]
    } mutableCopy];
    if (recordCBOR) {
        op[@"recordCBOR"] = recordCBOR;
    }

    RepoCommit *commit = nil;

    // Try to load the stored, signed commit block
    if (self.userDatabasePool && commitCID) {
        NSError *dbError = nil;
        PDSActorStore *store = [self.userDatabasePool storeForDid:did error:&dbError];
        if (store) {
            NSData *blockData = [store getBlockForCID:[commitCID bytes] forDid:did error:&dbError];
            if (blockData) {
                NSError *decodeError = nil;
                id decoded = [ATProtoDagCBOR decodeData:blockData error:&decodeError];
                if ([decoded isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *commitMap = (NSDictionary *)decoded;
                    commit = [[RepoCommit alloc] init];
                    commit.did = did;
                    commit.version = [commitMap[@"version"] integerValue] ?: 3;
                    commit.rev = commitMap[@"rev"];
                    
                    id dataVal = commitMap[@"data"];
                    if ([dataVal isKindOfClass:[CID class]]) commit.dataCID = (CID *)dataVal;
                    
                    id prevVal = commitMap[@"prev"];
                    if ([prevVal isKindOfClass:[CID class]]) commit.prevCID = (CID *)prevVal;
                    
                    id sigVal = commitMap[@"sig"];
                    if ([sigVal isKindOfClass:[NSData class]]) commit.signature = (NSData *)sigVal;
                    
            }
        }
    }
    }

    if (!commit || !commit.signature) {
             PDS_LOG_SYNC_ERROR(@"Failed to load valid signed commit for firehose broadcast (DID: %@)", did);
             return;
    }

    [self broadcastRepositoryCommit:commit forRepo:did ops:@[[op copy]] blobs:@[]];
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
        
        // Required fields per subscribeRepos lexicon
        event.seq = self.sequenceNumber;
        event.rebase = NO;  // Deprecated, always false
        event.tooBig = NO;  // Deprecated, always false
        event.repo = repoDid;
        event.commit = commit.computeCID;
        event.rev = commit.rev;
        event.since = self.lastCommitRevByDID[repoDid];  // Previous commit rev for this repo
        event.blocks = [self buildCARBlocksForCommit:commit ops:ops];  // Real CAR bytes
        event.ops = ops;
        event.blobs = blobs ?: @[];  // Already CID array
        event.time = [SubscribeReposHandler rfc3339Timestamp];
        event.prevData = commit.prevCID ?: nil;  // Previous MST root CID

        // Update the per-DID tracking for next event's since field
        if (commit.rev) {
            self.lastCommitRevByDID[repoDid] = commit.rev;
        }

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeCommitEvent:event error:&error];

        if (!eventData) {
            PDS_LOG_SYNC_ERROR(@"Failed to encode commit event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.serviceDatabases persistEvent:self.sequenceNumber type:@"commit" data:eventData error:&persistError]) {
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
        event.seq = self.sequenceNumber;
        event.did = did;
        event.time = [SubscribeReposHandler rfc3339Timestamp];
        event.handle = handle;

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeIdentityEvent:event error:&error];

        if (!eventData) {
            PDS_LOG_SYNC_ERROR(@"Failed to encode identity event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.serviceDatabases persistEvent:self.sequenceNumber type:@"identity" data:eventData error:&persistError]) {
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
        event.seq = self.sequenceNumber;
        event.did = did;
        event.active = NO;
        event.status = @"takendown";
        event.time = [SubscribeReposHandler rfc3339Timestamp];

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeAccountEvent:event error:&error];

        if (!eventData) {
            PDS_LOG_SYNC_ERROR(@"Failed to encode account event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.serviceDatabases persistEvent:self.sequenceNumber type:@"account" data:eventData error:&persistError]) {
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
        if (![self.serviceDatabases persistEvent:self.sequenceNumber type:@"info" data:eventData error:&persistError]) {
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
        // Removed: Sending initial state identity events is non-spec behavior
        // Per ATProto spec, firehose should only emit events for actual changes,
        // not send identity events for all existing repos on connection.
        // Clients should use getRepo/listRepos endpoints for initial discovery.
        /*
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
        */

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
        NSArray *events = [self.serviceDatabases getEventsSince:fetchCursor limit:kSubscribeReposReplayBatchSize error:&error];
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

    if (connection.pendingSendCount >= self.maxPendingSendsPerConnection ||
        connection.pendingSendBytes >= self.maxPendingBytesPerConnection) {
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
        int64_t maxSequence = [self.serviceDatabases getMaxEventSequence:&dbError];
        if (dbError) {
            PDS_LOG_SYNC_ERROR(@"Failed to get max event sequence: %@", dbError);
            return;
        }

        self.sequenceNumber = (NSUInteger)MAX((int64_t)0, maxSequence);
        self.sequenceInitialized = YES;
        PDS_LOG_SYNC_INFO(@"Initialized sequence number to %lu", (unsigned long)self.sequenceNumber);
    }
}

+ (NSString *)rfc3339Timestamp {
    static NSISO8601DateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                                   NSISO8601DateFormatWithFractionalSeconds;
    });
    return [formatter stringFromDate:[NSDate date]];
}

- (NSData *)buildCARBlocksForCommit:(RepoCommit *)commit ops:(NSArray<NSDictionary *> *)ops {
    // Build a CAR file containing commit block + record blocks for changed records.
    // Per ATProto spec, firehose CAR must contain:
    //  1. The signed commit block (root)
    //  2. Record blocks for create/update ops
    //  3. MST node blocks reachable from the new MST root (commit.dataCID)
    
    CID *commitCID = commit.computeCID;
    if (!commitCID) {
        PDS_LOG_SYNC_ERROR(@"Failed to compute commit CID for CAR");
        return [NSData data];
    }
    
    CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
    
    // Extract the signed commit block from the single-block CAR that exportCAR produces
    NSData *singleBlockCAR = [commit exportCAR];
    if (singleBlockCAR) {
        CARReader *reader = [CARReader readFromData:singleBlockCAR error:nil];
        CARBlock *commitBlock = reader.blocks.firstObject;
        if (commitBlock) {
            [writer addBlock:commitBlock];
        }
    }
    
    // Add record blocks for create/update ops
    NSUInteger recordBlockCount = 0;
    for (NSDictionary *op in ops) {
        NSString *action = op[@"action"];
        if ([action isEqualToString:@"delete"]) continue;
        
        NSData *recordCBOR = op[@"recordCBOR"];
        if (![recordCBOR isKindOfClass:[NSData class]] || recordCBOR.length == 0) continue;
        
        // Compute the CID for the record block from its DAG-CBOR bytes
        // CIDv1, dag-cbor codec (0x71), SHA-256 multihash
        NSData *digest = [CID rawSha256:recordCBOR];
        CID *recordCID = digest ? [CID cidWithDigest:digest codec:0x71] : nil;
        if (recordCID) {
            [writer addBlock:[CARBlock blockWithCID:recordCID data:recordCBOR]];
            recordBlockCount++;
        }
    }
    
    // Add MST node blocks reachable from the new MST root
    NSUInteger mstBlockCount = 0;
    if (commit.dataCID && commit.did.length > 0) {
        mstBlockCount = [self addMSTNodeBlocksForRootCID:commit.dataCID did:commit.did toWriter:writer];
    }

    NSData *carData = [writer serialize];
    PDS_LOG_SYNC_DEBUG(@"Built CAR blocks: %lu bytes (commit + %lu record blocks + %lu MST node blocks)",
                       (unsigned long)carData.length, (unsigned long)recordBlockCount,
                       (unsigned long)mstBlockCount);

    return carData ?: [NSData data];
}

- (nullable CID *)extractCIDFromCBORTag:(CBORValue *)tagValue {
    if (!tagValue || tagValue.type != CBORTypeTag) return nil;
    CBORValue *inner = tagValue.tagValue;
    if (!inner || inner.type != CBORTypeByteString || inner.byteString.length <= 1) return nil;
    NSData *cidBytes = [inner.byteString subdataWithRange:NSMakeRange(1, inner.byteString.length - 1)];
    return [CID cidFromBytes:cidBytes];
}

// BFS traversal of MST blocks from rootCID, loading each block from the actor store
// and adding it to writer. Returns the number of blocks added.
- (NSUInteger)addMSTNodeBlocksForRootCID:(CID *)rootCID did:(NSString *)repoDid toWriter:(CARWriter *)writer {
    if (!rootCID || !repoDid || !writer || !self.userDatabasePool) return 0;

    NSError *dbError = nil;
    PDSActorStore *store = [self.userDatabasePool storeForDid:repoDid error:&dbError];
    if (!store || dbError) {
        PDS_LOG_SYNC_WARN(@"Could not get actor store for %@ to load MST nodes: %@", repoDid, dbError);
        return 0;
    }

    NSMutableArray<NSData *> *queue = [NSMutableArray arrayWithObject:[rootCID bytes]];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    NSUInteger count = 0;

    while (queue.count > 0) {
        NSData *cidBytes = queue.firstObject;
        [queue removeObjectAtIndex:0];

        CID *nodeCID = [CID cidFromBytes:cidBytes];
        if (!nodeCID) continue;

        NSString *cidKey = nodeCID.stringValue;
        if (!cidKey || [visited containsObject:cidKey]) continue;
        [visited addObject:cidKey];

        NSError *blockError = nil;
        NSData *blockData = [store getBlockForCID:cidBytes forDid:repoDid error:&blockError];
        if (!blockData) {
            if (blockError) {
                PDS_LOG_SYNC_DEBUG(@"MST block not found for CID %@: %@", cidKey, blockError);
            }
            continue;
        }

        [writer addBlock:[CARBlock blockWithCID:nodeCID data:blockData]];
        count++;

        // Parse the MST node CBOR to discover child node CIDs:
        //   "l" key: left subtree CID (CBOR tag 42)
        //   "e" key: array of entry maps, each with "t" key: right subtree CID (CBOR tag 42)
        CBORValue *nodeMap = [CBORValue decode:blockData];
        if (!nodeMap || nodeMap.type != CBORTypeMap) continue;

        CID *lCID = [self extractCIDFromCBORTag:nodeMap.map[[CBORValue textString:@"l"]]];
        if (lCID) [queue addObject:[lCID bytes]];

        CBORValue *eArray = nodeMap.map[[CBORValue textString:@"e"]];
        if (eArray && eArray.type == CBORTypeArray) {
            for (CBORValue *entry in eArray.array) {
                if (entry.type != CBORTypeMap) continue;
                CID *tCID = [self extractCIDFromCBORTag:entry.map[[CBORValue textString:@"t"]]];
                if (tCID) [queue addObject:[tCID bytes]];
            }
        }
    }

    return count;
}

@end
