# Request Throttling

## Overview

Request throttling controls the rate at which requests are processed to prevent resource exhaustion and ensure fair access. The PDS implements throttling at multiple levels:

- **Global throttling** — Server-wide concurrency limits
- **Per-endpoint throttling** — Limits specific to endpoint types
- **Per-user throttling** — Rate limits per DID
- **Per-IP throttling** — Limits for unauthenticated requests

## Throttling vs Rate Limiting

**Rate Limiting:**
- Tracks request counts over time windows
- Enforces maximum requests per time period
- Returns 429 when limit exceeded

**Throttling:**
- Controls concurrent request processing
- Limits active requests at any moment
- Applies backpressure when overloaded

Both mechanisms work together to protect the server.

## Global Throttling

### Concurrency Semaphore

**Implementation (from HttpServer.m):**

```objc
static const NSUInteger kMaxConcurrentRequests = 64; // Limit concurrent threads

@interface HttpServer ()
@property(nonatomic, assign) dispatch_semaphore_t concurrencySemaphore;
@end

- (instancetype)initWithHost:(NSString *_Nullable)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _concurrencySemaphore = dispatch_semaphore_create(kMaxConcurrentRequests);
        // ...
    }
    return self;
}
```

**Request Processing:**

```objc
// Wait for available slot
dispatch_semaphore_wait(self.concurrencySemaphore, DISPATCH_TIME_FOREVER);

// Process request
dispatch_group_async(self.taskGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @autoreleasepool {
        [self handleRequest:request response:response];
        
        // Release slot
        dispatch_semaphore_signal(self.concurrencySemaphore);
    }
});
```

**Purpose:**
- Prevents thread exhaustion
- Limits memory usage per request
- Ensures predictable resource usage

**Configuration:**
- Default: 64 concurrent requests
- Compile-time constant
- Enforced via GCD semaphore

### Architecture

```
┌──────────────────────────────────────────┐
│   Incoming Requests                      │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   Concurrency Semaphore (64 slots)      │
│  - Wait for available slot               │
│  - Process request                       │
│  - Release slot                          │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
   Available         Queue Waits
   Process Now       for Slot
```

## Per-Endpoint Throttling

### Query Result Limits

Different endpoints enforce different result size limits to prevent large responses:

**Repository Listing:**

```objc
// com.atproto.repo.listRecords
NSInteger limit = 500;
NSString *limitParam = [request queryParamForKey:@"limit"];
if (limitParam.length > 0) {
    if (!parseStrictIntegerString(limitParam, &limit) || 
        limit < 1 || limit > 1000) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest", 
            @"message": @"limit must be an integer between 1 and 1000"
        }];
        return;
    }
}
```

**Feed Queries:**

```objc
// app.bsky.feed.getTimeline
NSInteger limit = 50;
if (![self parseLimit:request.queryParams[@"limit"] 
             outValue:&limit 
                  min:1 
                  max:100 
             response:response]) {
    return;
}
```

**Admin Queries:**

```objc
// com.atproto.admin.searchRepos
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

### Endpoint Limit Summary

| Endpoint Type | Default Limit | Max Limit | Purpose |
|--------------|---------------|-----------|---------|
| Repository lists | 500 | 1000 | Large repo queries |
| Feed queries | 50 | 100 | Timeline/feed pagination |
| Admin queries | 50 | 100 | Moderation operations |
| Label queries | 50 | 250 | Label lookups |
| Sync operations | 500 | 500 | Repository sync |

### Pagination Enforcement

All list endpoints require pagination:

```objc
// Enforce pagination with cursor
NSString *cursor = [request queryParamForKey:@"cursor"];
NSInteger limit = 50;

// Query with limit + 1 to detect more results
NSArray *results = [service queryRecords:collection 
                                   limit:limit + 1 
                                  cursor:cursor];

// Check if more results exist
BOOL hasMore = results.count > limit;
if (hasMore) {
    results = [results subarrayWithRange:NSMakeRange(0, limit)];
}

// Return cursor for next page
NSString *nextCursor = hasMore ? [self cursorFromLastResult:results.lastObject] : nil;

[response setJsonBody:@{
    @"records": results,
    @"cursor": nextCursor ?: [NSNull null]
}];
```

**Purpose:**
- Prevents large result sets
- Enables incremental loading
- Reduces memory usage
- Improves response times

## Per-User Throttling

### DID-Based Rate Limits

See [Rate Limiting](./rate-limiting.md) for detailed documentation.

**Summary:**
- 5000 requests per hour per DID
- Tracked in SQLite database
- Persistent across restarts

**Implementation:**

```objc
RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForDid:did];
if (!result.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
        @"error": @"RateLimitExceeded",
        @"message": @"Too many requests"
    }];
    [response setHeader:[NSString stringWithFormat:@"%.0f", result.retryAfter] 
                 forKey:@"Retry-After"];
    return;
}
```

### Blob Upload Throttling

Separate limits for blob operations:

```objc
// Check blob upload rate limit
RateLimitResult *blobResult = [[RateLimiter sharedLimiter] 
    checkBlobUploadRateLimitForDid:did];

if (!blobResult.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
        @"error": @"BlobUploadLimitExceeded",
        @"message": [NSString stringWithFormat:
            @"Blob upload limit exceeded. Try again in %.0f seconds", 
            blobResult.retryAfter]
    }];
    [response setHeader:[NSString stringWithFormat:@"%.0f", blobResult.retryAfter] 
                 forKey:@"Retry-After"];
    return;
}
```

**Configuration:**
- Default: 50 uploads per hour
- Separate from API request limits
- Prevents storage abuse

## Per-IP Throttling

### Unauthenticated Request Limits

**Implementation:**

```objc
// Extract client IP
NSString *clientIP = [self extractClientIP:request];

// Check IP rate limit
RateLimitResult *ipResult = [[RateLimiter sharedLimiter] checkRateLimitForIP:clientIP];
if (!ipResult.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
        @"error": @"RateLimitExceeded",
        @"message": @"Too many requests from this IP"
    }];
    [response setHeader:[NSString stringWithFormat:@"%.0f", ipResult.retryAfter] 
                 forKey:@"Retry-After"];
    return;
}
```

**Use Cases:**
- OAuth authorization endpoints
- Public API endpoints
- Unauthenticated queries
- Protection against IP-based attacks

**Configuration:**
- Default: 100 requests per minute
- Applied before authentication
- Extracted from X-Forwarded-For when behind proxy

### OAuth Endpoint Throttling

**Implementation (from HttpServer.m):**

```objc
if ([request.path hasPrefix:@"/oauth/"] && 
    !RateLimiterIsDisabledGlobally() &&
    [RateLimiter sharedLimiter].isEnabled) {
    
    NSString *clientIP = [self extractClientIP:request];
    RateLimitResult *result = [[RateLimiter sharedLimiter] 
        checkRateLimitForIP:clientIP];
    
    if (!result.allowed) {
        response.statusCode = 429;
        [response setJsonBody:@{
            @"error": @"rate_limit_exceeded",
            @"message": @"Too many requests"
        }];
        [response setHeader:[NSString stringWithFormat:@"%.0f", result.retryAfter] 
                     forKey:@"Retry-After"];
        return;
    }
}
```

**Purpose:**
- Prevents credential stuffing
- Limits OAuth flow abuse
- Protects authentication endpoints

## Backpressure Mechanisms

### Output Queue Throttling

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
    
    PDS_LOG_HTTP_WARN(@"Output queue high water mark reached, pausing reads");
    return;
}

// Add response to queue
[state.outputQueue addObject:queuedResponse];
state.outputQueueSize += queuedResponse.queueByteSize;
```

**Purpose:**
- Prevents memory exhaustion from slow clients
- Applies backpressure to fast producers
- Ensures bounded memory usage

**Flow Control:**

```
Fast Producer → Output Queue → Slow Consumer
                     │
                     ▼
              Queue Full?
                     │
                     ▼
              Pause Reading
              (Backpressure)
```

### Chunk-Based Streaming

**Implementation (from HttpServer.m):**

```objc
static const NSUInteger kHttpFileSendChunkSize = 64 * 1024;
static const NSUInteger kHttpGeneratedChunkSendSize = 64 * 1024;

// Send file in chunks
while (offset < fileSize) {
    NSUInteger chunkSize = MIN(kHttpFileSendChunkSize, fileSize - offset);
    NSData *chunk = [self readFileChunk:filePath offset:offset length:chunkSize];
    
    // Check if output queue has space
    if (state.outputQueueSize > kHttpOutputQueueHighWaterMark) {
        // Pause and wait for queue to drain
        break;
    }
    
    [self sendData:chunk toConnection:connection];
    offset += chunkSize;
}
```

**Purpose:**
- Prevents large memory allocations
- Enables streaming responses
- Reduces memory pressure

**Configuration:**
- File chunks: 64 KB
- Generated chunks: 64 KB
- Queue budget: 64 KB

## Custom Throttling

### Endpoint-Specific Limits

For specialized throttling needs:

```objc
// Custom rate limit for password reset
RateLimitResult *result = [[RateLimiter sharedLimiter] 
    checkRateLimitForKey:[NSString stringWithFormat:@"password_reset:%@", email]
                   limit:5
            windowSeconds:3600];

if (!result.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
        @"error": @"TooManyPasswordResets",
        @"message": @"Too many password reset attempts"
    }];
    return;
}
```

### Operation-Specific Limits

```objc
// Limit account creation per IP
RateLimitResult *result = [[RateLimiter sharedLimiter] 
    checkRateLimitForKey:[NSString stringWithFormat:@"account_create:%@", clientIP]
                   limit:3
            windowSeconds:86400]; // 24 hours

if (!result.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
        @"error": @"AccountCreationLimitExceeded",
        @"message": @"Too many account creation attempts"
    }];
    return;
}
```

## Monitoring and Metrics

### Log Throttling Events

```objc
if (!result.allowed) {
    PDS_LOG_HTTP_WARN(@"Request throttled for %@: %ld/%ld requests in %.0fs window", 
                      identifier, 
                      (long)result.limit, 
                      (long)result.limit,
                      result.resetSeconds);
}
```

### Track Queue Metrics

```objc
if (state.outputQueueSize > kHttpOutputQueueHighWaterMark / 2) {
    PDS_LOG_HTTP_DEBUG(@"Output queue at 50%% capacity: %lu bytes", 
                       (unsigned long)state.outputQueueSize);
}
```

### Monitor Concurrency

```objc
PDS_LOG_HTTP_DEBUG(@"Active requests: %lu/%lu", 
                   (unsigned long)activeRequests,
                   (unsigned long)kMaxConcurrentRequests);
```

## Response Headers

### Rate Limit Headers

```
HTTP/1.1 200 OK
X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 4999
X-RateLimit-Reset: 3600
```

### Throttled Response

```
HTTP/1.1 429 Too Many Requests
Retry-After: 60
X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 3600

{
  "error": "RateLimitExceeded",
  "message": "Too many requests. Try again in 60 seconds"
}
```

## Configuration

### Rate Limit Configuration

```json
{
  "rate_limit": {
    "enabled": true,
    "did_limit": 5000,
    "did_window": 3600,
    "ip_limit": 100,
    "ip_window": 60,
    "blob_limit": 50,
    "blob_window": 3600
  }
}
```

### Environment Variables

```bash
export PDS_RATELIMIT_ENABLED=true
export PDS_RATELIMIT_DID_LIMIT=10000
export PDS_RATELIMIT_IP_LIMIT=200
```

### Compile-Time Constants

```objc
// HttpServer.m
static const NSUInteger kMaxConcurrentRequests = 64;
static const NSUInteger kHttpMaxHeaderBytes = 16 * 1024;
static const NSUInteger kHttpMaxBodyBytes = 50 * 1024 * 1024;
static const NSUInteger kHttpOutputQueueHighWaterMark = 10 * 1024 * 1024;
static const NSTimeInterval kHttpHeaderTimeout = 5.0;
```

## Best Practices

### 1. Layer Throttling Mechanisms

Implement multiple layers:
- Global concurrency limits
- Per-endpoint result limits
- Per-user rate limits
- Per-IP rate limits

### 2. Provide Clear Feedback

Include helpful information in throttled responses:
- Retry-After header
- Clear error message
- Remaining quota
- Reset time

### 3. Monitor Throttling Patterns

Track metrics:
- Throttle hit rates
- Queue sizes
- Concurrency levels
- Response times

### 4. Tune Limits Based on Usage

Adjust limits based on:
- Legitimate traffic patterns
- Resource capacity
- Attack patterns
- User feedback

### 5. Graceful Degradation

Handle overload gracefully:
- Return 429 instead of 503
- Provide retry guidance
- Log throttling events
- Alert on sustained throttling

## Common Patterns

### Combining Multiple Limits

```objc
// Check global concurrency
dispatch_semaphore_wait(self.concurrencySemaphore, DISPATCH_TIME_FOREVER);

// Check DID rate limit
RateLimitResult *didResult = [[RateLimiter sharedLimiter] checkRateLimitForDid:did];
if (!didResult.allowed) {
    dispatch_semaphore_signal(self.concurrencySemaphore);
    [self sendRateLimitError:response result:didResult];
    return;
}

// Check endpoint-specific limit
if (limit > maxAllowedLimit) {
    dispatch_semaphore_signal(self.concurrencySemaphore);
    [self sendValidationError:response];
    return;
}

// Process request
[self processRequest:request response:response];

// Release concurrency slot
dispatch_semaphore_signal(self.concurrencySemaphore);
```

### Adaptive Throttling

```objc
// Adjust limits based on server load
NSUInteger currentLoad = [self calculateServerLoad];
NSInteger adjustedLimit = baseLimit;

if (currentLoad > 0.8) {
    // Reduce limits under high load
    adjustedLimit = baseLimit / 2;
} else if (currentLoad < 0.3) {
    // Increase limits under low load
    adjustedLimit = baseLimit * 1.5;
}

RateLimitResult *result = [[RateLimiter sharedLimiter] 
    checkRateLimitForKey:key
                   limit:adjustedLimit
            windowSeconds:windowSeconds];
```

### Burst Allowance

```objc
// Allow short bursts above sustained rate
NSInteger burstLimit = sustainedLimit * 2;
NSInteger burstWindow = 10; // seconds

// Check burst limit first
RateLimitResult *burstResult = [[RateLimiter sharedLimiter] 
    checkRateLimitForKey:[NSString stringWithFormat:@"burst:%@", key]
                   limit:burstLimit
            windowSeconds:burstWindow];

if (!burstResult.allowed) {
    // Burst limit exceeded
    return NO;
}

// Check sustained limit
RateLimitResult *sustainedResult = [[RateLimiter sharedLimiter] 
    checkRateLimitForKey:key
                   limit:sustainedLimit
            windowSeconds:sustainedWindow];

return sustainedResult.allowed;
```

## Testing

### Test Throttling Behavior

```objc
- (void)testConcurrencyLimit {
    // Send more requests than concurrency limit
    NSMutableArray *responses = [NSMutableArray array];
    
    for (NSInteger i = 0; i < kMaxConcurrentRequests + 10; i++) {
        [self sendAsyncRequest:^(HttpResponse *response) {
            [responses addObject:response];
        }];
    }
    
    // Wait for all responses
    [self waitForResponses:responses];
    
    // Verify no more than kMaxConcurrentRequests processed simultaneously
    XCTAssertLessThanOrEqual(self.maxConcurrentObserved, kMaxConcurrentRequests);
}
```

### Test Rate Limiting

```objc
- (void)testRateLimitEnforcement {
    NSString *did = @"did:test:user";
    
    // Send requests up to limit
    for (NSInteger i = 0; i < limiter.didLimit; i++) {
        RateLimitResult *result = [limiter checkRateLimitForDid:did];
        XCTAssertTrue(result.allowed);
    }
    
    // Next request should be throttled
    RateLimitResult *result = [limiter checkRateLimitForDid:did];
    XCTAssertFalse(result.allowed);
    XCTAssertGreaterThan(result.retryAfter, 0);
}
```

## See Also

- [Rate Limiting](./rate-limiting.md) — Rate limiting algorithms
- [DoS Protection](./dos-protection.md) — Attack mitigation
- [HTTP Server](./http-server.md) — Server implementation
- [Error Handling](./error-handling.md) — Error responses
- [Firehose Rate Limiting](../08-sync-firehose/firehose-rate-limiting.md) — Subscriber throttling
