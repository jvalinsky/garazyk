#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Compat/PDSTypes.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Core/PDSRecordEvents.h"
#import "Core/PDSAccountEvents.h"
#import "Core/TID.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Repository/RepoCommit.h"
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/FirehoseCARBuilder.h"
#import "Sync/Firehose/FirehoseProtocolSession.h"
#import "Sync/Firehose/Firehose.h"
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Sync/WebSocket/WebSocketServer.h"
#import "Metrics/PDSMetrics.h"
#import "Sync/Relay/RelayMetrics.h"

NSString *const SubscribeReposHandlerErrorDomain =
    @"com.atproto.pds.subscribeRepos";
NSInteger const SubscribeReposHandlerErrorCodeConnectionFailed = 3000;

static const NSUInteger kSubscribeReposReplayBatchSize = 100;
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;
static const NSUInteger kSubscribeReposMaxPendingSendsDefault = 512;
static const NSUInteger kSubscribeReposMaxPendingBytesDefault =
    16 * 1024 * 1024; // 16MB
static NSString *const kSubscribeReposErrorFutureCursor = @"FutureCursor";
static NSString *const kSubscribeReposErrorConsumerTooSlow = @"ConsumerTooSlow";
static NSString *const kSubscribeReposErrorInvalidCursor = @"InvalidCursor";
static NSString *const kSubscribeReposInfoOutdatedCursor = @"OutdatedCursor";

@interface SubscribeReposHandler () <WebSocketServerDelegate,
                                     WebSocketConnectionDelegate>

@property(nonatomic, strong) WebSocketServer *webSocketServer;
@property(nonatomic, strong) FirehoseProtocolSession *session;
@property(nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property(nonatomic, strong) PDSDatabasePool *userDatabasePool;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t syncQueue;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t broadcastFanoutQueue;
@property(nonatomic, assign) BOOL sequenceInitialized;
@property(atomic, assign) BOOL stopping;
@property(atomic, assign) BOOL observingNotifications;
@property(nonatomic, strong)
    NSMutableSet<WebSocketConnection *> *attachedConnections;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_source_t eventRateLimiter;
@property(nonatomic, assign) NSUInteger maxReplayEventsPerConnection;
@property(nonatomic, assign) NSUInteger maxPendingSendsPerConnection;
@property(nonatomic, assign) NSUInteger maxPendingBytesPerConnection;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, NSString *> *lastCommitRevByDID;

- (void)ensureSequenceInitialized;
- (BOOL)parseCursorString:(nullable NSString *)cursor
                 outValue:(NSUInteger *)outValue;
- (void)sendErrorFrameWithCode:(NSString *)code
                       message:(NSString *)message
                  toConnection:(WebSocketConnection *)connection;
- (void)detachConnection:(WebSocketConnection *)connection;
- (BOOL)sendEventData:(NSData *)eventData
    toConnectionWithBackpressureCheck:(WebSocketConnection *)connection;
+ (NSString *)rfc3339Timestamp;
- (nullable NSNumber *)oldestPersistedSequenceNumber;
- (NSUInteger)effectiveReplayCursorForRequestedCursor:(NSUInteger)requestedCursor
                                              outdated:(BOOL *)outdated;

@end

@implementation SubscribeReposHandler

static void *kSubscribeReposEventQueueKey = &kSubscribeReposEventQueueKey;

- (instancetype)init {
  return [self initWithServiceDatabases:nil userDatabasePool:nil];
}

- (instancetype)initWithServiceDatabases:
    (PDSServiceDatabases *)serviceDatabases {
  return [self initWithServiceDatabases:serviceDatabases userDatabasePool:nil];
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                         userDatabasePool:
                             (nullable PDSDatabasePool *)userDatabasePool {
  self = [super init];
  if (self) {
    _serviceDatabases = serviceDatabases;
    _userDatabasePool = userDatabasePool;
    _syncQueue = dispatch_queue_create("com.atproto.pds.subscribeRepos.sync",
                                        DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_syncQueue, kSubscribeReposEventQueueKey,
                                kSubscribeReposEventQueueKey, NULL);
    _broadcastFanoutQueue = dispatch_queue_create(
        "com.atproto.pds.subscribeRepos.broadcast", DISPATCH_QUEUE_CONCURRENT);
    _sequenceInitialized = NO;
    _stopping = NO;
    _observingNotifications = NO;
    _attachedConnections = [NSMutableSet set];
    _maxReplayEventsPerConnection = kSubscribeReposMaxReplayEventsDefault;
    _maxPendingSendsPerConnection = kSubscribeReposMaxPendingSendsDefault;
    _maxPendingBytesPerConnection = kSubscribeReposMaxPendingBytesDefault;
    _lastCommitRevByDID = [NSMutableDictionary dictionary];

    // Initialize backpressure rate limiter (100 events/sec)
    _eventRateLimiter = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _syncQueue);
    if (_eventRateLimiter) {
      uint64_t interval = NSEC_PER_SEC / 100; // 100 events per second
      dispatch_source_set_timer(_eventRateLimiter,
                                DISPATCH_TIME_NOW, interval, interval / 10);
      dispatch_source_set_event_handler(_eventRateLimiter, ^{
        // Timer fires to allow event processing
      });
      dispatch_resume(_eventRateLimiter);
    }

  }
  return self;
}

- (void)dealloc {
  [self stopObservingNotifications];
}

- (void)startObservingNotifications {
  @synchronized(self) {
    if (self.observingNotifications) {
      return;
    }

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleRecordChange:)
               name:PDSRecordDidChangeNotification
             object:nil];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleAccountLifecycleEvent:)
               name:PDSAccountCreatedNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleAccountLifecycleEvent:)
               name:PDSAccountActivatedNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleAccountLifecycleEvent:)
               name:PDSAccountDeactivatedNotification
             object:nil];

    self.stopping = NO;
    self.observingNotifications = YES;
  }
}

- (void)stopObservingNotifications {
  @synchronized(self) {
    if (!self.observingNotifications) {
      return;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.observingNotifications = NO;
  }
}

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error {
  PDS_LOG_SYNC_INFO(@"Starting subscribeRepos WebSocket handler on port %d",
                    port);

  [self ensureSequenceInitialized];

  self.webSocketServer =
      [[WebSocketServer alloc] initWithHost:@"localhost" port:port];
  self.webSocketServer.delegate = self;
  self.webSocketServer.subprotocol = @"com.atproto.sync.subscribeRepos";

  if (![self.webSocketServer start:error]) {
    PDS_LOG_SYNC_ERROR(@"Failed to start WebSocket server: %@", *error);
    return NO;
  }

  [self startObservingNotifications];

  if ([self.delegate
          respondsToSelector:@selector(subscribeReposHandlerDidStart:)]) {
    [self.delegate subscribeReposHandlerDidStart:self];
  }

  PDS_LOG_SYNC_INFO(@"SubscribeRepos WebSocket handler started successfully");
  return YES;
}

- (void)stop {
  PDS_LOG_SYNC_INFO(@"Stopping subscribeRepos WebSocket handler");

  self.stopping = YES;
  [self stopObservingNotifications];

  // Cancel and release rate limiter
  if (_eventRateLimiter) {
    dispatch_source_cancel(_eventRateLimiter);
    _eventRateLimiter = nil;
  }

  if (dispatch_get_specific(kSubscribeReposEventQueueKey) == NULL) {
    dispatch_sync(self.syncQueue, ^{
                  });
  }
  [self waitForIdleWithTimeout:5.0];

  NSSet<WebSocketConnection *> *attachedSnapshot = nil;
  @synchronized(_attachedConnections) {
    attachedSnapshot = [_attachedConnections copy];
  }
  for (WebSocketConnection *connection in attachedSnapshot) {
    [self detachConnection:connection];
    [connection close];
  }

  [self.webSocketServer stop];
  self.webSocketServer = nil;

  if ([self.delegate
          respondsToSelector:@selector(subscribeReposHandlerDidStop:)]) {
    [self.delegate subscribeReposHandlerDidStop:self];
  }

  PDS_LOG_SYNC_INFO(@"SubscribeRepos WebSocket handler stopped");
}

- (BOOL)waitForIdleWithTimeout:(NSTimeInterval)timeout {
  dispatch_group_t group = dispatch_group_create();
  dispatch_time_t deadline =
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));

  dispatch_group_enter(group);
  void (^drainFanout)(void) = ^{
    dispatch_barrier_async(self.broadcastFanoutQueue, ^{
      dispatch_group_leave(group);
    });
  };

  if (dispatch_get_specific(kSubscribeReposEventQueueKey) == NULL) {
    dispatch_async(self.syncQueue, drainFanout);
  } else {
    drainFanout();
  }

  return dispatch_group_wait(group, deadline) == 0;
}

- (void)acceptUpgradedConnection:(id<PDSNetworkConnection>)connection
                         request:(HttpRequest *)request {
  PDS_LOG_SYNC_INFO(@"Accepting upgraded connection for subscribeRepos from %@", request.remoteAddress);
  [self ensureSequenceInitialized];

  WebSocketConnection *webSocketConnection =
      [[WebSocketConnection alloc] initWithConnection:connection];
  if (request.remoteAddress.length > 0) {
    webSocketConnection.remoteAddress = request.remoteAddress;
  }
  webSocketConnection.delegate = self;
  NSUInteger count = 0;
  @synchronized(_attachedConnections) {
    [_attachedConnections addObject:webSocketConnection];
    count = _attachedConnections.count;
  }
  [[PDSMetrics sharedMetrics] setFirehoseSubscribers:(NSInteger)count];
  [self.relayMetrics recordDownstreamConnected];

  if ([self.delegate respondsToSelector:@selector(
                      subscribeReposHandler:didAcceptConnection:)]) {
    [self.delegate subscribeReposHandler:self
                     didAcceptConnection:webSocketConnection];
  }

  [webSocketConnection startOnExistingTransport];
  [self sendInitialRepositoryStateToConnection:webSocketConnection
                                        cursor:[request queryParamForKey:@"cursor"]];
}

#pragma mark - WebSocketServerDelegate

- (void)webSocketServer:(WebSocketServer *)server
    didAcceptConnection:(WebSocketConnection *)connection {
  PDS_LOG_SYNC_INFO(
      @"[%@] Accepted new WebSocket connection for subscribeRepos",
      connection.remoteAddress);

  NSUInteger count = 0;
  @synchronized(_attachedConnections) {
    [_attachedConnections addObject:connection];
    count = _attachedConnections.count;
  }
  [[PDSMetrics sharedMetrics] setFirehoseSubscribers:(NSInteger)count];
  [self.relayMetrics recordDownstreamConnected];

  if ([self.delegate respondsToSelector:@selector
                     (subscribeReposHandler:didAcceptConnection:)]) {
    [self.delegate subscribeReposHandler:self didAcceptConnection:connection];
  }

  [self sendInitialRepositoryStateToConnection:connection cursor:nil];
}

- (void)webSocketServer:(WebSocketServer *)server
     didCloseConnection:(WebSocketConnection *)connection {
  PDS_LOG_SYNC_INFO(@"[%@] Closed WebSocket connection for subscribeRepos",
                    connection.remoteAddress);
  [self detachConnection:connection];
}

- (void)webSocketServer:(WebSocketServer *)server
       didFailWithError:(NSError *)error {
  PDS_LOG_SYNC_ERROR(@"WebSocket server failed: %@", error);
}

- (void)webSocketServer:(WebSocketServer *)server
         stateDidChange:(WebSocketServerState)state {
  PDS_LOG_SYNC_INFO(@"WebSocket server state changed to: %ld", (long)state);
}

#pragma mark - WebSocketConnectionDelegate

- (void)webSocketConnection:(WebSocketConnection *)connection
           didCloseWithCode:(NSInteger)code
                     reason:(NSString *)reason {
  PDS_LOG_SYNC_INFO(
      @"[%@] Main-port WebSocket connection closed (code=%ld, reason=%@)",
      connection.remoteAddress, (long)code, reason ?: @"");
  [self detachConnection:connection];
}

- (void)webSocketConnection:(WebSocketConnection *)connection
           didFailWithError:(NSError *)error {
  PDS_LOG_SYNC_ERROR(@"[%@] Main-port WebSocket connection failed: %@",
                     connection.remoteAddress, error);
  [self detachConnection:connection];
}

#pragma mark - Record Change Notification

- (void)handleRecordChange:(NSNotification *)notification {
  NSDictionary *info = notification.userInfo;
  NSString *did = info[@"did"];
  NSString *collection = info[@"collection"];
  NSString *rkey = info[@"rkey"];
  NSString *action = info[@"action"];
  NSString *normalizedAction =
      ([action isKindOfClass:[NSString class]] && action.length > 0)
          ? action
          : @"create";
  NSString *previousRecordCIDString =
      [info[@"previousRecordCID"] isKindOfClass:[NSString class]]
          ? info[@"previousRecordCID"]
          : nil;

  if (!did || !collection || !rkey)
    return;

  NSString *cidStr = info[@"cid"];
  NSString *commitStr = info[@"commit"]; // This is the signed Commit CID
  id recordCBORValue = info[@"recordCBOR"];
  NSData *recordCBOR =
      ([recordCBORValue isKindOfClass:[NSData class]]) ? recordCBORValue : nil;

  // Dispatch the actual repo commit building and broadcast to the eventQueue
  // so it doesn't block the caller (e.g. the HTTP request handler thread taking
  // the DB transaction).
  __weak typeof(self) weakSelf = self;
  dispatch_async(self.syncQueue, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.stopping) return;

    CID *opCID = (cidStr && ![cidStr isKindOfClass:[NSNull class]])
                     ? [CID cidFromString:cidStr]
                     : nil;
    CID *commitCID = (commitStr && ![commitStr isKindOfClass:[NSNull class]])
                         ? [CID cidFromString:commitStr]
                         : nil;

    NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    NSMutableDictionary *op = [@{
      @"action" : normalizedAction,
      @"path" : path,
      @"cid" : opCID ?: [NSNull null]
    } mutableCopy];
    if (([normalizedAction isEqualToString:@"update"] ||
         [normalizedAction isEqualToString:@"delete"]) &&
        previousRecordCIDString.length > 0) {
      CID *previousRecordCID = [CID cidFromString:previousRecordCIDString];
      if (previousRecordCID) {
        op[@"prev"] = previousRecordCID;
      }
    }
    if (recordCBOR) {
      op[@"recordCBOR"] = recordCBOR;
    }

    RepoCommit *commit = nil;

    // Try to load the stored, signed commit block
    if (strongSelf.userDatabasePool && commitCID) {
      NSError *dbError = nil;
      PDSActorStore *store =
          [strongSelf.userDatabasePool storeForDid:did error:&dbError];
      if (store) {
        NSData *blockData =
            [store getBlockForCID:[commitCID bytes] forDid:did error:&dbError];
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
            if ([dataVal isKindOfClass:[CID class]])
              commit.dataCID = (CID *)dataVal;

            id prevVal = commitMap[@"prev"];
            if ([prevVal isKindOfClass:[CID class]])
              commit.prevCID = (CID *)prevVal;

            id sigVal = commitMap[@"sig"];
            if ([sigVal isKindOfClass:[NSData class]])
              commit.signature = (NSData *)sigVal;
          }
        }
      }
    }

    if (!commit || !commit.signature) {
      PDS_LOG_SYNC_ERROR(@"Failed to load valid signed commit for firehose "
                         @"broadcast (DID: %@)",
                         did);
      return;
    }

    [strongSelf broadcastRepositoryCommit:commit
                             forRepo:did
                                 ops:@[ [op copy] ]
                               blobs:@[]];
  });
}

#pragma mark - Account Lifecycle Notification

- (void)handleAccountLifecycleEvent:(NSNotification *)notification {
  NSDictionary *info = notification.userInfo;
  NSString *did = info[PDSAccountEventDidKey];
  if (!did) return;

  if ([notification.name isEqualToString:PDSAccountCreatedNotification]) {
    NSString *handle = info[PDSAccountEventHandleKey];
    [self broadcastIdentityChange:did handle:handle];
    [self broadcastAccountStatus:did active:YES status:nil];
  } else if ([notification.name isEqualToString:PDSAccountActivatedNotification]) {
    [self broadcastAccountStatus:did active:YES status:nil];
  } else if ([notification.name isEqualToString:PDSAccountDeactivatedNotification]) {
    NSString *status = info[PDSAccountEventStatusKey] ?: @"deactivated";
    [self broadcastAccountStatus:did active:NO status:status];
  }
}

#pragma mark - Event Broadcasting

- (void)broadcastCommitEvent:(FirehoseCommitEvent *)event {
  if (self.stopping || !event) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  dispatch_async(self.syncQueue, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.stopping) return;
    @autoreleasepool {
      [strongSelf ensureSequenceInitialized];
      NSData *eventData = [strongSelf.session encodeCommitEvent:event];
      if (eventData) {
        if (strongSelf.serviceDatabases) {
          [strongSelf.serviceDatabases persistEvent:strongSelf.session.sequenceNumber
                                         type:@"commit"
                                         data:eventData
                                        error:nil];
        }
        [strongSelf broadcastEventData:eventData];
      }
    }
  });
}

- (void)broadcastRepositoryCommit:(RepoCommit *)commit
                           forRepo:(NSString *)repoDid
                               ops:(NSArray<NSDictionary *> *)ops
                             blobs:(NSArray<CID *> *)blobs {
  if (self.stopping) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  void (^broadcastWork)(void) = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.stopping) return;
    [strongSelf ensureSequenceInitialized];

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];

    // Required fields per subscribeRepos lexicon
    event.rebase = NO; // Deprecated, always false
    event.tooBig = NO; // Deprecated, always false
    event.repo = repoDid;
    event.commit = commit.computeCID;
    event.rev = commit.rev;
    event.since =
        strongSelf.lastCommitRevByDID[repoDid]; // Previous commit rev for this repo
    
    event.blocks = [FirehoseCARBuilder buildCARForCommit:commit
                                                     ops:ops
                                           blockProvider:^NSData * _Nullable(NSData * _Nonnull cidBytes) {
                                               __strong typeof(weakSelf) innerSelf = weakSelf;
                                               if (!innerSelf || !innerSelf.userDatabasePool) return nil;
                                               return [[innerSelf.userDatabasePool storeForDid:repoDid error:nil] getBlockForCID:cidBytes forDid:repoDid error:nil];
                                           }
                                      revBlockListProvider:^NSArray<NSData *> * _Nullable(NSString * _Nonnull rev) {
                                               __strong typeof(weakSelf) innerSelf = weakSelf;
                                               if (!innerSelf || !innerSelf.userDatabasePool) return nil;
                                               return [[innerSelf.userDatabasePool storeForDid:repoDid error:nil] listBlockCIDsForRevision:rev limit:200000 error:nil];
                                      }];
    event.ops = ops;
    event.blobs = blobs ?: @[]; // Already CID array
    event.time = [SubscribeReposHandler rfc3339Timestamp];
    event.prevData = commit.prevCID ?: nil; // Previous MST root CID

    // Update the per-DID tracking for next event's since field
    if (commit.rev) {
      strongSelf.lastCommitRevByDID[repoDid] = commit.rev;
    }

    NSString *eventType = @"commit";
    NSData *eventData = [strongSelf.session encodeCommitEvent:event];
    if (!eventData) {
      PDS_LOG_SYNC_WARN(
          @"Commit event encoding failed for %@ at seq %lu, falling back "
          @"to #sync",
          repoDid, (unsigned long)strongSelf.session.sequenceNumber + 1);
      FirehoseSyncEvent *syncEvent = [[FirehoseSyncEvent alloc] init];
      syncEvent.did = repoDid;
      syncEvent.blocks = [FirehoseCARBuilder buildCARForSyncCommitOnly:commit];
      syncEvent.rev = commit.rev ?: @"";
      syncEvent.time = event.time;

      eventData = [strongSelf.session.eventFormatter encodeSyncEvent:syncEvent error:nil];
      if (!eventData) {
        PDS_LOG_SYNC_ERROR(@"Failed to encode sync fallback event");
        return;
      }
      eventType = @"sync";
    }

    NSError *persistError = nil;
    if (![strongSelf.serviceDatabases persistEvent:strongSelf.session.sequenceNumber
                                        type:eventType
                                        data:eventData
                                       error:&persistError]) {
      PDS_LOG_SYNC_ERROR(@"Failed to persist %@ event: %@", eventType,
                         persistError);
    }

    [strongSelf broadcastEventData:eventData];
    [[PDSMetrics sharedMetrics] incrementFirehoseEvent:@"commit"];
    [[PDSMetrics sharedMetrics] incrementRepoCommits];
    [[PDSMetrics sharedMetrics] setFirehoseSeq:(int64_t)strongSelf.session.sequenceNumber];
    PDS_LOG_SYNC_INFO(@"Broadcast %@ event for repo %@, seq %lu", eventType,
                      repoDid, (unsigned long)strongSelf.session.sequenceNumber);
  };

  if (dispatch_get_specific(kSubscribeReposEventQueueKey) != NULL) {
    broadcastWork();
  } else {
    dispatch_async(self.syncQueue, broadcastWork);
  }
}


- (void)broadcastIdentityChange:(NSString *)did
                         handle:(nullable NSString *)handle {
  if (self.stopping) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  dispatch_async(self.syncQueue, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.stopping) return;
    @autoreleasepool {
      [strongSelf ensureSequenceInitialized];

      FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
      event.did = did;
      event.time = [SubscribeReposHandler rfc3339Timestamp];
      event.handle = handle;

      NSData *eventData = [strongSelf.session encodeIdentityEvent:event];

      if (!eventData) {
        return;
      }

      if (strongSelf.serviceDatabases) {
        NSError *persistError = nil;
        if (![strongSelf.serviceDatabases persistEvent:strongSelf.session.sequenceNumber
                                            type:@"identity"
                                            data:eventData
                                           error:&persistError]) {
          PDS_LOG_SYNC_ERROR(@"Failed to persist identity event: %@", persistError);
        }
      }

      [strongSelf broadcastEventData:eventData];
      [[PDSMetrics sharedMetrics] incrementFirehoseEvent:@"identity"];
      [[PDSMetrics sharedMetrics] setFirehoseSeq:(int64_t)strongSelf.session.sequenceNumber];
      PDS_LOG_SYNC_INFO(@"Broadcast identity event for DID %@, seq %lu", did,
                        (unsigned long)strongSelf.session.sequenceNumber);
    }
  });
}

- (void)broadcastAccountStatus:(NSString *)did
                         active:(BOOL)active
                         status:(nullable NSString *)status {
  if (self.stopping) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  dispatch_async(self.syncQueue, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.stopping) return;
    @autoreleasepool {
      [strongSelf ensureSequenceInitialized];

      FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
      event.did = did;
      event.active = active;
      event.status = status;
      event.time = [SubscribeReposHandler rfc3339Timestamp];

      NSData *eventData = [strongSelf.session encodeAccountEvent:event];

      if (!eventData) {
        return;
      }

      if (strongSelf.serviceDatabases) {
        NSError *persistError = nil;
        if (![strongSelf.serviceDatabases persistEvent:strongSelf.session.sequenceNumber
                                            type:@"account"
                                            data:eventData
                                           error:&persistError]) {
          PDS_LOG_SYNC_ERROR(@"Failed to persist account event: %@", persistError);
        }
      }

      [strongSelf broadcastEventData:eventData];
      [[PDSMetrics sharedMetrics] incrementFirehoseEvent:@"account"];
      [[PDSMetrics sharedMetrics] setFirehoseSeq:(int64_t)strongSelf.session.sequenceNumber];
      PDS_LOG_SYNC_INFO(@"Broadcast account status event for DID %@ (active=%d, status=%@), seq %lu",
                        did, active, status ?: @"(null)", (unsigned long)strongSelf.session.sequenceNumber);
    }
  });
}

- (void)broadcastAccountTakedown:(NSString *)did {
  [self broadcastAccountStatus:did active:NO status:@"takendown"];
}

- (void)broadcastInfo:(NSString *)kind message:(NSString *)message {
  if (self.stopping) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  dispatch_async(self.syncQueue, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.stopping) return;
    [strongSelf ensureSequenceInitialized];
    NSUInteger sequenceNumber = [strongSelf nextSequenceNumber];
    FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
    event.kind = kind;
    event.message = message;

    NSData *eventData = [strongSelf.session encodeInfoEvent:event];

    if (eventData) {
      // Persist info events for replay
      if (strongSelf.serviceDatabases) {
        NSError *persistError = nil;
        if (![strongSelf.serviceDatabases persistEvent:(int64_t)sequenceNumber
                                            type:@"info"
                                            data:eventData
                                           error:&persistError]) {
          PDS_LOG_SYNC_ERROR(@"Failed to persist info event: %@", persistError);
        }
      }
      [strongSelf broadcastEventData:eventData];
      [[PDSMetrics sharedMetrics] setFirehoseSeq:(int64_t)sequenceNumber];
      PDS_LOG_SYNC_DEBUG(@"Broadcast info event (%@), seq %lu",
                          kind, (unsigned long)sequenceNumber);
    }
  });
}

- (NSUInteger)nextSequenceNumber {
  [self ensureSequenceInitialized];
  if (!self.session) return 0;
  return [self.session nextSequenceNumber];
}

- (void)broadcastEventData:(NSData *)eventData {
  NSArray<WebSocketConnection *> *snapshot;
  @synchronized(_attachedConnections) {
    snapshot = [_attachedConnections allObjects];
  }
  PDS_LOG_SYNC_DEBUG(@"Broadcasting event to %lu subscribers",
                     (unsigned long)snapshot.count);
  if (snapshot.count == 0) {
    return;
  }
  dispatch_queue_t fanout = self.broadcastFanoutQueue;
  __weak typeof(self) weakSelf = self;
  for (WebSocketConnection *connection in snapshot) {
    dispatch_async(fanout, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if (![strongSelf sendEventData:eventData
            toConnectionWithBackpressureCheck:connection]) {
        PDS_LOG_SYNC_WARN(@"Dropping slow consumer during live broadcast");
      }
    });
  }
}

- (void)sendInitialRepositoryStateToConnection:(WebSocketConnection *)connection
                                        cursor:(nullable NSString *)cursor {
  PDS_LOG_SYNC_INFO(@"New connection from %@ (requested path: %@)", connection.remoteAddress, connection.path);
  PDS_LOG_SYNC_INFO(@"Sending initial repository state to new connection");

  if (!cursor) {
    id cursorParam = connection.queryParams[@"cursor"];
    if ([cursorParam isKindOfClass:[NSString class]]) {
      cursor = cursorParam;
    } else if ([cursorParam isKindOfClass:[NSArray class]] &&
               [(NSArray *)cursorParam count] > 0) {
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
      PDS_LOG_SYNC_INFO(@"Client requested resumption from cursor %@ (parsed as seq %lu)",
                        cursor, (unsigned long)parsedCursor);
    } else {
      PDS_LOG_SYNC_WARN(@"Client requested resumption from invalid cursor: %@", cursor);
    }
  } else {
    PDS_LOG_SYNC_INFO(@"No cursor requested by client, connection will start in live update mode");
  }

  PDS_LOG_SYNC_INFO(@"Queuing initial state worker for connection %@ (queue: %p)", connection.remoteAddress, self.syncQueue);
  if (!self.syncQueue) {
    PDS_LOG_SYNC_ERROR(@"CRITICAL: eventQueue is NULL in SubscribeReposHandler!");
    return;
  }
  __weak typeof(self) weakSelf = self;
  dispatch_async(self.syncQueue, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.stopping) return;
    PDS_LOG_SYNC_INFO(@"Async worker started: processing initial state for connection %@", connection.remoteAddress);

    if (hasCursor && !cursorValid) {
      [strongSelf sendErrorFrameWithCode:kSubscribeReposErrorInvalidCursor
                           message:@"cursor must be a non-negative integer"
                      toConnection:connection];
      [strongSelf detachConnection:connection];
      [connection closeWithCode:1008 reason:kSubscribeReposErrorInvalidCursor];
      return;
    }

    // Per ATProto spec, if no cursor is provided, the stream starts from the current head.
    if (!hasCursor) {
      PDS_LOG_SYNC_INFO(@"No cursor provided; starting stream from current head.");
    }

    if (hasCursor && parsedCursor > strongSelf.session.sequenceNumber) {
      [strongSelf
          sendErrorFrameWithCode:kSubscribeReposErrorFutureCursor
                         message:@"requested cursor is ahead of server sequence"
                    toConnection:connection];
      [strongSelf detachConnection:connection];
      [connection closeWithCode:1008 reason:kSubscribeReposErrorFutureCursor];
      return;
    }

    if (!hasCursor) {
      PDS_LOG_SYNC_INFO(@"No cursor provided; client is now listening for live events.");
    } else if (parsedCursor == 0) {
      PDS_LOG_SYNC_INFO(@"Client requested cursor=0; replaying all events from the beginning.");
    }

    if (hasCursor) {
      BOOL outdated = NO;
      NSUInteger replayCursor =
          [strongSelf effectiveReplayCursorForRequestedCursor:parsedCursor
                                               outdated:&outdated];
      if (outdated) {
        PDS_LOG_SYNC_WARN(@"Outdated cursor %lu adjusted to %lu for connection %@",
                          (unsigned long)parsedCursor,
                          (unsigned long)replayCursor, connection);
        [strongSelf sendInfoEvent:kSubscribeReposInfoOutdatedCursor
                    message:@"Requested cursor exceeded limit. Possibly missing events"
               toConnection:connection];
      }

      if (replayCursor >= strongSelf.session.sequenceNumber) {
        PDS_LOG_SYNC_INFO(@"Cursor %lu is up to date at server sequence %lu.",
                          (unsigned long)replayCursor,
                          (unsigned long)strongSelf.session.sequenceNumber);
      } else {
        PDS_LOG_SYNC_INFO(@"Backfill requested (backlog: %lu). Replaying events from cursor %lu.",
                          (unsigned long)(strongSelf.session.sequenceNumber - replayCursor),
                          (unsigned long)replayCursor);
        [strongSelf replayEventsAfterCursor:replayCursor toConnection:connection];
      }
    }
  });
}

- (void)replayEventsAfterCursor:(NSUInteger)cursor
                   toConnection:(WebSocketConnection *)connection {
  if (!self.serviceDatabases) {
    PDS_LOG_SYNC_WARN(@"Cannot replay events: no service databases");
    return;
  }

  NSUInteger limit = self.maxReplayEventsPerConnection;
  if (limit == 0) {
    limit = 1000; // Default safety limit
  }

  NSError *error = nil;
  NSArray<NSDictionary *> *events =
      [self.serviceDatabases getEventsSince:(int64_t)cursor
                                      limit:(NSInteger)limit
                                      error:&error];
  if (error) {
    PDS_LOG_SYNC_ERROR(@"Failed to read events for replay: %@", error);
    return;
  }

  PDS_LOG_SYNC_INFO(@"Replaying %lu events after cursor %lu",
                     (unsigned long)events.count, (unsigned long)cursor);

  for (NSDictionary *eventDict in events) {
    NSData *eventData = eventDict[@"data"];
    if (![eventData isKindOfClass:[NSData class]] || eventData.length == 0) {
      continue;
    }
    [connection sendMessage:eventData];
  }
}

- (void)sendInfoEvent:(NSString *)kind
               message:(NSString *)message
          toConnection:(WebSocketConnection *)connection {
  FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
  event.kind = kind;
  event.message = message;

  NSData *eventData = [self.session encodeInfoEvent:event];

  if (eventData) {
    [connection sendMessage:eventData];
    PDS_LOG_SYNC_DEBUG(@"Sent info event (%@) to connection", kind);
  }
}

- (BOOL)parseCursorString:(nullable NSString *)cursor
                 outValue:(NSUInteger *)outValue {
  if (cursor.length == 0) {
    if (outValue)
      *outValue = 0;
    return YES;
  }

  NSCharacterSet *nonDigits =
      [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
  if ([cursor rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
    return NO;
  }

  NSScanner *scanner = [NSScanner scannerWithString:cursor];
  long long parsed = 0;
  if (![scanner scanLongLong:&parsed] || ![scanner isAtEnd]) {
    return NO;
  }
  if (parsed < 0 ||
      (unsigned long long)parsed > (unsigned long long)NSUIntegerMax) {
    return NO;
  }

  if (outValue)
    *outValue = (NSUInteger)parsed;
  return YES;
}

- (nullable NSNumber *)oldestPersistedSequenceNumber {
  NSError *error = nil;
  NSArray<NSDictionary *> *events =
      [self.serviceDatabases getEventsSince:0 limit:1 error:&error];
  if (error) {
    PDS_LOG_SYNC_WARN(@"Failed to read oldest persisted sequence: %@", error);
    return nil;
  }
  if (events.count == 0) {
    return nil;
  }

  id seqValue = events.firstObject[@"seq"];
  return [seqValue isKindOfClass:[NSNumber class]] ? seqValue : nil;
}

- (NSUInteger)effectiveReplayCursorForRequestedCursor:(NSUInteger)requestedCursor
                                              outdated:(BOOL *)outdated {
  NSUInteger minimumCursor = 0;

  NSNumber *oldestSeqValue = [self oldestPersistedSequenceNumber];
  if (oldestSeqValue != nil) {
    NSUInteger oldestSeq = oldestSeqValue.unsignedIntegerValue;
    if (oldestSeq > 0) {
      NSUInteger oldestCursor = oldestSeq - 1;
      if (oldestCursor > minimumCursor) {
        minimumCursor = oldestCursor;
      }
    }
  }

  if (self.session.sequenceNumber > self.maxReplayEventsPerConnection) {
    NSUInteger replayWindowCursor =
        self.session.sequenceNumber - self.maxReplayEventsPerConnection;
    if (replayWindowCursor > minimumCursor) {
      minimumCursor = replayWindowCursor;
    }
  }

  BOOL cursorOutdated = requestedCursor < minimumCursor;
  if (outdated) {
    *outdated = cursorOutdated;
  }
  return cursorOutdated ? minimumCursor : requestedCursor;
}

- (void)sendErrorFrameWithCode:(NSString *)code
                       message:(NSString *)message
                  toConnection:(WebSocketConnection *)connection {
  FirehoseErrorEvent *event =
      [FirehoseErrorEvent eventWithError:code message:message];
  NSData *eventData = [self.session encodeErrorEvent:event];
  if (eventData) {
    [connection sendMessage:eventData];
  }
}

- (void)detachConnection:(WebSocketConnection *)connection {
  BOOL removed = NO;
  NSUInteger count = 0;
  @synchronized(_attachedConnections) {
    if ([_attachedConnections containsObject:connection]) {
      [_attachedConnections removeObject:connection];
      removed = YES;
      count = _attachedConnections.count;
    }
  }
  if (removed) {
    [[PDSMetrics sharedMetrics] setFirehoseSubscribers:(NSInteger)count];
    [self.relayMetrics recordDownstreamDisconnected];
    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didCloseConnection:)]) {
      [self.delegate subscribeReposHandler:self didCloseConnection:connection];
    }
  }
}

- (BOOL)sendEventData:(NSData *)eventData
    toConnectionWithBackpressureCheck:(WebSocketConnection *)connection {
  if (!eventData || !connection) {
    return NO;
  }

  if (connection.pendingSendCount >= self.maxPendingSendsPerConnection ||
      connection.pendingSendBytes >= self.maxPendingBytesPerConnection) {
    [self
        sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
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
  @synchronized(self) {
    if (self.sequenceInitialized) {
      return;
    }

    NSUInteger startSeq = 0;
    if (self.serviceDatabases) {
        NSError *dbError = nil;
        int64_t maxSequence = [self.serviceDatabases getMaxEventSequence:&dbError];
        if (dbError) {
          PDS_LOG_SYNC_ERROR(@"Failed to get max event sequence: %@", dbError);
        }
        startSeq = (NSUInteger)MAX((int64_t)0, maxSequence);
    }

    self.session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:startSeq];
    self.sequenceInitialized = YES;
    PDS_LOG_SYNC_INFO(@"Initialized sequence number to %lu",
                      (unsigned long)self.session.sequenceNumber);
  }
}

- (void)skipPersistence {
  @synchronized(self) {
    if (self.sequenceInitialized) return;
    self.session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:0];
    self.sequenceInitialized = YES;
    PDS_LOG_SYNC_INFO(@"Firehose persistence disabled. Starting from sequence 0.");
  }
}

+ (NSString *)rfc3339Timestamp {
  return [NSDateFormatter atproto_stringFromDate:[NSDate date]];
}

@end
