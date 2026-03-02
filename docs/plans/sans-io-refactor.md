# Sans-I/O Refactor Plan

## Executive Summary

Incrementally extract I/O-free protocol cores from `WebSocketConnection`, `HttpServer`, and the outbound HTTP clients (`DIDPLCResolver`, `FederationClient`, `HandleResolver`). The goal is deterministic testability and cross-platform consistency without a risky big-bang rewrite.

---

## Current Status: In Progress

As of 2026-03-01: Execution has begun with a bottom-up approach — simplest extractions first.

### Execution Order (milestones, each committed separately):
1. ✅ **Milestone 1: SSRFValidator (Phase 3.2)** — extract duplicated IP classification into `SSRFValidator`, update consumers, add tests. *Why: Removes duplicated code and makes critical SSRF logic testable without network constraints.*
2. ✅ **Milestone 2: HttpParsing (Phase 2.3)** — consolidate query params, URL decode, method enum into `HttpParsing`, update consumers. *Why: Unifies URL decoding to prevent bypasses and centralizes query param logic for easier fuzzing.*
3. ✅ **Milestone 3: HttpRetryPolicy (Phase 3.1)** — extract retry/backoff logic, wire into `DIDPLCResolver`. *Why: Separates business logic (when to retry) from the transport mechanism (NSURLSession), making backoffs deterministically testable.*
4. ⏳ **Milestone 4: WebSocketCodec (Phase 1.1)** — extract frame parser/serializer + characterization tests. *Why: Allows rigorous testing of websocket frame edge cases (e.g. fragmentation, masks) purely in memory to harden against malformed network packets.*
5. ✅ **Milestone 5: WebSocketHeartbeatPolicy (Phase 1.2)** — extract heartbeat state machine. *Why: Separates protocol state (ping/pong expectations) from actual timer dispatch, enabling simulated time tests.*
6. ⏳ **Milestone 6: Http1Parser + Http1PipelinePolicy (Phase 2.1, 2.2)** — extract HTTP parsing + pipeline policy. *Why: Moves HTTP parsing away from network sockets into a pure function (`feedData:`) to safely test partial reads and pipelining.*
7. 🔲 **Milestone 7: Rewiring (Phase 1.3, 2.4, 3.3)** — thin adapter layer for WebSocketConnection, HttpServer, outbound consumers. *Why: Plugs the pure logic back into the asynchronous I/O layer, completing the refactor while keeping the transport logic completely dumb.*

### Completed:
- Milestone 1: SSRFValidator (Phase 3.2)
- Milestone 2: HttpParsing (Phase 2.3)
- Milestone 3: HttpRetryPolicy (Phase 3.1)
- Phase 0.5 SSRF characterization tests
- Phase 0.4 Outbound retry/backoff characterization

### Verified (plan accurate as-is):
- `HttpChunkedBodyParser.m` (315 lines) is confirmed to be already Sans-I/O
- Duplicated SSRF logic exists at:
  - `FederationClient.m` L15-44 (`pds_isPrivateIPv4Address`, `pds_isPrivateIPv6Address`)
  - `HandleResolver.m` L522-585 (`-isPrivateIPv4Address:`, `-isPrivateIPv6Address:`)
- Duplicated query param parsing exists at:
  - `HttpServer.m` L1210 (`parseQueryParamsFromString:`)
  - `HttpRequest.m` (also has parse logic)
- Duplicated retry/backoff logic exists at:
  - `DIDPLCResolver.m` L115-158 (`executeRequest:retries:currentDelay:`)
  - `DIDPLCResolver.m` L249-283 (`executeRawRequest:...` - near-duplicate)

### Verified file line counts (2026-03-01):
- `WebSocketConnection.m`: 680 lines
- `HttpServer.m`: 1434 lines
- `FederationClient.m`: 442 lines (Sources/Federation/FederationClient.m)
- `HandleResolver.m`: 587 lines (Sources/Identity/HandleResolver.m)
- `DIDPLCResolver.m`: 333 lines (Sources/PLC/DIDPLCResolver.m)

### Parser Hardening Audit Findings (2026-02-28)

The parser hardening audit (`skills/objc-parser-hardening-audit`) identified significant concerns in the codebase that this sans-io refactor should address:

**Priority targets for extraction/hardening:**
- `Base58.h` - parse/decoder signals without bounds guards
- `CID.h` - parse/decoder signals without bounds guards  
- `RepoCommit.h` - parse/decoder signals without bounds guards

**Signal counts in scanned paths:**
- Parse/decoder signals: 63
- Risky memory/range signals: 231
- Bounds/length signals: 417
- Integer/conversion signals: 374

The HTTP and WebSocket parsers being extracted in Phases 1 & 2 are medium-risk for integer overflow and bounds issues. The sans-io refactor provides an opportunity to add proper bounds checking in the extracted codec classes.

### Additional Code Review Findings

**Existing HttpRequest parsing approach:**
- Uses `CFHTTPMessageRef` for header parsing in `HttpServer.m`
- Has its own `parseFromData:` method in `HttpRequest.m` (lines 308+) that handles request-line splitting
- Both approaches coexist; `Http1Parser` extraction should consolidate

**Reference: sans-io patterns:**
- See https://fasterthanli.me/articles/the-case-for-sans-io for foundational concepts
- Key insight: protocol logic should be testable without network I/O

---

## Current Architecture Inventory

### What we're working with

| File | Lines | Responsibilities | Coupling |
|------|-------|-----------------|----------|
| `HttpServer.m` | 1431 | Connection state, HTTP/1.1 parsing, body framing, keep-alive, pipelining, concurrency limit, response streaming, route dispatch, WebSocket upgrade, query parsing | Transport via `PDSNetworkConnection` protocol |
| `WebSocketConnection.m` | 679 | Frame parse/serialize, heartbeat timers, state machine, transport I/O, backpressure queue | Transport via `PDSNetworkConnection` protocol |
| `HttpRequest.m` | 482 | Request model, query parsing, method-to-enum, `parseFromData:` full-request parser, multipart parsing | None (value object with parsing) |
| `HttpChunkedBodyParser.m` | 315 | Chunked transfer-encoding state machine | **Already Sans-I/O** — pure `appendData:` → state → `parsedData` |
| `DIDPLCResolver.m` | 285 | DID resolution, retry/backoff (3 retries, 0.5s×2^n), caching, redirect rejection | `NSURLSession` |
| `FederationClient.m` | 442 | XRPC forwarding, SSRF validation, DID→PDS resolution, lexicon-based method detection | `NSURLSession`, `CFHost` |
| `HandleResolver.m` | 587 | Handle→DID resolution, HTTPS+DNS fallback, SSRF validation, caching, rate limiting | `NSURLSession`/`NSURLConnection`, `CFHost` |
| `EventFormatter.m` | 408 | Firehose event encode/decode | **Already Sans-I/O** — pure data transform |
| `PDSNetworkTransportLinux.m` | 800 | BSD socket transport for Linux/GNUstep | Pure transport (no protocol logic) |

### Existing Sans-I/O-ready components (no extraction needed)

- `HttpChunkedBodyParser` — state machine with `appendData:error:` / `isComplete` / `parsedData`
- `EventFormatter` — pure encode/decode, no I/O
- `HttpRouteTrie` — pure trie data structure
- `HttpBufferPool` — pure memory management

### Duplicated logic to consolidate

| Logic | Location A | Location B | Location C |
|-------|-----------|-----------|-----------|
| SSRF IPv4 classification | `Federation/FederationClient.m` L15-29 (`pds_isPrivateIPv4Address` static) | `Identity/HandleResolver.m` L522-547 (`-isPrivateIPv4Address:` instance) | — |
| SSRF IPv6 classification | `Federation/FederationClient.m` L32-44 (`pds_isPrivateIPv6Address` static) | `Identity/HandleResolver.m` L561-585 (`-isPrivateIPv6Address:` instance) | — |
| Query param parsing | `Network/HttpServer.m` L1208-1231 (`-parseQueryParamsFromString:`) | `Network/HttpRequest.m` L350-368 (`-parseQueryParams:`) | `Sync/WebSocketConnection.m` ~L60 (`-parseQueryParams:`) |
| HTTP method string→enum | `Network/HttpServer.m` L1240-1256 (`-httpMethodFromString:`) | `Network/HttpRequest.m` L370-380 (`-methodFromString:`) | — |
| Retry/backoff | `PLC/DIDPLCResolver.m` L115-158 (`executeRequest:retries:currentDelay:completion:`) | `PLC/DIDPLCResolver.m` L249-283 (`executeRawRequest:...` — near-copy) | `Federation/FederationClient.m` (no retry at all) |
| URL decode | `Network/HttpServer.m` L1233-1238 (`-urlDecode:`) | `Network/HttpRequest.m` (inline percent-decoding) | — |

---

## Phase 0: Characterization Tests (1–2 weeks, parallel with Phase 1)

**Goal:** Lock down current behavior so extractions don't regress silently.

### 0.1 WebSocket frame-level characterization

Current `WebSocketFrameParsingTests` calls `handleReceivedData:` directly on a `WebSocketConnection` — this is the right shape but coverage is thin.

**Add tests for:**
- Fragmented frames (FIN=0 continuation sequences)
- Masked client→server frames (4-byte XOR mask)
- Interleaved control frames during fragmentation (ping between text continuation frames)
- Close frame with 2-byte status code + UTF-8 reason
- Close frame with empty payload
- Oversized frame rejection (>16MB → code 1009)
- Ping/pong round-trip (verify pong echoes ping payload)
- Binary frame at each length boundary: 0, 125, 126, 127, 65535, 65536 bytes
- Partial frame delivery (feed `handleReceivedData:` in 1-byte increments)

**File:** `ATProtoPDS/Tests/Sync/WebSocketFrameCharacterizationTests.m`

### 0.2 WebSocket heartbeat/state characterization

**Add tests for:**
- Heartbeat fires after `heartbeatInterval` seconds
- Missing pong triggers close with code 1001 after `heartbeatTimeout`
- State transitions: Connecting → Connected → Closing → Closed
- Outbound queue backpressure: sending > `WS_MAX_PENDING_SEND_BYTES` triggers code 1009 close
- Close handshake: close frame sent, 5s timeout elapses, state moves to Closed
- Double-close is idempotent

**File:** `ATProtoPDS/Tests/Sync/WebSocketStateCharacterizationTests.m`

### 0.3 HTTP/1.1 connection lifecycle characterization

Current `HttpServerTests` has fake listener/connection infrastructure. Extend it.

**Add tests for:**
- Header timeout: headers not completed within 5s → connection cancelled
- Header size limit: >16KB headers → 413
- Body size limit: Content-Length > 50MB → 413
- Keep-alive: successful request, verify server reads next request
- Pipelining: send 2 requests in one buffer, verify both dispatched and responses ordered
- Pipelining limit: 5th pipelined request is queued (max 4 concurrent)
- Transfer-Encoding + Content-Length both present → 400
- Chunked body: valid chunked encoding parsed correctly
- Chunked body: malformed chunk → 400
- POST/PUT/PATCH without Content-Length and without chunked → 411
- WebSocket upgrade: Upgrade header triggers `webSocketHandler`
- Output queue high-water mark: >10MB queued → oldest responses dropped
- Unsupported Transfer-Encoding → 501

**File:** `ATProtoPDS/Tests/Network/HttpConnectionCharacterizationTests.m`

### 0.4 Outbound retry/backoff characterization

**Add tests for `DIDPLCResolver`:**
- Retry on 500: verify 3 retries with exponential delay (0.5, 1.0, 2.0)
- Retry on network error: same behavior
- No retry on 404: returns `DIDPLCResolverErrorNotFound` immediately
- No retry on 400: returns `DIDPLCResolverErrorInvalidResponse` immediately
- Retry exhaustion: after 3 failures, returns last error
- Cache hit: second call for same DID returns cached doc without network request
- Redirect rejection: HTTP 3xx does not follow (delegate returns nil)

**File:** `ATProtoPDS/Tests/PLC/DIDPLCResolverCharacterizationTests.m`

### 0.5 SSRF characterization

**Add tests for the ip-classification logic directly (one test file, testing both implementations to confirm they agree):**
- 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16: YES
- 127.0.0.0/8: YES
- 169.254.0.0/16: YES
- 100.64.0.0/10 (CGNAT): YES
- TEST-NET ranges: YES
- 224.0.0.0/4, 240.0.0.0/4: YES
- Public IP (e.g. 8.8.8.8): NO
- IPv6 loopback, ULA, link-local: YES
- IPv4-mapped IPv6 with private IPv4: YES

**File:** `ATProtoPDS/Tests/Network/SSRFClassificationCharacterizationTests.m`

### 0.6 Parser Hardening Characterization

**Goal:** Capture current failure modes and performance of core parsers (`Base58`, `CID`, `RepoCommit`) to ensure hardening doesn't break valid inputs.

**Add tests for:**
- `Base58` decoder with max-length (64KB) string
- `Base58` decoder with invalid UTF-8 characters
- `CID` string parser with over-length (>256 chars) string
- `CID` varint reader with truncated buffers
- `RepoCommit` CAR decoder with malformed CBOR maps

**File:** `ATProtoPDS/Tests/Core/ParserHardeningCharacterizationTests.m`

---

## Phase 1: WebSocket Codec Core (2–3 weeks)

### 1.1 Create `WebSocketCodec` — pure frame parser/serializer

**New file:** `ATProtoPDS/Sources/Sync/WebSocketCodec.h`
**New file:** `ATProtoPDS/Sources/Sync/WebSocketCodec.m`

#### Interface design

```objc
// Event types emitted by the codec
typedef NS_ENUM(NSInteger, WSCodecEventType) {
    WSCodecEventTextMessage,
    WSCodecEventBinaryMessage,
    WSCodecEventPing,
    WSCodecEventPong,
    WSCodecEventClose,
    WSCodecEventProtocolError
};

@interface WSCodecEvent : NSObject
@property (nonatomic, readonly) WSCodecEventType type;
@property (nonatomic, readonly, nullable) NSData *payload;
@property (nonatomic, readonly) NSInteger closeCode;
@property (nonatomic, readonly, nullable) NSString *closeReason;
@property (nonatomic, readonly, nullable) NSString *text;
@end

@interface WebSocketCodec : NSObject

// Feed raw bytes in, get protocol events out
- (NSArray<WSCodecEvent *> *)feedData:(NSData *)data;

// Build outbound frames (no I/O, returns bytes to write)
- (NSData *)textFrame:(NSString *)text;
- (NSData *)binaryFrame:(NSData *)payload;
- (NSData *)pingFrame:(nullable NSData *)payload;
- (NSData *)pongFrame:(nullable NSData *)payload;
- (NSData *)closeFrame:(NSInteger)code reason:(nullable NSString *)reason;

// Codec configuration
@property (nonatomic, assign) uint64_t maxFrameSize; // default 16MB

@end
```

#### Extraction steps

1. Move frame constants (`WS_OPCODE_*`, `WS_FLAG_FIN`, `WS_MASK`, `WS_MAX_FRAME_SIZE`) into `WebSocketCodec.m`.
2. Extract `handleReceivedData:` parsing loop (L293–358) into `WebSocketCodec.feedData:`. Instead of calling `handleFrameWithOpcode:fin:payload:` which dispatches to delegate on main queue, return `WSCodecEvent` objects.
3. Extract `createFrameWithOpcode:payload:` (L564–594) into the frame builder methods.
4. Extract close-frame payload parsing (L392–411) into `WSCodecEvent` construction inside `feedData:`.
5. `WebSocketCodec` holds only a `readBuffer` (NSMutableData) and `maxFrameSize`. No dispatch queues, no timers, no delegate, no transport.

#### Verification

- All existing `WebSocketFrameParsingTests` must pass when rewritten to use `WebSocketCodec.feedData:` directly.
- All Phase 0.1 characterization tests must pass against `WebSocketCodec`.
- `WebSocketConnection` tests continue to pass because it delegates to `WebSocketCodec`.

### 1.2 Create `WebSocketHeartbeatPolicy` — pure heartbeat state machine

**New file:** `ATProtoPDS/Sources/Sync/WebSocketHeartbeatPolicy.h`
**New file:** `ATProtoPDS/Sources/Sync/WebSocketHeartbeatPolicy.m`

#### Interface design

```objc
typedef NS_ENUM(NSInteger, WSHeartbeatAction) {
    WSHeartbeatActionNone,
    WSHeartbeatActionSendPing,
    WSHeartbeatActionTimeout     // connection should be closed
};

@interface WebSocketHeartbeatPolicy : NSObject

@property (nonatomic, assign) NSTimeInterval heartbeatInterval;
@property (nonatomic, assign) NSTimeInterval heartbeatTimeout;

// Called by the adapter at regular intervals (e.g., timer tick)
- (WSHeartbeatAction)tick:(NSTimeInterval)now;

// Called when a pong is received
- (void)pongReceived:(NSTimeInterval)now;

// Called when a ping is sent
- (void)pingSent:(NSTimeInterval)now;

@end
```

#### Extraction steps

1. Move `waitingForPong`, `heartbeatInterval`, `heartbeatTimeout` tracking into `WebSocketHeartbeatPolicy`.
2. Replace `sendHeartbeat` / `handleHeartbeatTimeout` / `handlePongFrame:` in `WebSocketConnection` with calls to the policy.
3. `WebSocketConnection` retains timer creation/cancellation (those are I/O concerns), but the decision logic lives in the policy.

### 1.3 Rewire `WebSocketConnection` as thin adapter

After 1.1 and 1.2, `WebSocketConnection` becomes:
- Owns a `WebSocketCodec` and a `WebSocketHeartbeatPolicy`
- `handleReceivedData:` → calls `[codec feedData:]`, iterates events, dispatches to delegate
- `sendMessage:` / `sendText:` / `sendPing:` / `sendPong:` → calls codec frame builders, passes bytes to `writeData:`
- Timer fires → calls `[heartbeatPolicy tick:now]`, acts on result
- All transport I/O (`startReading`, `writeData:`, `flushWriteBuffer`) stays in `WebSocketConnection`
- State machine stays in `WebSocketConnection` (it couples to transport lifecycle)

**Estimated diff:** ~150 lines removed from `WebSocketConnection.m`, ~250 lines in new `WebSocketCodec.m`, ~60 lines in new `WebSocketHeartbeatPolicy.m`.

---

## Phase 2: HTTP/1.1 Connection Core (3–4 weeks)

### 2.1 Create `Http1Parser` — incremental HTTP/1.1 request parser

**New file:** `ATProtoPDS/Sources/Network/Http1Parser.h`
**New file:** `ATProtoPDS/Sources/Network/Http1Parser.m`

#### Interface design

```objc
typedef NS_ENUM(NSInteger, Http1ParserState) {
    Http1ParserStateReadingHeaders,
    Http1ParserStateReadingBody,
    Http1ParserStateReadingChunkedBody,
    Http1ParserStateComplete,
    Http1ParserStateError
};

@interface Http1ParseResult : NSObject
@property (nonatomic, readonly) NSString *method;
@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *queryString;
@property (nonatomic, readonly) NSString *version;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, readonly, nullable) NSData *body;
@end

@interface Http1ParserError : NSObject
@property (nonatomic, readonly) NSUInteger statusCode;  // e.g. 400, 411, 413, 501
@property (nonatomic, readonly) NSString *errorCode;    // e.g. "RequestTooLarge"
@property (nonatomic, readonly) NSString *message;
@end

@interface Http1Parser : NSObject

@property (nonatomic, readonly) Http1ParserState state;
@property (nonatomic, assign) NSUInteger maxHeaderBytes;  // default 16KB
@property (nonatomic, assign) NSUInteger maxBodyBytes;    // default 50MB
@property (nonatomic, assign) NSTimeInterval headerTimeout;

// Feed raw bytes. Returns YES if a complete request is available or an error occurred.
- (BOOL)feedData:(NSData *)data atTime:(NSTimeInterval)now;

// After feedData: returns YES, exactly one of these is non-nil:
- (nullable Http1ParseResult *)completedRequest;
- (nullable Http1ParserError *)parseError;

// Remaining bytes after the consumed request (for pipelining)
- (NSData *)unconsumedData;

// Reset for next request on same connection
- (void)reset;

@end
```

#### Extraction steps

1. Extract the header-parsing logic from `tryProcessRequestFromState:connection:` (L458–560) into `Http1Parser.feedData:atTime:`. This includes:
   - `\r\n\r\n` scan (`headerEndRangeInData:`)
   - Header size limit check
   - `CFHTTPMessage` append + header complete check
   - Content-Length extraction
   - Transfer-Encoding + Content-Length conflict detection
   - Chunked detection

2. Extract body-reading logic (L562–608) into `Http1Parser`:
   - Content-Length body accumulation
   - Chunked body parsing (delegates to existing `HttpChunkedBodyParser`)
   - Body size limit enforcement

3. Extract validation decisions:
   - POST/PUT/PATCH requiring Content-Length or chunked → 411
   - Unsupported Transfer-Encoding → 501

4. `Http1Parser` owns a `CFHTTPMessageRef` (create/release internally), an `NSMutableData` buffer, and optionally an `HttpChunkedBodyParser`. No dispatch queues, no connections.

5. Extract `headersFromMessage:`, `contentLengthForMessage:`, `headerEndRangeInData:`, `isSupportedTransferEncoding:` as private methods of `Http1Parser`.

### 2.2 Create `Http1PipelinePolicy` — keep-alive/pipelining decisions

**New file:** `ATProtoPDS/Sources/Network/Http1PipelinePolicy.h`
**New file:** `ATProtoPDS/Sources/Network/Http1PipelinePolicy.m`

#### Interface design

```objc
typedef NS_ENUM(NSInteger, Http1PipelineAction) {
    Http1PipelineActionDispatch,      // dispatch this request now
    Http1PipelineActionQueue,         // queue for later (pipeline full)
    Http1PipelineActionReadMore,      // connection idle, read more data
    Http1PipelineActionClose          // connection should close
};

@interface Http1PipelinePolicy : NSObject

@property (nonatomic, assign) NSUInteger maxPipelinedRequests; // default 4
@property (nonatomic, readonly) NSUInteger pendingDispatchCount;

- (Http1PipelineAction)requestParsed;
- (void)requestDispatched;
- (void)responseCompleted;
- (BOOL)shouldReadMoreData;

@end
```

#### Extraction steps

1. Extract pipeline-depth tracking from `HttpConnectionState`: `pendingDispatchCount`, `maxPipelinedRequests`.
2. `processPipelinedRequestsForState:connection:` decision logic moves to policy.
3. `continueConnection:withState:` decision logic moves to policy.

### 2.3 Consolidate query parameter parsing and HTTP method mapping

**New file:** `ATProtoPDS/Sources/Network/HttpParsing.h`
**New file:** `ATProtoPDS/Sources/Network/HttpParsing.m`

```objc
@interface HttpParsing : NSObject

// Consolidated query parameter parser (replaces 3 copies)
+ (NSDictionary<NSString *, NSString *> *)parseQueryString:(NSString *)queryString;

// Consolidated URL decoder
+ (NSString *)urlDecode:(NSString *)string;

// Consolidated method string→enum (replaces 2 copies)
+ (HttpMethod)methodFromString:(NSString *)string;

@end
```

#### Extraction steps

1. Move `HttpServer.parseQueryParamsFromString:` into `HttpParsing`.
2. Delete the copy in `HttpRequest.parseQueryParams:` and `WebSocketConnection.parseQueryParams:`, replace with `[HttpParsing parseQueryString:]`.
3. Move `HttpServer.urlDecode:` into `HttpParsing.urlDecode:`.
4. Merge `HttpServer.httpMethodFromString:` and `HttpRequest.methodFromString:` into `HttpParsing.methodFromString:`. Both are identical.

### 2.4 Rewire `HttpServer` as thin adapter

After 2.1–2.3, `HttpServer` becomes:
- Owns an `Http1Parser` per connection (in `HttpConnectionState`)
- `handleReceivedData:onConnection:` → feeds data to parser, checks result
- Routing, rate limiting, WebSocket upgrade detection stay in `HttpServer`
- Response serialization/streaming stays in `HttpServer` (I/O-bound)
- Connection lifecycle (accept, cancel, timeout) stays in `HttpServer`

`HttpConnectionState` shrinks: drop `buffer`, `message`, `headersComplete`, `expectedBodyLength`, `headerStartTime`, `headerEndOffset`, `isChunkedEncoding`, `chunkedBodyParser` — all owned by `Http1Parser`.

**Estimated diff:** ~350 lines removed from `HttpServer.m`, ~300 lines in new `Http1Parser.m`, ~40 lines in new `Http1PipelinePolicy.m`, ~50 lines in new `HttpParsing.m`.

---

## Phase 3: Outbound Request Policy Core (1–2 weeks)

### 3.1 Create `HttpRetryPolicy` — I/O-free retry/backoff decisions

**New file:** `ATProtoPDS/Sources/Network/HttpRetryPolicy.h`
**New file:** `ATProtoPDS/Sources/Network/HttpRetryPolicy.m`

#### Interface design

```objc
typedef NS_ENUM(NSInteger, HttpRetryDecision) {
    HttpRetryDecisionSucceed,      // request succeeded, use response
    HttpRetryDecisionRetryAfter,   // retry after `retryDelay` seconds
    HttpRetryDecisionFail          // give up, return error
};

@interface HttpRetryResult : NSObject
@property (nonatomic, readonly) HttpRetryDecision decision;
@property (nonatomic, readonly) NSTimeInterval retryDelay;
@end

@interface HttpRetryPolicy : NSObject

@property (nonatomic, assign) NSInteger maxRetries;           // default 3
@property (nonatomic, assign) NSTimeInterval initialDelay;    // default 0.5
@property (nonatomic, assign) double backoffMultiplier;       // default 2.0

// Evaluate an HTTP response or error
- (HttpRetryResult *)evaluateStatusCode:(NSInteger)statusCode
                          networkError:(nullable NSError *)error
                          attemptNumber:(NSInteger)attempt;

@end
```

#### Default policy (matching current `DIDPLCResolver` behavior)

- Network error or status ≥ 500 → retry (up to `maxRetries`)
- 404 → fail immediately (not retryable)
- 200 → succeed
- Other 4xx → fail immediately
- Delay: `initialDelay × backoffMultiplier^attempt`

### 3.2 Create `SSRFValidator` — consolidated IP classification

**New file:** `ATProtoPDS/Sources/Network/SSRFValidator.h`
**New file:** `ATProtoPDS/Sources/Network/SSRFValidator.m`

```objc
@interface SSRFValidator : NSObject

// Pure classification — no DNS resolution
+ (BOOL)isPrivateIPv4Address:(uint32_t)ip;
+ (BOOL)isPrivateIPv6Address:(struct in6_addr)ip6;

// DNS resolution + classification (the I/O part, stays here as convenience)
+ (BOOL)validateHostResolvesToPublicIP:(NSString *)hostname
                                 error:(NSError **)error;

@end
```

#### Extraction steps

1. Move `pds_isPrivateIPv4Address` and `pds_isPrivateIPv6Address` from `FederationClient.m` into `SSRFValidator` class methods.
2. Delete `-isPrivateIPv4Address:` and `-isPrivateIPv6Address:` from `HandleResolver.m`, replace with `[SSRFValidator isPrivateIPv4Address:]`.
3. Move `FederationClient.validateHostResolvesToPublicIP:error:` into `SSRFValidator`.
4. Update `HandleResolver.m` SSRF check (`validateNotPrivateIP:error:` area, ~L460-508) to call `SSRFValidator`.
5. The IPv4/IPv6 classification methods are pure functions — zero I/O, fully testable.

### 3.3 Wire `HttpRetryPolicy` into consumers

**`DIDPLCResolver.m`:**
- Replace `executeRequest:retries:currentDelay:completion:` with a loop that uses `[HttpRetryPolicy evaluateStatusCode:networkError:attemptNumber:]`.
- Delete `executeRawRequest:retries:currentDelay:completion:` (near-duplicate of `executeRequest:`). Unify both into a single method that takes a response-transform block.

**`FederationClient.m`:**
- Add retry support via `HttpRetryPolicy` for `forwardXrpcRequest:` and `forwardXrpcBinaryRequest:`. Currently these do single-shot requests with no retry — the policy makes it trivial to add consistent retry behavior.

**`HandleResolver.m` HTTP path:**
- If the HTTPS resolution path does any retrying (currently it does not for the HTTP fetch, only for DNS), wire in `HttpRetryPolicy` for consistency.

---

## Phase Dependency Graph

```
Phase 0 (Characterization Tests)
  ├── 0.1 WebSocket frame tests
  ├── 0.2 WebSocket state tests
  ├── 0.3 HTTP connection tests
  ├── 0.4 Outbound retry tests
  └── 0.5 SSRF tests

Phase 1 (WebSocket Codec)          Phase 2 (HTTP Parser)         Phase 3 (Outbound Policy)
  depends on: 0.1, 0.2               depends on: 0.3               depends on: 0.4, 0.5
  ├── 1.1 WebSocketCodec             ├── 2.1 Http1Parser           ├── 3.1 HttpRetryPolicy
  ├── 1.2 HeartbeatPolicy            ├── 2.2 Http1PipelinePolicy   ├── 3.2 SSRFValidator
  └── 1.3 Rewire Connection          ├── 2.3 HttpParsing           └── 3.3 Wire into consumers
                                     └── 2.4 Rewire HttpServer
```

Phase 0 runs in parallel with everything. Phases 1, 2, 3 are independent of each other and can run in parallel after their Phase 0 dependencies are met.

---

## File Impact Summary

### New files (10)

| File | Purpose | Est. Lines |
|------|---------|-----------|
| `Sources/Sync/WebSocketCodec.h` | Frame codec interface | ~40 |
| `Sources/Sync/WebSocketCodec.m` | Frame parse + serialize | ~250 |
| `Sources/Sync/WebSocketHeartbeatPolicy.h` | Heartbeat policy interface | ~25 |
| `Sources/Sync/WebSocketHeartbeatPolicy.m` | Heartbeat state machine | ~60 |
| `Sources/Network/Http1Parser.h` | HTTP/1.1 parser interface | ~50 |
| `Sources/Network/Http1Parser.m` | Incremental HTTP parse | ~300 |
| `Sources/Network/Http1PipelinePolicy.h` | Pipeline policy interface | ~25 |
| `Sources/Network/Http1PipelinePolicy.m` | Pipeline depth tracking | ~40 |
| `Sources/Network/HttpParsing.h` | Shared parsing utilities interface | ~20 |
| `Sources/Network/HttpParsing.m` | Query params, URL decode, method enum | ~50 |
| `Sources/Network/HttpRetryPolicy.h` | Retry/backoff policy interface | ~30 |
| `Sources/Network/HttpRetryPolicy.m` | Retry decision logic | ~50 |
| `Sources/Network/SSRFValidator.h` | SSRF IP classification interface | ~20 |
| `Sources/Network/SSRFValidator.m` | IPv4/IPv6 private range checks | ~80 |

### New test files (5+)

| File | Covers |
|------|--------|
| `Tests/Sync/WebSocketFrameCharacterizationTests.m` | Phase 0.1 |
| `Tests/Sync/WebSocketStateCharacterizationTests.m` | Phase 0.2 |
| `Tests/Network/HttpConnectionCharacterizationTests.m` | Phase 0.3 |
| `Tests/PLC/DIDPLCResolverCharacterizationTests.m` | Phase 0.4 |
| `Tests/Network/SSRFClassificationCharacterizationTests.m` | Phase 0.5 |
| `Tests/Sync/WebSocketCodecTests.m` | Phase 1.1 |
| `Tests/Sync/WebSocketHeartbeatPolicyTests.m` | Phase 1.2 |
| `Tests/Network/Http1ParserTests.m` | Phase 2.1 |
| `Tests/Network/HttpParsingTests.m` | Phase 2.3 |
| `Tests/Network/HttpRetryPolicyTests.m` | Phase 3.1 |
| `Tests/Network/SSRFValidatorTests.m` | Phase 3.2 |

### Modified files

| File | Change |
|------|--------|
| `WebSocketConnection.m` | Remove ~150 lines (frame parse/serialize, heartbeat logic), add codec/policy delegation |
| `HttpServer.m` | Remove ~350 lines (parsing, pipeline, query/method utils), add `Http1Parser` usage |
| `HttpRequest.m` | Remove `parseQueryParams:`, `methodFromString:`, use `HttpParsing` |
| `DIDPLCResolver.m` | Remove duplicate `executeRawRequest:`, use `HttpRetryPolicy` |
| `FederationClient.m` | Remove SSRF functions, use `SSRFValidator`, optionally add retry via `HttpRetryPolicy` |
| `HandleResolver.m` | Remove SSRF instance methods, use `SSRFValidator` |
| `CMakeLists.txt` | Add new source files |
| `project.yml` | Add new source/test files if needed for Xcode |

### Deleted code (no new files, just removals)

| Location | What | Lines |
|----------|------|-------|
| `FederationClient.m` L15-44 | `pds_isPrivateIPv4Address`, `pds_isPrivateIPv6Address` static functions | 30 |
| `HandleResolver.m` L522-585 | `-isPrivateIPv4Address:`, `-isPrivateIPv6Address:` instance methods | 64 |
| `HttpServer.m` L1208-1238 | `-parseQueryParamsFromString:`, `-urlDecode:` | 30 |
| `HttpServer.m` L1240-1256 | `-httpMethodFromString:` | 16 |
| `HttpRequest.m` L370-380 | `-methodFromString:` | 10 |
| `DIDPLCResolver.m` L249-283 | `executeRawRequest:retries:currentDelay:completion:` (duplicate) | 34 |

---

## Risk Mitigations

| Risk | Mitigation |
|------|-----------|
| Regression in keep-alive/pipelining | Phase 0.3 characterization tests lock behavior before any extraction |
| `CFHTTPMessageRef` lifecycle bugs during `Http1Parser` extraction | Parser owns creation/release internally; `HttpConnectionState` stops touching it |
| WebSocket frame parsing regression | Phase 0.1 adds boundary-condition tests; Phase 1.1 runs all old + new tests |
| Subtle timing differences in heartbeat after extraction | `WebSocketHeartbeatPolicy` is time-parameterized (`tick:now`), tests use synthetic time |
| GNUstep/Linux compatibility | All new classes are Foundation-only (no `Network.framework`, no `CFHost`). `SSRFValidator.validateHostResolvesToPublicIP:` uses `CFHost` but is the I/O wrapper, not the core. |
| Build breakage from CMakeLists/project.yml changes | Add new files to build system in the same commit as the source. Run `xcodegen generate` + full build as gate. |

## Quality Gates Per Phase

Each phase PR must pass before merging:

1. `xcodegen generate` succeeds
2. `xcodebuild -scheme AllTests build` succeeds
3. `./build/tests/AllTests` passes with 0 failures
4. `xcodebuild -scheme ATProtoPDS-CLI build` succeeds
5. No new `clang-tidy` warnings in changed files
6. Net line count of `HttpServer.m` and `WebSocketConnection.m` decreases (or stays flat for Phase 0)

---

## Timeline Estimate

| Phase | Duration | Can parallelize with |
|-------|----------|---------------------|
| Phase 0 | 1–2 weeks | Phases 1, 2, 3 (start after relevant 0.x subtask) |
| Phase 1 | 2–3 weeks | Phases 2, 3 |
| Phase 2 | 3–4 weeks | Phases 1, 3 |
| Phase 3 | 1–2 weeks | Phases 1, 2 |

**Sequential (one engineer):** ~8–11 weeks
**With parallelism (Phase 0 overlapping, Phases 1+3 concurrent):** ~6–8 weeks

---

## Architecture Diagrams

### Before: Tightly Coupled I/O and Protocol Logic

```text
       [ Network Socket ]
              │
              ▼ (Bytes via dispatch queue)
┌──────────────────────────────────────────────┐
│  HttpServer / WebSocketConnection            │
│                                              │
│  [ I/O Layer ]                               │
│  - dispatch_read / GCD timers                │
│  - Socket cancellation & errors              │
│       ↕                                      │
│  [ Protocol Layer ]                          │
│  - Parse HTTP headers / WS masks             │  <-- Hard to test! Requires
│  - Track Content-Length / payload frames     │      spinning up a real socket
│  - Manage keep-alive & ping/pong state       │      and waiting for timers.
│       ↕                                      │
│  [ Application Layer ]                       │
│  - Route dispatch / Delegate callbacks       │
└──────────────────────────────────────────────┘
```

### After: "Sans-I/O" Architecture

```text
       [ Network Socket ]
              │
              ▼ (Bytes)
┌────────────────────────────┐         ┌──────────────────────────────┐
│       "Dumb" Adapter       │         │        Pure Protocol         │
│   (WebSocketConnection)    │         │       (WebSocketCodec)       │
│                            │         │                              │
│ - Reads from socket      ──┼─Bytes──▶│ - Parses bytes in memory     │
│ - Manages GCD timers       │         │ - Handles bounds/masks       │
│ - Writes to socket       ◀─┼─Events──│ - Validates protocol rules   │
└─────────────┬──────────────┘         └──────────────────────────────┘
              │ 
              ▼ (Events: "MessageReceived", "PingRequired")
     [ Application Logic ]
```

---

## Why the "Sans-I/O" Pattern is Highly Beneficial

The term "Sans-I/O" gained prominence in the Python community (most notably popularized by Cory Benfield and the `h11` library) but its principles apply universally to systems engineering.

1. **Deterministic Testability (No Flaky Tests)**
   *   *Concept:* Network sockets introduce non-determinism (latency, TCP fragmentation, dropped packets). By removing the network from the protocol logic, a parser simply becomes a pure function: `State + Bytes = New State + Events`.
   *   *Citation:* "The Case for Sans-I/O" (fasterthanli.me/articles/the-case-for-sans-io) — "If your protocol implementation doesn't do I/O, you can test it by just giving it bytes... You don't need a mock network, you don't need `asyncio`, you don't need threads."
2. **Security Hardening & Fuzzing**
   *   *Concept:* Parsers are the primary surface for remote code execution and denial-of-service attacks. A Sans-I/O parser can be plugged directly into a fuzzer (like libFuzzer) because it executes synchronously in memory.
   *   *Citation:* "Building Protocol Libraries The Right Way" (Cory Benfield, PyCon 2016) — emphasizing that separating state machines from transport allows security tooling to pound the parser with malformed data thousands of times per second.
3. **Time Simulation**
   *   *Concept:* By extracting policies (like `HttpRetryPolicy` or `WebSocketHeartbeatPolicy`) to take a timestamp (`now`) as an argument rather than relying on system clocks, you can test complex timeout edge cases instantly.
4. **Transport Agnosticism**
   *   *Concept:* A pure protocol core doesn't care if bytes come from a TCP socket, a TLS buffer, a mock testing array, or a Unix domain socket. This is especially relevant here as the codebase targets both macOS and Linux/GNUstep where transport implementations differ (`NSURLSession` vs. custom BSD sockets).
