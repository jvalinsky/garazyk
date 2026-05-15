---
title: DoS Protection
---

# DoS Protection

Garazyk protects the PDS from Denial of Service (DoS) attacks through multiple layers of defense, ranging from protocol-level constraints to application-level rate limiting.

## Network and Transport Limits

The PDS enforces hard limits on the HTTP transport layer to prevent resource exhaustion from malformed or excessive requests.

### 1. Connection and Concurrency
Located in `HttpServer.m`:
- **Max Concurrent Requests**: The server uses a global semaphore (`_concurrencySemaphore`) to limit active request processing to **64** concurrent operations. Requests exceeding this limit wait in the dispatch queue.
- **Active Connection Tracking**: The server monitors total active connections and reports them via `PDSMetrics`.

### 2. Request Size Constraints
- **Header Size**: Limited to **16 KB** (`kHttpMaxHeaderBytes`). Requests with larger headers are rejected early in the parsing phase.
- **Body Size**: The default maximum request body size is **50 MB** (`kHttpMaxBodyBytes`). Individual XRPC methods may enforce stricter limits (e.g., blob uploads vs. record creation).

### 3. Timeouts
- **Header Timeout**: The server enforces a **5.0 second** timeout (`kHttpHeaderTimeout`) for receiving the complete set of HTTP headers. This protects against Slowloris-style attacks where a client sends headers extremely slowly to keep connections open.

## Rate Limiting

The `RateLimiter` provides sliding-window protection using a persistent SQLite backend.

### Standard Limits
- **DID-based (Authenticated)**: 5,000 requests per hour per DID by default.
- **IP-based (Unauthenticated)**: 100 requests per minute per IP address.
- **Blob Uploads**: 50 uploads per hour per DID.

### Rate Limit Implementation
Handlers check limits before performing expensive operations. For example, in authenticated XRPC handlers:

```objc
RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForDid:authenticatedDid];
if (!result.allowed) {
    // Return 429 Too Many Requests with Retry-After header
}
```

The system automatically applies `X-RateLimit-*` headers to responses using `[limiter applyRateLimitHeadersToResponse:forDid:ip:]`.

## Application-Level Protection

### WebSocket Backpressure
The Firehose and other WebSocket streams use `WebSocketProtocolSession` to monitor outbound buffer sizes. If a client cannot consume data fast enough, the PDS triggers backpressure, eventually dropping the connection if the buffer exceeds safety thresholds.

### Database Safety
The database layer uses SQLite's `busy_timeout` and WAL mode to ensure that long-running queries do not block the entire system. MST operations are constrained by depth and node count to prevent computational exhaustion.

## External Defense (Reverse Proxy)

In production environments, it is recommended to run Garazyk behind a reverse proxy like Nginx or a cloud load balancer. This provides an additional layer for:
- IP-based connection limiting (`limit_conn`).
- High-volume request throttling (`limit_req`).
- SSL/TLS termination.
- Buffering slow clients before they reach the PDS application.

## Next Steps

- **[Rate Limiting](rate-limiting)**: Details on sliding window configuration.
- **[Request Throttling](request-throttling)**: Per-endpoint custom limits.
- **[Input Validation](input-validation)**: Hardening the PDS against malformed payloads.

## Related

- [HTTP Server implementation](../../Garazyk/Sources/Network/HttpServer.m)
- [Rate Limiter implementation](../../Garazyk/Sources/Network/RateLimiter.m)
