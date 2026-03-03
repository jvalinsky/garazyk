# Firehose Rate Limiting

## Overview

Firehose rate limiting protects the PDS from being overwhelmed by WebSocket subscribers while ensuring fair resource distribution. Unlike HTTP request rate limiting, firehose rate limiting must handle:

- Long-lived connections (hours to days)
- High-volume event streams
- Variable subscriber consumption rates
- Backpressure from slow clients
- Connection resource limits

## Why Firehose Rate Limiting?

### Problems Without Rate Limiting

1. **Resource exhaustion** — Too many subscribers consume all memory/CPU
2. **Slow client impact** — One slow client can affect others
3. **Bandwidth saturation** — High-volume streams consume all bandwidth
4. **Connection pool exhaustion** — Too many WebSocket connections
5. **Unfair resource distribution** — Some clients monopolize resources

### Goals

1. **Protect server resources** — Prevent exhaustion
2. **Fair distribution** — All subscribers get reasonable service
3. **Graceful degradation** — Slow clients don't affect fast ones
4. **Prevent abuse** — Limit malicious or misconfigured clients
5. **Maintain reliability** — Keep firehose available for all

## Rate Limiting Dimensions

### 1. Connection Limits

Limit the number of concurrent WebSocket connections:

```objc
// In WebSocketServer.m - Connection limits
@interface WebSocketServer ()
@property (nonatomic, assign) NSUInteger maxConnections;
@property (nonatomic, strong) NSMutableSet *activeConnections;
@property (nonatomic, strong) NSMutableDictionary *connectionsPerIP;
@property (nonatomic, assign) NSUInteger maxConnectionsPerIP;
@end

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port path:(NSString *)path {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _path = [path copy];
        _maxConnections = 500;           // Max 500 total connections
        _maxConnectionsPerIP = 5;        // Max 5 connections per IP
        _activeConnections = [NSMutableSet set];
        _connectionsPerIP = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)shouldAcceptConnection:(NSString *)remoteIP {
    // 1. Check global limit
    if (self.activeConnections.count >= self.maxConnections) {
        PDS_LOG_WEBSOCKET_WARNING(@"Rejecting connection: max connections reached (%lu)",
                                  (unsigned long)self.maxConnections);
        return NO;
    }
    
    // 2. Check per-IP limit
    NSNumber *ipConnections = self.connectionsPerIP[remoteIP] ?: @0;
    if (ipConnections.integerValue >= self.maxConnectionsPerIP) {
        PDS_LOG_WEBSOCKET_WARNING(@"Rejecting connection from %@: per-IP limit reached", remoteIP);
        return NO;
    }
    
    return YES;
}

- (void)trackConnection:(WebSocketConnection *)connection remoteIP:(NSString *)remoteIP {
    [self.activeConnections addObject:connection];
    
    NSNumber *count = self.connectionsPerIP[remoteIP] ?: @0;
    self.connectionsPerIP[remoteIP] = @(count.integerValue + 1);
}

- (void)untrackConnection:(WebSocketConnection *)connection remoteIP:(NSString *)remoteIP {
    [self.activeConnections removeObject:connection];
    
    NSNumber *count = self.connectionsPerIP[remoteIP];
    if (count && count.integerValue > 0) {
        self.connectionsPerIP[remoteIP] = @(count.integerValue - 1);
    }
}
```

### 2. Event Rate Limits

Limit the rate at which events are sent to subscribers:

```objc
// In SubscribeReposHandler.m - Event rate limiting
@interface SubscribeReposHandler ()
@property (nonatomic, strong) NSMutableDictionary *subscriberRateLimits;
@end

- (BOOL)shouldSendEventToConnection:(WebSocketConnection *)connection {
    // 1. Get rate limit state for connection
    NSString *connectionID = [NSString stringWithFormat:@"%p", connection];
    NSMutableDictionary *state = self.subscriberRateLimits[connectionID];
    
    if (!state) {
        state = [@{
            @"events_sent": @0,
            @"window_start": [NSDate date],
            @"max_events_per_second": @1000  // 1000 events/second per subscriber
        } mutableCopy];
        self.subscriberRateLimits[connectionID] = state;
    }
    
    // 2. Check if window expired
    NSDate *windowStart = state[@"window_start"];
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:windowStart];
    
    if (elapsed >= 1.0) {
        // Reset window
        state[@"events_sent"] = @0;
        state[@"window_start"] = [NSDate date];
    }
    
    // 3. Check rate limit
    NSInteger eventsSent = [state[@"events_sent"] integerValue];
    NSInteger maxEvents = [state[@"max_events_per_second"] integerValue];
    
    if (eventsSent >= maxEvents) {
        PDS_LOG_WEBSOCKET_DEBUG(@"Rate limit exceeded for connection %@", connectionID);
        return NO;
    }
    
    // 4. Increment counter
    state[@"events_sent"] = @(eventsSent + 1);
    return YES;
}
```

### 3. Bandwidth Limits

Limit the bandwidth consumed by each subscriber:

```objc
// In WebSocketConnection.m - Bandwidth tracking
@interface WebSocketConnection ()
@property (nonatomic, assign) NSUInteger bytesSent;
@property (nonatomic, strong) NSDate *bandwidthWindowStart;
@property (nonatomic, assign) NSUInteger maxBytesPerSecond;
@end

- (BOOL)canSendData:(NSData *)data {
    // 1. Initialize bandwidth tracking
    if (!self.bandwidthWindowStart) {
        self.bandwidthWindowStart = [NSDate date];
        self.bytesSent = 0;
        self.maxBytesPerSecond = 1 * 1024 * 1024;  // 1 MB/s per connection
    }
    
    // 2. Check if window expired
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.bandwidthWindowStart];
    if (elapsed >= 1.0) {
        // Reset window
        self.bytesSent = 0;
        self.bandwidthWindowStart = [NSDate date];
    }
    
    // 3. Check bandwidth limit
    if (self.bytesSent + data.length > self.maxBytesPerSecond) {
        PDS_LOG_WEBSOCKET_DEBUG(@"Bandwidth limit exceeded: %lu bytes sent in window",
                                (unsigned long)self.bytesSent);
        return NO;
    }
    
    // 4. Update counter
    self.bytesSent += data.length;
    return YES;
}
```

### 4. Buffer Limits

Limit the amount of buffered data per connection:

```objc
// In WebSocketConnection.m - Buffer management
- (void)sendFrame:(NSData *)frame {
  dispatch_async(self.writeQueue, ^{
    if (self.state == WebSocketConnectionStateClosing ||
        self.state == WebSocketConnectionStateClosed) {
      return;
    }
    
    // Check buffer limit
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

**Source:** `ATProtoPDS/Sources/Sync/WebSocketConnection.m` (lines 280-300)

## Backpressure Strategies

### Strategy 1: Pause and Resume

Pause event delivery when buffer fills, resume when it drains:

```objc
// In SubscribeReposHandler.m - Backpressure handling
- (void)broadcastCommit:(NSDictionary *)commit {
    NSArray *connections = [self.attachedConnections allObjects];
    
    for (WebSocketConnection *connection in connections) {
        // 1. Check buffer level
        NSUInteger pendingBytes = [connection pendingSendBytes];
        
        if (pendingBytes > WS_BACKPRESSURE_THRESHOLD) {
            // 2. Apply backpressure
            [self pauseEventsForConnection:connection];
            
            // 3. Schedule resume check
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                          dispatch_get_main_queue(), ^{
                [self checkResumeForConnection:connection];
            });
            
            continue;
        }
        
        // 4. Send event
        [self sendCommitToConnection:connection commit:commit];
    }
}

- (void)pauseEventsForConnection:(WebSocketConnection *)connection {
    NSString *connectionID = [NSString stringWithFormat:@"%p", connection];
    self.pausedConnections[connectionID] = @YES;
    
    PDS_LOG_WEBSOCKET_DEBUG(@"Paused events for connection %@", connectionID);
}

- (void)checkResumeForConnection:(WebSocketConnection *)connection {
    NSUInteger pendingBytes = [connection pendingSendBytes];
    
    if (pendingBytes < WS_BACKPRESSURE_RELEASE_THRESHOLD) {
        NSString *connectionID = [NSString stringWithFormat:@"%p", connection];
        [self.pausedConnections removeObjectForKey:connectionID];
        
        PDS_LOG_WEBSOCKET_DEBUG(@"Resumed events for connection %@", connectionID);
    } else {
        // Check again later
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                      dispatch_get_main_queue(), ^{
            [self checkResumeForConnection:connection];
        });
    }
}
```

### Strategy 2: Event Dropping

Drop events for slow clients to prevent buffer overflow:

```objc
// In SubscribeReposHandler.m - Event dropping
- (void)broadcastCommitWithDropping:(NSDictionary *)commit {
    NSArray *connections = [self.attachedConnections allObjects];
    
    for (WebSocketConnection *connection in connections) {
        NSUInteger pendingBytes = [connection pendingSendBytes];
        
        if (pendingBytes > WS_MAX_PENDING_SEND_BYTES * 0.9) {
            // 1. Buffer nearly full - drop event
            [self recordDroppedEvent:connection];
            
            PDS_LOG_WEBSOCKET_WARNING(@"Dropped event for slow connection %p", connection);
            continue;
        }
        
        // 2. Send event
        [self sendCommitToConnection:connection commit:commit];
    }
}

- (void)recordDroppedEvent:(WebSocketConnection *)connection {
    NSString *connectionID = [NSString stringWithFormat:@"%p", connection];
    NSNumber *dropped = self.droppedEvents[connectionID] ?: @0;
    self.droppedEvents[connectionID] = @(dropped.integerValue + 1);
    
    // Send info message periodically
    if (dropped.integerValue % 100 == 0) {
        [self sendInfoMessage:connection 
                      message:[NSString stringWithFormat:@"Dropped %ld events due to slow consumption", 
                              (long)dropped.integerValue]];
    }
}
```

### Strategy 3: Connection Termination

Close connections that consistently can't keep up:

```objc
// In SubscribeReposHandler.m - Slow client detection
- (void)monitorSlowClients {
    NSArray *connections = [self.attachedConnections allObjects];
    
    for (WebSocketConnection *connection in connections) {
        NSString *connectionID = [NSString stringWithFormat:@"%p", connection];
        
        // 1. Check dropped event count
        NSNumber *dropped = self.droppedEvents[connectionID] ?: @0;
        if (dropped.integerValue > 1000) {
            // Too many dropped events - close connection
            PDS_LOG_WEBSOCKET_WARNING(@"Closing slow connection %@ (dropped %ld events)",
                                     connectionID, (long)dropped.integerValue);
            
            [connection closeWithCode:1008 reason:@"Client too slow"];
            continue;
        }
        
        // 2. Check buffer level
        NSUInteger pendingBytes = [connection pendingSendBytes];
        if (pendingBytes > WS_MAX_PENDING_SEND_BYTES * 0.95) {
            // Buffer nearly full for too long
            NSDate *pausedAt = self.pausedTimestamps[connectionID];
            if (pausedAt && [[NSDate date] timeIntervalSinceDate:pausedAt] > 60) {
                PDS_LOG_WEBSOCKET_WARNING(@"Closing stalled connection %@", connectionID);
                [connection closeWithCode:1008 reason:@"Connection stalled"];
            }
        }
    }
}
```

### Strategy 4: Adaptive Rate Adjustment

Dynamically adjust event rate based on client performance:

```objc
// In SubscribeReposHandler.m - Adaptive rate adjustment
@interface SubscribeReposHandler ()
@property (nonatomic, strong) NSMutableDictionary *connectionRates;
@end

- (NSTimeInterval)getDelayForConnection:(WebSocketConnection *)connection {
    NSString *connectionID = [NSString stringWithFormat:@"%p", connection];
    NSNumber *rate = self.connectionRates[connectionID];
    
    if (!rate) {
        // Default: no delay (full speed)
        rate = @1.0;
        self.connectionRates[connectionID] = rate;
    }
    
    // Calculate delay based on rate
    // rate = 1.0 → no delay
    // rate = 0.5 → 50% slower (delay between events)
    // rate = 0.1 → 90% slower
    
    NSTimeInterval baseDelay = 0.001;  // 1ms base
    return baseDelay / rate.doubleValue;
}

- (void)adjustRateForConnection:(WebSocketConnection *)connection {
    NSString *connectionID = [NSString stringWithFormat:@"%p", connection];
    NSNumber *currentRate = self.connectionRates[connectionID] ?: @1.0;
    
    NSUInteger pendingBytes = [connection pendingSendBytes];
    double fillPercentage = (double)pendingBytes / WS_MAX_PENDING_SEND_BYTES;
    
    double newRate;
    if (fillPercentage > 0.8) {
        // Buffer filling - slow down
        newRate = currentRate.doubleValue * 0.8;
    } else if (fillPercentage < 0.3) {
        // Buffer draining - speed up
        newRate = MIN(1.0, currentRate.doubleValue * 1.2);
    } else {
        // Stable - no change
        newRate = currentRate.doubleValue;
    }
    
    self.connectionRates[connectionID] = @(newRate);
}

- (void)sendCommitWithAdaptiveRate:(NSDictionary *)commit 
                       toConnection:(WebSocketConnection *)connection {
    // 1. Get delay for this connection
    NSTimeInterval delay = [self getDelayForConnection:connection];
    
    // 2. Schedule send with delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC),
                  dispatch_get_main_queue(), ^{
        [self sendCommitToConnection:connection commit:commit];
        
        // 3. Adjust rate for next event
        [self adjustRateForConnection:connection];
    });
}
```

## Subscriber Prioritization

### Priority Levels

```objc
// In SubscribeReposHandler.m - Subscriber priorities
typedef NS_ENUM(NSInteger, SubscriberPriority) {
    SubscriberPriorityLow = 0,
    SubscriberPriorityNormal = 1,
    SubscriberPriorityHigh = 2,
    SubscriberPriorityCritical = 3
};

@interface SubscriptionContext : NSObject
@property (nonatomic, strong) WebSocketConnection *connection;
@property (nonatomic, assign) SubscriberPriority priority;
@property (nonatomic, copy) NSString *did;
@end

- (SubscriberPriority)getPriorityForDID:(NSString *)did {
    // 1. Check if official relay
    if ([self isOfficialRelay:did]) {
        return SubscriberPriorityCritical;
    }
    
    // 2. Check if trusted subscriber
    if ([self isTrustedSubscriber:did]) {
        return SubscriberPriorityHigh;
    }
    
    // 3. Default priority
    return SubscriberPriorityNormal;
}
```

### Priority-Based Broadcasting

```objc
// In SubscribeReposHandler.m - Priority-aware broadcasting
- (void)broadcastCommitWithPriority:(NSDictionary *)commit {
    // 1. Sort connections by priority
    NSArray *sortedConnections = [self.subscriptions sortedArrayUsingComparator:^NSComparisonResult(SubscriptionContext *ctx1, SubscriptionContext *ctx2) {
        if (ctx1.priority > ctx2.priority) {
            return NSOrderedAscending;
        } else if (ctx1.priority < ctx2.priority) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    
    // 2. Send to high-priority subscribers first
    for (SubscriptionContext *context in sortedConnections) {
        if (context.priority >= SubscriberPriorityHigh) {
            [self sendCommitToConnection:context.connection commit:commit];
        }
    }
    
    // 3. Send to normal/low priority subscribers
    for (SubscriptionContext *context in sortedConnections) {
        if (context.priority < SubscriberPriorityHigh) {
            // Apply rate limiting for lower priority
            if ([self shouldSendEventToConnection:context.connection]) {
                [self sendCommitToConnection:context.connection commit:commit];
            }
        }
    }
}
```

## Monitoring and Metrics

### Subscriber Metrics

```objc
// In SubscribeReposHandler.m - Metrics collection
@interface SubscriberMetrics : NSObject
@property (nonatomic, assign) NSUInteger totalSubscribers;
@property (nonatomic, assign) NSUInteger activeSubscribers;
@property (nonatomic, assign) NSUInteger pausedSubscribers;
@property (nonatomic, assign) NSUInteger slowSubscribers;
@property (nonatomic, assign) NSUInteger eventsDelivered;
@property (nonatomic, assign) NSUInteger eventsDropped;
@property (nonatomic, assign) NSUInteger bytesDelivered;
@end

- (void)collectMetrics {
    self.metrics.totalSubscribers = self.attachedConnections.count;
    self.metrics.activeSubscribers = 0;
    self.metrics.pausedSubscribers = 0;
    self.metrics.slowSubscribers = 0;
    
    for (WebSocketConnection *connection in self.attachedConnections) {
        NSString *connectionID = [NSString stringWithFormat:@"%p", connection];
        
        // Check if paused
        if (self.pausedConnections[connectionID]) {
            self.metrics.pausedSubscribers++;
        } else {
            self.metrics.activeSubscribers++;
        }
        
        // Check if slow
        NSUInteger pendingBytes = [connection pendingSendBytes];
        if (pendingBytes > WS_BACKPRESSURE_THRESHOLD) {
            self.metrics.slowSubscribers++;
        }
    }
}

- (NSDictionary *)getMetrics {
    return @{
        @"total_subscribers": @(self.metrics.totalSubscribers),
        @"active_subscribers": @(self.metrics.activeSubscribers),
        @"paused_subscribers": @(self.metrics.pausedSubscribers),
        @"slow_subscribers": @(self.metrics.slowSubscribers),
        @"events_delivered": @(self.metrics.eventsDelivered),
        @"events_dropped": @(self.metrics.eventsDropped),
        @"bytes_delivered": @(self.metrics.bytesDelivered),
        @"drop_rate": @((double)self.metrics.eventsDropped / MAX(1, self.metrics.eventsDelivered))
    };
}
```

## Configuration

### Recommended Settings

```objc
// In SubscribeReposHandler.m - Configuration
static const NSUInteger WS_MAX_CONNECTIONS = 500;
static const NSUInteger WS_MAX_CONNECTIONS_PER_IP = 5;
static const NSUInteger WS_MAX_EVENTS_PER_SECOND = 1000;
static const NSUInteger WS_MAX_BYTES_PER_SECOND = 1 * 1024 * 1024;  // 1 MB/s
static const NSUInteger WS_MAX_PENDING_SEND_BYTES = 10 * 1024 * 1024;  // 10 MB
static const NSUInteger WS_BACKPRESSURE_THRESHOLD = 7 * 1024 * 1024;  // 7 MB (70%)
static const NSUInteger WS_BACKPRESSURE_RELEASE_THRESHOLD = 3 * 1024 * 1024;  // 3 MB (30%)
static const NSUInteger WS_MAX_DROPPED_EVENTS = 1000;
static const NSTimeInterval WS_STALL_TIMEOUT = 60.0;  // 60 seconds
```

### Configuration File

```json
{
  "firehose": {
    "max_connections": 500,
    "max_connections_per_ip": 5,
    "max_events_per_second": 1000,
    "max_bytes_per_second": 1048576,
    "max_pending_send_bytes": 10485760,
    "backpressure_threshold": 7340032,
    "backpressure_release_threshold": 3145728,
    "max_dropped_events": 1000,
    "stall_timeout": 60,
    "enable_adaptive_rate": true,
    "enable_event_dropping": false,
    "enable_priority": true
  }
}
```

## Best Practices

1. **Set conservative limits** — Protect server resources
2. **Monitor subscriber health** — Track slow/stalled connections
3. **Apply backpressure early** — Don't wait for buffer overflow
4. **Prioritize critical subscribers** — Relays get priority
5. **Drop events gracefully** — Inform clients of drops
6. **Close stalled connections** — Don't let them linger
7. **Log rate limit events** — Track patterns
8. **Test under load** — Verify limits work
9. **Provide feedback** — Tell clients why they're limited
10. **Review regularly** — Adjust based on usage

## Next Steps

- **[Backpressure](./backpressure)** — Backpressure mechanisms
- **[WebSocket Server](./websocket-server)** — WebSocket implementation
- **[Commit Broadcasting](./commit-broadcasting)** — Event broadcasting
- **[Request Throttling](../04-network-layer/request-throttling)** — HTTP throttling
