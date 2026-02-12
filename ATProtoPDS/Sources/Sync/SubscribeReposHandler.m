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
#import <os/log.h>

NSString * const SubscribeReposHandlerErrorDomain = @"com.atproto.pds.subscribeRepos";
NSInteger const SubscribeReposHandlerErrorCodeConnectionFailed = 3000;

@interface SubscribeReposHandler () <WebSocketServerDelegate, WebSocketConnectionDelegate>

@property (nonatomic, strong) WebSocketServer *webSocketServer;
@property (nonatomic, strong) EventFormatter *eventFormatter;
@property (nonatomic, strong) PDSController *controller;
#if defined(GNUSTEP)
@property (nonatomic, assign) os_log_t log;
#else
@property (nonatomic, strong) os_log_t log;
#endif
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t eventQueue;
@property (nonatomic, assign) NSUInteger sequenceNumber;
@property (nonatomic, assign) BOOL sequenceInitialized;
@property (nonatomic, strong) NSMutableSet<WebSocketConnection *> *attachedConnections;

- (void)ensureSequenceInitialized;

@end

@implementation SubscribeReposHandler

- (instancetype)initWithController:(PDSController *)controller {
    self = [super init];
    if (self) {
        _controller = controller;
        _eventFormatter = [[EventFormatter alloc] init];
        _log = os_log_create("com.atproto.pds.subscribeRepos", "SubscribeReposHandler");
        _eventQueue = dispatch_queue_create("com.atproto.pds.subscribeRepos.events", DISPATCH_QUEUE_SERIAL);
        _sequenceNumber = 0;
        _sequenceInitialized = NO;
        _attachedConnections = [NSMutableSet set];

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
    os_log_info(self.log, "Starting subscribeRepos WebSocket handler on port %d", port);

    [self ensureSequenceInitialized];

    self.webSocketServer = [[WebSocketServer alloc] initWithHost:@"localhost" port:port];
    self.webSocketServer.delegate = self;
    self.webSocketServer.subprotocol = @"com.atproto.sync.subscribeRepos";

    if (![self.webSocketServer start:error]) {
        os_log_error(self.log, "Failed to start WebSocket server: %@", *error);
        return NO;
    }

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandlerDidStart:)]) {
        [self.delegate subscribeReposHandlerDidStart:self];
    }

    os_log_info(self.log, "SubscribeRepos WebSocket handler started successfully");
    return YES;
}

- (void)stop {
    os_log_info(self.log, "Stopping subscribeRepos WebSocket handler");

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

    os_log_info(self.log, "SubscribeRepos WebSocket handler stopped");
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
    os_log_info(self.log, "Accepted new WebSocket connection for subscribeRepos");

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didAcceptConnection:)]) {
        [self.delegate subscribeReposHandler:self didAcceptConnection:connection];
    }

    [self sendInitialRepositoryStateToConnection:connection cursor:nil];
}

- (void)webSocketServer:(WebSocketServer *)server didCloseConnection:(WebSocketConnection *)connection {
    os_log_info(self.log, "Closed WebSocket connection for subscribeRepos");

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didCloseConnection:)]) {
        [self.delegate subscribeReposHandler:self didCloseConnection:connection];
    }
}

- (void)webSocketServer:(WebSocketServer *)server didFailWithError:(NSError *)error {
    os_log_error(self.log, "WebSocket server failed: %@", error);
}

- (void)webSocketServer:(WebSocketServer *)server stateDidChange:(WebSocketServerState)state {
    os_log_info(self.log, "WebSocket server state changed to: %ld", (long)state);
}

#pragma mark - WebSocketConnectionDelegate

- (void)webSocketConnection:(WebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason {
    os_log_info(self.log, "Main-port WebSocket connection closed (code=%ld, reason=%@)", (long)code, reason ?: @"");
    @synchronized (self.attachedConnections) {
        [self.attachedConnections removeObject:connection];
    }
    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didCloseConnection:)]) {
        [self.delegate subscribeReposHandler:self didCloseConnection:connection];
    }
}

- (void)webSocketConnection:(WebSocketConnection *)connection didFailWithError:(NSError *)error {
    os_log_error(self.log, "Main-port WebSocket connection failed: %@", error);
    @synchronized (self.attachedConnections) {
        [self.attachedConnections removeObject:connection];
    }
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
            os_log_error(self.log, "Failed to encode commit event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.controller.serviceDatabases persistEvent:self.sequenceNumber type:@"commit" data:eventData error:&persistError]) {
            os_log_error(self.log, "Failed to persist commit event: %@", persistError);
        }

        [self broadcastEventData:eventData];
        os_log_info(self.log, "Broadcast commit event for repo %@, seq %lu", repoDid, (unsigned long)self.sequenceNumber);
    });
}

- (void)broadcastIdentityChange:(NSString *)did handle:(nullable NSString *)handle {
    dispatch_async(self.eventQueue, ^{
        [self ensureSequenceInitialized];
        self.sequenceNumber++;

        FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
        event.did = did;
        event.handle = handle;

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeIdentityEvent:event error:&error];

        if (!eventData) {
            os_log_error(self.log, "Failed to encode identity event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.controller.serviceDatabases persistEvent:self.sequenceNumber type:@"identity" data:eventData error:&persistError]) {
            os_log_error(self.log, "Failed to persist identity event: %@", persistError);
        }

        [self broadcastEventData:eventData];
        os_log_info(self.log, "Broadcast identity event for DID %@, seq %lu", did, (unsigned long)self.sequenceNumber);
    });
}

- (void)broadcastAccountTakedown:(NSString *)did {
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
            os_log_error(self.log, "Failed to encode account event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.controller.serviceDatabases persistEvent:self.sequenceNumber type:@"account" data:eventData error:&persistError]) {
            os_log_error(self.log, "Failed to persist account event: %@", persistError);
        }

        [self broadcastEventData:eventData];
        os_log_info(self.log, "Broadcast account takedown event for DID %@, seq %lu", did, (unsigned long)self.sequenceNumber);
    });
}

- (void)broadcastInfo:(NSString *)kind message:(NSString *)message {
    dispatch_async(self.eventQueue, ^{
        [self ensureSequenceInitialized];
        self.sequenceNumber++;

        FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
        event.kind = kind;
        event.message = message;

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeInfoEvent:event error:&error];

        if (!eventData) {
            os_log_error(self.log, "Failed to encode info event: %@", error);
            return;
        }

        NSError *persistError = nil;
        if (![self.controller.serviceDatabases persistEvent:self.sequenceNumber type:@"info" data:eventData error:&persistError]) {
            os_log_error(self.log, "Failed to persist info event: %@", persistError);
        }

        [self broadcastEventData:eventData];
        os_log_info(self.log, "Broadcast info event (%@), seq %lu", kind, (unsigned long)self.sequenceNumber);
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
        [connection sendMessage:eventData];
    }
}

- (void)sendInitialRepositoryStateToConnection:(WebSocketConnection *)connection cursor:(nullable NSString *)cursor {
    os_log_info(self.log, "Sending initial repository state to new connection");

    if (!cursor) {
        cursor = connection.queryParams[@"cursor"];
    }
    NSUInteger cursorSeq = 0;
    if (cursor) {
        cursorSeq = [cursor integerValue];
        os_log_info(self.log, "Client requested resumption from cursor %@ (seq %lu)", cursor, (unsigned long)cursorSeq);
    }

    dispatch_async(self.eventQueue, ^{
        if (cursorSeq == 0) {
            NSError *error = nil;
            NSArray<PDSDatabaseRepo *> *repos = [self.controller.userDatabasePool getAllReposWithError:&error];

            if (error) {
                os_log_error(self.log, "Failed to get all repos: %@", error);
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
                        [connection sendMessage:eventData];
                        os_log_debug(self.log, "Sent identity event for repo %@ (root: %@)", repo.ownerDid, cidString);
                    } else {
                        os_log_error(self.log, "Failed to encode identity event for repo %@: %@", repo.ownerDid, encodeError);
                    }
                }
            }
            os_log_info(self.log, "Completed sending initial state for %lu repos to new connection", (unsigned long)repos.count);
        }

        if (cursorSeq > 0) {
            [self replayEventsAfterCursor:cursorSeq toConnection:connection];
        }
    });
}

- (void)replayEventsAfterCursor:(NSUInteger)cursor toConnection:(WebSocketConnection *)connection {
    os_log_info(self.log, "Replaying events after cursor %lu", (unsigned long)cursor);
    [self ensureSequenceInitialized];
    
    NSUInteger fetchCursor = cursor;
    BOOL hasMore = YES;
    
    while (hasMore) {
        NSError *error = nil;
        NSArray *events = [self.controller.serviceDatabases getEventsSince:fetchCursor limit:100 error:&error];
        if (error || !events) {
            os_log_error(self.log, "Failed to fetch events for replay: %@", error);
            break;
        }
        
        if (events.count == 0) {
            hasMore = NO;
            break;
        }
        
        for (NSDictionary *event in events) {
            NSNumber *seq = event[@"seq"];
            NSData *data = event[@"data"];
            
            [connection sendMessage:data];
            fetchCursor = [seq unsignedIntegerValue];
        }
        
        if (events.count < 100) {
            hasMore = NO;
        }
        
        if (fetchCursor >= self.sequenceNumber) {
            hasMore = NO;
        }
    }
    
    os_log_info(self.log, "Replay completed. Last cursor: %lu", (unsigned long)fetchCursor);
}

- (void)sendInfoEvent:(NSString *)kind message:(NSString *)message toConnection:(WebSocketConnection *)connection {
    FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
    event.kind = kind;
    event.message = message;

    NSError *error = nil;
    NSData *eventData = [self.eventFormatter encodeInfoEvent:event error:&error];

    if (eventData) {
        [connection sendMessage:eventData];
        os_log_debug(self.log, "Sent info event (%@) to connection", kind);
    } else {
        os_log_error(self.log, "Failed to encode info event: %@", error);
    }
}

- (void)ensureSequenceInitialized {
    @synchronized (self) {
        if (self.sequenceInitialized) {
            return;
        }

        NSError *dbError = nil;
        int64_t maxSequence = [self.controller.serviceDatabases getMaxEventSequence:&dbError];
        if (dbError) {
            os_log_error(self.log, "Failed to get max event sequence: %@", dbError);
            return;
        }

        self.sequenceNumber = (NSUInteger)MAX((int64_t)0, maxSequence);
        self.sequenceInitialized = YES;
        os_log_info(self.log, "Initialized sequence number to %lu", (unsigned long)self.sequenceNumber);
    }
}

@end
