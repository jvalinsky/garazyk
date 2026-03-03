# Rate Limiting

## Overview

Rate limiting prevents abuse by restricting the number of requests a client can make within a time window. The PDS implements sliding window rate limiting with SQLite persistence, supporting multiple limit types:

- **DID-based API limits** — Per-user authenticated request limits
- **IP-based limits** — Per-IP unauthenticated request limits  
- **Blob upload limits** — Per-user blob upload limits
- **Custom limits** — Flexible limits for specific operations

## Why Rate Limiting?

Rate limiting protects the PDS from:

1. **Abuse** — Malicious actors overwhelming the server
2. **Resource exhaustion** — Excessive requests consuming CPU/memory/disk
3. **Denial of service** — Legitimate users unable to access the service
4. **Cost overruns** — Excessive bandwidth or compute costs
5. **Data scraping** — Automated harvesting of user data

## Rate Limiting Strategies

### 1. Fixed Window

Counts requests in fixed time windows (e.g., per minute, per hour).

**Pros:**
- Simple to implement
- Low memory overhead
- Easy to understand

**Cons:**
- Burst traffic at window boundaries
- Can allow 2x limit at boundary
- Not smooth rate enforcement

**Example:**
```
Window 1: 00:00-01:00 → 100 requests allowed
Window 2: 01:00-02:00 → 100 requests allowed

Problem: 100 requests at 00:59, 100 at 01:01 = 200 in 2 minutes
```

### 2. Sliding Window (Used by PDS)

Tracks request timestamps and counts requests within a rolling time window.

**Pros:**
- Smooth rate enforcement
- No boundary burst issues
- Accurate limit enforcement

**Cons:**
- Higher memory overhead
- More complex implementation
- Requires timestamp storage

**Example:**
```
Current time: 01:30
Window: Last 60 minutes (00:30-01:30)
Count: All requests with timestamp > 00:30
```

### 3. Token Bucket

Tokens added at fixed rate, consumed per request. Allows bursts up to bucket size.

**Pros:**
- Allows controlled bursts
- Smooth long-term rate
- Flexible configuration

**Cons:**
- Complex to implement
- Requires state management
- Harder to explain to users

### 4. Leaky Bucket

Requests queued and processed at fixed rate. Excess requests dropped.

**Pros:**
- Smooth output rate
- Predictable behavior
- Good for rate shaping

**Cons:**
- Adds latency (queuing)
- Complex implementation
- May drop valid requests

## PDS Implementation: Sliding Window

The PDS uses a sliding window algorithm with SQLite persistence:

```objc
// In RateLimiter.h
@interface RateLimiter : NSObject

/*! Maximum API requests per hour per DID (default: 5000) */
@property (nonatomic, assign) NSInteger didLimit;

/*! Time window for DID rate limiting in seconds (default: 3600) */
@property (nonatomic, assign) NSTimeInterval didWindowSeconds;

/*! Maximum API requests per minute per IP address (default: 100) */
@property (nonatomic, assign) NSInteger ipLimit;

/*! Time window for IP rate limiting in seconds (default: 60) */
@property (nonatomic, assign) NSTimeInterval ipWindowSeconds;

/*! Maximum blob uploads per hour per DID (default: 50) */
@property (nonatomic, assign) NSInteger blobLimit;

/*! Time window for blob upload limiting in seconds (default: 3600) */
@property (nonatomic, assign) NSTimeInterval blobWindowSeconds;

/*! Whether rate limiting is enabled (default: YES) */
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

@end
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.h` (lines 90-115)

## Algorithm Details

### Sliding Window Algorithm

```objc
// In RateLimiter.m - Core sliding window check
- (RateLimitResult *)checkRateLimitInternalForIdentifier:(NSString *)identifier
                                                     type:(RateLimitType)type
                                                    limit:(NSInteger)limit
                                              windowSeconds:(NSTimeInterval)windowSeconds {
    if (![self ensureDatabaseOpened]) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    
    // 1. Query current count within window
    NSString *selectSQL = @"SELECT request_count, window_start FROM rate_limits WHERE identifier = ? AND type = ? AND window_start > ?";
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(_db, selectSQL.UTF8String, -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    
    sqlite3_bind_text(stmt, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, type);
    sqlite3_bind_double(stmt, 3, windowStart);
    
    NSInteger requestCount = 0;
    NSTimeInterval existingWindowStart = 0;
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        requestCount = sqlite3_column_int(stmt, 0);
        existingWindowStart = sqlite3_column_double(stmt, 1);
    }
    
    // 2. Check if limit exceeded
    if (requestCount >= limit) {
        NSTimeInterval resetSeconds = (existingWindowStart + windowSeconds) - now;
        return [RateLimitResult resultAllowed:NO limit:limit remaining:0 resetSeconds:resetSeconds retryAfter:resetSeconds];
    }
    
    // 3. Increment count (UPSERT)
    NSString *upsertSQL = @"INSERT INTO rate_limits (identifier, type, request_count, window_start) "
                          @"VALUES (?, ?, ?, ?) "
                          @"ON CONFLICT(identifier, type) DO UPDATE SET "
                          @"request_count = CASE WHEN window_start > ? THEN request_count + 1 ELSE 1 END, "
                          @"window_start = CASE WHEN window_start > ? THEN window_start ELSE ? END";
    
    // ... (execute upsert)
    
    return [RateLimitResult resultAllowed:YES
                                    limit:limit
                                remaining:(limit - requestCount - 1)
                              resetSeconds:windowSeconds
                               retryAfter:0];
}
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 210-270)

### Database Schema

```sql
-- Rate limits table
CREATE TABLE IF NOT EXISTS rate_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    identifier TEXT NOT NULL,
    type INTEGER NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    window_start INTEGER NOT NULL,
    UNIQUE(identifier, type)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_identifier ON rate_limits(identifier);

-- Blob rate limits table
CREATE TABLE IF NOT EXISTS blob_rate_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    upload_count INTEGER NOT NULL DEFAULT 0,
    window_start INTEGER NOT NULL,
    UNIQUE(did)
);
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 118-150)

## Rate Limit Types

### 1. DID-Based API Limits

Applied to authenticated XRPC requests:

```objc
// In RateLimiter.m
- (RateLimitResult *)checkRateLimitForDid:(NSString *)did {
    if (!self.isEnabled) {
        return [RateLimitResult resultAllowed:YES limit:self.didLimit remaining:self.didLimit resetSeconds:0 retryAfter:0];
    }
    if (!did || did.length == 0) {
        return [RateLimitResult resultAllowed:YES limit:self.didLimit remaining:self.didLimit resetSeconds:0 retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkRateLimitInternalForIdentifier:did type:RateLimitTypeDID limit:self.didLimit windowSeconds:self.didWindowSeconds];
    });
    return result;
}
```

**Default:** 5000 requests/hour per DID

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 154-168)

### 2. IP-Based Limits

Applied to unauthenticated requests (e.g., OAuth endpoints):

```objc
// In HttpServer.m - OAuth endpoint rate limiting
if ([request.path hasPrefix:@"/oauth/"] && !RateLimiterIsDisabledGlobally() &&
    [RateLimiter sharedLimiter].isEnabled) {
  RateLimitResult *result =
      [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];

  if (!result.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
      @"error" : @"too_many_requests",
      @"message" : @"Rate limit exceeded"
    }];
    return response;
  }
}
```

**Default:** 100 requests/minute per IP

**Source:** `ATProtoPDS/Sources/Network/HttpServer.m` (lines 994-1005)

### 3. Blob Upload Limits

Applied to blob upload operations:

```objc
// In RateLimiter.m
- (RateLimitResult *)checkBlobUploadRateLimitForDid:(NSString *)did {
    if (!self.isEnabled) {
        return [RateLimitResult resultAllowed:YES limit:self.blobLimit remaining:self.blobLimit resetSeconds:0 retryAfter:0];
    }
    if (!did || did.length == 0) {
        return [RateLimitResult resultAllowed:YES limit:self.blobLimit remaining:self.blobLimit resetSeconds:0 retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkBlobRateLimitInternalForDid:did limit:self.blobLimit windowSeconds:self.blobWindowSeconds];
    });
    return result;
}
```

**Default:** 50 uploads/hour per DID

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 190-203)

### 4. Custom Limits

Flexible limits for specific operations:

```objc
// In RateLimiter.m
- (RateLimitResult *)checkRateLimitForKey:(NSString *)key 
                                    limit:(NSInteger)limit 
                            windowSeconds:(NSTimeInterval)windowSeconds {
    if (!self.isEnabled) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    if (!key || key.length == 0) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkRateLimitInternalForIdentifier:key type:RateLimitTypeCustom limit:limit windowSeconds:windowSeconds];
    });
    return result;
}
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 205-220)

## Configuration

### Initialization

```objc
// In RateLimiter.m
- (instancetype)initWithDatabasePath:(nullable NSString *)path {
    self = [super init];
    if (self) {
        _didLimit = 5000;
        _didWindowSeconds = 3600;
        _ipLimit = 100;
        _ipWindowSeconds = 60;
        _blobLimit = 50;
        _blobWindowSeconds = 3600;
        _enabled = !_rateLimiterDisabledGlobally;
        
        _dbQueue = dispatch_queue_create("com.atproto.ratelimiter.db", DISPATCH_QUEUE_SERIAL);
        
        if (path) {
            _databasePath = [path copy];
        } else {
            _databasePath = nil; // Will be determined on-demand
        }
    }
    return self;
}
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 68-90)

### Customizing Limits

```objc
// Example: Increase DID limit for premium users
RateLimiter *limiter = [[RateLimiter alloc] initWithDatabasePath:@"rate_limits.db"];
limiter.didLimit = 10000;  // 10k requests/hour
limiter.didWindowSeconds = 3600;

// Example: Stricter IP limits
limiter.ipLimit = 50;  // 50 requests/minute
limiter.ipWindowSeconds = 60;

// Example: More generous blob limits
limiter.blobLimit = 100;  // 100 uploads/hour
limiter.blobWindowSeconds = 3600;
```

### Global Disable (Development)

```objc
// In RateLimiter.m
#ifdef DEBUG
static BOOL _rateLimiterDisabledGlobally = YES;
#else
static BOOL _rateLimiterDisabledGlobally = NO;
#endif

void RateLimiterSetDisabledGlobally(BOOL disabled) {
    _rateLimiterDisabledGlobally = disabled;
}

BOOL RateLimiterIsDisabledGlobally(void) {
    return _rateLimiterDisabledGlobally;
}
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 12-25)

## HTTP Headers

### X-RateLimit-* Headers

The PDS returns standard rate limit headers per RFC 6585:

```objc
// In RateLimiter.m
- (NSDictionary<NSString *, NSString *> *)headersFromResult:(RateLimitResult *)result {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    
    [headers setObject:[NSString stringWithFormat:@"%ld", (long)result.limit] forKey:@"X-RateLimit-Limit"];
    [headers setObject:[NSString stringWithFormat:@"%ld", (long)result.remaining] forKey:@"X-RateLimit-Remaining"];
    [headers setObject:[NSString stringWithFormat:@"%.0f", result.resetSeconds] forKey:@"X-RateLimit-Reset"];
    
    if (!result.allowed) {
        [headers setObject:[NSString stringWithFormat:@"%.0f", result.retryAfter] forKey:@"Retry-After"];
    }
    
    return [headers copy];
}
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 450-465)

### Header Examples

**Successful request:**
```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 4999
X-RateLimit-Reset: 3600
```

**Rate limit exceeded:**
```http
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1234
Retry-After: 1234
Content-Type: application/json

{
  "error": "too_many_requests",
  "message": "Rate limit exceeded"
}
```

## Thread Safety

The RateLimiter is thread-safe through SQLite serialization:

```objc
// In RateLimiter.m
@interface RateLimiter ()
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t dbQueue;
@end

@implementation RateLimiter

- (instancetype)initWithDatabasePath:(nullable NSString *)path {
    // ...
    _dbQueue = dispatch_queue_create("com.atproto.ratelimiter.db", DISPATCH_QUEUE_SERIAL);
    // ...
}

- (RateLimitResult *)checkRateLimitForDid:(NSString *)did {
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkRateLimitInternalForIdentifier:did type:RateLimitTypeDID limit:self.didLimit windowSeconds:self.didWindowSeconds];
    });
    return result;
}
```

All database operations are serialized through `dbQueue`, ensuring thread-safe access.

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 45-50, 154-168)

## Performance Considerations

### Database Persistence

Rate limits are persisted to SQLite, surviving server restarts:

```objc
// In RateLimiter.m
- (BOOL)ensureDatabaseOpened {
    if (_db) return YES;
    
    if (!_databasePath) {
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        NSString *baseDir = config ? config.dataPaths.serviceDirectory
                                   : [PDSDataPaths pathsForBaseDirectory:[PDSConfiguration defaultDataDirectory]].serviceDirectory;
        [[NSFileManager defaultManager] createDirectoryAtPath:baseDir withIntermediateDirectories:YES attributes:nil error:nil];
        _databasePath = [baseDir stringByAppendingPathComponent:@"ratelimits.db"];
    }
    
    [self initializeDatabase];
    return _db != NULL;
}
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 92-106)

### Index Optimization

```sql
CREATE INDEX IF NOT EXISTS idx_rate_limits_identifier ON rate_limits(identifier);
```

The index on `identifier` ensures fast lookups for rate limit checks.

### Memory Overhead

- **Per identifier:** ~100 bytes (identifier + metadata)
- **1000 active users:** ~100 KB
- **10,000 active users:** ~1 MB

Minimal memory footprint due to SQLite storage.

## Best Practices

1. **Set appropriate limits** — Balance protection and usability
2. **Monitor rate limit hits** — Track 429 responses
3. **Provide clear error messages** — Include retry-after information
4. **Use different limits per resource** — API vs blobs vs auth
5. **Consider user tiers** — Premium users may need higher limits
6. **Test under load** — Verify limits work as expected
7. **Log rate limit events** — Track abuse patterns
8. **Implement gradual backoff** — Increase limits for trusted users

## Monitoring

### Metrics to Track

```objc
// Example metrics collection
@interface RateLimiterMetrics : NSObject
@property (nonatomic, assign) NSUInteger totalRequests;
@property (nonatomic, assign) NSUInteger rateLimitedRequests;
@property (nonatomic, assign) NSUInteger uniqueIdentifiers;
@property (nonatomic, strong) NSMutableDictionary *limitsByType;
@end

- (void)recordRateLimitCheck:(RateLimitResult *)result type:(RateLimitType)type {
    self.totalRequests++;
    if (!result.allowed) {
        self.rateLimitedRequests++;
    }
    
    NSString *typeKey = [self keyForType:type];
    NSNumber *count = self.limitsByType[typeKey] ?: @0;
    self.limitsByType[typeKey] = @(count.integerValue + 1);
}
```

### Key Metrics

- **Rate limit hit rate** — Percentage of requests rate limited
- **Unique identifiers** — Number of distinct users/IPs
- **Limits by type** — DID vs IP vs blob distribution
- **Reset time distribution** — When limits reset
- **Retry-after compliance** — Do clients respect retry-after?

## Next Steps

- **[DoS Protection](./dos-protection)** — Attack mitigation strategies
- **[Request Throttling](./request-throttling)** — Per-endpoint throttling
- **[Error Handling](./error-handling)** — Standardized error responses
