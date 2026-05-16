---
title: Network Transport Tests
---

# Network Transport Tests

Tests for network transport layer, SSL pinning, and rate limiting.

## Test Classes

### ATProtoNetworkTransportTests
**File:** `Tests/Network/ATProtoNetworkTransportTests.m`

**Purpose:** Linux network transport listener (skipped on macOS).

---

### ATProtoNetworkTransportLinuxTests
**File:** `Tests/Network/ATProtoNetworkTransportLinuxTests.m`

**Purpose:** Linux-specific socket operations using Unix socket pairs.

#### How It Works

**Socket pair for testing:**

```objc
int sv[2];
socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
int clientFd = sv[0];
int serverFd = sv[1];

// Test buffered read
ATProtoNetworkTransportLinux *transport = [[ATProtoNetworkTransportLinux alloc] initWithFd:serverFd];
NSData *data = [transport receiveWithTimeout:5.0 isComplete:&complete error:&error];
```

**Non-blocking connect:**

```objc
// Connect to localhost with non-blocking socket
int fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
connect(fd, (struct sockaddr *)&addr, sizeof(addr));
// Returns EINPROGRESS - connection in progress

// Wait for completion via dispatch source
dispatch_source_t writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, fd, 0, queue);
dispatch_source_set_event_handler(writeSource, ^{
    // Connection ready
});
```

#### Why It Matters

| Feature | Purpose |
|---------|---------|
| Non-blocking I/O | Prevents thread blocking |
| Buffered reads | Handles partial data |
| Cancellation | Graceful shutdown |

---

### SSLPinningTests
**File:** `Tests/Network/SSLPinningTests.m`

**Purpose:** SSL certificate pinning for secure server-to-server communication.

#### How It Works

```objc
SSLPinningManager *manager = [SSLPinningManager sharedManager];
[manager setPinningEnabled:YES];
[manager addPinnedKey:@"sha256/abc123..." forHost:@"bsky.social"];

// Create session with pinning
NSURLSession *session = [manager createSession];

// Challenge handler verifies pinned keys
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge {
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    if ([manager validateTrust:trust forHost:host]) {
        // Proceed
    } else {
        // Cancel
    }
}
```

#### Why It Matters

SSL pinning prevents MITM attacks by verifying server certificates against known public keys.

---

### RateLimiterTests
**File:** `Tests/Network/RateLimiterTests.m`

**Purpose:** Token-bucket rate limiting for DIDs, IPs, and blob uploads.

#### How It Works

**Token bucket algorithm:**

```objc
// Each bucket has:
// - capacity (max tokens)
// - tokens (current count)
// - refillRate (tokens per second)

RateLimiter *limiter = [[RateLimiter alloc] init];
RateLimitResult *result = [limiter checkLimitForDID:@"did:plc:abc" type:RateLimitTypeDID];

if (result.allowed) {
    // Token consumed
    // remaining = tokens - 1
}
```

**Header generation:**

```objc
NSDictionary *headers = @{
    @"X-RateLimit-Limit": @"5000",
    @"X-RateLimit-Remaining": @(result.remaining),
    @"X-RateLimit-Reset": @(result.resetTimestamp)
};
```

#### Why It Matters

| Type | Default | Purpose |
|------|---------|---------|
| DID | 5000/hr | Per-user throttling |
| IP | 100/min | Flood protection |
| Blob | 50/hr | Storage limits |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/RateLimiterTests
./build/tests/AllTests -only-testing:AllTests/SSLPinningTests
./build/tests/AllTests -only-testing:AllTests/ATProtoNetworkTransportLinuxTests
```

## Rate Limit Configuration

| Type | Default Limit | Window |
|------|---------------|--------|
| DID | 5000 | per hour |
| IP | 100 | per minute |
| Blob Upload | 50 | per hour |

## Response Headers

```

X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 4999
X-RateLimit-Reset: 1704067200
```

## Related Documentation

- [Folder README](README) - Network tests overview
- [Test Index](../README) - Main test documentation index
- [HTTP Stack Tests](http-stack) - HTTP server tests
- [WebSocket Tests](websocket) - WebSocket/firehose tests
- [SSRF Protection](../../security/SSRF_PROTECTION) - Network security
- [GNUstep Compatibility](../../plans/archive/GNUSTEP_COMPATIBILITY) - Linux porting
