# Event Ordering and Sequence Numbers

## Overview

Event ordering is critical for maintaining consistency in the firehose. The PDS guarantees that:
- Events are assigned monotonically increasing sequence numbers
- Events are delivered in sequence number order
- Sequence numbers are never reused
- Gaps in sequence numbers indicate missing events

## Sequence Number Architecture

### Sequence Number Assignment

Every firehose event receives a unique, monotonically increasing sequence number:

```objc
// In SubscribeReposHandler.m - Sequence number initialization
- (void)ensureSequenceInitialized {
  @synchronized(self) {
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
    PDS_LOG_SYNC_INFO(@"Initialized sequence number to %lu",
                      (unsigned long)self.sequenceNumber);
  }
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 1000-1020)

### Broadcasting with Sequence Numbers

Each event is assigned the next sequence number before broadcasting:

```objc
// In SubscribeReposHandler.m - Broadcasting repository commits
- (void)broadcastRepositoryCommit:(RepoCommit *)commit
                          forRepo:(NSString *)repoDid
                              ops:(NSArray<NSDictionary *> *)ops
                            blobs:(NSArray<CID *> *)blobs {
  if (self.stopping) {
    return;
  }
  dispatch_async(self.eventQueue, ^{
    [self ensureSequenceInitialized];
    self.sequenceNumber++;  // Monotonically increasing

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];

    // Required fields per subscribeRepos lexicon
    event.seq = self.sequenceNumber;
    event.rebase = NO;
    event.tooBig = NO;
    event.repo = repoDid;
    event.commit = commit.computeCID;
    event.rev = commit.rev;
    event.since = self.lastCommitRevByDID[repoDid];
    event.blocks = [self buildCARBlocksForCommit:commit ops:ops];
    event.ops = ops;
    event.blobs = blobs ?: @[];
    event.time = [SubscribeReposHandler rfc3339Timestamp];
    event.prevData = commit.prevCID ?: nil;

    // Update the per-DID tracking for next event's since field
    if (commit.rev) {
      self.lastCommitRevByDID[repoDid] = commit.rev;
    }

    NSString *eventType = @"commit";
    NSError *error = nil;
    NSData *eventData =
        [self.eventFormatter encodeCommitEvent:event error:&error];
    if (!eventData) {
      PDS_LOG_SYNC_WARN(
          @"Commit event encoding failed for %@ at seq %lu (%@), falling back "
          @"to #sync",
          repoDid, (unsigned long)self.sequenceNumber, error);
      // Fallback to sync event...
    }

    NSError *persistError = nil;
    if (![self.serviceDatabases persistEvent:self.sequenceNumber
                                        type:eventType
                                        data:eventData
                                       error:&persistError]) {
      PDS_LOG_SYNC_ERROR(@"Failed to persist %@ event: %@", eventType,
                         persistError);
    }

    [self broadcastEventData:eventData];
    PDS_LOG_SYNC_INFO(@"Broadcast %@ event for repo %@, seq %lu", eventType,
                      repoDid, (unsigned long)self.sequenceNumber);
  });
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 400-470)

## Event Ordering Guarantees

### Monotonic Sequence Numbers

The PDS guarantees that sequence numbers are strictly increasing:

```
Event 1: seq = 1000
Event 2: seq = 1001
Event 3: seq = 1002
...
```

This guarantee is enforced by:
1. Using a serial dispatch queue for all event broadcasting
2. Incrementing the sequence number atomically
3. Persisting events to the database with their sequence numbers

### Serial Event Queue

All event broadcasting happens on a serial queue to ensure ordering:

```objc
// In SubscribeReposHandler.m - Initialization
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                        userDatabasePool:
                            (nullable PDSDatabasePool *)userDatabasePool {
  self = [super init];
  if (self) {
    _serviceDatabases = serviceDatabases;
    _userDatabasePool = userDatabasePool;
    _eventFormatter = [[EventFormatter alloc] init];
    _eventQueue = dispatch_queue_create("com.atproto.pds.subscribeRepos.events",
                                        DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_eventQueue, kSubscribeReposEventQueueKey,
                                kSubscribeReposEventQueueKey, NULL);
    _sequenceNumber = 0;
    _sequenceInitialized = NO;
    _stopping = NO;
    _attachedConnections = [NSMutableSet set];
    _maxReplayEventsPerConnection = kSubscribeReposMaxReplayEventsDefault;
    _maxPendingSendsPerConnection = kSubscribeReposMaxPendingSendsDefault;
    _maxPendingBytesPerConnection = kSubscribeReposMaxPendingBytesDefault;
    _lastCommitRevByDID = [NSMutableDictionary dictionary];
    // ...
  }
  return self;
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 90-120)

### Event Persistence

Events are persisted to the database with their sequence numbers:

```objc
// In PDSServiceDatabases.m (conceptual example)
- (BOOL)persistEvent:(NSUInteger)seq
                type:(NSString *)type
                data:(NSData *)data
               error:(NSError **)error {
    
    NSString *query = @"INSERT INTO sequencer (seq, type, data, created_at) "
                      @"VALUES (?, ?, ?, ?)";
    
    NSArray *params = @[
        @(seq),
        type,
        data,
        [NSDate date]
    ];
    
    return [self.serviceDB executeUpdate:query 
                              withParams:params 
                                   error:error];
}
```

## Sequence Number Recovery

### Initialization from Database

On startup, the handler recovers the last sequence number from the database:

```objc
// In SubscribeReposHandler.m
- (void)ensureSequenceInitialized {
  @synchronized(self) {
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
    PDS_LOG_SYNC_INFO(@"Initialized sequence number to %lu",
                      (unsigned long)self.sequenceNumber);
  }
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 1000-1020)

### Crash Recovery

If the PDS crashes and restarts:
1. The handler reads the maximum sequence number from the database
2. The next event will use `maxSequence + 1`
3. No sequence numbers are lost or reused

## Event Types and Sequence Numbers

### Commit Events

Repository commit events are the most common:

```json
{
  "seq": 12345,
  "repo": "did:plc:user123",
  "commit": "bafyreiabc123...",
  "rev": "3jqfk...",
  "since": "3jqfj...",
  "blocks": "<CAR bytes>",
  "ops": [
    {
      "action": "create",
      "path": "app.bsky.feed.post/3k2j...",
      "cid": "bafyredef456..."
    }
  ],
  "blobs": [],
  "time": "2024-01-01T00:00:00.000Z"
}
```

### Identity Events

Identity change events also receive sequence numbers:

```objc
// In SubscribeReposHandler.m
- (void)broadcastIdentityChange:(NSString *)did
                         handle:(nullable NSString *)handle {
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
    NSData *eventData =
        [self.eventFormatter encodeIdentityEvent:event error:&error];

    if (!eventData) {
      PDS_LOG_SYNC_ERROR(@"Failed to encode identity event: %@", error);
      return;
    }

    NSError *persistError = nil;
    if (![self.serviceDatabases persistEvent:self.sequenceNumber
                                        type:@"identity"
                                        data:eventData
                                       error:&persistError]) {
      PDS_LOG_SYNC_ERROR(@"Failed to persist identity event: %@", persistError);
    }

    [self broadcastEventData:eventData];
    PDS_LOG_SYNC_INFO(@"Broadcast identity event for DID %@, seq %lu", did,
                      (unsigned long)self.sequenceNumber);
  });
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 500-540)

### Account Events

Account status events (takedowns, suspensions):

```objc
// In SubscribeReposHandler.m
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
    NSData *eventData =
        [self.eventFormatter encodeAccountEvent:event error:&error];

    if (!eventData) {
      PDS_LOG_SYNC_ERROR(@"Failed to encode account event: %@", error);
      return;
    }

    NSError *persistError = nil;
    if (![self.serviceDatabases persistEvent:self.sequenceNumber
                                        type:@"account"
                                        data:eventData
                                       error:&persistError]) {
      PDS_LOG_SYNC_ERROR(@"Failed to persist account event: %@", persistError);
    }

    [self broadcastEventData:eventData];
    PDS_LOG_SYNC_INFO(@"Broadcast account takedown event for DID %@, seq %lu",
                      did, (unsigned long)self.sequenceNumber);
  });
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 540-580)

## Detecting Missing Events

### Gap Detection

Clients can detect missing events by checking for gaps in sequence numbers:

```objc
// Client-side example (conceptual)
- (void)handleEvent:(NSDictionary *)event {
    NSInteger seq = [event[@"seq"] integerValue];
    
    if (self.lastSeq > 0 && seq != self.lastSeq + 1) {
        // Gap detected!
        NSInteger gap = seq - self.lastSeq - 1;
        NSLog(@"Missing %ld events (last: %ld, current: %ld)", 
              (long)gap, (long)self.lastSeq, (long)seq);
        
        // Request replay from lastSeq
        [self reconnectWithCursor:@(self.lastSeq).stringValue];
    }
    
    self.lastSeq = seq;
}
```

### Handling Gaps

When a gap is detected, clients should:
1. Close the current connection
2. Reconnect with a cursor pointing to the last received sequence number
3. Replay missing events from the server

## Ordering Across Event Types

### Mixed Event Streams

The firehose can contain multiple event types in sequence:

```
seq=1000: #commit (repo: did:plc:user1)
seq=1001: #commit (repo: did:plc:user2)
seq=1002: #identity (did: did:plc:user1, handle: alice.bsky.social)
seq=1003: #commit (repo: did:plc:user3)
seq=1004: #account (did: did:plc:user4, status: takendown)
seq=1005: #commit (repo: did:plc:user1)
```

All event types share the same sequence number space, ensuring total ordering.

## Timestamp vs Sequence Number

### Event Timestamps

Events include both sequence numbers and timestamps:

```objc
// In SubscribeReposHandler.m
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
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 1020-1035)

### Ordering Semantics

- **Sequence numbers** define the canonical order
- **Timestamps** are informational only
- Clock skew or NTP adjustments do not affect ordering
- Always use sequence numbers for ordering, not timestamps

## Best Practices

1. **Always use sequence numbers for ordering** — Never rely on timestamps
2. **Detect gaps** — Check for missing sequence numbers
3. **Persist last sequence** — Track the last received sequence number
4. **Reconnect on gaps** — Use cursor-based replay to fill gaps
5. **Handle out-of-order delivery** — Buffer events if needed
6. **Monitor sequence progression** — Alert on stalled sequences

## Performance Considerations

### Serial Queue Impact

The serial event queue ensures ordering but limits throughput:
- All events are processed sequentially
- High-frequency commits may queue up
- Consider batching for high-volume scenarios

### Database Persistence

Every event is persisted to the database:
- Adds latency to event broadcasting
- Enables crash recovery
- Allows cursor-based replay

## See Also

- [Reconnection Strategy](./reconnection-strategy) — Handling disconnections
- [Event Replay](./event-replay) — Cursor-based catch-up
- [Reliability Guarantees](./reliability-guarantees) — Delivery semantics
- [Commit Broadcasting](./commit-broadcasting) — Event distribution
- [Firehose Overview](./firehose-overview) — Architecture overview

