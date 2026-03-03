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

## Best Practices

1. **Relay Selection**
   - Use multiple relays for redundancy
   - Include official relays (bsky.network)
   - Monitor relay health
   - Remove dead relays

2. **Notification Timing**
   - Notify relays immediately after commit
   - Don't wait for relay response
   - Use async/background notifications
   - Implement timeout (5-10 seconds)

3. **Error Handling**
   - Log all relay failures
   - Implement exponential backoff
   - Monitor retry queue size
   - Alert on persistent failures

4. **Performance**
   - Don't block record operations on relay notification
   - Use background queue for notifications
   - Batch notifications if possible
   - Implement rate limiting

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

- [Services Overview](./services-overview)
- [PDSApplication](./pds-application)
- [Record Service](./record-service)
- [Firehose Overview](../08-sync-firehose/firehose-overview)
