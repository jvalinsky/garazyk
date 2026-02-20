# Rate Limiting and DoS Checklist

Use this checklist while validating candidates from `scan_dos.sh`.

## HTTP endpoints
- Verify rate limiting on all authentication endpoints.
- Verify rate limiting on expensive operations (search, sync).
- Add per-IP and per-account rate limits.
- Return 429 Too Many Requests with Retry-After header.
- Log rate limit violations for monitoring.

## WebSocket and streaming
- Verify message size limits on WebSocket messages.
- Implement backpressure (pause/resume) for slow consumers.
- Limit concurrent connections per client.
- Add heartbeat/keepalive timeout for idle connections.
- Close connections on protocol violations.

## Memory and collections
- Verify collection growth is bounded (max size checks).
- Validate array/dictionary sizes before extending.
- Use autorelease pools in tight loops.
- Release resources promptly after use.
- Check for retain cycles in blocks and delegates.

## File and blob operations
- Verify file size limits before reading into memory.
- Stream large files instead of loading entirely.
- Validate MIME types before processing.
- Check disk space before write operations.
- Clean up temporary files on error paths.

## Loops and recursion
- Verify all loops have explicit termination conditions.
- Add iteration counters with maximum limits.
- Prevent infinite recursion with depth limits.
- Handle exceptions/errors within loops properly.
- Avoid blocking operations in tight loops.

## Common fixes
```objc
// BAD: Unbounded loop
while (YES) {
  // process without break condition
}

// GOOD: Bounded with counter
NSUInteger iterations = 0;
const NSUInteger maxIterations = 10000;
while (iterations < maxIterations && shouldContinue) {
  iterations++;
  // process
}

// BAD: Unbounded collection
NSMutableArray *results = [NSMutableArray array];
for (id item in items) {
  [results addObject:item];  // Could grow unbounded
}

// GOOD: Bounded collection
NSMutableArray *results = [NSMutableArray array];
const NSUInteger maxResults = 1000;
for (id item in items) {
  if (results.count >= maxResults) break;
  [results addObject:item];
}
```

## Rate limiting patterns
```objc
// Per-IP rate limiting
- (BOOL)shouldAllowRequest:(NSString *)clientIP {
    NSString *key = [NSString stringWithFormat:@"rate:%@", clientIP];
    NSUInteger count = [self.rateStore increment:key ttl:60];
    return count <= MAX_REQUESTS_PER_MINUTE;
}

// Circuit breaker for external calls
- (void)callExternalService {
    if (self.circuitBreaker.isOpen) {
        if ([self.circuitBreaker shouldAttemptReset]) {
            // try one request
        } else {
            return [self failFast];
        }
    }
    // make call, update circuit breaker state
}
```
