# Firehose Overview

## What is the Firehose?

The firehose is a real-time event stream that broadcasts all commits to the PDS. It allows:
- **Real-time sync** — Clients receive updates as they happen
- **Repository monitoring** — Track changes to specific repositories
- **Event processing** — Build applications on top of events

## Firehose Architecture

### WebSocket Connection

The firehose is served via WebSocket upgrade on the HTTP port:

```
Client connects to: ws://pds.example.com/xrpc/com.atproto.sync.subscribeRepos
    ↓
HttpServer upgrades connection to WebSocket
    ↓
SubscribeReposHandler manages connection
    ↓
CommitBroadcaster sends events
    ↓
Client receives commit events
```

### Event Flow

```
Record is created/updated
    ↓
PDSRecordService.createRecord
    ↓
PDSRepositoryService.createCommit
    ↓
CommitBroadcaster.broadcastCommit
    ↓
Send to all connected WebSocket clients
```

## Subscribing to the Firehose

### WebSocket Subscription

```objc
// Client-side example
NSURL *url = [NSURL URLWithString:@"ws://pds.example.com/xrpc/com.atproto.sync.subscribeRepos"];
NSURLRequest *request = [NSURLRequest requestWithURL:url];

// Connect to WebSocket
// Receive commit events
```

### Commit Event Format

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
  "time": "2024-01-01T00:00:00Z"
}
```

## Implementing the Firehose

### WebSocket Handler

The SubscribeReposHandler manages WebSocket connections and sends initial repository state:

```objc
// In SubscribeReposHandler.m - Accepting upgraded connections
- (void)acceptUpgradedConnection:(id<PDSNetworkConnection>)connection
                         request:(HttpRequest *)request {
  [self ensureSequenceInitialized];

  WebSocketConnection *webSocketConnection =
      [[WebSocketConnection alloc] initWithConnection:connection];
  if (request.remoteAddress.length > 0) {
    webSocketConnection.remoteAddress = request.remoteAddress;
  }
  webSocketConnection.delegate = self;
  @synchronized(self.attachedConnections) {
    [self.attachedConnections addObject:webSocketConnection];
  }

  if ([self.delegate respondsToSelector:@selector
                     (subscribeReposHandler:didAcceptConnection:)]) {
    [self.delegate subscribeReposHandler:self
                     didAcceptConnection:webSocketConnection];
  }

  [webSocketConnection startOnExistingTransport];
  [self sendInitialRepositoryStateToConnection:webSocketConnection
                                        cursor:[request
                                                   queryParamForKey:@"cursor"]];
}
```

**Source:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` (lines 150-170)

### Commit Broadcasting

```objc
// In CommitBroadcaster.m
- (void)broadcastCommit:(NSDictionary *)commit 
                   did:(NSString *)did
                   seq:(NSInteger)seq {
    
    // 1. Create event
    NSDictionary *event = @{
        @"t": @"#commit",
        @"commit": commit,
        @"seq": @(seq),
        @"time": [NSDate date]
    };
    
    // 2. Encode as JSON
    NSData *json = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    
    // 3. Send to all connected clients
    @synchronized(self.connections) {
        for (WebSocketConnection *connection in self.connections) {
            [connection sendMessage:json];
        }
    }
}
```

## Backpressure Handling

### Flow Control

When clients can't keep up with events:

```objc
// In WebSocketConnection.m
- (void)sendMessage:(NSData *)message {
    // 1. Check if send buffer is full
    if (self.sendBuffer.length > MAX_BUFFER_SIZE) {
        // 2. Apply backpressure
        [self pauseReceiving];
        
        // 3. Wait for buffer to drain
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 
                      dispatch_get_main_queue(), ^{
            [self resumeReceiving];
        });
        
        return;
    }
    
    // 4. Send message
    [self.socket sendData:message];
}
```

## Cursor Management

### Sequence Numbers

Each commit has a sequence number for tracking position:

```objc
// In PDSRepositoryService.m
- (void)createCommitWithRootCID:(NSString *)rootCID
                            did:(NSString *)did
                     completion:(void (^)(NSString *commitCID, NSError *error))completion {
    
    // 1. Get next sequence number
    NSInteger seq = [self.serviceDatabases getNextSequenceNumber];
    
    // 2. Create commit
    NSDictionary *commit = @{
        @"root": rootCID,
        @"prev": [self getHeadCommitCID:did] ?: [NSNull null],
        @"timestamp": [NSDate date],
        @"did": did
    };
    
    // 3. Store commit with sequence number
    [self.serviceDatabases storeCommit:commit seq:seq];
    
    // 4. Broadcast to firehose
    [self.broadcaster broadcastCommit:commit did:did seq:seq];
    
    completion([CID calculateCIDForData:[ATProtoCBORSerialization encodeObject:commit error:nil]], nil);
}
```

### Cursor Queries

```objc
// In SubscribeReposHandler.m
- (void)sendHistoricalEvents:(NSString *)cursor 
                toConnection:(WebSocketConnection *)connection {
    
    // 1. Parse cursor as sequence number
    NSInteger startSeq = [cursor integerValue];
    
    // 2. Query commits from sequencer
    NSArray *commits = [self.serviceDatabases getCommitsAfterSeq:startSeq];
    
    // 3. Send each commit
    for (NSDictionary *commit in commits) {
        NSDictionary *event = @{
            @"t": @"#commit",
            @"commit": commit[@"commit"],
            @"seq": commit[@"seq"],
            @"time": commit[@"timestamp"]
        };
        
        NSData *json = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
        [connection sendMessage:json];
    }
}
```

## Error Handling

### Connection Errors

```objc
// In SubscribeReposHandler.m
- (void)handleConnectionError:(NSError *)error 
                   connection:(WebSocketConnection *)connection {
    
    // 1. Log error
    NSLog(@"WebSocket error: %@", error);
    
    // 2. Send error event
    NSDictionary *errorEvent = @{
        @"t": @"#error",
        @"error": error.localizedDescription
    };
    
    NSData *json = [NSJSONSerialization dataWithJSONObject:errorEvent options:0 error:nil];
    [connection sendMessage:json];
    
    // 3. Close connection
    [connection close];
}
```

## Performance Optimization

### Event Batching

```objc
// Batch events for efficiency
- (void)broadcastCommitsBatch:(NSArray *)commits {
    // 1. Collect events
    NSMutableArray *events = [NSMutableArray array];
    for (NSDictionary *commit in commits) {
        [events addObject:@{
            @"t": @"#commit",
            @"commit": commit
        }];
    }
    
    // 2. Send batch
    NSData *json = [NSJSONSerialization dataWithJSONObject:events options:0 error:nil];
    
    @synchronized(self.connections) {
        for (WebSocketConnection *connection in self.connections) {
            [connection sendMessage:json];
        }
    }
}
```

### Connection Pooling

```objc
// Reuse connections
- (void)registerConnection:(WebSocketConnection *)connection {
    @synchronized(self.connections) {
        [self.connections addObject:connection];
    }
    
    // Monitor connection health
    [self startHealthCheckForConnection:connection];
}
```

## Monitoring

### Metrics

```objc
// Track firehose metrics
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
[self recordMetric:@"commits_per_second" value:@(commitCount)];
[self recordMetric:@"connected_clients" value:@(self.connections.count)];
[self recordMetric:@"average_latency_ms" value:@(latency)];
```

## Best Practices

1. **Handle backpressure** — Don't overwhelm slow clients
2. **Use cursors** — Allow resuming from last position
3. **Batch events** — Improve throughput
4. **Monitor connections** — Track health
5. **Implement reconnection** — Handle network failures
6. **Validate events** — Verify signatures before processing

## Next Steps

- **[WebSocket Server](./websocket-server)** — WebSocket implementation
- **[Commit Broadcasting](./commit-broadcasting)** — Broadcasting details
- **[Backpressure](./backpressure)** — Flow control
