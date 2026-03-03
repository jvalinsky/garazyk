# Event Replay and Catch-Up Mechanisms

## Overview

Event replay allows subscribers to catch up on missed events after disconnections or when starting from a specific point in history. The firehose implements efficient batch replay with:
- Cursor-based positioning
- Batch fetching for performance
- Backpressure-aware delivery
- Replay window limits

## Replay Architecture

### Replay Flow

```
Client reconnects with cursor=1000
    ↓
Server validates cursor
    ↓
Server fetches events 1001-1100 (batch 1)
    ↓
Server sends batch to client
    ↓
Server fetches events 1101-1200 (batch 2)
    ↓
Server sends batch to client
    ↓
... continue until caught up ...
    ↓
Switch to live event mode
```

## Batch Replay Implementation

### Replay Entry Point

The replay process starts after cursor validation:

```objc
// In SubscribeReposHandler.m - Starting replay
if (hasCursor) {
  BOOL outdated = NO;
  NSUInteger replayCursor =
      [self effectiveReplayCursorForRequestedCursor:parsedCursor
                                           outdated:&outdated];
  if (outdated) {
    PDS_LOG_SYNC_WARN(@"Outdated cursor %lu adjusted to %lu for connection %@",
                      (unsigned long)parsedCursor,
                      (unsigned long)replayCursor, connection);
    [self sendInfoEvent:kSubscribeReposInfoOutdatedCursor
                message:@"Requested cursor exceeded limit. Possibly missing events"
           toConnection:connection];
  }

  if (replayCursor >= self.sequenceNumber) {
    PDS_LOG_SYNC_INFO(@"Cursor %lu is up to date at server sequence %lu.",
                      (unsigned long)replayCursor,
                      (unsigned long)self.sequenceNumber);
  } else {
    NSUInteger backlog = self.sequenceNumber - replayCursor;
    PDS_LOG_SYNC_INFO(@"Starting replay of %lu events for connection %@",
                      (unsigned long)backlog, connection);
    [self replayEventsAfterCursor:replayCursor toConnection:connection];
  }
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 760-790)

### Batch Fetching

Events are fetched in batches for efficiency:

```objc
// In SubscribeReposHandler.m - Batch replay implementation
- (void)replayEventsAfterCursor:(NSUInteger)cursor
                   toConnection:(WebSocketConnection *)connection {
  PDS_LOG_SYNC_INFO(@"Replaying events after cursor %lu",
                    (unsigned long)cursor);
  [self ensureSequenceInitialized];

  NSUInteger fetchCursor = cursor;
  NSUInteger replayedCount = 0;
  BOOL hasMore = YES;

  while (hasMore) {
    NSError *error = nil;
    NSArray *events =
        [self.serviceDatabases getEventsSince:fetchCursor
                                        limit:kSubscribeReposReplayBatchSize
                                        error:&error];
    if (error || !events) {
      PDS_LOG_SYNC_ERROR(@"Failed to fetch events for replay: %@", error);
      break;
    }

    if (events.count == 0) {
      hasMore = NO;
      PDS_LOG_SYNC_INFO(@"No more events to replay for connection %@", connection);
      break;
    }

    PDS_LOG_SYNC_INFO(@"Fetched batch of %lu events for replay (current seq: %lu)",
                      (unsigned long)events.count, (unsigned long)fetchCursor);

    for (NSDictionary *event in events) {
      NSNumber *seq = event[@"seq"];
      NSData *data = event[@"data"];

      replayedCount++;
      if (replayedCount > self.maxReplayEventsPerConnection) {
        PDS_LOG_SYNC_WARN(@"Replay limit exceeded (%lu) during backfill for connection %@",
                         (unsigned long)replayedCount, connection);
        [self sendInfoEvent:kSubscribeReposInfoOutdatedCursor
                    message:@"Replay window exceeded while backfilling"
               toConnection:connection];
        return;
      }

      if (![self sendEventData:data
              toConnectionWithBackpressureCheck:connection]) {
        PDS_LOG_SYNC_WARN(@"Failed to send event %lu during replay (backpressure or closed)",
                         (unsigned long)[seq unsignedIntegerValue]);
        return;
      }
      fetchCursor = [seq unsignedIntegerValue];
    }
    PDS_LOG_SYNC_INFO(@"Completed replay batch, next cursor: %lu", (unsigned long)fetchCursor);

    if (events.count < kSubscribeReposReplayBatchSize) {
      hasMore = NO;
    }

    if (fetchCursor >= self.sequenceNumber) {
      hasMore = NO;
    }
  }

  PDS_LOG_SYNC_INFO(@"Replay completed. Last cursor: %lu",
                    (unsigned long)fetchCursor);
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 790-860)

## Batch Size Configuration

### Default Batch Size

```objc
// In SubscribeReposHandler.m
static const NSUInteger kSubscribeReposReplayBatchSize = 100;
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (line 28)

This means:
- Events are fetched 100 at a time from the database
- Reduces database query overhead
- Balances memory usage and performance

## Replay Limits

### Maximum Replay Events

The server limits total replay to prevent resource exhaustion:

```objc
// In SubscribeReposHandler.m
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;

// In initialization
_maxReplayEventsPerConnection = kSubscribeReposMaxReplayEventsDefault;
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 29, 110)

### Exceeding Replay Limit

If replay exceeds the limit, the server sends an info event and stops:

```objc
// In SubscribeReposHandler.m
replayedCount++;
if (replayedCount > self.maxReplayEventsPerConnection) {
  PDS_LOG_SYNC_WARN(@"Replay limit exceeded (%lu) during backfill for connection %@",
                   (unsigned long)replayedCount, connection);
  [self sendInfoEvent:kSubscribeReposInfoOutdatedCursor
              message:@"Replay window exceeded while backfilling"
         toConnection:connection];
  return;
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 820-830)

## Cursor Management

### Cursor Format

Cursors are string representations of sequence numbers:

```
cursor=0       → Start from beginning
cursor=12345   → Resume from sequence 12345
cursor=999999  → Resume from sequence 999999
```

### Cursor Validation

The server validates cursor format:

```objc
// In SubscribeReposHandler.m - Cursor parsing
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
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 850-880)

### Effective Replay Cursor

The server may adjust cursors that are too old:

```objc
// In SubscribeReposHandler.m - Effective replay cursor calculation
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

  if (self.sequenceNumber > self.maxReplayEventsPerConnection) {
    NSUInteger replayWindowCursor =
        self.sequenceNumber - self.maxReplayEventsPerConnection;
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
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 900-930)

## Database Event Storage

### Event Persistence

Events are stored in the sequencer table:

```sql
CREATE TABLE sequencer (
    seq INTEGER PRIMARY KEY,
    type TEXT NOT NULL,
    data BLOB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sequencer_seq ON sequencer(seq);
```

### Fetching Events

Events are fetched with a cursor and limit:

```objc
// In PDSServiceDatabases.m (conceptual)
- (NSArray *)getEventsSince:(NSUInteger)cursor
                      limit:(NSUInteger)limit
                      error:(NSError **)error {
    
    NSString *query = @"SELECT seq, type, data, created_at "
                      @"FROM sequencer "
                      @"WHERE seq > ? "
                      @"ORDER BY seq ASC "
                      @"LIMIT ?";
    
    NSArray *params = @[@(cursor), @(limit)];
    
    return [self.serviceDB executeQuery:query 
                             withParams:params 
                                  error:error];
}
```

## Backpressure During Replay

### Backpressure Check

Each event is sent with a backpressure check:

```objc
// In SubscribeReposHandler.m - Sending with backpressure check
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

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 970-990)

### Backpressure Limits

```objc
// In SubscribeReposHandler.m
static const NSUInteger kSubscribeReposMaxPendingSendsDefault = 512;
static const NSUInteger kSubscribeReposMaxPendingBytesDefault = 16 * 1024 * 1024; // 16MB

// In initialization
_maxPendingSendsPerConnection = kSubscribeReposMaxPendingSendsDefault;
_maxPendingBytesPerConnection = kSubscribeReposMaxPendingBytesDefault;
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 30-32, 111-112)

## Transition to Live Mode

### Detecting Catch-Up Completion

Replay completes when:
1. All batches have been sent
2. The fetch cursor reaches the current sequence number
3. No more events are available

```objc
// In SubscribeReposHandler.m
if (events.count < kSubscribeReposReplayBatchSize) {
  hasMore = NO;
}

if (fetchCursor >= self.sequenceNumber) {
  hasMore = NO;
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 850-860)

### Live Event Delivery

After replay completes, the connection automatically receives live events:

```objc
// In SubscribeReposHandler.m - Broadcasting to all connections
- (void)broadcastEventData:(NSData *)eventData {
  [self.webSocketServer broadcastMessage:eventData toConnectionsMatching:nil];
  NSSet<WebSocketConnection *> *attachedSnapshot = nil;
  @synchronized(self.attachedConnections) {
    attachedSnapshot = [self.attachedConnections copy];
  }
  for (WebSocketConnection *connection in attachedSnapshot) {
    [self sendEventData:eventData toConnectionWithBackpressureCheck:connection];
  }
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 630-645)

## Client-Side Cursor Management

### Persisting Cursors

Clients should persist the last received sequence number:

```objc
// Client-side example (conceptual)
- (void)handleEvent:(NSDictionary *)event {
    NSInteger seq = [event[@"seq"] integerValue];
    
    // Process event...
    
    // Persist cursor
    [[NSUserDefaults standardUserDefaults] setInteger:seq forKey:@"lastFirehoseSeq"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    self.lastSeq = seq;
}

- (NSString *)loadCursor {
    NSInteger seq = [[NSUserDefaults standardUserDefaults] integerForKey:@"lastFirehoseSeq"];
    return seq > 0 ? @(seq).stringValue : nil;
}
```

### Reconnecting with Cursor

On reconnection, provide the saved cursor:

```objc
// Client-side example (conceptual)
- (void)connect {
    NSString *cursor = [self loadCursor];
    NSString *urlString = @"ws://pds.example.com/xrpc/com.atproto.sync.subscribeRepos";
    
    if (cursor) {
        urlString = [urlString stringByAppendingFormat:@"?cursor=%@", cursor];
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    // Connect to WebSocket...
}
```

## Performance Optimization

### Batch Size Tuning

The batch size affects:
- **Smaller batches** (e.g., 50):
  - More database queries
  - Lower memory usage
  - More responsive to backpressure
- **Larger batches** (e.g., 500):
  - Fewer database queries
  - Higher memory usage
  - Faster replay for fast clients

### Database Indexing

Ensure the sequencer table has proper indexes:

```sql
CREATE INDEX idx_sequencer_seq ON sequencer(seq);
CREATE INDEX idx_sequencer_created_at ON sequencer(created_at);
```

### Event Pruning

Old events should be pruned to limit database growth:

```sql
-- Delete events older than 7 days
DELETE FROM sequencer 
WHERE created_at < datetime('now', '-7 days');
```

## Monitoring

### Replay Metrics

Track replay performance:

```objc
// Conceptual metrics
- (void)recordReplayMetrics:(NSUInteger)eventCount 
                   duration:(NSTimeInterval)duration {
    
    double eventsPerSecond = eventCount / duration;
    
    NSLog(@"Replay metrics:");
    NSLog(@"  Events replayed: %lu", (unsigned long)eventCount);
    NSLog(@"  Duration: %.2f seconds", duration);
    NSLog(@"  Throughput: %.0f events/sec", eventsPerSecond);
}
```

### Replay Failures

Log and monitor replay failures:

```objc
// In SubscribeReposHandler.m
if (error || !events) {
  PDS_LOG_SYNC_ERROR(@"Failed to fetch events for replay: %@", error);
  break;
}
```

## Best Practices

1. **Persist cursors** — Save the last received sequence number
2. **Use appropriate batch sizes** — Balance performance and memory
3. **Monitor replay progress** — Track events replayed
4. **Handle backpressure** — Respect server limits
5. **Prune old events** — Limit database growth
6. **Index properly** — Ensure fast cursor-based queries
7. **Test replay scenarios** — Verify catch-up works correctly
8. **Log replay metrics** — Aid performance tuning

## Error Scenarios

### Database Query Failure

If event fetching fails:
- Log the error
- Stop replay
- Connection remains open for live events

### Backpressure During Replay

If the client is too slow:
- Server sends error frame
- Connection is closed
- Client should reconnect with exponential backoff

### Replay Limit Exceeded

If replay exceeds the maximum:
- Server sends info event
- Replay stops at the limit
- Client may have missed events

## See Also

- [Event Ordering](./event-ordering.md) — Sequence number guarantees
- [Reconnection Strategy](./reconnection-strategy.md) — Handling disconnections
- [Reliability Guarantees](./reliability-guarantees.md) — Delivery semantics
- [Backpressure](./backpressure.md) — Flow control
- [Firehose Overview](./firehose-overview.md) — Architecture overview

