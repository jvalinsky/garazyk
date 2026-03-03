# Request Throttling

## Overview

Request throttling controls the rate at which specific operations can be performed, providing fine-grained control beyond basic rate limiting. While rate limiting applies broad limits (e.g., 5000 requests/hour), throttling applies targeted limits to specific endpoints, operations, or resource types.

## Throttling vs Rate Limiting

### Rate Limiting

- **Scope:** Broad (all API requests)
- **Granularity:** Coarse (per-user, per-IP)
- **Purpose:** Prevent abuse and resource exhaustion
- **Example:** 5000 requests/hour per DID

### Request Throttling

- **Scope:** Narrow (specific endpoints/operations)
- **Granularity:** Fine (per-endpoint, per-operation-type)
- **Purpose:** Protect expensive operations
- **Example:** 10 blob uploads/minute per DID

## Throttling Strategies

### 1. Per-Endpoint Throttling

Different endpoints have different resource costs. Expensive endpoints need stricter limits:

```objc
// In XrpcMethodRegistry.m - Endpoint-specific limits
@interface XrpcMethodRegistry ()
@property (nonatomic, strong) NSDictionary *endpointLimits;
@end

- (void)configureEndpointLimits {
    self.endpointLimits = @{
        // Expensive operations
        @"com.atproto.repo.uploadBlob": @{
            @"limit": @10,
            @"window": @60  // 10 uploads per minute
        },
        @"com.atproto.repo.createRecord": @{
            @"limit": @100,
            @"window": @60  // 100 creates per minute
        },
        @"com.atproto.sync.getRepo": @{
            @"limit": @5,
            @"window": @60  // 5 repo exports per minute
        },
        
        // Moderate operations
        @"com.atproto.repo.getRecord": @{
            @"limit": @500,
            @"window": @60  // 500 reads per minute
        },
        @"com.atproto.repo.listRecords": @{
            @"limit": @100,
            @"window": @60  // 100 lists per minute
        },
        
        // Lightweight operations
        @"com.atproto.server.getSession": @{
            @"limit": @1000,
            @"window": @60  // 1000 session checks per minute
        }
    };
}
```

### 2. Per-User Throttling

Different users may have different limits based on trust level or subscription tier:

```objc
// In UserThrottleManager.m - User-specific limits
@interface UserThrottleManager : NSObject
@property (nonatomic, strong) NSMutableDictionary *userTiers;
@end

- (NSDictionary *)getLimitsForDID:(NSString *)did {
    NSString *tier = [self getTierForDID:did];
    
    if ([tier isEqualToString:@"premium"]) {
        return @{
            @"blob_uploads": @{@"limit": @50, @"window": @60},
            @"record_creates": @{@"limit": @500, @"window": @60},
            @"api_requests": @{@"limit": @10000, @"window": @3600}
        };
    } else if ([tier isEqualToString:@"trusted"]) {
        return @{
            @"blob_uploads": @{@"limit": @20, @"window": @60},
            @"record_creates": @{@"limit": @200, @"window": @60},
            @"api_requests": @{@"limit": @7500, @"window": @3600}
        };
    } else {
        // Default tier
        return @{
            @"blob_uploads": @{@"limit": @10, @"window": @60},
            @"record_creates": @{@"limit": @100, @"window": @60},
            @"api_requests": @{@"limit": @5000, @"window": @3600}
        };
    }
}

- (NSString *)getTierForDID:(NSString *)did {
    // Check user tier from database
    NSString *tier = self.userTiers[did];
    return tier ?: @"default";
}
```

### 3. Global Throttling

System-wide limits to protect overall server capacity:

```objc
// In GlobalThrottleManager.m - System-wide limits
@interface GlobalThrottleManager : NSObject
@property (nonatomic, assign) NSUInteger maxConcurrentBlobUploads;
@property (nonatomic, assign) NSUInteger maxConcurrentRepoExports;
@property (nonatomic, assign) NSUInteger maxConcurrentDatabaseWrites;
@property (nonatomic, strong) dispatch_semaphore_t blobUploadSemaphore;
@property (nonatomic, strong) dispatch_semaphore_t repoExportSemaphore;
@property (nonatomic, strong) dispatch_semaphore_t databaseWriteSemaphore;
@end

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxConcurrentBlobUploads = 50;
        _maxConcurrentRepoExports = 10;
        _maxConcurrentDatabaseWrites = 100;
        
        _blobUploadSemaphore = dispatch_semaphore_create(_maxConcurrentBlobUploads);
        _repoExportSemaphore = dispatch_semaphore_create(_maxConcurrentRepoExports);
        _databaseWriteSemaphore = dispatch_semaphore_create(_maxConcurrentDatabaseWrites);
    }
    return self;
}

- (void)performBlobUpload:(void (^)(void))uploadBlock {
    // Wait for available slot
    dispatch_semaphore_wait(self.blobUploadSemaphore, DISPATCH_TIME_FOREVER);
    
    // Perform upload
    uploadBlock();
    
    // Release slot
    dispatch_semaphore_signal(self.blobUploadSemaphore);
}
```

## Implementation Patterns

### Pattern 1: Custom Rate Limiter

Use the RateLimiter's custom limit feature for endpoint-specific throttling:

```objc
// In XrpcRepoMethods.m - Blob upload throttling
- (void)handleUploadBlob:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Extract DID
    NSString *did = [self extractDIDFromRequest:request];
    if (!did) {
        response.statusCode = 401;
        return;
    }
    
    // 2. Check endpoint-specific throttle
    NSString *throttleKey = [NSString stringWithFormat:@"blob_upload:%@", did];
    RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForKey:throttleKey
                                                                          limit:10
                                                                  windowSeconds:60];
    
    if (!result.allowed) {
        response.statusCode = 429;
        [response setHeader:[NSString stringWithFormat:@"%.0f", result.retryAfter] 
                     forKey:@"Retry-After"];
        [response setJsonBody:@{
            @"error": @"RateLimitExceeded",
            @"message": @"Blob upload limit exceeded (10 per minute)"
        }];
        return;
    }
    
    // 3. Process upload
    [self processBlobUpload:request response:response];
}
```

### Pattern 2: Semaphore-Based Concurrency Control

Limit concurrent execution of expensive operations:

```objc
// In PDSRepositoryService.m - Concurrent export limit
@interface PDSRepositoryService ()
@property (nonatomic, strong) dispatch_semaphore_t exportSemaphore;
@end

- (instancetype)init {
    self = [super init];
    if (self) {
        _exportSemaphore = dispatch_semaphore_create(10);  // Max 10 concurrent exports
    }
    return self;
}

- (void)exportRepository:(NSString *)did
              completion:(void (^)(NSData *carData, NSError *error))completion {
    
    // 1. Wait for available slot (with timeout)
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC);
    long result = dispatch_semaphore_wait(self.exportSemaphore, timeout);
    
    if (result != 0) {
        // Timeout - too many concurrent exports
        NSError *error = [NSError errorWithDomain:@"RepositoryError"
                                             code:503
                                         userInfo:@{NSLocalizedDescriptionKey: @"Server busy, please retry"}];
        completion(nil, error);
        return;
    }
    
    // 2. Perform export
    [self performRepositoryExport:did completion:^(NSData *carData, NSError *error) {
        // 3. Release slot
        dispatch_semaphore_signal(self.exportSemaphore);
        
        // 4. Call completion
        completion(carData, error);
    }];
}
```

### Pattern 3: Token Bucket

Allow bursts while maintaining average rate:

```objc
// In TokenBucket.m - Token bucket throttling
@interface TokenBucket : NSObject
@property (nonatomic, assign) NSUInteger capacity;
@property (nonatomic, assign) NSUInteger tokens;
@property (nonatomic, assign) NSTimeInterval refillRate;
@property (nonatomic, strong) NSDate *lastRefill;
@property (nonatomic, strong) NSLock *lock;
@end

- (instancetype)initWithCapacity:(NSUInteger)capacity refillRate:(NSTimeInterval)refillRate {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _tokens = capacity;
        _refillRate = refillRate;
        _lastRefill = [NSDate date];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (BOOL)consumeTokens:(NSUInteger)count {
    [self.lock lock];
    
    // 1. Refill tokens based on elapsed time
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.lastRefill];
    NSUInteger tokensToAdd = (NSUInteger)(elapsed / self.refillRate);
    
    if (tokensToAdd > 0) {
        self.tokens = MIN(self.capacity, self.tokens + tokensToAdd);
        self.lastRefill = [NSDate date];
    }
    
    // 2. Check if enough tokens available
    if (self.tokens >= count) {
        self.tokens -= count;
        [self.lock unlock];
        return YES;
    }
    
    [self.lock unlock];
    return NO;
}

- (NSTimeInterval)timeUntilAvailable:(NSUInteger)count {
    [self.lock lock];
    
    if (self.tokens >= count) {
        [self.lock unlock];
        return 0;
    }
    
    NSUInteger tokensNeeded = count - self.tokens;
    NSTimeInterval timeNeeded = tokensNeeded * self.refillRate;
    
    [self.lock unlock];
    return timeNeeded;
}
```

**Usage:**

```objc
// In XrpcRepoMethods.m - Token bucket for record creation
@interface XrpcRepoMethods ()
@property (nonatomic, strong) NSMutableDictionary *userBuckets;
@end

- (void)handleCreateRecord:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *did = [self extractDIDFromRequest:request];
    
    // 1. Get or create token bucket for user
    TokenBucket *bucket = self.userBuckets[did];
    if (!bucket) {
        bucket = [[TokenBucket alloc] initWithCapacity:100 refillRate:0.6];  // 100 tokens, refill 1 per 0.6s
        self.userBuckets[did] = bucket;
    }
    
    // 2. Try to consume token
    if (![bucket consumeTokens:1]) {
        NSTimeInterval retryAfter = [bucket timeUntilAvailable:1];
        response.statusCode = 429;
        [response setHeader:[NSString stringWithFormat:@"%.0f", retryAfter] 
                     forKey:@"Retry-After"];
        [response setJsonBody:@{
            @"error": @"RateLimitExceeded",
            @"message": @"Record creation rate limit exceeded"
        }];
        return;
    }
    
    // 3. Process request
    [self processCreateRecord:request response:response];
}
```

## Endpoint-Specific Limits

### Blob Operations

```objc
// Blob upload throttling
@"com.atproto.repo.uploadBlob": @{
    @"limit": @10,           // 10 uploads
    @"window": @60,          // per minute
    @"cost": @"high",        // Resource cost
    @"global_limit": @50     // Max 50 concurrent uploads system-wide
}

// Blob download throttling
@"com.atproto.sync.getBlob": @{
    @"limit": @100,          // 100 downloads
    @"window": @60,          // per minute
    @"cost": @"medium",
    @"global_limit": @200
}
```

### Record Operations

```objc
// Record creation throttling
@"com.atproto.repo.createRecord": @{
    @"limit": @100,          // 100 creates
    @"window": @60,          // per minute
    @"cost": @"medium",
    @"burst_allowed": @YES   // Allow bursts
}

// Record deletion throttling
@"com.atproto.repo.deleteRecord": @{
    @"limit": @50,           // 50 deletes
    @"window": @60,          // per minute
    @"cost": @"medium"
}

// Batch operations throttling
@"com.atproto.repo.applyWrites": @{
    @"limit": @20,           // 20 batch operations
    @"window": @60,          // per minute
    @"cost": @"high",
    @"max_batch_size": @100  // Max 100 writes per batch
}
```

### Repository Operations

```objc
// Repository export throttling
@"com.atproto.sync.getRepo": @{
    @"limit": @5,            // 5 exports
    @"window": @60,          // per minute
    @"cost": @"very_high",
    @"global_limit": @10,    // Max 10 concurrent exports
    @"timeout": @300         // 5 minute timeout
}

// Repository checkout throttling
@"com.atproto.sync.getCheckout": @{
    @"limit": @10,
    @"window": @60,
    @"cost": @"high"
}
```

### Authentication Operations

```objc
// Session creation throttling
@"com.atproto.server.createSession": @{
    @"limit": @10,           // 10 logins
    @"window": @300,         // per 5 minutes
    @"cost": @"high",        // Expensive (crypto)
    @"lockout_threshold": @5 // Lock after 5 failures
}

// Token refresh throttling
@"com.atproto.server.refreshSession": @{
    @"limit": @100,
    @"window": @3600,        // per hour
    @"cost": @"medium"
}
```

### Search and List Operations

```objc
// Record listing throttling
@"com.atproto.repo.listRecords": @{
    @"limit": @100,
    @"window": @60,
    @"cost": @"medium",
    @"max_page_size": @100   // Max 100 records per page
}

// Feed generation throttling
@"app.bsky.feed.getFeedSkeleton": @{
    @"limit": @50,
    @"window": @60,
    @"cost": @"high",
    @"max_page_size": @50
}
```

## Adaptive Throttling

Adjust limits based on server load:

```objc
// In AdaptiveThrottleManager.m - Load-based throttling
@interface AdaptiveThrottleManager : NSObject
@property (nonatomic, assign) double cpuThreshold;
@property (nonatomic, assign) double memoryThreshold;
@property (nonatomic, assign) double baseMultiplier;
@end

- (double)getCurrentMultiplier {
    // 1. Get current resource usage
    double cpuUsage = [self getCurrentCPUUsage];
    double memoryUsage = [self getCurrentMemoryUsage];
    
    // 2. Calculate multiplier based on load
    double multiplier = self.baseMultiplier;
    
    if (cpuUsage > self.cpuThreshold) {
        multiplier *= (1.0 - (cpuUsage - self.cpuThreshold));
    }
    
    if (memoryUsage > self.memoryThreshold) {
        multiplier *= (1.0 - (memoryUsage - self.memoryThreshold));
    }
    
    // 3. Ensure minimum multiplier
    return MAX(0.1, multiplier);  // Never go below 10% of base rate
}

- (NSInteger)getAdjustedLimit:(NSInteger)baseLimit {
    double multiplier = [self getCurrentMultiplier];
    return (NSInteger)(baseLimit * multiplier);
}
```

**Usage:**

```objc
// In XrpcMethodRegistry.m - Apply adaptive throttling
- (BOOL)checkThrottle:(NSString *)endpoint forDID:(NSString *)did {
    NSDictionary *limits = self.endpointLimits[endpoint];
    NSInteger baseLimit = [limits[@"limit"] integerValue];
    NSTimeInterval window = [limits[@"window"] doubleValue];
    
    // 1. Get adjusted limit based on server load
    NSInteger adjustedLimit = [self.adaptiveThrottleManager getAdjustedLimit:baseLimit];
    
    // 2. Check throttle with adjusted limit
    NSString *throttleKey = [NSString stringWithFormat:@"%@:%@", endpoint, did];
    RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForKey:throttleKey
                                                                          limit:adjustedLimit
                                                                  windowSeconds:window];
    
    return result.allowed;
}
```

## Burst Handling

Allow short bursts while maintaining average rate:

```objc
// In BurstThrottleManager.m - Burst-aware throttling
@interface BurstThrottleManager : NSObject
@property (nonatomic, assign) NSInteger sustainedRate;
@property (nonatomic, assign) NSInteger burstRate;
@property (nonatomic, assign) NSTimeInterval burstWindow;
@end

- (BOOL)checkThrottle:(NSString *)key {
    // 1. Check burst limit (short window)
    RateLimitResult *burstResult = [[RateLimiter sharedLimiter] 
        checkRateLimitForKey:[NSString stringWithFormat:@"burst:%@", key]
                       limit:self.burstRate
               windowSeconds:self.burstWindow];
    
    if (!burstResult.allowed) {
        return NO;
    }
    
    // 2. Check sustained limit (long window)
    RateLimitResult *sustainedResult = [[RateLimiter sharedLimiter]
        checkRateLimitForKey:[NSString stringWithFormat:@"sustained:%@", key]
                       limit:self.sustainedRate
               windowSeconds:60];
    
    return sustainedResult.allowed;
}
```

**Example:**

```objc
// Allow bursts of 20 requests in 5 seconds, but only 100 per minute sustained
BurstThrottleManager *throttle = [[BurstThrottleManager alloc] init];
throttle.burstRate = 20;
throttle.burstWindow = 5;
throttle.sustainedRate = 100;
```

## Monitoring

### Throttle Metrics

```objc
// In ThrottleMetrics.m - Track throttling effectiveness
@interface ThrottleMetrics : NSObject
@property (nonatomic, strong) NSMutableDictionary *endpointMetrics;
@end

- (void)recordThrottle:(NSString *)endpoint allowed:(BOOL)allowed {
    NSMutableDictionary *metrics = self.endpointMetrics[endpoint];
    if (!metrics) {
        metrics = [@{
            @"total": @0,
            @"allowed": @0,
            @"throttled": @0
        } mutableCopy];
        self.endpointMetrics[endpoint] = metrics;
    }
    
    metrics[@"total"] = @([metrics[@"total"] integerValue] + 1);
    
    if (allowed) {
        metrics[@"allowed"] = @([metrics[@"allowed"] integerValue] + 1);
    } else {
        metrics[@"throttled"] = @([metrics[@"throttled"] integerValue] + 1);
    }
}

- (NSDictionary *)getMetricsForEndpoint:(NSString *)endpoint {
    NSDictionary *metrics = self.endpointMetrics[endpoint];
    if (!metrics) {
        return @{};
    }
    
    NSInteger total = [metrics[@"total"] integerValue];
    NSInteger throttled = [metrics[@"throttled"] integerValue];
    
    return @{
        @"total": metrics[@"total"],
        @"allowed": metrics[@"allowed"],
        @"throttled": metrics[@"throttled"],
        @"throttle_rate": @((double)throttled / total)
    };
}
```

## Configuration

### Throttle Configuration File

```json
{
  "throttling": {
    "enabled": true,
    "adaptive": true,
    "endpoints": {
      "com.atproto.repo.uploadBlob": {
        "limit": 10,
        "window": 60,
        "burst_limit": 20,
        "burst_window": 5,
        "global_limit": 50
      },
      "com.atproto.repo.createRecord": {
        "limit": 100,
        "window": 60,
        "burst_limit": 150,
        "burst_window": 10
      },
      "com.atproto.sync.getRepo": {
        "limit": 5,
        "window": 60,
        "global_limit": 10,
        "timeout": 300
      }
    },
    "user_tiers": {
      "default": {
        "multiplier": 1.0
      },
      "trusted": {
        "multiplier": 1.5
      },
      "premium": {
        "multiplier": 2.0
      }
    }
  }
}
```

## Best Practices

1. **Set appropriate limits** — Balance protection and usability
2. **Allow bursts** — Don't penalize legitimate spikes
3. **Monitor throttle rates** — Track how often limits are hit
4. **Adjust based on load** — Reduce limits when server is stressed
5. **Provide clear feedback** — Tell users why they're throttled
6. **Log throttle events** — Track patterns and adjust limits
7. **Test under load** — Verify throttling works as expected
8. **Document limits** — Make limits visible to developers
9. **Implement gracefully** — Degrade service, don't fail completely
10. **Review regularly** — Adjust limits based on usage patterns

## Next Steps

- **[Rate Limiting](./rate-limiting.md)** — Rate limiting strategies
- **[DoS Protection](./dos-protection.md)** — Attack mitigation
- **[Firehose Rate Limiting](../08-sync-firehose/firehose-rate-limiting.md)** — WebSocket throttling
