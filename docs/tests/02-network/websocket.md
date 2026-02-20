# WebSocket & Firehose Tests

Tests for WebSocket server, firehose event streaming, and subscription handling.

## Test Classes

### WebSocketServerTests
**File:** `Tests/Sync/WebSocketServerTests.m`

**Purpose:** WebSocket server lifecycle, connection management, and frame handling.

#### How It Works

**WebSocket handshake verification:**

```objc
// HTTP upgrade request
HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                queryString:@""
                                                queryParams:@{}
                                                    version:@"HTTP/1.1"
                                                    headers:@{
                                                        @"Upgrade": @"websocket",
                                                        @"Connection": @"Upgrade",
                                                        @"Sec-WebSocket-Key": @"dGhlIHNhbXBsZSBub25jZQ==",
                                                        @"Sec-WebSocket-Version": @"13"
                                                    }
                                                       body:nil
                                             remoteAddress:@"127.0.0.1"];
```

**Frame encoding/decoding:**

```objc
// Text frame
WebSocketFrame *frame = [[WebSocketFrame alloc] initWithOpcode:WebSocketOpcodeText
                                                        data:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]];
NSData *encoded = [frame encode];

// Parse back
WebSocketFrame *decoded = [WebSocketFrame decodeFromData:encoded error:nil];
XCTAssertEqualObjects(decoded.stringPayload, @"hello");
```

---

### EventFormatterTests
**File:** `Tests/Sync/EventFormatterTests.m`

**Purpose:** DAG-CBOR event formatting for firehose events.

#### How It Works

**Event structure:**

```objc
// Commit event
NSDictionary *commitEvent = @{
    @"$type": @"com.atproto.sync.subscribeRepos#commit",
    @"seq": @1,
    @"repo": @"did:plc:abc",
    @"commit": commitCID,
    @"ops": @[
        @{@"action": @"create", @"path": @"app.bsky.feed.post/abc", @"cid": recordCID}
    ]
};

NSData *encoded = [EventFormatter encodeEvent:commitEvent error:nil];
```

#### Why It Matters

| Event Type | Fields |
|------------|--------|
| `#commit` | seq, repo, commit, ops, blobs |
| `#identity` | seq, did, handle |
| `#account` | seq, did, active, status |
| `#error` | code, message |

Events are DAG-CBOR encoded for efficient binary transmission.

---

### SubscribeReposHandlerTests
**File:** `Tests/Sync/SubscribeReposHandlerTests.m`

**Purpose:** `com.atproto.sync.subscribeRepos` endpoint for repository event streaming.

#### How It Works

**Cursor-based streaming:**

```objc
// Client connects with cursor
HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/xrpc/com.atproto.sync.subscribeRepos"
                                                queryString:@"cursor=12345"
                                                queryParams:@{@"cursor": @"12345"}
                                                       ...];

// Handler streams events from cursor onwards
[handler handleSubscribeRepos:request connection:connection];
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/WebSocketServerTests
./build/tests/AllTests -only-testing:AllTests/EventFormatterTests
./build/tests/AllTests -only-testing:AllTests/SubscribeReposHandlerTests
```

## Firehose Event Flow

```
Client                          Server
  |                               |
  |--- WebSocket Connect -------->|
  |                               |
  |<-- #identity event -----------|
  |<-- #commit event -------------|
  |<-- #commit event -------------|
  |                               |
  |--- subscribeRepos cursor ---->|
  |                               |
  |<-- events from cursor --------|
```

## References

- [ATProto Sync Spec](https://atproto.com/specs/sync)
- [RFC 6455 (WebSocket)](https://datatracker.ietf.org/doc/html/rfc6455)

## Related Documentation

- [Folder README](README.md) - Network tests overview
- [Test Index](../README.md) - Main test documentation index
- [HTTP Stack Tests](http-stack.md) - HTTP server tests
- [XRPC Tests](xrpc.md) - XRPC protocol tests
- [Integration Tests](../06-integration/e2e.md) - E2E firehose testing
- [Federation Tests](../06-integration/federation.md) - Relay synchronization
- [Repository Tests](../01-repository/mst.md) - Repository sync with CAR
