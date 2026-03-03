# Commit Broadcasting

## Overview

Commit broadcasting is the mechanism that sends repository commits to all connected firehose subscribers in real-time. It:
- Captures commits from the repository service
- Formats commits as firehose events
- Distributes events to all subscribed clients
- Handles filtering by repository
- Manages event ordering and sequencing

## Architecture

### Broadcasting Pipeline

```
Record operation (create/update/delete)
    ↓
PDSRecordService processes operation
    ↓
PDSRepositoryService creates commit
    ↓
CommitBroadcaster.broadcastCommit called
    ↓
Event formatted with metadata
    ↓
Sequencer assigns sequence number
    ↓
Event stored in sequencer database
    ↓
Event sent to all subscribed clients
    ↓
Clients receive commit event
```

**ASCII Diagram: Commit Broadcasting Flow**

```
┌─────────────────────────────────────────────────────────┐
│  Record Operation                                       │
│  (create/update/delete via XRPC endpoint)              │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │  PDSRecordService       │
        │  - Validate record      │
        │  - Check permissions    │
        └────────────┬────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  PDSRepositoryService           │
        │  - Update MST                   │
        │  - Create commit                │
        │  - Calculate root CID           │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  Get next sequence number       │
        │  From PDSServiceDatabases       │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  Store commit in sequencer      │
        │  seq, did, commit, rebase, etc  │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  Format firehose event          │
        │  {t: "#commit", commit, seq...} │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  Encode as JSON                 │
        │  NSJSONSerialization            │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  Get all subscriptions          │
        │  From CommitBroadcaster         │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  For each subscription:         │
        │  - Check filter match           │
        │  - Send to client               │
        │  - Handle backpressure          │
        └─────────────────────────────────┘
```

### Event Flow

```
┌─────────────────────────────────────────────────────────┐
│                  Record Operation                       │
│  (create/update/delete via XRPC endpoint)              │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │  PDSRecordService       │
        │  - Validate record      │
        │  - Check permissions    │
        └────────────┬────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  PDSRepositoryService           │
        │  - Update MST                   │
        │  - Create commit                │
        │  - Calculate root CID           │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  CommitBroadcaster              │
        │  - Format event                 │
        │  - Assign sequence number       │
        │  - Store in sequencer           │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │  WebSocket Connections          │
        │  - Filter by repository         │
        │  - Send to subscribers          │
        │  - Handle backpressure          │
        └─────────────────────────────────┘
```

## Commit Event Format

### Event Structure

```json
{
  "t": "#commit",
  "commit": {
    "root": "bafyreiabc123...",
    "prev": "bafyredef456...",
    "timestamp": "2024-01-01T00:00:00Z",
    "did": "did:plc:user123"
  },
  "seq": 12345,
  "time": "2024-01-01T00:00:00Z",
  "rebase": false,
  "tooBig": false
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| t | string | Event type (always "#commit") |
| commit | object | Commit data |
| commit.root | string | CID of repository root after commit |
| commit.prev | string | CID of previous root (null for first commit) |
| commit.timestamp | string | ISO 8601 timestamp of commit |
| commit.did | string | DID of repository owner |
| seq | integer | Sequence number for ordering |
| time | string | ISO 8601 timestamp of event |
| rebase | boolean | Whether this is a rebase operation |
| tooBig | boolean | Whether commit was too large to include |

## Broadcasting Implementation

### Broadcaster Initialization

```objc
// In CommitBroadcaster.m
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    self = [super init];
    if (!self) return nil;
    
    self.serviceDatabases = serviceDatabases;
    self.subscriptions = [NSMutableArray array];
    self.subscriptionLock = [[NSLock alloc] init];
    self.eventQueue = dispatch_queue_create("com.atproto.broadcaster", 
                                            DISPATCH_QUEUE_SERIAL);
    
    return self;
}
```

### Broadcasting Commits

The SubscribeReposHandler broadcasts repository commits to all connected clients:

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
    self.sequenceNumber++;

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];

    // Required fields per subscribeRepos lexicon
    event.seq = self.sequenceNumber;
    event.rebase = NO; // Deprecated, always false
    event.tooBig = NO; // Deprecated, always false
    event.repo = repoDid;
    event.commit = commit.computeCID;
    event.rev = commit.rev;
    event.since =
        self.lastCommitRevByDID[repoDid]; // Previous commit rev for this repo
    event.blocks =
        [self buildCARBlocksForCommit:commit ops:ops]; // Real CAR bytes
    event.ops = ops;
    event.blobs = blobs ?: @[]; // Already CID array
    event.time = [SubscribeReposHandler rfc3339Timestamp];
    event.prevData = commit.prevCID ?: nil; // Previous MST root CID

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
      FirehoseSyncEvent *syncEvent = [[FirehoseSyncEvent alloc] init];
      syncEvent.seq = self.sequenceNumber;
      syncEvent.did = repoDid;
      syncEvent.blocks = [self buildCARBlocksForSyncCommitOnly:commit];
      syncEvent.rev = commit.rev ?: @"";
      syncEvent.time = event.time;

      NSError *syncError = nil;
      eventData = [self.eventFormatter encodeSyncEvent:syncEvent error:&syncError];
      if (!eventData) {
        PDS_LOG_SYNC_ERROR(@"Failed to encode sync fallback event: %@",
                           syncError);
        return;
      }
      eventType = @"sync";
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

### Subscription Filtering

```objc
// In CommitBroadcaster.m
- (BOOL)subscriptionMatches:(SubscriptionContext *)context 
                    commit:(NSDictionary *)commit {
    
    // 1. Get repository DID from commit
    NSString *did = commit[@"did"];
    
    // 2. If no repo filter, match all
    if (!context.repos || context.repos.count == 0) {
        return YES;
    }
    
    // 3. Check if DID is in filter list
    return [context.repos containsObject:did];
}
```

## Sequencing

### Sequence Number Assignment

```objc
// In PDSServiceDatabases.m
- (NSInteger)getNextSequenceNumber {
    NSInteger seq = 0;
    
    NSString *query = @"SELECT MAX(seq) as max_seq FROM sequencer";
    
    [self.serviceDB executeQuery:query 
                     completion:^(NSArray *rows, NSError *error) {
        if (rows.count > 0) {
            NSDictionary *row = rows[0];
            NSNumber *maxSeq = row[@"max_seq"];
            if (maxSeq && ![maxSeq isKindOfClass:[NSNull class]]) {
                seq = [maxSeq integerValue] + 1;
            } else {
                seq = 1;
            }
        }
    }];
    
    return seq;
}
```

### Storing Commits in Sequencer

```objc
// In PDSServiceDatabases.m
- (void)storeCommit:(NSDictionary *)commit 
                seq:(NSInteger)seq
                did:(NSString *)did
           rebase:(BOOL)rebase
          tooBig:(BOOL)tooBig
       completion:(void (^)(NSError *error))completion {
    
    NSString *query = @"INSERT INTO sequencer (seq, did, commit, rebase, too_big, created_at) "
                      @"VALUES (?, ?, ?, ?, ?, ?)";
    
    NSData *commitData = [NSJSONSerialization dataWithJSONObject:commit 
                                                         options:0 
                                                           error:nil];
    
    NSArray *params = @[
        @(seq),
        did,
        commitData,
        @(rebase),
        @(tooBig),
        [NSDate date]
    ];
    
    [self.serviceDB executeUpdate:query 
                      withParams:params 
                      completion:completion];
}
```

### Cursor-Based Retrieval

```objc
// In PDSServiceDatabases.m
- (void)getCommitsAfterSeq:(NSInteger)seq 
                completion:(void (^)(NSArray *commits, NSError *error))completion {
    
    NSString *query = @"SELECT seq, did, commit, rebase, too_big, created_at "
                      @"FROM sequencer WHERE seq > ? ORDER BY seq ASC LIMIT 1000";
    
    [self.serviceDB executeQuery:query 
                      withParams:@[@(seq)]
                      completion:^(NSArray *rows, NSError *error) {
        
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSMutableArray *commits = [NSMutableArray array];
        
        for (NSDictionary *row in rows) {
            NSData *commitData = row[@"commit"];
            NSDictionary *commit = [NSJSONSerialization JSONObjectWithData:commitData 
                                                                   options:0 
                                                                     error:nil];
            
            [commits addObject:@{
                @"seq": row[@"seq"],
                @"did": row[@"did"],
                @"commit": commit,
                @"rebase": row[@"rebase"],
                @"tooBig": row[@"too_big"],
                @"timestamp": row[@"created_at"]
            }];
        }
        
        completion(commits, nil);
    }];
}
```

## Subscription Management

### Registering Subscriptions

```objc
// In CommitBroadcaster.m
- (void)registerSubscription:(SubscriptionContext *)context {
    [self.subscriptionLock lock];
    [self.subscriptions addObject:context];
    [self.subscriptionLock unlock];
    
    NSLog(@"Subscription registered. Total: %lu", self.subscriptions.count);
    
    // Record metric
    [self recordMetric:@"active_subscriptions" value:@(self.subscriptions.count)];
}

- (void)unregisterSubscription:(SubscriptionContext *)context {
    [self.subscriptionLock lock];
    [self.subscriptions removeObject:context];
    [self.subscriptionLock unlock];
    
    NSLog(@"Subscription unregistered. Total: %lu", self.subscriptions.count);
    
    // Record metric
    [self recordMetric:@"active_subscriptions" value:@(self.subscriptions.count)];
}
```

### Subscription Context

```objc
// In SubscriptionContext.h
@interface SubscriptionContext : NSObject

@property (nonatomic, strong) WebSocketConnection *connection;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, copy) NSArray *repos;  // Repository DIDs to filter
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) NSInteger eventsReceived;
@property (nonatomic, assign) NSInteger bytesSent;

@end
```

## Event Ordering

### Maintaining Order

```objc
// In CommitBroadcaster.m
- (void)broadcastCommit:(NSDictionary *)commit 
                   did:(NSString *)did
                   seq:(NSInteger)seq
                  rebase:(BOOL)rebase
                 tooBig:(BOOL)tooBig {
    
    // 1. Ensure sequence numbers are monotonically increasing
    if (seq <= self.lastSeq) {
        NSLog(@"Warning: Out-of-order sequence number: %ld <= %ld", 
              (long)seq, (long)self.lastSeq);
        return;
    }
    
    self.lastSeq = seq;
    
    // 2. Create event with sequence number
    NSDictionary *event = @{
        @"t": @"#commit",
        @"commit": commit,
        @"seq": @(seq),
        @"time": [self formatTimestamp:[NSDate date]],
        @"rebase": @(rebase),
        @"tooBig": @(tooBig)
    };
    
    // 3. Broadcast to subscribers
    [self broadcastEvent:event];
}
```

### Handling Out-of-Order Events

```objc
// In SubscribeReposHandler.m
- (void)handleClientMessage:(NSData *)message 
                subscription:(SubscriptionContext *)context {
    
    // Parse message
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:message 
                                                            options:0 
                                                              error:nil];
    
    NSString *action = request[@"action"];
    
    if ([action isEqualToString:@"subscribe"]) {
        // 1. Update subscription filter
        context.repos = request[@"repos"];
        
        // 2. Send historical events if cursor provided
        NSString *cursor = request[@"cursor"];
        if (cursor) {
            [self sendHistoricalEvents:cursor toSubscription:context];
        }
    }
}
```

## Rebase Handling

### Detecting Rebases

```objc
// In PDSRepositoryService.m
- (void)createCommitWithRootCID:(NSString *)rootCID
                            did:(NSString *)did
                       prevCID:(NSString *)prevCID
                    completion:(void (^)(NSString *commitCID, NSError *error))completion {
    
    // 1. Get current head
    NSString *currentHead = [self getHeadCommitCID:did];
    
    // 2. Detect rebase (prev doesn't match current head)
    BOOL isRebase = prevCID && ![prevCID isEqualToString:currentHead];
    
    // 3. Create commit
    NSDictionary *commit = @{
        @"root": rootCID,
        @"prev": prevCID ?: [NSNull null],
        @"timestamp": [NSDate date],
        @"did": did
    };
    
    // 4. Store and broadcast
    NSInteger seq = [self.serviceDatabases getNextSequenceNumber];
    [self.serviceDatabases storeCommit:commit seq:seq did:did rebase:isRebase tooBig:NO];
    
    [self.broadcaster broadcastCommit:commit did:did seq:seq rebase:isRebase tooBig:NO];
    
    completion([CID calculateCIDForData:[ATProtoCBORSerialization encodeObject:commit error:nil]], nil);
}
```

## Large Commit Handling

### Detecting Large Commits

```objc
// In CommitBroadcaster.m
- (void)broadcastCommit:(NSDictionary *)commit 
                   did:(NSString *)did
                   seq:(NSInteger)seq
                  rebase:(BOOL)rebase {
    
    // 1. Encode commit to check size
    NSData *commitData = [NSJSONSerialization dataWithJSONObject:commit 
                                                         options:0 
                                                           error:nil];
    
    // 2. Check if too large (> 1MB)
    BOOL tooBig = commitData.length > (1024 * 1024);
    
    if (tooBig) {
        NSLog(@"Large commit detected: %lu bytes", (unsigned long)commitData.length);
    }
    
    // 3. Create event
    NSDictionary *event = @{
        @"t": @"#commit",
        @"commit": tooBig ? @{} : commit,  // Omit commit data if too big
        @"seq": @(seq),
        @"time": [self formatTimestamp:[NSDate date]],
        @"rebase": @(rebase),
        @"tooBig": @(tooBig)
    };
    
    // 4. Broadcast
    [self broadcastEvent:event];
}
```

## Error Handling

### Handling Broadcast Failures

```objc
// In CommitBroadcaster.m
- (void)sendEventToSubscribers:(NSData *)eventData 
                       commit:(NSDictionary *)commit {
    
    [self.subscriptionLock lock];
    NSArray *subscriptions = [self.subscriptions copy];
    [self.subscriptionLock unlock];
    
    NSMutableArray *failedSubscriptions = [NSMutableArray array];
    
    for (SubscriptionContext *context in subscriptions) {
        if (![self subscriptionMatches:context commit:commit]) {
            continue;
        }
        
        NSError *error = nil;
        [context.connection sendMessage:eventData opcode:0x1 fin:YES error:&error];
        
        if (error) {
            NSLog(@"Failed to send event to subscription: %@", error);
            [failedSubscriptions addObject:context];
        } else {
            context.eventsReceived++;
            context.bytesSent += eventData.length;
        }
    }
    
    // Remove failed subscriptions
    if (failedSubscriptions.count > 0) {
        [self.subscriptionLock lock];
        [self.subscriptions removeObjectsInArray:failedSubscriptions];
        [self.subscriptionLock unlock];
    }
}
```

## Monitoring

### Broadcasting Metrics

```objc
// In CommitBroadcaster.m
- (void)recordMetric:(NSString *)name value:(NSNumber *)value {
    @synchronized(self.metrics) {
        NSMutableArray *values = self.metrics[name];
        if (!values) {
            values = [NSMutableArray array];
            self.metrics[name] = values;
        }
        [values addObject:value];
    }
}

// Usage
[self recordMetric:@"commits_broadcast" value:@(1)];
[self recordMetric:@"active_subscriptions" value:@(self.subscriptions.count)];
[self recordMetric:@"event_size_bytes" value:@(eventData.length)];
```

### Health Monitoring

```objc
// In CommitBroadcaster.m
- (void)performHealthCheck {
    @synchronized(self.metrics) {
        NSMutableDictionary *stats = [NSMutableDictionary dictionary];
        
        stats[@"active_subscriptions"] = @(self.subscriptions.count);
        stats[@"last_seq"] = @(self.lastSeq);
        
        for (NSString *metric in self.metrics) {
            NSArray *values = self.metrics[metric];
            if (values.count > 0) {
                NSNumber *lastValue = values.lastObject;
                stats[metric] = lastValue;
            }
        }
        
        NSLog(@"Broadcaster health: %@", stats);
    }
}
```

## Best Practices

1. **Maintain sequence order** — Ensure monotonically increasing sequence numbers
2. **Filter subscriptions** — Only send relevant commits to each subscriber
3. **Handle large commits** — Set tooBig flag for oversized commits
4. **Detect rebases** — Identify when prev doesn't match current head
5. **Monitor metrics** — Track active subscriptions and event throughput
6. **Handle failures gracefully** — Remove dead subscriptions
7. **Batch events** — Send multiple events in single frame when possible
8. **Implement backpressure** — Don't overwhelm slow clients

## Next Steps

- **[Backpressure](./backpressure)** — Flow control
- **[WebSocket Server](./websocket-server)** — WebSocket implementation
- **[Firehose Overview](./firehose-overview)** — Architecture overview

