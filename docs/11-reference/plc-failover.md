---
title: PLC Failover and Redundancy
---

# PLC Failover and Redundancy

This guide covers redundancy strategies and fallback mechanisms for PLC directory integration in September PDS.

## Overview

The PLC (Public Ledger of Credentials) directory is a critical dependency for DID resolution. September implements several strategies to maintain availability and reliability when interacting with PLC servers.

## Retry Policy

### Automatic Retry Logic

September uses `HttpRetryPolicy` to automatically retry transient failures when communicating with PLC servers:

```objective-c
@interface HttpRetryPolicy : NSObject

@property (nonatomic, assign) NSInteger maxRetries;           // default 3
@property (nonatomic, assign) NSTimeInterval initialDelay;    // default 0.5
@property (nonatomic, assign) double backoffMultiplier;       // default 2.0

- (HttpRetryResult *)evaluateStatusCode:(NSInteger)statusCode
                           networkError:(nullable NSError *)error
                          attemptNumber:(NSInteger)attempt;
@end
```

### Retry Behavior

The retry policy distinguishes between transient and permanent failures:

**Transient Failures (Retryable)**:
- Network errors (connection timeout, DNS failure, etc.)
- HTTP 5xx status codes (server errors)
- Retry with exponential backoff: `delay = initialDelay * (backoffMultiplier ^ attempt)`

**Permanent Failures (Not Retryable)**:
- HTTP 4xx status codes (client errors, including 404 Not Found)
- HTTP 3xx redirects (security: redirects are blocked)
- Invalid responses after max retries exhausted

### Example Retry Sequence

```

Attempt 0: Immediate request
  ↓ (500 Server Error)
Attempt 1: Retry after 0.5s
  ↓ (503 Service Unavailable)
Attempt 2: Retry after 1.0s
  ↓ (502 Bad Gateway)
Attempt 3: Retry after 2.0s
  ↓ (Still failing)
Final: Return error to caller
```

## Caching Strategy

### DID Document Cache

`DIDPLCResolver` maintains an in-memory cache to reduce PLC server load and improve resilience:

```objective-c
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *cache;

- (instancetype)initWithPlcUrl:(NSString *)url {
    // ...
    _cache = [[NSCache alloc] init];
    _cache.countLimit = 1000;  // Cache up to 1000 DID documents
    // ...
}
```

### Cache Behavior

1. **Cache Hit**: Return cached DID document immediately (no network request)
2. **Cache Miss**: Fetch from PLC server, cache on success
3. **Cache Eviction**: NSCache automatically evicts least-recently-used entries when limit reached

### Cache Limitations

- **No TTL**: Cached documents never expire (until evicted by LRU policy)
- **No Invalidation**: No mechanism to detect stale cached documents
- **Memory Only**: Cache is lost on process restart

**Production Consideration**: For long-running servers, consider implementing cache TTL or periodic refresh for frequently-accessed DIDs.

## Timeout Configuration

### Request Timeouts

```objective-c
@property (nonatomic, assign) NSTimeInterval timeout;  // default 5.0 seconds

- (instancetype)initWithPlcUrl:(NSString *)url {
    // ...
    _timeout = 5.0;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = _timeout;
    config.timeoutIntervalForResource = _timeout * 2;
    // ...
}
```

**Timeout Hierarchy**:
- `timeoutIntervalForRequest`: 5 seconds (per request attempt)
- `timeoutIntervalForResource`: 10 seconds (total time including retries)
- Synchronous wrapper timeout: 6 seconds (timeout + 1 second safety margin)

### Timeout Tuning

Adjust timeouts based on your deployment:

```objective-c
DIDPLCResolver *resolver = [[DIDPLCResolver alloc] initWithPlcUrl:@"https://plc.directory"];
resolver.timeout = 10.0;  // Increase for slow networks
```

**Trade-offs**:
- **Lower timeout**: Faster failure detection, more false positives on slow networks
- **Higher timeout**: Better reliability on slow networks, slower failure detection

## Redirect Prevention

### Security Measure

September blocks HTTP redirects to prevent potential security issues:

```objective-c
- (void)URLSession:(NSURLSession *)session 
              task:(NSURLSessionTask *)task 
willPerformHTTPRedirection:(NSHTTPURLResponse *)response 
        newRequest:(NSURLRequest *)request 
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(nil);  // Block all redirects
}
```

**Rationale**:
- Prevents redirect-based attacks (e.g., redirect to malicious PLC server)
- Ensures DID resolution always uses configured PLC URL
- Fails fast if PLC server attempts redirect

## Redundancy Strategies

### Multiple PLC Server Configuration

While September's `DIDPLCResolver` currently supports a single PLC URL, you can implement redundancy at the application level:

#### Strategy 1: Primary/Fallback Pattern

```objective-c
@interface RedundantPLCResolver : NSObject
@property (nonatomic, strong) DIDPLCResolver *primaryResolver;
@property (nonatomic, strong) DIDPLCResolver *fallbackResolver;
@end

@implementation RedundantPLCResolver

- (instancetype)init {
    self = [super init];
    if (self) {
        _primaryResolver = [[DIDPLCResolver alloc] 
            initWithPlcUrl:@"https://plc.directory"];
        _fallbackResolver = [[DIDPLCResolver alloc] 
            initWithPlcUrl:@"https://plc-backup.example.com"];
    }
    return self;
}

- (NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error {
    // Try primary first
    NSError *primaryError = nil;
    NSDictionary *doc = [self.primaryResolver resolveDID:did error:&primaryError];
    if (doc) return doc;
    
    // Fall back to secondary
    NSLog(@"Primary PLC failed: %@, trying fallback", primaryError);
    return [self.fallbackResolver resolveDID:did error:error];
}

@end
```

#### Strategy 2: Round-Robin Load Balancing

```objective-c
@interface LoadBalancedPLCResolver : NSObject
@property (nonatomic, strong) NSArray<DIDPLCResolver *> *resolvers;
@property (nonatomic, assign) NSUInteger currentIndex;
@end

@implementation LoadBalancedPLCResolver

- (instancetype)initWithUrls:(NSArray<NSString *> *)urls {
    self = [super init];
    if (self) {
        NSMutableArray *resolvers = [NSMutableArray array];
        for (NSString *url in urls) {
            [resolvers addObject:[[DIDPLCResolver alloc] initWithPlcUrl:url]];
        }
        _resolvers = [resolvers copy];
        _currentIndex = 0;
    }
    return self;
}

- (NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error {
    NSUInteger startIndex = self.currentIndex;
    
    do {
        DIDPLCResolver *resolver = self.resolvers[self.currentIndex];
        self.currentIndex = (self.currentIndex + 1) % self.resolvers.count;
        
        NSError *resolveError = nil;
        NSDictionary *doc = [resolver resolveDID:did error:&resolveError];
        if (doc) return doc;
        
        NSLog(@"PLC server %@ failed: %@", resolver.plcUrl, resolveError);
    } while (self.currentIndex != startIndex);
    
    if (error) {
        *error = [NSError errorWithDomain:@"com.atproto.plc.loadbalancer"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"All PLC servers failed"}];
    }
    return nil;
}

@end
```

### Infrastructure-Level Redundancy

For production deployments, consider infrastructure-level redundancy:

#### DNS-Based Failover

Configure multiple A/AAAA records for your PLC domain:

```

plc.example.com.  300  IN  A  203.0.113.10
plc.example.com.  300  IN  A  203.0.113.11
plc.example.com.  300  IN  A  203.0.113.12
```

The OS resolver will automatically try different IPs on connection failure.

#### Load Balancer with Health Checks

```

                    ┌─────────────────┐
                    │  Load Balancer  │
                    │  (HAProxy/nginx)│
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
         │ PLC #1  │    │ PLC #2  │    │ PLC #3  │
         │ (active)│    │ (active)│    │ (active)│
         └─────────┘    └─────────┘    └─────────┘
```

Health check configuration (HAProxy example):

```

backend plc_servers
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server plc1 10.0.1.10:3000 check inter 5s fall 3 rise 2
    server plc2 10.0.1.11:3000 check inter 5s fall 3 rise 2
    server plc3 10.0.1.12:3000 check inter 5s fall 3 rise 2
```

## Monitoring and Alerting

### Key Metrics to Monitor

1. **PLC Resolution Success Rate**
   ```objective-c
   // Track in PDSMetrics
   [metrics incrementCounter:@"plc.resolution.success"];
   [metrics incrementCounter:@"plc.resolution.failure"];
   ```text

2. **PLC Resolution Latency**
   ```objective-c
   NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
   NSDictionary *doc = [resolver resolveDID:did error:&error];
   NSTimeInterval duration = [NSDate timeIntervalSinceReferenceDate] - start;
   [metrics recordHistogram:@"plc.resolution.duration" value:duration];
   ```text

3. **Cache Hit Rate**
   ```objective-c
   [metrics incrementCounter:@"plc.cache.hit"];
   [metrics incrementCounter:@"plc.cache.miss"];
   ```text

4. **Retry Attempts**
   ```objective-c
   [metrics recordHistogram:@"plc.retry.attempts" value:attemptNumber];
   ```text

### Alert Thresholds

Configure alerts for:

- **High Failure Rate**: > 5% of PLC resolutions failing
- **High Latency**: P95 latency > 2 seconds
- **Low Cache Hit Rate**: < 80% cache hits (may indicate cache size too small)
- **Frequent Retries**: > 20% of requests requiring retries

## Graceful Degradation

### Handling PLC Unavailability

When PLC is unavailable, consider these degradation strategies:

#### 1. Serve Cached Data with Warning

```objective-c
- (NSDictionary *)resolveDIDWithGracefulDegradation:(NSString *)did 
                                              error:(NSError **)error 
                                              stale:(BOOL *)isStale {
    // Try fresh resolution
    NSError *resolveError = nil;
    NSDictionary *doc = [self.resolver resolveDID:did error:&resolveError];
    if (doc) {
        if (isStale) *isStale = NO;
        return doc;
    }
    
    // Check cache for stale data
    NSDictionary *cached = [self.staleCache objectForKey:did];
    if (cached) {
        NSLog(@"PLC unavailable, serving stale cached DID document for %@", did);
        if (isStale) *isStale = YES;
        return cached;
    }
    
    if (error) *error = resolveError;
    return nil;
}
```

#### 2. Accept did:web as Fallback

```objective-c
- (NSDictionary *)resolveDIDWithWebFallback:(NSString *)did error:(NSError **)error {
    if ([did hasPrefix:@"did:plc:"]) {
        NSDictionary *doc = [self.plcResolver resolveDID:did error:error];
        if (doc) return doc;
        
        // PLC failed, check if user has did:web alternative
        NSString *webDID = [self lookupWebDIDForPLCDID:did];
        if (webDID) {
            NSLog(@"PLC unavailable, using did:web alternative: %@", webDID);
            return [self.webResolver resolveDID:webDID error:error];
        }
    }
    return nil;
}
```

#### 3. Reject New Operations, Allow Cached

```objective-c
- (BOOL)shouldAllowOperationDuringPLCOutage:(NSString *)operation did:(NSString *)did {
    // Allow operations for known DIDs (in cache)
    if ([self.cache objectForKey:did]) {
        return YES;
    }
    
    // Reject operations requiring fresh DID resolution
    NSLog(@"Rejecting %@ for unknown DID %@ during PLC outage", operation, did);
    return NO;
}
```

## Configuration Best Practices

### Production Configuration

```json
{
  "plc": {
    "url": "https://plc.directory",
    "timeout": 5.0,
    "cache_size": 10000,
    "retry_max_attempts": 3,
    "retry_initial_delay": 0.5,
    "retry_backoff_multiplier": 2.0
  }
}
```

### Development/Testing Configuration

```json
{
  "plc": {
    "url": "http://localhost:2582",
    "timeout": 10.0,
    "cache_size": 100,
    "retry_max_attempts": 1,
    "retry_initial_delay": 0.1,
    "retry_backoff_multiplier": 1.0
  }
}
```

### Mock PLC for Testing

For integration tests, use September's built-in PLC server (campagnola):

```bash
# Start mock PLC server
./build/bin/campagnola --port 2582 --data-dir ./test-plc-data

# Configure PDS to use mock
export PLC_URL="http://localhost:2582"
./build/bin/kaszlak serve
```

## Troubleshooting

### Common Issues

#### Issue: High PLC Resolution Latency

**Symptoms**: Slow DID resolution, timeouts

**Diagnosis**:
```bash
# Test PLC server directly
time curl -H "Accept: application/json" \
  https://plc.directory/did:plc:z72i7hdynmk6r22z27h6tvur

# Check network path
traceroute plc.directory
```

**Solutions**:
- Increase timeout if network is slow but reliable
- Deploy PLC server closer to PDS (same region/datacenter)
- Increase cache size to reduce PLC requests

## Issue: Frequent Cache Misses

**Symptoms**: High PLC request rate, poor performance

**Diagnosis**:
```objective-c
// Log cache statistics
NSLog(@"Cache count: %lu / %lu", 
      (unsigned long)self.cache.count, 
      (unsigned long)self.cache.countLimit);
```

**Solutions**:
- Increase cache size: `cache.countLimit = 10000`
- Implement persistent cache (Redis, SQLite)
- Pre-warm cache with frequently-accessed DIDs

### Issue: PLC Server Unreachable

**Symptoms**: All resolutions failing, network errors

**Diagnosis**:
```bash
# Check DNS resolution
dig plc.directory

# Check connectivity
curl -v https://plc.directory/health

# Check from PDS server
docker exec nspds curl -v https://plc.directory/health
```

**Solutions**:
- Verify DNS configuration
- Check firewall rules
- Verify TLS certificates
- Implement fallback PLC server

## Related Documentation

- [PLC Directory Concepts](../02-core-concepts/plc-directory)
- [PLC Server Operations](plc-server-operations)
- [DID Document Updates](../02-core-concepts/did-document-updates)
- [Monitoring and Metrics](metrics-collection)
- [Performance Monitoring](performance-monitoring)
