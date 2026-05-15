---
title: Request Throttling
---

# Request Throttling

Request throttling provides fine-grained control over specific operations, supplementing the broad protections offered by global rate limits. While global rate limiting prevents general server abuse, throttling protects resource-intensive endpoints or prevents specific types of data-entry bursts.

## Throttling vs. Rate Limiting

- **Rate Limiting**: Applied to broad categories (e.g., all authenticated API calls). Managed via `checkRateLimitForDid:` or `checkRateLimitForIP:`.
- **Request Throttling**: Applied to specific NSIDs or custom keys. Managed via `checkRateLimitForKey:limit:windowSeconds:`.

## The RateLimiter API

The `RateLimiter` class is the primary mechanism for all throttling in Garazyk. It uses a sliding-window algorithm backed by SQLite for persistence across server restarts.

### Custom Throttling
To throttle a specific action that doesn't fall into the standard categories, use a custom key:

```objc
// Throttle an expensive search operation to 10 calls per minute per user
NSString *throttleKey = [NSString stringWithFormat:@"search:%@", authenticatedDid];
RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForKey:throttleKey
                                                                      limit:10
                                                              windowSeconds:60];

if (!result.allowed) {
    // Deny request
}
```

## Implementation Patterns

### 1. Per-Method Throttling
Individual XRPC handlers can enforce their own limits. This is typically used for operations that involve heavy database writes or complex MST mutations.

### 2. Burst Protection
The sliding window naturally allows for bursts up to the defined limit at the start of a window, while enforcing the average rate over time. For more aggressive burst control, developers use shorter window durations (e.g., 5 requests per 10 seconds).

### 3. Resource-Based Throttling
Throttling can be tied to the size of the request. For example, the PDS might allow more frequent small record updates but throttle large batch operations (`applyWrites`) more strictly.

## Standard Throttled Operations

The PDS includes built-in throttling for:
- **Blob Uploads**: Managed via `checkBlobUploadRateLimitForDid:`.
- **Account Creation**: Strictly throttled by IP to prevent mass bot registration.
- **Session Refreshes**: Limited to prevent excessive JWT rotation.

## Configuration

Throttling behavior is controlled by properties on the `RateLimiter` instance:

- `didLimit`: Max authenticated requests per hour.
- `ipLimit`: Max unauthenticated requests per minute.
- `blobLimit`: Max blob uploads per hour.

Individual endpoint limits are currently hardcoded in their respective route packs or handlers to ensure they align with the resource costs of the implementation.

## Monitoring

Throttling events are recorded in `PDSMetrics`. Monitoring the `rejected_requests` metric can help administrators identify whether limits are too restrictive for legitimate users or if the PDS is under active attack.

## Related

- [DoS Protection](dos-protection)
- [Rate Limiting](rate-limiting)
- [RateLimiter.h](../../Garazyk/Sources/Network/RateLimiter.h)
