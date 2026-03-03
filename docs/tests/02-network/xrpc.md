# XRPC Protocol Tests

Tests for XRPC method handling, input validation, error responses, and integration.

## Test Classes

### XrpcHandlerTests
**File:** `Tests/XRPC/XrpcHandlerTests.m`

**Purpose:** XRPC request handling and method dispatch.

#### How It Works

**Request construction:**

```objc
HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/xrpc/com.atproto.sync.getRepo"
                                                queryString:@"did=did:plc:abc"
                                                queryParams:@{@"did": @"did:plc:abc"}
                                                    version:@"HTTP/1.1"
                                                    headers:@{}
                                                       body:nil
                                             remoteAddress:@"127.0.0.1"];
```

**Handler dispatch:**

```objc
XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
[dispatcher registerMethod:@"com.atproto.sync.getRepo" handler:^(XrpcRequest *req, XrpcResponse *res) {
    NSString *did = req.queryParams[@"did"];
    // Handle request
}];
```

---

### XrpcInputValidationTests
**File:** `Tests/XRPC/XrpcInputValidationTests.m`

**Purpose:** XRPC input validation for query params and request bodies.

#### How It Works

**Type validation:**

```objc
// Boolean parsing
XCTAssertEqual([XrpcInput parseBool:@"true"], YES);
XCTAssertEqual([XrpcInput parseBool:@"false"], NO);
XCTAssertNil([XrpcInput parseBool:@"yes"]);  // Invalid

// Integer parsing
XCTAssertEqual([XrpcInput parseInt:@"42"], @42);
XCTAssertNil([XrpcInput parseInt:@"not-a-number"]);

// Array from repeated params
NSDictionary *params = @{@"tag": @[@"a", @"b", @"c"]};
NSArray *tags = [XrpcInput parseArray:params[@"tag"]];
XCTAssertEqualObjects(tags, (@[@"a", @"b", @"c"]));
```

#### Why It Matters

| Type | Validation |
|------|------------|
| Boolean | Only `true`/`false` accepted |
| Integer | Must parse as number |
| Array | Repeated query params |
| Body | Must be `application/json` |

---

### XrpcErrorResponseTests
**File:** `Tests/XRPC/XrpcErrorResponseTests.m`

**Purpose:** Error mapping from internal errors to XRPC error codes.

#### How It Works

**Error code mapping:**

```objc
NSError *internalError = [NSError errorWithDomain:@"ATProto" code:ATProtoErrorInvalidToken userInfo:nil];
XrpcResponse *response = [XrpcErrorResponse responseFromError:internalError];

XCTAssertEqual(response.statusCode, 401);
XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
```

#### Why It Matters

| Internal Error | XRPC Error | HTTP Status |
|----------------|------------|-------------|
| `InvalidToken` | `InvalidToken` | 401 |
| `ExpiredToken` | `ExpiredToken` | 401 |
| `RateLimitExceeded` | `RateLimitExceeded` | 429 |
| `RecordNotFound` | `RecordNotFound` | 404 |

---

### LexiconValidationTests
**File:** `Tests/Lexicon/LexiconValidationTests.m`

**Purpose:** Lexicon schema validation for record types.

#### How It Works

**Schema loading:**

```objc
ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
[registry loadLexiconFromFile:@"Resources/lexicons/app/bsky/feed/post.json" error:nil];

ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];
```

**Record validation:**

```objc
NSDictionary *validPost = @{
    @"$type": @"app.bsky.feed.post",
    @"text": @"Hello World",
    @"createdAt": @"2025-01-01T12:00:00Z"
};
BOOL valid = [validator validateRecord:validPost collection:@"app.bsky.feed.post" mode:ATProtoValidationModeRequired error:nil];
XCTAssertTrue(valid);

NSDictionary *missingText = @{
    @"$type": @"app.bsky.feed.post",
    @"createdAt": @"2025-01-01T12:00:00Z"
};
valid = [validator validateRecord:missingText collection:@"app.bsky.feed.post" mode:ATProtoValidationModeRequired error:&error];
XCTAssertFalse(valid);  // Missing required 'text' field
```

#### Why It Matters

Lexicon validation ensures records conform to schema - preventing malformed data from entering the repository.

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/XrpcHandlerTests
./build/tests/AllTests -only-testing:AllTests/XrpcInputValidationTests
./build/tests/AllTests -only-testing:AllTests/XrpcErrorResponseTests
./build/tests/AllTests -only-testing:AllTests/LexiconValidationTests
```

## XRPC Format

**Query (GET):**
```
GET /xrpc/com.atproto.sync.getRepo?did=did:plc:abc
```

**Procedure (POST):**
```
POST /xrpc/com.atproto.repo.createRecord
Content-Type: application/json

{"repo": "did:plc:abc", "collection": "app.bsky.feed.post", ...}
```

**Error Response:**
```json
{"error": "InvalidRequest", "message": "Missing required field"}
```

## Related Documentation

- [Folder README](README) - Network tests overview
- [Test Index](../README) - Main test documentation index
- [HTTP Stack Tests](http-stack) - HTTP server tests
- [Transport Tests](transport) - Network transport tests
- [WebSocket Tests](websocket) - WebSocket/firehose tests
- [Auth Security Tests](../05-security/auth-security) - XRPC authorization
- [Repository Tests](../01-repository/README) - Repository data models
- [XRPC Protocol Reference](../../architecture/XRPC_PROTOCOL_REFERENCE) - XRPC specification
