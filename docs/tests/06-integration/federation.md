# Federation Tests

Tests for cross-PDS communication and relay synchronization.

## Test Classes

### FederationClientTests
**File:** `Tests/Federation/FederationClientTests.m`

**Purpose:** Federation client for forwarding XRPC to remote PDSs.

#### How It Works

**DID resolution for routing:**

```objc
FederationClient *client = [[FederationClient alloc] init];

// Resolve DID to find PDS endpoint
DIDDocument *doc = [didResolver resolve:@"did:plc:abc"];
NSString *pdsEndpoint = [doc serviceEndpointWithType:@"atproto_pds"];
// pdsEndpoint = "https://remote-pds.example.com"
```

**Request forwarding:**

```objc
// Forward GET request
HttpRequest *forwarded = [client forwardXrpcRequest:request
                                           forDID:@"did:plc:abc"
                                            method:@"GET"
                                               uri:@"https://remote-pds.example.com/xrpc/com.atproto.sync.getRepo"
                                             error:nil];

XCTAssertEqual(forwarded.method, HttpMethodGET);
XCTAssertTrue([forwarded.path containsString:@"did=did:plc:abc"]);
```

**Error mapping:**

```objc
// Remote PDS returns 500
HttpResponse *remoteResponse = [[HttpResponse alloc] initWithStatusCode:500 ...];
NSError *error = [client mapErrorFromResponse:remoteResponse];

// Client receives appropriate error
XCTAssertEqual(error.code, PDSFederationErrorUpstream);
```

---

### RelayClientTests
**File:** `Tests/Sync/RelayClientTests.m`

**Purpose:** Relay client cursor storage and commit dispatch.

#### How It Works

**Cursor persistence:**

```objc
RelayClient *client = [[RelayClient alloc] initWithDatabasePath:dbPath];

// Store cursor
[client storeCursor:12345 forRelay:@"wss://relay.bsky.network" error:nil];

// Retrieve cursor
NSUInteger cursor = [client getCursorForRelay:@"wss://relay.bsky.network" error:nil];
XCTAssertEqual(cursor, 12345);
```

**Event dispatch:**

```objc
client.delegate = self;  // Implements RelayClientDelegate

[client connectToRelay:@"wss://relay.bsky.network" cursor:nil error:nil];

// Delegate receives events
- (void)relayClient:(RelayClient *)client didReceiveCommit:(NSDictionary *)commit {
    XCTAssertNotNil(commit[@"seq"]);
    XCTAssertNotNil(commit[@"repo"]);
}
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/FederationClientTests
./build/tests/AllTests -only-testing:AllTests/RelayClientTests
```

## Federation Flow

```
Client → Local PDS → Resolve DID → Remote PDS → Response
                      ↓
              didDocument.service
              "atproto_pds" endpoint
```
