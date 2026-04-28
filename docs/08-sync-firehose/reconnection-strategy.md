---
title: Reconnection Strategy and State Recovery
---

# Reconnection Strategy and State Recovery

## Overview

The firehose implements reconnection strategies so subscribers recover from:
- Network interruptions
- Server restarts
- Client crashes
- Timeout conditions
- Backpressure-induced disconnections

## Connection Lifecycle

### Initial Connection

When a client first connects to the firehose:

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

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 150-175)

### Connection States

WebSocket connections progress through several states:

```objc
// In WebSocketConnection.h
typedef NS_ENUM(NSInteger, WebSocketConnectionState) {
    WebSocketConnectionStateConnecting,
    WebSocketConnectionStateConnected,
    WebSocketConnectionStateClosing,
    WebSocketConnectionStateClosed
};
```

## Cursor-Based Reconnection

### Cursor Parameter

Clients reconnect by providing a cursor (sequence number) in the query string:

```

ws://pds.example.com/xrpc/com.atproto.sync.subscribeRepos?cursor=12345
```

### Parsing Cursor

The server parses and validates the cursor:

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

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 850-880)

### Cursor Validation

The server validates cursors against several conditions:

```objc
// In SubscribeReposHandler.m - Initial state sending with cursor validation
- (void)sendInitialRepositoryStateToConnection:(WebSocketConnection *)connection
                                        cursor:(nullable NSString *)cursor {
  PDS_LOG_SYNC_INFO(@"New connection from %@ (requested path: %@)", 
                    connection.remoteAddress, connection.path);
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

  dispatch_async(self.eventQueue, ^{
    PDS_LOG_SYNC_INFO(@"Async worker started: processing initial state for connection %@", 
                      connection.remoteAddress);
    [self ensureSequenceInitialized];

    if (hasCursor && !cursorValid) {
      [self sendErrorFrameWithCode:kSubscribeReposErrorInvalidCursor
                           message:@"cursor must be a non-negative integer"
                      toConnection:connection];
      [self detachConnection:connection];
      [connection closeWithCode:1008 reason:kSubscribeReposErrorInvalidCursor];
      return;
    }

    // Check for future cursor
    if (hasCursor && parsedCursor > self.sequenceNumber) {
      [self
          sendErrorFrameWithCode:kSubscribeReposErrorFutureCursor
                         message:@"requested cursor is ahead of server sequence"
                    toConnection:connection];
      [self detachConnection:connection];
      [connection closeWithCode:1008 reason:kSubscribeReposErrorFutureCursor];
      return;
    }

    // Handle cursor replay...
  });
}
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 650-720)

## State Recovery Strategies

### No Cursor (Fresh Connection)

When no cursor is provided, the server sends the current repository state:

```objc
// In SubscribeReposHandler.m - Initial repository state replay
if (!hasCursor) {
  PDS_LOG_SYNC_INFO(@"No cursor provided; replaying existing repository state before live updates.");
  
  if (!self.userDatabasePool) {
    PDS_LOG_SYNC_ERROR(@"User database pool not available for initial replay");
  } else {
    NSError *error = nil;
    NSArray<PDSDatabaseRepo *> *repos = [self.userDatabasePool getAllReposWithError:&error];
    if (error) {
      PDS_LOG_SYNC_ERROR(@"Failed to fetch repositories for initial replay: %@", error);
    } else {
      PDS_LOG_SYNC_DEBUG(@"Found %lu repos to replay", (unsigned long)repos.count);
      for (PDSDatabaseRepo *repo in repos) {
        PDS_LOG_SYNC_DEBUG(@"Replaying repository %@", repo.ownerDid);
        
        NSError *repoError = nil;
        PDSActorStore *store = [self.userDatabasePool storeForDid:repo.ownerDid error:&repoError];
        if (!store || repoError) {
          PDS_LOG_SYNC_WARN(@"Could not get actor store for %@ - skipping: %@", 
                           repo.ownerDid, repoError);
          continue;
        }
        
        NSString *rev = [store getRepoRevisionForDid:repo.ownerDid error:&repoError];
        if (!rev || rev.length == 0) {
          PDS_LOG_SYNC_WARN(@"Could not get revision for %@ - skipping", repo.ownerDid);
          continue;
        }
        
        // Build and send commit event for each repository...
      }
    }
  }
}
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 720-760)

### With Cursor (Resumption)

When a cursor is provided, the server replays events from that point:

```objc
// In SubscribeReposHandler.m - Cursor-based resumption
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

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 760-790)

### Outdated Cursor Handling

If a cursor is too old (beyond the replay window), the server adjusts it:

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

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 900-930)

## Replay Window Management

### Maximum Replay Events

The server limits how many events can be replayed:

```objc
// In SubscribeReposHandler.m - Constants
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;

// In initialization
_maxReplayEventsPerConnection = kSubscribeReposMaxReplayEventsDefault;
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 30, 110)

### Oldest Persisted Sequence

The server tracks the oldest available event:

```objc
// In SubscribeReposHandler.m - Finding oldest persisted sequence
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
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 880-900)

## Error Handling

### Invalid Cursor

If the cursor is malformed:

```objc
// In SubscribeReposHandler.m
if (hasCursor && !cursorValid) {
  [self sendErrorFrameWithCode:kSubscribeReposErrorInvalidCursor
                       message:@"cursor must be a non-negative integer"
                  toConnection:connection];
  [self detachConnection:connection];
  [connection closeWithCode:1008 reason:kSubscribeReposErrorInvalidCursor];
  return;
}
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 700-710)

### Future Cursor

If the cursor is ahead of the server:

```objc
// In SubscribeReposHandler.m
if (hasCursor && parsedCursor > self.sequenceNumber) {
  [self
      sendErrorFrameWithCode:kSubscribeReposErrorFutureCursor
                     message:@"requested cursor is ahead of server sequence"
                toConnection:connection];
  [self detachConnection:connection];
  [connection closeWithCode:1008 reason:kSubscribeReposErrorFutureCursor];
  return;
}
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 710-720)

### Sending Error Frames

Error frames are sent using the XRPC streaming protocol:

```objc
// In SubscribeReposHandler.m - Sending error frames
- (void)sendErrorFrameWithCode:(NSString *)code
                       message:(NSString *)message
                  toConnection:(WebSocketConnection *)connection {
  FirehoseErrorEvent *event =
      [FirehoseErrorEvent eventWithError:code message:message];
  NSError *error = nil;
  NSData *eventData = [self.eventFormatter encodeErrorEvent:event error:&error];
  if (eventData) {
    [connection sendMessage:eventData];
  } else {
    PDS_LOG_SYNC_ERROR(@"Failed to encode error event (%@): %@", code, error);
  }
}
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 950-965)

## Info Events

### Outdated Cursor Notification

When a cursor is adjusted, the server sends an info event:

```objc
// In SubscribeReposHandler.m - Sending info events
- (void)sendInfoEvent:(NSString *)kind
              message:(NSString *)message
         toConnection:(WebSocketConnection *)connection {
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
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 830-850)

## Connection Cleanup

### Detaching Connections

When a connection closes or fails, it's removed from the active set:

```objc
// In SubscribeReposHandler.m - Detaching connections
- (void)detachConnection:(WebSocketConnection *)connection {
  @synchronized(self.attachedConnections) {
    [self.attachedConnections removeObject:connection];
  }
}
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 965-970)

### Connection Delegate Methods

The handler implements WebSocket delegate methods for lifecycle events:

```objc
// In SubscribeReposHandler.m - Connection lifecycle
- (void)webSocketConnection:(WebSocketConnection *)connection
           didCloseWithCode:(NSInteger)code
                     reason:(NSString *)reason {
  PDS_LOG_SYNC_INFO(
      @"[%@] Main-port WebSocket connection closed (code=%ld, reason=%@)",
      connection.remoteAddress, (long)code, reason ?: @"");
  [self detachConnection:connection];
  if ([self.delegate respondsToSelector:@selector
                     (subscribeReposHandler:didCloseConnection:)]) {
    [self.delegate subscribeReposHandler:self didCloseConnection:connection];
  }
}

- (void)webSocketConnection:(WebSocketConnection *)connection
           didFailWithError:(NSError *)error {
  PDS_LOG_SYNC_ERROR(@"[%@] Main-port WebSocket connection failed: %@",
                     connection.remoteAddress, error);
  [self detachConnection:connection];
  if ([self.delegate respondsToSelector:@selector
                     (subscribeReposHandler:didCloseConnection:)]) {
    [self.delegate subscribeReposHandler:self didCloseConnection:connection];
  }
}
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 260-285)

## Client-Side Reconnection

### Tracking Last Sequence

Clients should track the last received sequence number:

```objc
// Client-side example (conceptual)
@interface FirehoseClient : NSObject
@property (nonatomic, assign) NSUInteger lastSeq;
@property (nonatomic, strong) NSTimer *reconnectTimer;
@end

@implementation FirehoseClient

- (void)handleEvent:(NSDictionary *)event {
    NSInteger seq = [event[@"seq"] integerValue];
    self.lastSeq = seq;
    
    // Process event...
}

- (void)connectionDidClose {
    // Reconnect with cursor
    [self reconnectWithCursor:@(self.lastSeq).stringValue];
}

@end
```

### Exponential Backoff

Clients should implement exponential backoff for reconnection:

```objc
// Client-side example (conceptual)
- (void)reconnectWithBackoff {
    if (self.reconnectAttempts == 0) {
        self.reconnectDelay = 1.0;  // Start with 1 second
    } else {
        self.reconnectDelay = MIN(self.reconnectDelay * 2, 60.0);  // Max 60 seconds
    }
    
    self.reconnectAttempts++;
    
    NSLog(@"Reconnecting in %.1f seconds (attempt %lu)", 
          self.reconnectDelay, (unsigned long)self.reconnectAttempts);
    
    self.reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:self.reconnectDelay
                                                           target:self
                                                         selector:@selector(attemptReconnect)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)attemptReconnect {
    [self connectWithCursor:@(self.lastSeq).stringValue];
}

- (void)connectionDidSucceed {
    // Reset backoff on successful connection
    self.reconnectAttempts = 0;
    self.reconnectDelay = 1.0;
}
```

## Best Practices

1. **Always provide a cursor on reconnection** — Resume from last received sequence
2. **Track sequence numbers persistently** — Survive client restarts
3. **Implement exponential backoff** — Avoid overwhelming the server
4. **Handle outdated cursor info events** — Expect possible gaps
5. **Validate cursor format** — Ensure it's a non-negative integer
6. **Monitor connection health** — Detect stalls and reconnect proactively
7. **Log reconnection attempts** — Aid debugging
8. **Handle error frames gracefully** — Close and retry with valid cursor

## Configuration

### Replay Window Settings

```objc
// In SubscribeReposHandler.m
static const NSUInteger kSubscribeReposMaxReplayEventsDefault = 10000;

// Configurable per instance
@property (nonatomic, assign) NSUInteger maxReplayEventsPerConnection;
```

### Error Codes

```objc
// In SubscribeReposHandler.m
static NSString *const kSubscribeReposErrorFutureCursor = @"FutureCursor";
static NSString *const kSubscribeReposErrorConsumerTooSlow = @"ConsumerTooSlow";
static NSString *const kSubscribeReposErrorInvalidCursor = @"InvalidCursor";
static NSString *const kSubscribeReposInfoOutdatedCursor = @"OutdatedCursor";
```

**Source:** `Garazyk/Sources/Sync/SubscribeReposHandler.m` (lines 30-35)

## See Also

- [Event Ordering](event-ordering) — Sequence number guarantees
- [Event Replay](event-replay) — Cursor-based catch-up mechanism
- [Reliability Guarantees](reliability-guarantees) — Delivery semantics
- [Backpressure](backpressure) — Flow control
- [Firehose Overview](firehose-overview) — Architecture overview

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

