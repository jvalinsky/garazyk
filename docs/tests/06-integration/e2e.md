# End-to-End Integration Tests

Tests for complete system flows including account lifecycle and commit chains.

## Test Classes

### PDSIntegrationTests
**File:** `Tests/Integration/PDSIntegrationTests.m`

**Purpose:** End-to-end integration for account, session, record, and blob operations.

#### How It Works

**Full lifecycle test:**

```objc
// 1. Create account
NSDictionary *account = [controller createAccountForEmail:@"test@example.com"
                                                password:@"testpass"
                                                  handle:@"test.example.com"
                                                     did:nil
                                                   error:&error];
NSString *did = account[@"did"];

// 2. Create session
NSDictionary *session = [controller createSessionForIdentifier:@"test@example.com"
                                                      password:@"testpass"
                                                       handle:@"test.example.com"
                                                         did:did
                                                        error:&error];
NSString *accessToken = session[@"accessJwt"];

// 3. Create record
NSDictionary *record = @{@"text": @"Hello", @"createdAt": @"2024-01-01T00:00:00Z"};
NSDictionary *result = [controller createRecordForDid:did
                                           collection:@"app.bsky.feed.post"
                                              record:record
                                      validationMode:PDSValidationModeRequired
                                               error:&error];

// 4. Retrieve record
NSString *rkey = [self extractRkeyFromURI:result[@"uri"]];
NSDictionary *retrieved = [controller getRecordForDid:did
                                           collection:@"app.bsky.feed.post"
                                                 rkey:rkey
                                                error:&error];
XCTAssertEqualObjects(retrieved[@"value"][@"text"], @"Hello");
```

**Concurrent operations test:**

```objc
dispatch_group_t group = dispatch_group_create();
for (int i = 0; i < 5; i++) {
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [controller createRecordForDid:did collection:@"app.bsky.feed.post" ...];
    });
}
dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
```

---

### CommitChainTests
**File:** `Tests/Integration/CommitChainTests.m`

**Purpose:** Merkle commit chain integrity.

#### How It Works

**Chain verification:**

```objc
// Create record -> commit 1
CID *commit1 = [recordService applyWrites:...].commitCID;

// Create another record -> commit 2
CID *commit2 = [recordService applyWrites:...].commitCID;

// Verify chain
RepoCommit *commit2Obj = [repo getCommit:commit2];
XCTAssertEqualObjects(commit2Obj.prev, commit1, "Commit 2 must link to commit 1");
```

---

### FirehoseIntegrationTests
**File:** `Tests/Integration/FirehoseIntegrationTests.m`

**Purpose:** Firehose broadcast of commit events.

#### How It Works

**Event broadcasting:**

```objc
// Subscribe to firehose
WebSocketConnection *conn = [wsServer acceptConnection:...];

// Create record
[recordService createRecord:...];

// Verify broadcast
NSData *frame = [conn receiveFrameWithTimeout:5.0];
NSDictionary *event = [EventFormatter decodeEvent:frame];
XCTAssertEqualObjects(event[@"$type"], @"com.atproto.sync.subscribeRepos#commit");
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSIntegrationTests
./build/tests/AllTests -only-testing:AllTests/CommitChainTests
./build/tests/AllTests -only-testing:AllTests/FirehoseIntegrationTests
```

## Integration Test Flow

```
1. Create Account → DID generated
2. Create Session → Access token returned
3. Put Record → CID computed, MST updated
4. Get Record → Retrieved by rkey
5. Delete Record → Tombstone created
6. Refresh Session → New tokens, old revoked
```

## Related Documentation

- [Folder README](README) - Integration tests overview
- [Test Index](../README) - Main test documentation index
- [Federation Tests](federation) - Cross-PDS communication
- [PLC Tests](plc) - PLC directory operations
- [Services Tests](../04-application/services) - Business services
- [Repository Tests](../01-repository/mst) - Commit chains
- [WebSocket Tests](../02-network/websocket) - Firehose events
- [OAuth Tests](../00-identity-auth/oauth) - Session management
