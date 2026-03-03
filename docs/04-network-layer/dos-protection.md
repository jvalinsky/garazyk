# DoS Protection

## Overview

The PDS implements multiple layers of Denial of Service (DoS) protection to ensure availability and prevent resource exhaustion. Protection mechanisms operate at the network, application, and resource levels.

## Attack Vectors

### 1. Connection Flooding

**Attack:** Opening many connections to exhaust server resources.

**Mitigation:**
- Connection concurrency limits
- Connection timeout enforcement
- Resource cleanup on connection close

### 2. Slowloris Attacks

**Attack:** Sending partial HTTP headers slowly to keep connections open.

**Mitigation:**
- Header timeout enforcement
- Maximum header size limits
- Connection state tracking

### 3. Request Flooding

**Attack:** Sending many valid requests to overwhelm the server.

**Mitigation:**
- Rate limiting per DID/IP
- Request concurrency limits
- Backpressure mechanisms

### 4. Large Payload Attacks

**Attack:** Sending extremely large request bodies to exhaust memory.

**Mitigation:**
- Maximum body size limits
- Streaming request parsing
- Memory-bounded buffers

### 5. Amplification Attacks

**Attack:** Requesting large responses with small requests.

**Mitigation:**
- Response size limits
- Pagination enforcement
- Query result limits

## Protection Layers

```
┌──────────────────────────────────────────┐
│   Network Layer                          │
│  - Connection limits                     │
│  - Timeout enforcement                   │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   Application Layer                      │
│  - Rate limiting                         │
│  - Request validation                    │
│  - Concurrency control                   │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   Resource Layer                         │
│  - Memory limits                         │
│  - Database connection pools             │
│  - Queue size limits                     │
└──────────────────────────────────────────┘
```

## Network Layer Protection

### Connection Concurrency Limits

**Implementation (from HttpServer.m):**

```objc
static const NSUInteger kMaxConcurrentRequests = 64; // Limit concurrent threads

- (instancetype)initWithHost:(NSString *_Nullable)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        // ... other initialization
        _concurrencySemaphore = dispatch_semaphore_create(kMaxConcurrentRequests);
        // ...
    }
    return self;
}
```

**Purpose:**
- Prevents thread exhaustion
- Limits memory usage per connection
- Ensures fair resource allocation

**Configuration:**
- Default: 64 concurrent requests
- Adjustable via compile-time constant
- Enforced via dispatch semaphore

### Header Timeout Enforcement

**Implementation (from HttpServer.m):**

```objc
static const NSTimeInterval kHttpHeaderTimeout = 5.0;

@interface HttpConnectionState : NSObject
@property(nonatomic, assign) NSTimeInterval headerStartTime;
@end

// Check timeout during header parsing
NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - state.headerStartTime;
if (elapsed > kHttpHeaderTimeout) {
    // Close connection
    [self closeConnection:connection reason:@"Header timeout"];
    return;
}
```

**Purpose:**
- Prevents Slowloris attacks
- Frees resources from slow clients
- Enforces reasonable request timing

**Configuration:**
- Default: 5.0 seconds
- Applied to header parsing only
- Connection closed on timeout

### Maximum Header Size

**Implementation (from HttpServer.m):**

```objc
static const NSUInteger kHttpMaxHeaderBytes = 16 * 1024; // 16KB

if (headerSize > kHttpMaxHeaderBytes) {
    response.statusCode = 431; // Request Header Fields Too Large
    [self sendErrorResponse:response toConnection:connection];
    [self closeConnection:connection];
    return;
}
```

**Purpose:**
- Prevents memory exhaustion
- Limits header parsing overhead
- Protects against malformed requests

**Configuration:**
- Default: 16 KB
- Enforced during header parsing
- Returns 431 status code

### Maximum Body Size

**Implementation (from HttpServer.m):**

```objc
static const NSUInteger kHttpMaxBodyBytes = 50 * 1024 * 1024; // 50MB

if (contentLength > kHttpMaxBodyBytes) {
    response.statusCode = 413; // Payload Too Large
    [self sendErrorResponse:response toConnection:connection];
    [self closeConnection:connection];
    return;
}
```

**Purpose:**
- Prevents memory exhaustion
- Limits request processing time
- Protects against large payload attacks

**Configuration:**
- Default: 50 MB
- Checked against Content-Length header
- Returns 413 status code

## Application Layer Protection

### Rate Limiting

See [Rate Limiting](./rate-limiting.md) for detailed documentation.

**Summary:**
- Per-DID API limits (5000/hour)
- Per-IP request limits (100/minute)
- Per-DID blob limits (50/hour)

**Implementation:**

```objc
RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForDid:did];
if (!result.allowed) {
    response.statusCode = 429; // Too Many Requests
    [response setHeader:[NSString stringWithFormat:@"%.0f", result.retryAfter] 
                 forKey:@"Retry-After"];
    return;
}
```

### Request Validation

**Input Validation:**

```objc
// Validate required parameters
if (!repo || repo.length == 0) {
    [XrpcErrorHelper setValidationError:response 
                                message:@"Missing required parameter: repo"];
    return;
}

// Validate parameter format
if (![repo hasPrefix:@"did:"]) {
    [XrpcErrorHelper setValidationError:response 
                                message:@"Invalid DID format"];
    return;
}
```

**Query Parameter Limits:**

```objc
// Limit query result size
NSInteger limit = 50;
NSString *limitParam = [request queryParamForKey:@"limit"];
if (limitParam.length > 0 && 
    (!parseStrictIntegerString(limitParam, &limit) || 
     limit < 1 || limit > 100)) {
    response.statusCode = HttpStatusBadRequest;
    [response setJsonBody:@{
        @"error": @"InvalidRequest", 
        @"message": @"limit must be an integer between 1 and 100"
    }];
    return;
}
```

**Purpose:**
- Prevents invalid data processing
- Limits query result sizes
- Protects against injection attacks

### Authentication Verification

**Early Authentication Check:**

```objc
// Verify authentication before processing
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request];

if (!did) {
    [XrpcErrorHelper setAuthenticationError:response];
    return; // Fail fast
}
```

**Purpose:**
- Fails fast on invalid auth
- Prevents unauthenticated resource usage
- Reduces attack surface

## Resource Layer Protection

### Output Queue Limits

**Implementation (from HttpServer.m):**

```objc
static const NSUInteger kHttpOutputQueueHighWaterMark = 10 * 1024 * 1024; // 10MB

@interface HttpConnectionState : NSObject
@property(nonatomic, assign) NSUInteger outputQueueSize;
@property(nonatomic, assign) BOOL readingPaused;
@end

// Check queue size before adding response
if (state.outputQueueSize > kHttpOutputQueueHighWaterMark) {
    // Pause reading to apply backpressure
    state.readingPaused = YES;
    return;
}
```

**Purpose:**
- Prevents memory exhaustion from slow clients
- Applies backpressure to fast producers
- Ensures bounded memory usage

### Database Connection Pooling

**Implementation:**

```objc
@interface PDSDatabasePool : NSObject

// Limit number of open databases
- (PDSActorDatabase *)databaseForDID:(NSString *)did {
    // Check cache
    PDSActorDatabase *db = [self.cache objectForKey:did];
    if (db) return db;
    
    // Enforce pool size limit
    if (self.cache.count >= self.maxPoolSize) {
        [self evictLeastRecentlyUsed];
    }
    
    // Open new database
    db = [self openDatabaseForDID:did];
    [self.cache setObject:db forKey:did];
    return db;
}

@end
```

**Purpose:**
- Limits database file handles
- Prevents resource exhaustion
- Ensures fair resource allocation

### Chunk Size Limits

**Implementation (from HttpServer.m):**

```objc
static const NSUInteger kHttpFileSendChunkSize = 64 * 1024;
static const NSUInteger kHttpGeneratedChunkSendSize = 64 * 1024;
static const NSUInteger kHttpGeneratedQueueBudget = 64 * 1024;

// Send file in chunks
while (offset < fileSize) {
    NSUInteger chunkSize = MIN(kHttpFileSendChunkSize, fileSize - offset);
    NSData *chunk = [self readFileChunk:filePath offset:offset length:chunkSize];
    [self sendData:chunk toConnection:connection];
    offset += chunkSize;
}
```

**Purpose:**
- Prevents large memory allocations
- Enables streaming responses
- Reduces memory pressure

## Firehose-Specific Protection

### Subscriber Queue Limits

**Implementation (from SubscribeReposHandler.m):**

```objc
static const NSUInteger kSubscribeReposMaxOutputQueueBytes = 16 * 1024 * 1024; // 16MB

- (BOOL)sendEventData:(NSData *)eventData
    toConnectionWithBackpressureCheck:(WebSocketConnection *)connection {
    
    if (!eventData || !connection) {
        return NO;
    }
    
    // Check output queue size
    if (connection.queuedSendBytes > kSubscribeReposMaxOutputQueueBytes) {
        [self sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
                             message:@"connection output queue exceeded server limit"
                        toConnection:connection];
        [self detachConnection:connection];
        return NO;
    }
    
    [connection sendBinaryFrame:eventData];
    return YES;
}
```

**Purpose:**
- Prevents slow subscribers from exhausting memory
- Disconnects consumers that can't keep up
- Protects server from backpressure

**Error Code:**
- `ConsumerTooSlow` — Subscriber queue exceeded limit

### Replay Cursor Limits

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
- Prevents excessive replay operations
- Limits historical data retrieval
- Protects against resource exhaustion

## Proxy and Trust Configuration

### Trusted Proxy Headers

**Implementation (from PDSConfiguration.m):**

```objc
// Trust X-Forwarded-For when behind proxy
if (getenv("PDS_TRUST_PROXY_HEADERS")) {
    NSString *forwardedFor = [request headerForName:@"X-Forwarded-For"];
    if (forwardedFor) {
        clientIP = [[forwardedFor componentsSeparatedByString:@","] firstObject];
    }
}
```

**Purpose:**
- Enables rate limiting behind reverse proxy
- Extracts real client IP
- Prevents proxy IP rate limiting

**Configuration:**
- Environment variable: `PDS_TRUST_PROXY_HEADERS=1`
- Only enable when behind trusted proxy (nginx)
- Required for production deployment

## Monitoring and Alerting

### Log Rate Limit Violations

```objc
if (!result.allowed) {
    PDS_LOG_HTTP_WARN(@"Rate limit exceeded for %@: %ld/%ld requests", 
                      identifier, 
                      (long)result.limit, 
                      (long)result.limit);
}
```

### Track Connection Metrics

```objc
PDS_LOG_HTTP_DEBUG(@"Active connections: %lu, queued: %lu", 
                   (unsigned long)self.activeConnections.count,
                   (unsigned long)self.queuedConnections.count);
```

### Monitor Queue Sizes

```objc
if (state.outputQueueSize > kHttpOutputQueueHighWaterMark / 2) {
    PDS_LOG_HTTP_WARN(@"Output queue approaching limit: %lu bytes", 
                      (unsigned long)state.outputQueueSize);
}
```

## Best Practices

### 1. Defense in Depth

Implement multiple protection layers:
- Network limits (connections, timeouts)
- Application limits (rate limiting, validation)
- Resource limits (memory, database connections)

### 2. Fail Fast

Reject invalid requests early:
- Validate authentication first
- Check rate limits before processing
- Validate input before database queries

### 3. Graceful Degradation

Handle overload gracefully:
- Return 429 with Retry-After header
- Provide clear error messages
- Log violations for analysis

### 4. Monitor and Alert

Track protection metrics:
- Rate limit hit rates
- Connection rejection rates
- Queue size trends
- Response time percentiles

### 5. Tune Limits

Adjust limits based on usage:
- Start conservative
- Monitor legitimate traffic patterns
- Increase limits gradually
- Document changes

## Common Attack Scenarios

### Scenario 1: Credential Stuffing

**Attack:** Trying many username/password combinations.

**Protection:**
- Rate limit authentication endpoints
- Implement account lockout
- Log failed attempts
- Monitor for patterns

**Implementation:**

```objc
// Rate limit password attempts
RateLimitResult *result = [[RateLimiter sharedLimiter] 
    checkRateLimitForKey:[NSString stringWithFormat:@"auth:%@", username]
                   limit:5
            windowSeconds:3600];

if (!result.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
        @"error": @"TooManyAttempts",
        @"message": @"Too many authentication attempts"
    }];
    return;
}
```

### Scenario 2: Repository Enumeration

**Attack:** Scanning for valid DIDs/repositories.

**Protection:**
- Rate limit per IP
- Require authentication for sensitive endpoints
- Log enumeration attempts
- Implement CAPTCHA for suspicious patterns

### Scenario 3: Blob Storage Exhaustion

**Attack:** Uploading many large blobs to exhaust storage.

**Protection:**
- Separate blob upload rate limits
- Enforce blob size quotas
- Implement garbage collection
- Monitor storage usage

**Implementation:**

```objc
// Check blob upload rate limit
RateLimitResult *blobResult = [[RateLimiter sharedLimiter] 
    checkBlobUploadRateLimitForDid:did];

if (!blobResult.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
        @"error": @"BlobUploadLimitExceeded",
        @"message": @"Too many blob uploads"
    }];
    return;
}

// Check blob quota
NSUInteger totalBlobSize = [blobService totalBlobSizeForDid:did];
if (totalBlobSize + blobSize > maxBlobQuota) {
    response.statusCode = 413;
    [response setJsonBody:@{
        @"error": @"BlobQuotaExceeded",
        @"message": @"Blob storage quota exceeded"
    }];
    return;
}
```

### Scenario 4: Firehose Subscription Abuse

**Attack:** Opening many firehose connections to exhaust resources.

**Protection:**
- Limit concurrent subscriptions per DID
- Enforce output queue limits
- Disconnect slow consumers
- Monitor subscription patterns

**Implementation:**

```objc
// Limit concurrent subscriptions
NSUInteger activeSubscriptions = [self countActiveSubscriptionsForDid:did];
if (activeSubscriptions >= kMaxSubscriptionsPerDid) {
    [self sendErrorFrameWithCode:@"TooManySubscriptions"
                         message:@"Maximum concurrent subscriptions exceeded"
                    toConnection:connection];
    [connection close];
    return;
}
```

## Production Deployment

### Reverse Proxy Configuration

**nginx Configuration:**

```nginx
# Rate limiting at nginx level
limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
limit_req_zone $binary_remote_addr zone=auth:10m rate=10r/m;

server {
    listen 443 ssl http2;
    server_name pds.example.com;
    
    # Apply rate limits
    location /xrpc/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://localhost:2583;
    }
    
    location /oauth/ {
        limit_req zone=auth burst=5 nodelay;
        proxy_pass http://localhost:2583;
    }
    
    # Set proxy headers
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
}
```

### Firewall Rules

```bash
# Limit connection rate per IP
iptables -A INPUT -p tcp --dport 2583 -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport 2583 -m state --state NEW -m recent --update --seconds 60 --hitcount 20 -j DROP
```

### Monitoring

```bash
# Monitor rate limit database size
watch -n 60 'du -h /data/service/ratelimits.db'

# Monitor active connections
watch -n 5 'netstat -an | grep :2583 | wc -l'

# Monitor memory usage
watch -n 10 'ps aux | grep kaszlak'
```

## See Also

- [Rate Limiting](./rate-limiting.md) — Rate limiting algorithms
- [Request Throttling](./request-throttling.md) — Per-endpoint throttling
- [HTTP Server](./http-server.md) — Server implementation
- [Firehose Rate Limiting](../08-sync-firehose/firehose-rate-limiting.md) — Subscriber limits
