---
title: Relay Service
---

# Relay Service

## Overview

The `PDSRelayService` notifies external relays of repository updates. It enables the PDS to participate in the ATProto network by broadcasting changes to relay servers, which aggregate and distribute data across the network.

## Responsibilities

- Listen for repository change notifications
- Notify configured relay servers
- Handle relay communication failures
- Manage relay connection state
- Implement retry logic
- Track relay notification status

## Architecture

```

┌──────────────────────────────────────────┐
│   Repository Change Events               │
│  (PDSRecordDidChangeNotification)        │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   PDSRelayService                        │
│  - start()                               │
│  - stop()                                │
│  - notifyRelay()                         │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────────┐  ┌──▼──────────────┐
│ HTTP Client      │  │ Retry Queue     │
│ (Relay Requests) │  │ (Failed Notifs) │
└──────────────────┘  └──────────────────┘
        │
        └────────┬────────┘
                 │
        ┌────────▼────────────┐
        │ External Relays     │
        │ (e.g., bsky.network)│
        └─────────────────────┘
```

## Key Methods

### Initialize Service

```objc
- (instancetype)initWithRelays:(NSArray<NSString *> *)relays
                      hostname:(NSString *)hostname;
```

Initializes the relay service with a list of relay servers.

**Parameters:**
- `relays`: Array of relay URLs (e.g., @[@"https://bsky.network"])
- `hostname`: Public hostname of this PDS (e.g., "pds.example.com")

**Example:**
```objc
NSArray *relays = @[
    @"https://bsky.network",
    @"https://relay.example.com"
];

PDSRelayService *relayService = [[PDSRelayService alloc] 
    initWithRelays:relays 
          hostname:@"pds.example.com"];
```

### Start Service

```objc
- (void)start;
```

Starts listening for repository change notifications and begins notifying relays.

**Example:**
```objc
[relayService start];
```

### Stop Service

```objc
- (void)stop;
```

Stops listening for notifications and halts relay notifications.

**Example:**
```objc
[relayService stop];
```

### Notify Specific Relay

```objc
- (void)notifyRelay:(NSString *)relayHost;
```

Manually notifies a specific relay server to crawl this PDS.

**Parameters:**
- `relayHost`: Relay hostname (e.g., "https://bsky.network")

**Example:**
```objc
[relayService notifyRelay:@"https://bsky.network"];
```

## Notification Flow

### Automatic Notification

```

1. Record is created/updated/deleted
   ↓
2. PDSRecordDidChangeNotification posted
   ↓
3. RelayService receives notification
   ↓
4. For each configured relay:
   - Send HTTP POST to relay
   - Include PDS hostname
   - Include change details
   ↓
5. Relay crawls PDS for updates
   ↓
6. Relay aggregates and distributes data
```

### Relay Crawl Request

The relay service sends a request like:

```

POST /xrpc/com.atproto.sync.notifyOfUpdate HTTP/1.1
Host: relay.example.com
Content-Type: application/json

{
  "hostname": "pds.example.com",
  "did": "did:web:pds.example.com"
}
```

The relay then:
1. Connects to the PDS
2. Calls `com.atproto.sync.getLatestCommit` to get current state
3. Calls `com.atproto.sync.getRepo` to fetch repository data
4. Stores data in relay database
5. Broadcasts to subscribers

## Configuration

### Relay URLs

Relays are configured as HTTPS URLs:

```objc
NSArray *relays = @[
    @"https://bsky.network",           // Official Bluesky relay
    @"https://relay.example.com",      // Custom relay
    @"https://relay2.example.com"      // Backup relay
];
```

### Hostname

The PDS hostname must be:
- Publicly resolvable
- HTTPS accessible
- Matching the DID web identifier

```objc
NSString *hostname = @"pds.example.com";
// Results in DID: did:web:pds.example.com
```

## Error Handling

### Relay Communication Failures

If a relay is unreachable:

1. Log the failure
2. Add to retry queue
3. Retry with exponential backoff
4. Eventually give up after max retries

### Retry Strategy

```

Attempt 1: Immediate
Attempt 2: 1 minute delay
Attempt 3: 5 minutes delay
Attempt 4: 30 minutes delay
Attempt 5: 2 hours delay
Give up after 5 attempts
```

### Partial Failures

If some relays fail:
- Continue notifying other relays
- Retry failed relays independently
- Don't block on relay failures

## Overview

The `PDSRelayService` notifies external relays of repository updates. It enables the PDS to participate in the ATProto network by broadcasting changes to relay servers, which aggregate and distribute data across the network.

### Why This Service Matters

Relays are the backbone of ATProto's decentralized architecture. The Relay Service ensures:

- **Network Participation**: Your PDS's data is discoverable and accessible across the network
- **Data Distribution**: Changes propagate to aggregators and indexers automatically
- **Decentralization**: No single point of failure - multiple relays provide redundancy
- **Real-time Updates**: Subscribers receive updates through relay firehose streams

Without the Relay Service, your PDS would be isolated - users could access it directly, but their content wouldn't appear in network-wide feeds, search, or discovery.

## When to Use This Service

### Use Relay Service When:

- **Running a production PDS**: Essential for network participation
- **Broadcasting repository changes**: Automatically notifies relays of new commits
- **Implementing federation**: Enables your PDS to participate in the broader network
- **Testing relay integration**: Verify your PDS correctly notifies relays

### Don't Use Relay Service For:

- **Direct client notifications**: Use Firehose for real-time client updates
- **Internal synchronization**: Use Repository Service for PDS-to-PDS sync
- **Backup operations**: Use repository export for backups
- **Testing in isolation**: Disable relay notifications for local development

## Common Pitfalls and Troubleshooting

### Pitfall 1: Relay Notification Blocking Record Operations

**Problem**: Record creation becomes slow because it waits for relay notification.

**Why it happens**: Synchronous relay notification blocks the request thread.

**Solution**: Use asynchronous notification:
```objc
- (void)notifyRelaysAsync:(NSString *)did {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSString *relayHost in self.relays) {
            NSError *error = nil;
            [self notifyRelay:relayHost forDid:did error:&error];
            
            if (error) {
                PDS_LOG_WARN(@"Relay notification failed: %@ - %@", 
                            relayHost, error.localizedDescription);
                // Add to retry queue
                [self.retryQueue addNotification:relayHost did:did];
            }
        }
    });
}

// In record service
- (BOOL)putRecord:(NSString *)collection /* ... */ {
    // ... create record ...
    
    // Notify relays asynchronously (don't wait)
    [self.relayService notifyRelaysAsync:did];
    
    return YES;
}
```

### Pitfall 2: Relay Failures Causing Data Loss

**Problem**: Failed relay notifications are lost, causing data to not propagate.

**Why it happens**: No retry mechanism for failed notifications.

**Solution**: Implement persistent retry queue:
```objc
@interface PDSRelayRetryQueue : NSObject

- (void)addNotification:(NSString *)relayHost did:(NSString *)did;
- (void)processRetries;

@end

@implementation PDSRelayRetryQueue {
    NSMutableArray *_pendingNotifications;
    dispatch_queue_t _retryQueue;
}

- (instancetype)init {
    if (self = [super init]) {
        _pendingNotifications = [NSMutableArray array];
        _retryQueue = dispatch_queue_create("com.pds.relay.retry", DISPATCH_QUEUE_SERIAL);
        
        // Process retries every 5 minutes
        [self scheduleRetryProcessing];
    }
    return self;
}

- (void)addNotification:(NSString *)relayHost did:(NSString *)did {
    dispatch_async(_retryQueue, ^{
        NSDictionary *notification = @{
            @"relayHost": relayHost,
            @"did": did,
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"attempts": @(0)
        };
        [_pendingNotifications addObject:notification];
    });
}

- (void)processRetries {
    dispatch_async(_retryQueue, ^{
        NSMutableArray *toRemove = [NSMutableArray array];
        
        for (NSMutableDictionary *notification in _pendingNotifications) {
            NSInteger attempts = [notification[@"attempts"] integerValue];
            
            if (attempts >= 5) {
                // Give up after 5 attempts
                PDS_LOG_ERROR(@"Giving up on relay notification: %@", notification);
                [toRemove addObject:notification];
                continue;
            }
            
            // Exponential backoff
            NSTimeInterval delay = pow(2, attempts) * 60; // 1, 2, 4, 8, 16 minutes
            NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - 
                                    [notification[@"timestamp"] doubleValue];
            
            if (elapsed < delay) continue;
            
            // Retry notification
            NSError *error = nil;
            BOOL success = [self notifyRelay:notification[@"relayHost"]
                                      forDid:notification[@"did"]
                                       error:&error];
            
            if (success) {
                [toRemove addObject:notification];
            } else {
                notification[@"attempts"] = @(attempts + 1);
            }
        }
        
        [_pendingNotifications removeObjectsInArray:toRemove];
    });
}

@end
```

### Pitfall 3: Incorrect Hostname Configuration

**Problem**: Relays cannot crawl the PDS because hostname is wrong.

**Why it happens**: Using localhost, internal IP, or non-resolvable hostname.

**Solution**: Verify hostname configuration:
```objc
- (BOOL)validateHostname:(NSString *)hostname error:(NSError **)error {
    // Check for localhost
    if ([hostname hasPrefix:@"localhost"] || [hostname hasPrefix:@"127.0.0.1"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"RelayService"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"Hostname cannot be localhost"}];
        }
        return NO;
    }
    
    // Check for private IP ranges
    if ([self isPrivateIP:hostname]) {
        if (error) {
            *error = [NSError errorWithDomain:@"RelayService"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"Hostname cannot be private IP"}];
        }
        return NO;
    }
    
    // Verify DNS resolution
    struct hostent *host = gethostbyname([hostname UTF8String]);
    if (!host) {
        if (error) {
            *error = [NSError errorWithDomain:@"RelayService"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"Hostname not resolvable"}];
        }
        return NO;
    }
    
    return YES;
}
```

### Pitfall 4: Relay Notification Storms

**Problem**: Excessive relay notifications for batch operations.

**Why it happens**: Notifying relay for every individual record change.

**Solution**: Batch notifications:
```objc
@interface PDSRelayService ()
@property (nonatomic, strong) NSMutableSet *pendingNotifications;
@property (nonatomic, strong) NSTimer *batchTimer;
@end

- (void)notifyRelaysForDid:(NSString *)did {
    @synchronized(self.pendingNotifications) {
        [self.pendingNotifications addObject:did];
    }
    
    // Debounce: wait 1 second before sending
    [self.batchTimer invalidate];
    self.batchTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(sendBatchedNotifications)
                                                     userInfo:nil
                                                      repeats:NO];
}

- (void)sendBatchedNotifications {
    NSSet *didsToNotify;
    @synchronized(self.pendingNotifications) {
        didsToNotify = [self.pendingNotifications copy];
        [self.pendingNotifications removeAllObjects];
    }
    
    // Send one notification per DID
    for (NSString *did in didsToNotify) {
        [self notifyRelaysAsync:did];
    }
}
```

### Troubleshooting Guide

#### Issue: Relays not receiving notifications

**Symptoms**: Content not appearing in network feeds.

**Possible causes**:
1. Relay URL incorrect
2. Hostname not publicly accessible
3. Firewall blocking relay requests

**Diagnosis**:
```objc
// Test relay connectivity
- (void)testRelayConnectivity:(NSString *)relayHost {
    // 1. Verify relay is reachable
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.sync.notifyOfUpdate", relayHost]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            PDS_LOG_ERROR(@"Relay unreachable: %@", error);
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            PDS_LOG_DEBUG(@"Relay response: %ld", httpResponse.statusCode);
        }
    }] resume];
    
    // 2. Verify PDS is accessible from relay
    [self testPDSAccessibility];
}

- (void)testPDSAccessibility {
    NSString *testURL = [NSString stringWithFormat:@"https://%@/xrpc/com.atproto.sync.getLatestCommit?did=%@",
                        self.hostname, @"did:web:example.com"];
    
    PDS_LOG_INFO(@"Test PDS accessibility: %@", testURL);
    PDS_LOG_INFO(@"Relay should be able to access this URL");
}
```

#### Issue: Relay notifications timing out

**Symptoms**: Relay notification errors with timeout.

**Possible causes**:
1. Relay server overloaded
2. Network latency
3. Timeout too short

**Diagnosis**:
```objc
// Increase timeout and add logging
- (BOOL)notifyRelay:(NSString *)relayHost forDid:(NSString *)did error:(NSError **)error {
    NSDate *startTime = [NSDate date];
    
    // Create request with longer timeout
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:30.0];  // 30 second timeout
    
    // ... send request ...
    
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
    PDS_LOG_DEBUG(@"Relay notification took %.2f seconds", elapsed);
    
    if (elapsed > 10.0) {
        PDS_LOG_WARN(@"Slow relay notification: %@ (%.2f seconds)", relayHost, elapsed);
    }
    
    return success;
}
```

## Best Practices

1. **Relay Selection**
   - Use multiple relays for redundancy (2-3 recommended)
   - Include official relays (bsky.network for Bluesky)
   - Monitor relay health and remove dead relays
   - Test relay connectivity before adding to configuration
   - Document relay selection criteria

2. **Notification Timing**
   - Notify relays immediately after commit (don't delay)
   - Don't wait for relay response (use async notification)
   - Use async/background notifications to avoid blocking
   - Implement timeout (5-10 seconds) for relay requests
   - Batch notifications for bulk operations

3. **Error Handling**
   - Log all relay failures with details (relay, error, timestamp)
   - Implement exponential backoff for retries (1, 2, 4, 8, 16 minutes)
   - Monitor retry queue size and alert if growing
   - Alert on persistent failures (> 24 hours)
   - Implement circuit breaker for consistently failing relays

4. **Performance**
   - Don't block record operations on relay notification
   - Use background queue for notifications
   - Batch notifications if possible (debounce 1 second)
   - Implement rate limiting to prevent notification storms
   - Monitor notification latency and throughput

5. **Configuration**
   - Validate hostname is publicly accessible
   - Use HTTPS for relay URLs
   - Document relay configuration in deployment guide
   - Provide relay health check endpoint
   - Allow runtime relay configuration updates

## Common Patterns

### Starting the Service

```objc
// In PDSApplication initialization
NSArray *relays = @[@"https://bsky.network"];
PDSRelayService *relayService = [[PDSRelayService alloc]
    initWithRelays:relays
          hostname:@"pds.example.com"];

[relayService start];

// Store for later
self.relayService = relayService;
```

### Handling Repository Changes

```objc
// In PDSRecordService or similar
- (void)recordDidChange:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *did = userInfo[@"did"];
    NSString *action = userInfo[@"action"];
    
    // Relay service automatically notifies relays
    // (if it's listening to this notification)
}
```

### Manual Relay Notification

```objc
// Manually notify a relay (e.g., after adding new relay)
[relayService notifyRelay:@"https://new-relay.example.com"];
```

### Graceful Shutdown

```objc
// In application shutdown
[relayService stop];

// Wait for pending notifications to complete
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
               dispatch_get_main_queue(), ^{
    // Continue shutdown
});
```

## Monitoring

### Metrics to Track

- Relay notification success rate
- Average notification latency
- Retry queue size
- Failed relay count
- Notification throughput

### Logging

Log all relay operations:

```

[INFO] Notifying relay: https://bsky.network
[INFO] Relay notification succeeded: https://bsky.network
[WARN] Relay notification failed: https://relay.example.com (attempt 1/5)
[ERROR] Relay notification failed after 5 attempts: https://relay.example.com
```

## Integration with PDS

### Initialization

```objc
// In PDSApplication.m
- (void)setupRelayService {
    NSArray *relays = self.configuration.relays;
    NSString *hostname = self.configuration.serverHostname;
    
    self.relayService = [[PDSRelayService alloc]
        initWithRelays:relays
              hostname:hostname];
    
    [self.relayService start];
}
```

### Shutdown

```objc
- (void)shutdown {
    [self.relayService stop];
    // ... other shutdown
}
```

## See Also

- [Services Overview](services-overview) - How Relay Service fits into the service layer
- [PDSApplication](pds-application) - Application-level integration
- [Record Service](record-service) - Record operations that trigger relay notifications
- [Firehose Overview](../08-sync-firehose/firehose-overview) - How relays consume PDS updates
- [Commit Broadcasting](../08-sync-firehose/commit-broadcasting) - Understanding the notification flow
- [Repository Service](repository-service) - Repository-level operations
