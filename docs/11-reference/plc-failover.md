---
title: PLC Failover and Redundancy
---

# PLC Failover and Redundancy

Garazyk maintains DID resolution availability through retry policies, caching, and redundant infrastructure patterns.

## Retry Policy

The PDS uses `HttpRetryPolicy` to manage transient communication failures.

```objective-c
@interface HttpRetryPolicy : NSObject
@property (nonatomic, assign) NSInteger maxRetries;           // default 3
@property (nonatomic, assign) NSTimeInterval initialDelay;    // default 0.5
@property (nonatomic, assign) double backoffMultiplier;       // default 2.0
@end
```

### Classification

The policy separates failures into two categories:

- **Transient (Retryable)**: Network errors like timeouts or DNS failures, and HTTP 5xx status codes. Backoff follows the formula `delay = initialDelay * (backoffMultiplier ^ attempt)`.
- **Permanent (Terminal)**: HTTP 4xx status codes (including 404), redirects, and exhausted retry attempts.

## Caching Strategy

`DIDPLCResolver` uses an in-memory `NSCache` to improve resilience.

### Implementation

- **Cache Hit**: Returns the document immediately.
- **Cache Miss**: Fetches from the server and stores on success.
- **Eviction**: `NSCache` removes the least-recently-used entries when reaching the 1000-count limit.

### Constraints

Process restarts clear the cache. Cached documents do not have a TTL and only expire when evicted. Production environments with high DID churn may require persistent storage or TTL logic.

## Timeouts

The system defaults to 5 seconds per request attempt via `NSURLSessionConfiguration.timeoutIntervalForRequest`. The total resource timeout, including retries, is 10 seconds.

## Redirect Security

Garazyk blocks HTTP redirects to ensure resolution only uses the configured PLC URL and to prevent redirect-based attacks.

```objective-c
- (void)URLSession:(NSURLSession *)session 
              task:(NSURLSessionTask *)task 
willPerformHTTPRedirection:(NSHTTPURLResponse *)response 
        newRequest:(NSURLRequest *)request 
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(nil);
}
```

## Redundancy Patterns

`DIDPLCResolver` supports one URL. Implement multi-server logic by wrapping multiple resolvers or using infrastructure-level failover.

### Primary and Fallback Example

```objective-c
- (NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error {
    NSError *primaryError = nil;
    NSDictionary *doc = [self.primaryResolver resolveDID:did error:&primaryError];
    if (doc) return doc;
    return [self.fallbackResolver resolveDID:did error:error];
}
```

### Infrastructure Options

- **DNS Failover**: Configure multiple A/AAAA records for the PLC domain.
- **Load Balancing**: Use HAProxy or nginx with health checks pointing to `/_health`.

## Monitoring and Alerts

Track these metrics to ensure resolution health:

- `plc.resolution.success` and `plc.resolution.failure`
- `plc.resolution.duration` (P95 should stay below 2 seconds)
- `plc.cache.hit` and `plc.cache.miss`
- `plc.retry.attempts`

Alert if the failure rate exceeds 5% or the cache hit rate drops below 80%.

## Graceful Degradation

If the PLC server is unreachable:

1. Serve stale data from the cache with a warning.
2. Fall back to `did:web` if applicable.
3. Block operations requiring fresh resolution while allowing reads from cache.

## Troubleshooting

- **High Latency**: Test directly with `time curl -H "Accept: application/json" https://plc.directory/did:plc:...`
- **Connectivity**: Verify with `curl -v https://plc.directory/_health`.
- **Containers**: Inspect from inside the PDS container using `docker exec nspds curl -v https://plc.directory/_health`.

## Related Resources

- [PLC Directory Concepts](../02-core-concepts/plc-directory)
- [PLC Server Operations](./plc-server-operations)
- [DID Document Updates](../02-core-concepts/did-document-updates)
- [Performance Monitoring](./performance-monitoring)
- [Documentation Map](documentation-map.md)
