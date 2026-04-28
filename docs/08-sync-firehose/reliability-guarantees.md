---
title: Reliability Guarantees and Delivery Semantics
---

# Reliability Guarantees and Delivery Semantics

## Overview

The firehose provides specific reliability guarantees for event delivery.

## Delivery Semantics

### At-Least-Once Delivery

The firehose guarantees **at-least-once delivery** for all events:
- Every event will be delivered to connected subscribers
- Events may be delivered more than once in failure scenarios
- Subscribers must handle duplicate events idempotently

### Why Not Exactly-Once?

Exactly-once delivery is impossible to guarantee in distributed systems due to:
- Network partitions
- Client crashes
- Server restarts
- Ambiguous acknowledgments

The firehose chooses at-least-once semantics because:
1. It's achievable with reasonable complexity
2. Clients can implement idempotency
3. It's better than at-most-once (potential data loss)

## Event Persistence

### Database Storage

All events are persisted to the database before broadcasting:

```objc
// In SubscribeReposHandler.m - Event persistence
NSError *persistError = nil;
if (![self.serviceDatabases persistEvent:self.sequenceNumber
                                    type:eventType
                                    data:eventData
                                   error:&persistError]) {
  PDS_LOG_SYNC_ERROR(@"Failed to persist %@ event: %@", eventType,
                     persistError);
}

[self broadcastEventData:eventData];
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 460-470)

This ensures:
- Events survive server crashes
- Events can be replayed after disconnections
- No events are lost due to server failures

### Durability Guarantees

Events are stored in SQLite with WAL mode:
- Write-Ahead Logging ensures durability
- Transactions are atomic
- Database survives crashes

## Ordering Guarantees

### Total Order

The firehose guarantees total ordering of events:
- Events are assigned monotonically increasing sequence numbers
- Events are delivered in sequence number order
- All subscribers see the same order

```objc
// In SubscribeReposHandler.m - Monotonic sequence assignment
dispatch_async(self.eventQueue, ^{
  [self ensureSequenceInitialized];
  self.sequenceNumber++;  // Atomic increment

  FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
  event.seq = self.sequenceNumber;
  // ...
});
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 400-410)

### Serial Event Queue

All event broadcasting happens on a serial queue:

```objc
// In SubscribeReposHandler.m - Serial queue initialization
_eventQueue = dispatch_queue_create("com.atproto.pds.subscribeRepos.events",
                                    DISPATCH_QUEUE_SERIAL);
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (line 95)

This ensures:
- Events are processed one at a time
- Sequence numbers are assigned in order
- No race conditions in event broadcasting

## Duplicate Detection

### Why Duplicates Occur

Duplicates can occur in several scenarios:

1. **Network Retransmission**:
   - Client receives event but ACK is lost
   - Server retransmits the event
   - Client receives it twice

2. **Reconnection Overlap**:
   - Client disconnects after receiving event N
   - Client reconnects with cursor N-1
   - Event N is replayed

3. **Server Restart**:
   - Server crashes after broadcasting but before client ACK
   - Server restarts and replays from last persisted state
   - Events may be rebroadcast

### Idempotency Keys

Each event has a unique identifier (sequence number):

```json
{
  "seq": 12345,
  "repo": "did:plc:user123",
  "commit": "bafyreiabc123...",
  "rev": "3jqfk...",
  // ...
}
```

Clients should use the sequence number for deduplication:

```objc
// Client-side example (conceptual)
@interface FirehoseClient : NSObject
@property (nonatomic, strong) NSMutableSet<NSNumber *> *processedSeqs;
@end

@implementation FirehoseClient

- (void)handleEvent:(NSDictionary *)event {
    NSNumber *seq = event[@"seq"];
    
    // Check if already processed
    if ([self.processedSeqs containsObject:seq]) {
        NSLog(@"Duplicate event detected: seq=%@", seq);
        return;
    }
    
    // Process event
    [self processEvent:event];
    
    // Mark as processed
    [self.processedSeqs addObject:seq];
    
    // Prune old sequence numbers (keep last 10000)
    if (self.processedSeqs.count > 10000) {
        [self pruneOldSequenceNumbers];
    }
}

@end
```

### Repository Revision Tracking

For commit events, the `rev` field provides additional deduplication:

```objc
// Client-side example (conceptual)
@interface RepositoryTracker : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *lastRevByDID;
@end

@implementation RepositoryTracker

- (BOOL)isNewCommit:(NSDictionary *)event {
    NSString *repo = event[@"repo"];
    NSString *rev = event[@"rev"];
    NSString *lastRev = self.lastRevByDID[repo];
    
    if ([rev isEqualToString:lastRev]) {
        // Duplicate commit
        return NO;
    }
    
    // New commit
    self.lastRevByDID[repo] = rev;
    return YES;
}

@end
```

## Gap Detection

### Detecting Missing Events

Clients can detect gaps by checking sequence numbers:

```objc
// Client-side example (conceptual)
- (void)handleEvent:(NSDictionary *)event {
    NSInteger seq = [event[@"seq"] integerValue];
    
    if (self.lastSeq > 0 && seq != self.lastSeq + 1) {
        // Gap detected!
        NSInteger gap = seq - self.lastSeq - 1;
        NSLog(@"Missing %ld events (last: %ld, current: %ld)", 
              (long)gap, (long)self.lastSeq, (long)seq);
        
        // Reconnect to fill gap
        [self reconnectWithCursor:@(self.lastSeq).stringValue];
        return;
    }
    
    self.lastSeq = seq;
    [self processEvent:event];
}
```

### Handling Gaps

When a gap is detected:
1. Close the current connection
2. Reconnect with cursor pointing to last received sequence
3. Replay missing events
4. Resume normal operation

## Crash Recovery

### Server Crash

If the server crashes:
1. Events are persisted in the database
2. On restart, sequence number is recovered from database
3. Clients reconnect with their last cursor
4. Missing events are replayed

```objc
// In SubscribeReposHandler.m - Sequence recovery
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

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 1000-1020)

### Client Crash

If the client crashes:
1. Client should persist last received sequence number
2. On restart, load persisted cursor
3. Reconnect with cursor
4. Replay missed events

```objc
// Client-side example (conceptual)
- (void)persistCursor:(NSInteger)seq {
    // Persist to disk
    [[NSUserDefaults standardUserDefaults] setInteger:seq forKey:@"lastFirehoseSeq"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSInteger)loadCursor {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"lastFirehoseSeq"];
}

- (void)reconnectAfterCrash {
    NSInteger cursor = [self loadCursor];
    if (cursor > 0) {
        [self connectWithCursor:@(cursor).stringValue];
    } else {
        [self connectWithoutCursor];
    }
}
```

## Backpressure and Reliability

### Slow Consumer Protection

The server protects itself from slow consumers:

```objc
// In SubscribeReposHandler.m - Backpressure check
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
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 970-990)

If a client is too slow:
- Server closes the connection
- Client must reconnect with cursor
- Events are replayed from cursor

This ensures:
- Server doesn't run out of memory
- Fast clients aren't blocked by slow clients
- Slow clients can catch up via replay

## Replay Window Limits

### Maximum Replay Events

The server limits replay to prevent resource exhaustion:

```objc
// In SubscribeReposHandler.m
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (line 29)

If a client's cursor is too old:
- Server adjusts cursor to oldest available
- Server sends info event about adjustment
- Client may miss events beyond the window

### Event Pruning

Old events should be pruned to limit database growth:

```sql
-- Prune events older than 7 days
DELETE FROM sequencer 
WHERE created_at < datetime('now', '-7 days');
```

This means:
- Events older than the retention period are lost
- Clients must connect within the retention window
- Long-disconnected clients may miss events

## Consistency Guarantees

### Per-Repository Consistency

For a single repository, the firehose guarantees:
- Commits are delivered in order
- The `since` field links to the previous commit
- The `rev` field is monotonically increasing

```objc
// In SubscribeReposHandler.m - Per-DID tracking
event.since = self.lastCommitRevByDID[repoDid];

// Update the per-DID tracking for next event's since field
if (commit.rev) {
  self.lastCommitRevByDID[repoDid] = commit.rev;
}
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 420-425)

### Cross-Repository Ordering

Across repositories, the firehose guarantees:
- Total ordering by sequence number
- Causality is preserved (if A happens before B, seq(A) < seq(B))

## Network Partition Handling

### During Partition

If a network partition occurs:
- Client loses connection
- Server continues broadcasting to other clients
- Events are persisted in database

### After Partition

When the partition heals:
- Client reconnects with cursor
- Server replays missed events
- Client catches up to current state

## Best Practices for Reliability

### Client-Side

1. **Persist cursors** — Save last received sequence number to disk
2. **Implement idempotency** — Handle duplicate events gracefully
3. **Detect gaps** — Check for missing sequence numbers
4. **Reconnect on failure** — Use exponential backoff
5. **Monitor lag** — Track how far behind the client is
6. **Handle backpressure** — Process events quickly or buffer appropriately

### Server-Side

1. **Persist events** — Store all events in database
2. **Use WAL mode** — Ensure durability
3. **Monitor replay window** — Alert when window is too small
4. **Prune old events** — Limit database growth
5. **Track slow clients** — Identify and handle slow consumers
6. **Log failures** — Aid debugging

## Failure Scenarios

### Scenario 1: Client Disconnect During Replay

```

1. Client connects with cursor=1000
2. Server starts replaying events 1001-1100
3. Client receives events 1001-1050
4. Network fails
5. Client reconnects with cursor=1050
6. Server replays events 1051-1100 (no duplicates)
7. Client catches up
```

### Scenario 2: Server Crash During Broadcast

```

1. Server broadcasts event seq=2000
2. Some clients receive it, others don't
3. Server crashes before all clients receive it
4. Server restarts, recovers seq=2000 from database
5. Clients that received it: detect duplicate, ignore
6. Clients that didn't: receive it normally
```

### Scenario 3: Slow Client

```

1. Client falls behind due to slow processing
2. Server's send buffer fills up
3. Server sends error frame and closes connection
4. Client reconnects with cursor
5. Server replays missed events
6. Client catches up (if within replay window)
```

## Monitoring and Alerting

### Key Metrics

Track these metrics for reliability:

```objc
// Conceptual metrics
- (void)recordReliabilityMetrics {
    // Server-side
    NSUInteger activeConnections = self.attachedConnections.count;
    NSUInteger currentSeq = self.sequenceNumber;
    NSUInteger oldestSeq = [self oldestPersistedSequenceNumber].unsignedIntegerValue;
    NSUInteger replayWindow = currentSeq - oldestSeq;
    
    // Client-side
    NSInteger lag = self.serverSeq - self.lastSeq;
    NSUInteger duplicates = self.duplicateCount;
    NSUInteger gaps = self.gapCount;
}
```

### Alerts

Set up alerts for:
- Replay window too small (< 1000 events)
- High duplicate rate (> 1%)
- Frequent gaps detected
- High client lag (> 1000 events)
- Frequent slow consumer disconnections

## See Also

- [Event Ordering](event-ordering) — Sequence number guarantees
- [Reconnection Strategy](reconnection-strategy) — Handling disconnections
- [Event Replay](event-replay) — Cursor-based catch-up
- [Backpressure](backpressure) — Flow control
- [Firehose Overview](firehose-overview) — Architecture overview

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

