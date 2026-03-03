# Rate Limiting

## Overview

The PDS implements sliding window rate limiting to prevent abuse and ensure fair resource allocation. Rate limiting is applied at multiple levels:

- **Per-DID API requests** — Limits authenticated API calls per user
- **Per-IP requests** — Limits unauthenticated requests per IP address
- **Per-DID blob uploads** — Separate limits for blob operations

Rate limits use SQLite for persistent tracking across server restarts, ensuring limits are enforced even after crashes or deployments.

## Architecture

```
┌──────────────────────────────────────────┐
│   HTTP Request                           │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   Rate Limiter Check                     │
│  - Extract DID or IP                     │
│  - Query SQLite for request count        │
│  - Check against limit                   │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
   Allowed          Rate Limited
        │                 │
        ▼                 ▼
   Continue         Return 429
   Request          + Retry-After
```

## Rate Limiting Algorithm

### Sliding Window

The PDS uses a **sliding window** algorithm that tracks request timestamps within a time window:

1. **Record Request** — Store timestamp in SQLite
2. **Count Requests** — Count requests within window (now - window_seconds)
3. **Check Limit** — Compare count against configured limit
4. **Allow or Deny** — Return result with remaining count

**Implementation (from RateLimiter.m):**

```objc
- (RateLimitResult *)checkRateLimitInternalForIdentifier:(NSString *)identifier
                                                     type:(RateLimitType)type
                                                    limit:(NSInteger)limit
                                              windowSeconds:(NSTimeInterval)windowSeconds {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    
    // Query requests within window
    NSString *selectSQL = @"SELECT request_count, window_start "
                          @"FROM rate_limits "
                          @"WHERE identifier = ? AND type = ? AND window_start > ?";
    
    // ... bind parameters and execute query
    
    if (requestCount >= limit) {
        NSTimeInterval resetSeconds = (existingWindowStart + windowSeconds) - now;
        return [RateLimitResult resultAllowed:NO 
                                        limit:limit 
                                    remaining:0 
                                  resetSeconds:resetSeconds 
                                   retryAfter:resetSeconds];
    }
    
    // Increment counter using UPSERT
    NSString *upsertSQL = @"INSERT INTO rate_limits (identifier, type, request_count, window_start) "
                          @"VALUES (?, ?, ?, ?) "
                          @"ON CONFLICT(identifier, type) DO UPDATE SET "
                          @"request_count = CASE WHEN window_start > ? THEN request_count + 1 ELSE 1 END, "
                          @"window_start = CASE WHEN window_start > ? THEN window_start ELSE ? END";
    
    // ... execute upsert
    
    return [RateLimitResult resultAllowed:YES
                                    limit:limit
                                remaining:(limit - requestCount - 1)
                              resetSeconds:windowSeconds
                               retryAfter:0];
}
```

### Why Sliding Window?

**Advantages:**
- Smooth rate limiting without burst spikes
- Fair distribution across time
- Accurate tracking of request patterns

**Trade-offs:**
- Requires persistent storage (SQLite)
- Slightly more complex than fixed window
- Database queries on every request

## Rate Limit Types

### 1. DID-Based API Limits

Limits authenticated API requests per user (DID).

**Default Configuration:**
- Limit: 5000 requests
- Window: 3600 seconds (1 hour)

**Implementation (from RateLimiter.h):**

```objc
- (RateLimitResult *)checkRateLimitForDid:(NSString *)did {
    if (!self.isEnabled) {
        return [RateLimitResult resultAllowed:YES 
                                        limit:self.didLimit 
                                    remaining:self.didLimit 
                                  resetSeconds:0 
                                   retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkRateLimitInternalForIdentifier:did 
                                                      type:RateLimitTypeDID 
                                                     limit:self.didLimit 
                                              windowSeconds:self.didWindowSeconds];
    });
    return result;
}
```

**Usage in XRPC Handlers:**

```objc
// Extract DID from authentication
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request];

// Check rate limit
RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForDid:did];
if (!result.allowed) {
    response.statusCode = 429; // Too Many Requests
    [response setJsonBody:@{
        @"error": @"RateLimitExceeded",
        @"message": @"Too many requests"
    }];
    [response setHeader:[NSString stringWithFormat:@"%.0f", result.retryAfter] 
                 forKey:@"Retry-After"];
    return;
}
```

### 2. IP-Based Request Limits

Limits unauthenticated requests per IP address.

**Default Configuration:**
- Limit: 100 requests
- Window: 60 seconds (1 minute)

**Implementation:**

```objc
- (RateLimitResult *)checkRateLimitForIP:(NSString *)ip {
    if (!self.isEnabled || _rateLimiterDisabledGlobally) {
        return [RateLimitResult resultAllowed:YES 
                                        limit:self.ipLimit 
                                    remaining:self.ipLimit 
                                  resetSeconds:0 
                                   retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkRateLimitInternalForIdentifier:ip 
                                                      type:RateLimitTypeIP 
                                                     limit:self.ipLimit 
                                              windowSeconds:self.ipWindowSeconds];
    });
    return result;
}
```

**Use Case:**
- Public endpoints (e.g., OAuth authorization)
- Unauthenticated API calls
- Protection against IP-based attacks

### 3. Blob Upload Limits

Separate limits for blob uploads to prevent storage abuse.

**Default Configuration:**
- Limit: 50 uploads
- Window: 3600 seconds (1 hour)

**Implementation:**

```objc
- (RateLimitResult *)checkBlobUploadRateLimitForDid:(NSString *)did {
    if (!self.isEnabled) {
        return [RateLimitResult resultAllowed:YES 
                                        limit:self.blobLimit 
                                    remaining:self.blobLimit 
                                  resetSeconds:0 
                                   retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkBlobRateLimitInternalForDid:did 
                                                   limit:self.blobLimit 
                                            windowSeconds:self.blobWindowSeconds];
    });
    return result;
}
```

**Separate Table:**

Blob limits use a dedicated SQLite table for isolation:

```sql
CREATE TABLE IF NOT EXISTS blob_rate_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    upload_count INTEGER NOT NULL DEFAULT 0,
    window_start INTEGER NOT NULL,
    UNIQUE(did)
)
```

## Configuration

### Configuration File

Rate limits are configured in `config.json`:

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

Environment variables override configuration file:

```bash
export PDS_RATELIMIT_ENABLED=true
export PDS_RATELIMIT_DID_LIMIT=10000
export PDS_RATELIMIT_DID_WINDOW=3600
export PDS_RATELIMIT_IP_LIMIT=200
export PDS_RATELIMIT_IP_WINDOW=60
```

### Programmatic Configuration

**Implementation (from PDSApplication.m):**

```objc
- (void)configureRateLimiter {
    if (!_configuration) return;
    
    RateLimiter *limiter = [RateLimiter sharedLimiter];
    limiter.enabled = _configuration.rateLimitEnabled;
    limiter.didLimit = _configuration.rateLimitDidLimit;
    limiter.didWindowSeconds = _configuration.rateLimitDidWindowSeconds;
    limiter.ipLimit = _configuration.rateLimitIpLimit;
    limiter.ipWindowSeconds = _configuration.rateLimitIpWindowSeconds;
    limiter.blobLimit = _configuration.rateLimitBlobLimit;
    limiter.blobWindowSeconds = _configuration.rateLimitBlobWindowSeconds;
}
```

### Default Values

**Implementation (from PDSConfiguration.m):**

```objc
_rateLimitEnabled = YES;
_rateLimitDidLimit = 5000;
_rateLimitDidWindowSeconds = 3600;
_rateLimitIpLimit = 1000; // Increased default for tests
_rateLimitIpWindowSeconds = 60;
_rateLimitBlobLimit = 50;
_rateLimitBlobWindowSeconds = 3600;
```

## HTTP Headers

### X-RateLimit Headers

The PDS returns standard rate limit headers (RFC 6585):

```
X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 4999
X-RateLimit-Reset: 3600
```

**Implementation:**

```objc
- (NSDictionary<NSString *, NSString *> *)headersFromResult:(RateLimitResult *)result {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    
    [headers setObject:[NSString stringWithFormat:@"%ld", (long)result.limit] 
                forKey:@"X-RateLimit-Limit"];
    [headers setObject:[NSString stringWithFormat:@"%ld", (long)result.remaining] 
                forKey:@"X-RateLimit-Remaining"];
    [headers setObject:[NSString stringWithFormat:@"%.0f", result.resetSeconds] 
                forKey:@"X-RateLimit-Reset"];
    
    if (!result.allowed) {
        [headers setObject:[NSString stringWithFormat:@"%.0f", result.retryAfter] 
                    forKey:@"Retry-After"];
    }
    
    return [headers copy];
}
```

### Applying Headers to Response

```objc
- (void)applyRateLimitHeadersToResponse:(HttpResponse *)response
                                  forDid:(nullable NSString *)did
                                    ip:(nullable NSString *)ip {
    if (did) {
        NSDictionary *didHeaders = [self rateLimitHeadersForDid:did];
        [didHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [response setHeader:value forKey:(NSString *)key];
        }];
    }
    
    if (ip) {
        NSDictionary *ipHeaders = [self rateLimitHeadersForIP:ip];
        [ipHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [response setHeader:value forKey:(NSString *)key];
        }];
    }
}
```

## Database Schema

### Rate Limits Table

```sql
CREATE TABLE IF NOT EXISTS rate_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    identifier TEXT NOT NULL,
    type INTEGER NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    window_start INTEGER NOT NULL,
    UNIQUE(identifier, type)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_identifier 
    ON rate_limits(identifier);
```

**Fields:**
- `identifier` — DID or IP address
- `type` — RateLimitType enum (DID=0, IP=1, Blob=2, Custom=3)
- `request_count` — Number of requests in current window
- `window_start` — Unix timestamp of window start

### Blob Rate Limits Table

```sql
CREATE TABLE IF NOT EXISTS blob_rate_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    upload_count INTEGER NOT NULL DEFAULT 0,
    window_start INTEGER NOT NULL,
    UNIQUE(did)
);
```

## Thread Safety

Rate limiting is thread-safe through SQLite serialization:

```objc
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t dbQueue;

- (instancetype)initWithDatabasePath:(nullable NSString *)path {
    self = [super init];
    if (self) {
        _dbQueue = dispatch_queue_create("com.atproto.ratelimiter.db", 
                                         DISPATCH_QUEUE_SERIAL);
        // ... initialize database
    }
    return self;
}
```

All database operations are dispatched to the serial queue:

```objc
__block RateLimitResult *result;
dispatch_sync(self.dbQueue, ^{
    result = [self checkRateLimitInternalForIdentifier:did 
                                                  type:RateLimitTypeDID 
                                                 limit:self.didLimit 
                                          windowSeconds:self.didWindowSeconds];
});
return result;
```

## Custom Rate Limits

For specialized rate limiting needs:

```objc
- (RateLimitResult *)checkRateLimitForKey:(NSString *)key 
                                    limit:(NSInteger)limit 
                             windowSeconds:(NSTimeInterval)windowSeconds {
    if (!self.isEnabled) {
        return [RateLimitResult resultAllowed:YES 
                                        limit:limit 
                                    remaining:limit 
                                  resetSeconds:0 
                                   retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkRateLimitInternalForIdentifier:key 
                                                      type:RateLimitTypeCustom 
                                                     limit:limit 
                                              windowSeconds:windowSeconds];
    });
    return result;
}
```

**Example Usage:**

```objc
// Rate limit password reset attempts
RateLimitResult *result = [[RateLimiter sharedLimiter] 
    checkRateLimitForKey:[NSString stringWithFormat:@"password_reset:%@", email]
                   limit:5
            windowSeconds:3600];
```

## Performance Considerations

### Database Location

Rate limits are stored in the service directory:

```objc
NSString *baseDir = config.dataPaths.serviceDirectory;
_databasePath = [baseDir stringByAppendingPathComponent:@"ratelimits.db"];
```

### Query Optimization

Queries use indexed lookups:

```sql
CREATE INDEX IF NOT EXISTS idx_rate_limits_identifier 
    ON rate_limits(identifier);
```

### Cleanup Strategy

Old entries are automatically cleaned by the sliding window query:

```sql
WHERE window_start > ?  -- Only queries recent windows
```

## Testing

**Example Test (from RateLimiterTests.m):**

```objc
- (void)testRateLimitDecrementsRemaining {
    RateLimitResult *result1 = [self.limiter checkRateLimitForDid:@"did:test:user2"];
    RateLimitResult *result2 = [self.limiter checkRateLimitForDid:@"did:test:user2"];

    XCTAssertTrue(result1.allowed, @"First request should be allowed");
    XCTAssertTrue(result2.allowed, @"Second request should be allowed");
    XCTAssertEqual(result2.remaining, result1.remaining - 1, 
                   @"Remaining should decrement by 1");
}
```

## Best Practices

1. **Enable in Production**
   - Always enable rate limiting in production
   - Use conservative limits initially
   - Monitor and adjust based on usage

2. **Different Limits for Different Resources**
   - API calls: Higher limits (5000/hour)
   - Blob uploads: Lower limits (50/hour)
   - Authentication: Very low limits (5/hour)

3. **Provide Clear Error Messages**
   - Include `Retry-After` header
   - Explain rate limit in error message
   - Document limits in API documentation

4. **Monitor Rate Limit Hits**
   - Log rate limit violations
   - Track which endpoints hit limits
   - Identify potential abuse patterns

5. **Graceful Degradation**
   - If rate limiter fails, allow requests
   - Log failures for investigation
   - Don't block legitimate traffic

## Common Patterns

### OAuth Endpoint Rate Limiting

**Implementation (from HttpServer.m):**

```objc
if ([request.path hasPrefix:@"/oauth/"] && 
    !RateLimiterIsDisabledGlobally() &&
    [RateLimiter sharedLimiter].isEnabled) {
    
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

### Combining DID and IP Limits

```objc
// Check both DID and IP limits
RateLimitResult *didResult = [[RateLimiter sharedLimiter] checkRateLimitForDid:did];
RateLimitResult *ipResult = [[RateLimiter sharedLimiter] checkRateLimitForIP:ip];

if (!didResult.allowed || !ipResult.allowed) {
    // Return 429 with appropriate headers
}
```

## See Also

- [DoS Protection](./dos-protection.md) — Attack mitigation strategies
- [Request Throttling](./request-throttling.md) — Per-endpoint throttling
- [Error Handling](./error-handling.md) — Error response patterns
- [HTTP Server](./http-server.md) — Server implementation
