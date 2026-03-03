# Firehose Rate Limiting

## Overview

The firehose (subscribeRepos) implements specialized rate limiting and backpressure mechanisms to protect the server from slow or abusive subscribers. Unlike HTTP request rate limiting, firehose rate limiting focuses on:

- **Output queue limits** — Preventing memory exhaustion from slow consumers
- **Backpressure detection** — Identifying subscribers that can't keep up
- **Automatic disconnection** — Removing slow consumers to protect the server
- **Replay limits** — Controlling historical event retrieval

## Architecture

```
┌──────────────────────────────────────────┐
│   Commit Event                           │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   Broadcast to All Subscribers           │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
   Fast Consumer     Slow Consumer
        │                 │
        ▼                 ▼
   Queue Empty      Queue Growing
   (Healthy)        (Backpressure)
                         │
                         ▼
                  Queue Limit Exceeded
                         │
                         ▼
                  Disconnect Consumer
```

## Subscriber Limits

### Output Queue Limits

**Implementation (from SubscribeReposHandler.m):**

```objc
static const NSUInteger kSubscribeReposMaxPendingSendsDefault = 512;
static const NSUInteger kSubscribeReposMaxPendingBytesDefault = 16 * 1024 * 1024; // 16MB

@interface SubscribeReposHandler ()
@property(nonatomic, assign) NSUInteger maxPendingSendsPerConnection;
@property(nonatomic, assign) NSUInteger maxPendingBytesPerConnection;
@end

- (instancetype)initWithWebSocketServer:(WebSocketServer *)server
                       serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                       userDatabasePool:(PDSDatabasePool *)userDatabasePool {
    self = [super init];
    if (self) {
        _maxPendingSendsPerConnection = kSubscribeReposMaxPendingSendsDefault;
        _maxPendingBytesPerConnection = kSubscribeReposMaxPendingBytesDefault;
        // ...
    }
    return self;
}
```

**Purpose:**
- Prevents memory exhaustion from slow subscribers
- Limits per-connection resource usage
- Ensures fair resource allocation

**Configuration:**
- Default pending sends: 512 messages
- Default pending bytes: 16 MB
- Per-connection limits

### Backpressure Detection

**Implementation (from SubscribeReposHandler.m):**

```objc
- (BOOL)sendEventData:(NSData *)eventData
    toConnectionWithBackpressureCheck:(WebSocketConnection *)connection {
    
    if (!eventData || !connection) {
        return NO;
    }
    
    // Check both message count and byte size
    if (connection.pendingSendCount >= self.maxPendingSendsPerConnection ||
        connection.pendingSendBytes >= self.maxPendingBytesPerConnection) {
        
        // Send error frame before disconnecting
        [self sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
                             message:@"connection output queue exceeded server limit"
                        toConnection:connection];
        
        // Detach and close connection
        [self detachConnection:connection];
        [connection closeWithCode:1008 reason:kSubscribeReposErrorConsumerTooSlow];
        
        return NO;
    }
    
    // Send event
    [connection sendMessage:eventData];
    return YES;
}
```

**Detection Criteria:**
- Pending send count ≥ 512 messages
- Pending send bytes ≥ 16 MB

**Action:**
- Send `ConsumerTooSlow` error frame
- Detach connection from subscriber list
- Close WebSocket with code 1008

### Queue Tracking

**Implementation (from WebSocketConnection.m):**

```objc
@interface WebSocketConnection ()
@property(nonatomic, strong) NSMutableArray<NSData *> *messageQueue;
@property(nonatomic, assign) NSUInteger queuedSendBytes;
@end

- (NSUInteger)pendingSendCount {
    __block NSUInteger count = 0;
    if (!self.writeQueue) {
        return 0;
    }
    
    dispatch_sync(self.writeQueue, ^{
        count = self.messageQueue.count;
    });
    return count;
}

- (NSUInteger)pendingSendBytes {
    __block NSUInteger bytes = 0;
    if (!self.writeQueue) {
        return 0;
    }
    
    dispatch_sync(self.writeQueue, ^{
        bytes = self.queuedSendBytes;
    });
    return bytes;
}
```

**Thread Safety:**
- Queue operations on serial write queue
- Synchronous reads for accurate counts
- Atomic updates to queue size

### WebSocket-Level Limits

**Implementation (from WebSocketConnection.m):**

```objc
static const NSUInteger WS_MAX_PENDING_SEND_BYTES = 32 * 1024 * 1024; // 32MB

- (void)sendFrame:(NSData *)frame {
    dispatch_async(self.writeQueue, ^{
        if (self.state == WebSocketConnectionStateClosing ||
            self.state == WebSocketConnectionStateClosed) {
            return;
        }
        
        // Check WebSocket-level limit
        if (self.queuedSendBytes + frame.length > WS_MAX_PENDING_SEND_BYTES) {
            [self.messageQueue removeAllObjects];
            self.queuedSendBytes = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self closeWithCode:1009 reason:@"Outbound queue limit exceeded"];
            });
            return;
        }
        
        [self.messageQueue addObject:frame];
        self.queuedSendBytes += frame.length;
        
        if (self.messageQueue.count == 1) {
            [self flushWriteBuffer];
        }
    });
}
```

**Purpose:**
- Hard limit at WebSocket layer
- Prevents catastrophic memory growth
- Last line of defense

**Configuration:**
- WebSocket limit: 32 MB (higher than firehose limit)
- Closes with code 1009 (Message Too Big)

## Replay Limits

### Maximum Replay Events

**Implementation (from SubscribeReposHandler.m):**

```objc
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;

@interface SubscribeReposHandler ()
@property(nonatomic, assign) NSUInteger maxReplayEventsPerConnection;
@end

- (instancetype)initWithWebSocketServer:(WebSocketServer *)server
                       serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                       userDatabasePool:(PDSDatabasePool *)userDatabasePool {
    self = [super init];
    if (self) {
        _maxReplayEventsPerConnection = kSubscribeReposMaxReplayEventsDefault;
        // ...
    }
    return self;
}
```

**Purpose:**
- Limits historical event retrieval
- Prevents excessive database queries
- Protects against cursor abuse

**Configuration:**
- Default: 10,000 events per connection
- Applied during cursor-based replay

### Replay Batch Size

**Implementation (from SubscribeReposHandler.m):**

```objc
static const NSUInteger kSubscribeReposReplayBatchSize = 100;

// Replay events in batches
while (replayedCount < maxReplayEvents && currentCursor <= latestSequence) {
    NSArray *events = [self.serviceDatabases 
        getEventsFromSequence:currentCursor 
                        limit:kSubscribeReposReplayBatchSize 
                        error:&error];
    
    for (NSDictionary *event in events) {
        NSData *eventData = [self formatEvent:event];
        
        if (![self sendEventData:eventData 
            toConnectionWithBackpressureCheck:connection]) {
            // Subscriber too slow, stop replay
            return;
        }
        
        replayedCount++;
    }
    
    currentCursor += events.count;
}
```

**Purpose:**
- Prevents large memory allocations
- Enables incremental replay
- Allows backpressure checks between batches

**Configuration:**
- Batch size: 100 events
- Checked after each batch

### Outdated Cursor Handling

**Implementation (from SubscribeReposHandler.m):**

```objc
// Check if cursor is too far in the past
if (replayCursor < oldestAvailableCursor) {
    [self sendInfoEvent:kSubscribeReposInfoOutdatedCursor
                message:@"Requested cursor exceeded limit. Possibly missing events"
           toConnection:connection];
}
```

**Purpose:**
- Informs subscribers of data loss
- Prevents excessive historical queries
- Manages event retention

**Info Code:**
- `OutdatedCursor` — Cursor too old, events may be missing

## Backpressure Strategies

### Strategy 1: Immediate Disconnection

**When:** Queue limits exceeded

**Action:**
1. Send error frame with `ConsumerTooSlow` code
2. Detach connection from subscriber list
3. Close WebSocket connection
4. Log disconnection event

**Implementation:**

```objc
if (connection.pendingSendCount >= self.maxPendingSendsPerConnection ||
    connection.pendingSendBytes >= self.maxPendingBytesPerConnection) {
    
    PDS_LOG_SYNC_WARN(@"Disconnecting slow consumer: %lu pending sends, %lu pending bytes",
                      (unsigned long)connection.pendingSendCount,
                      (unsigned long)connection.pendingSendBytes);
    
    [self sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
                         message:@"connection output queue exceeded server limit"
                    toConnection:connection];
    
    [self detachConnection:connection];
    [connection closeWithCode:1008 reason:kSubscribeReposErrorConsumerTooSlow];
    
    return NO;
}
```

### Strategy 2: Replay Interruption

**When:** Backpressure detected during replay

**Action:**
1. Stop sending replay events
2. Return from replay function
3. Connection remains open for live events

**Implementation:**

```objc
// During replay
for (NSDictionary *event in events) {
    NSData *eventData = [self formatEvent:event];
    
    if (![self sendEventData:eventData 
        toConnectionWithBackpressureCheck:connection]) {
        // Backpressure detected, stop replay
        PDS_LOG_SYNC_WARN(@"Replay interrupted due to backpressure");
        return;
    }
}
```

### Strategy 3: Queue Monitoring

**When:** Continuously during operation

**Action:**
1. Monitor queue sizes
2. Log warnings at thresholds
3. Track slow consumer patterns

**Implementation:**

```objc
// Monitor queue size
if (connection.pendingSendBytes > self.maxPendingBytesPerConnection / 2) {
    PDS_LOG_SYNC_DEBUG(@"Subscriber queue at 50%% capacity: %lu bytes",
                       (unsigned long)connection.pendingSendBytes);
}

if (connection.pendingSendCount > self.maxPendingSendsPerConnection / 2) {
    PDS_LOG_SYNC_DEBUG(@"Subscriber queue at 50%% capacity: %lu messages",
                       (unsigned long)connection.pendingSendCount);
}
```

## Error Codes

### ConsumerTooSlow

**Code:** `ConsumerTooSlow`

**Meaning:** Subscriber's output queue exceeded server limits

**Response:**
```json
{
  "error": "ConsumerTooSlow",
  "message": "connection output queue exceeded server limit"
}
```

**WebSocket Close Code:** 1008 (Policy Violation)

**Client Action:**
- Reconnect with cursor
- Optimize event processing
- Reduce processing overhead

### OutdatedCursor (Info)

**Code:** `OutdatedCursor`

**Meaning:** Requested cursor is too old, events may be missing

**Response:**
```json
{
  "info": "OutdatedCursor",
  "message": "Requested cursor exceeded limit. Possibly missing events"
}
```

**Client Action:**
- Accept potential data loss
- Continue from available cursor
- Consider full repository sync

## Monitoring and Metrics

### Log Slow Consumers

```objc
PDS_LOG_SYNC_WARN(@"Disconnecting slow consumer: %lu pending sends, %lu pending bytes",
                  (unsigned long)connection.pendingSendCount,
                  (unsigned long)connection.pendingSendBytes);
```

### Track Disconnection Rates

```objc
PDS_LOG_SYNC_INFO(@"Subscriber disconnected due to backpressure. "
                  @"Total slow consumer disconnects: %lu",
                  (unsigned long)slowConsumerDisconnectCount);
```

### Monitor Queue Sizes

```objc
// Periodic queue size logging
dispatch_async(self.eventQueue, ^{
    for (WebSocketConnection *conn in self.attachedConnections) {
        if (conn.pendingSendBytes > threshold) {
            PDS_LOG_SYNC_DEBUG(@"Subscriber queue size: %lu bytes, %lu messages",
                               (unsigned long)conn.pendingSendBytes,
                               (unsigned long)conn.pendingSendCount);
        }
    }
});
```

### Track Replay Performance

```objc
NSTimeInterval replayStart = [NSDate timeIntervalSinceReferenceDate];

// Perform replay...

NSTimeInterval replayDuration = [NSDate timeIntervalSinceReferenceDate] - replayStart;
PDS_LOG_SYNC_INFO(@"Replay completed: %lu events in %.2fs (%.0f events/sec)",
                  (unsigned long)replayedCount,
                  replayDuration,
                  replayedCount / replayDuration);
```

## Configuration

### Compile-Time Constants

```objc
// SubscribeReposHandler.m
static const NSUInteger kSubscribeReposReplayBatchSize = 100;
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;
static const NSUInteger kSubscribeReposMaxPendingSendsDefault = 512;
static const NSUInteger kSubscribeReposMaxPendingBytesDefault = 16 * 1024 * 1024;

// WebSocketConnection.m
static const NSUInteger WS_MAX_PENDING_SEND_BYTES = 32 * 1024 * 1024;
```

### Runtime Configuration

```objc
// Adjust limits at runtime
handler.maxPendingSendsPerConnection = 1024;
handler.maxPendingBytesPerConnection = 32 * 1024 * 1024;
handler.maxReplayEventsPerConnection = 20000;
```

## Best Practices

### 1. Monitor Subscriber Health

Track metrics:
- Queue sizes per subscriber
- Disconnection rates
- Replay durations
- Event processing latency

### 2. Tune Limits Based on Usage

Adjust limits based on:
- Network conditions
- Event sizes
- Subscriber capabilities
- Server resources

### 3. Provide Clear Error Messages

Include helpful information:
- Error code
- Queue size at disconnection
- Recommended actions
- Reconnection guidance

### 4. Log Backpressure Events

Log important events:
- Slow consumer disconnections
- Queue size warnings
- Replay interruptions
- Cursor issues

### 5. Test Slow Consumer Scenarios

Test edge cases:
- Extremely slow subscribers
- Network interruptions
- Large event bursts
- Replay with backpressure

## Client-Side Considerations

### Handling ConsumerTooSlow

**Client Implementation:**

```objc
- (void)webSocketDidReceiveError:(NSError *)error {
    if ([error.userInfo[@"code"] isEqualToString:@"ConsumerTooSlow"]) {
        // Log the issue
        NSLog(@"Disconnected: processing too slow");
        
        // Optimize processing
        [self optimizeEventProcessing];
        
        // Reconnect with cursor
        [self reconnectWithCursor:self.lastProcessedCursor];
    }
}
```

### Optimizing Event Processing

**Strategies:**
- Process events asynchronously
- Batch database writes
- Use efficient data structures
- Minimize per-event overhead
- Consider event sampling

**Example:**

```objc
- (void)handleFirehoseEvent:(NSData *)eventData {
    // Queue event for async processing
    [self.eventQueue addObject:eventData];
    
    // Process in batches
    if (self.eventQueue.count >= batchSize) {
        [self processBatch:self.eventQueue];
        [self.eventQueue removeAllObjects];
    }
}
```

### Cursor Management

**Save cursor frequently:**

```objc
- (void)handleCommitEvent:(NSDictionary *)event {
    // Process event
    [self processCommit:event];
    
    // Save cursor
    NSNumber *seq = event[@"seq"];
    [self saveLastProcessedCursor:seq];
}
```

**Reconnect with cursor:**

```objc
- (void)reconnect {
    NSNumber *cursor = [self loadLastProcessedCursor];
    [self connectToFirehoseWithCursor:cursor];
}
```

## Performance Tuning

### Increasing Limits

For high-throughput scenarios:

```objc
// Increase limits for powerful subscribers
handler.maxPendingSendsPerConnection = 2048;
handler.maxPendingBytesPerConnection = 64 * 1024 * 1024;
```

**Considerations:**
- Available memory
- Network bandwidth
- Subscriber capabilities
- Event sizes

### Decreasing Limits

For resource-constrained environments:

```objc
// Decrease limits to protect server
handler.maxPendingSendsPerConnection = 256;
handler.maxPendingBytesPerConnection = 8 * 1024 * 1024;
```

**Considerations:**
- Server memory limits
- Number of subscribers
- Event burst patterns
- Network conditions

## Testing

### Test Slow Consumer Handling

```objc
- (void)testSlowConsumerDisconnection {
    // Create subscriber
    WebSocketConnection *slowSubscriber = [self createSubscriber];
    
    // Simulate slow processing by not reading from socket
    [slowSubscriber pauseReading];
    
    // Send events until queue fills
    for (NSInteger i = 0; i < maxPendingSends + 10; i++) {
        [handler broadcastEvent:[self createTestEvent]];
    }
    
    // Verify disconnection
    XCTAssertTrue(slowSubscriber.isClosed);
    XCTAssertEqualObjects(slowSubscriber.closeReason, @"ConsumerTooSlow");
}
```

### Test Replay Limits

```objc
- (void)testReplayEventLimit {
    // Create many historical events
    for (NSInteger i = 0; i < maxReplayEvents + 1000; i++) {
        [self createHistoricalEvent];
    }
    
    // Subscribe with old cursor
    WebSocketConnection *subscriber = [self subscribeWithCursor:0];
    
    // Wait for replay
    [self waitForReplayCompletion];
    
    // Verify event count limit
    XCTAssertLessThanOrEqual(subscriber.receivedEventCount, maxReplayEvents);
}
```

### Test Backpressure During Replay

```objc
- (void)testReplayBackpressure {
    // Create subscriber with small queue
    WebSocketConnection *subscriber = [self createSubscriberWithSmallQueue];
    
    // Start replay
    [handler replayEventsForSubscriber:subscriber fromCursor:0];
    
    // Verify replay stops when queue fills
    XCTAssertLessThan(subscriber.receivedEventCount, totalHistoricalEvents);
    XCTAssertTrue(subscriber.isConnected); // Still connected
}
```

## See Also

- [Backpressure](./backpressure.md) — Backpressure mechanisms
- [Commit Broadcasting](./commit-broadcasting.md) — Event distribution
- [WebSocket Server](./websocket-server.md) — WebSocket implementation
- [Rate Limiting](../04-network-layer/rate-limiting.md) — HTTP rate limiting
- [DoS Protection](../04-network-layer/dos-protection.md) — Attack mitigation
