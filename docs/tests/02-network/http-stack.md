# HTTP Stack Tests

Tests for HTTP server implementation, routing, request/response handling, and streaming.

## Test Classes

### HttpServerTests
**File:** `Tests/Network/HttpServerTests.m`

**Purpose:** HTTP server lifecycle, listener integration, and chunked streaming.

#### How It Works

**Method swizzling** injects fake listeners for controlled testing:

```objc
// Swizzle factory to return fake listener
static PDSNetworkListener *fakeListener;
PDSNetworkTransportFactory originalFactory = PDSNetworkTransportFactoryCreateListener(^(uint16_t port) {
    return fakeListener;
});

// Test listener failure scenarios
fakeListener = nil; // Factory returns nil
BOOL started = [server startWithError:&error];
XCTAssertFalse(started);
XCTAssertEqual(error.code, -1);
```

**Fake objects** implement listener/connection protocols:

```objc
@interface PDSFakeListener : NSObject <PDSNetworkListener>
@property (nonatomic, assign) PDSListenerState state;
@property (nonatomic, copy) void (^onReady)(void);
@end

@implementation PDSFakeListener
- (void)startWithQueue:(dispatch_queue_t)queue readyHandler:(void (^)(void))handler {
    self.onReady = handler;
    if (self.state == PDSListenerStateReady) {
        dispatch_async(queue, handler);
    }
}
@end
```

#### Why It Matters

| Feature | Why It's Critical |
|---------|-------------------|
| Listener failure handling | Server must report errors, not hang |
| Chunked transfer encoding | Required for CAR file streaming in ATProto sync |
| Chunk splitting policy | Prevents memory exhaustion from oversized payloads |

**Chunked encoding for CAR streaming:**

```objc
// CAR files can be large - stream them
[response setBodyChunkProducer:^NSData *(NSError **error) {
    // Yield blocks incrementally
    NSData *block = [carReader nextBlock];
    return block;
}];
```

| Method | What It Verifies |
|--------|------------------|
| `testStartFailsWhenListenerFactoryReturnsNil` | Error propagation |
| `testSendResponseStreamsChunkedProducerFrames` | Correct HTTP/1.1 chunked format |
| `testSendResponseSplitsOversizedProducerChunkByPolicy` | 64KB splitting |

---

### HttpRouterTests
**File:** `Tests/Network/HttpRouterTests.m`

**Purpose:** HTTP routing with exact matching, parameters, and wildcards.

#### How It Works

**Run-loop polling** waits for async handlers:

```objc
- (void)waitForHandlerInRouter:(HttpRouter *)router request:(HttpRequest *)request {
    __block BOOL handled = NO;
    [router handleRequest:request withHandler:^(HttpRequest *req, HttpResponse *res) {
        handled = YES;
    }];
    
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while (!handled && [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}
```

**Inline handler blocks** capture routing results:

```objc
__block NSDictionary *capturedParams = nil;
[router registerRoute:@"/users/:id" method:HttpMethodGET handler:^(HttpRequest *req, HttpResponse *res) {
    capturedParams = req.pathParams;
}];
// Test: capturedParams[@"id"] should equal expected value
```

#### Why It Matters

| Feature | Why It's Critical |
|---------|-------------------|
| Exact matching | Health checks, static endpoints |
| Parameterized routes | User-specific data (e.g., `/repos/:did`) |
| Wildcard routes | Static file serving (`/explore/*`) |
| Method enforcement | Prevents accidental data exposure |

**ATProto routing patterns:**

```
/xrpc/com.atproto.sync.getRepo        → GET, repo sync
/xrpc/com.atproto.repo.uploadBlob     → POST, blob upload
/xrpc/com.atproto.sync.subscribeRepos → WebSocket upgrade
```

| Method | What It Verifies |
|--------|------------------|
| `testExactMatchHandlesRequest` | `/health` matches |
| `testMethodMismatchReturnsNotFound` | Wrong method → 404 |
| `testParameterizedRouteAndExtraction` | `/users/:id` extracts params |
| `testWildcardRouteDeepPathMatch` | `/explore/css/style.css` matches `/explore/*` |

---

### HttpRouteTrieTests
**File:** `Tests/Network/HttpRouteTrieTests.m`

**Purpose:** Trie-based route data structure for O(k) matching.

#### How It Works

**Trie structure** enables efficient prefix matching:

```
Root
├── users/
│   ├── :id (parameter node)
│   │   └── posts/
│   │       └── * (wildcard)
│   └── me (exact node)
└── health (exact node)
```

**Concurrent access stress test:**

```objc
dispatch_apply(1000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
    [trie insert:@"test/path" value:handler];
    [trie lookup:@"test/path"]; // Thread-safe
});
```

| Method | What It Verifies |
|--------|------------------|
| `testBasicInsertionAndRetrieval` | Handler storage |
| `testParameterExtraction` | Dynamic params extracted |
| `testWildcardMatching` | Wildcards work |
| `testConcurrentAccess` | Thread safety |

---

### RateLimiterTests
**File:** `Tests/Network/RateLimiterTests.m`

**Purpose:** Token-bucket rate limiting for DIDs, IPs, and blob uploads.

#### How It Works

**SQLite-backed state** persists across requests:

```objc
RateLimiter *limiter = [[RateLimiter alloc] initWithDatabasePath:tempDBPath];

// Check and consume
RateLimitResult *result = [limiter checkLimitForDID:@"did:plc:abc" type:RateLimitTypeDID];
XCTAssertTrue(result.allowed);
XCTAssertEqual(result.remaining, 4999); // Decremented

// Generate headers
NSDictionary *headers = [limiter headersForDID:@"did:plc:abc" type:RateLimitTypeDID];
// X-RateLimit-Limit: 5000
// X-RateLimit-Remaining: 4999
// X-RateLimit-Reset: 1704067200
```

**Independent counters** per identifier and type:

```objc
[limiter checkLimitForDID:@"did:plc:alice" type:RateLimitTypeDID];
[limiter checkLimitForDID:@"did:plc:bob" type:RateLimitTypeDID];   // Separate counter
[limiter checkLimitForDID:@"did:plc:alice" type:RateLimitTypeBlob]; // Different type
```

#### Why It Matters

| Limit Type | Default | Purpose |
|------------|---------|---------|
| DID | 5000/hour | Per-user throttling |
| IP | 100/min | Unauthenticated flood protection |
| Blob | 50/hour | Storage exhaustion prevention |

| Method | What It Verifies |
|--------|------------------|
| `testDefaultLimitsTest` | Correct default values |
| `testRateLimitDecrementsRemaining` | Counter updates |
| `testDifferentIdentifiersIndependent` | Per-DID isolation |
| `testRateLimitHeadersForDID` | Header generation |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/HttpServerTests
./build/tests/AllTests -only-testing:AllTests/HttpRouterTests
./build/tests/AllTests -only-testing:AllTests/RateLimiterTests
```
