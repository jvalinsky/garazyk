---
title: Business Services Tests
---

# Business Services Tests

Tests for account, record, repository, and blob services.

## Test Classes

### PDSAccountServiceTests
**File:** `Tests/App/Services/PDSAccountServiceTests.m`

**Purpose:** Account creation, login, and token refresh.

#### How It Works

**Account creation flow:**

```objc
PDSAccountService *service = [[PDSAccountService alloc] initWithDatabasePool:pool];

NSDictionary *account = [service createAccountWithEmail:@"user@example.com"
                                              password:@"secret123"
                                                handle:@"user.bsky.social"
                                                   did:nil
                                                 error:&error];

XCTAssertNotNil(account[@"did"]);
XCTAssertNotNil(account[@"handle"]);
```

**Login with token generation:**

```objc
NSDictionary *session = [service loginWithHandle:@"user.bsky.social"
                                        password:@"secret123"
                                           error:&error];

XCTAssertNotNil(session[@"accessJwt"]);
XCTAssertNotNil(session[@"refreshJwt"]);
```

**Token rotation on refresh:**

```objc
NSString *oldRefresh = session[@"refreshJwt"];

NSDictionary *newSession = [service refreshAccessToken:oldRefresh error:&error];
NSString *newRefresh = newSession[@"refreshJwt"];

XCTAssertNotEqualObjects(oldRefresh, newRefresh, "Refresh token must rotate");

// Old token should be revoked
NSDictionary *fail = [service refreshAccessToken:oldRefresh error:&error];
XCTAssertNil(fail);
```

#### Why It Matters

| Property | Enforcement |
|----------|-------------|
| Password hashing | bcrypt with 32-byte salt |
| Token rotation | Prevents replay attacks |
| DID generation | Creates did:plc for new accounts |

---

### PDSRecordServiceTests
**File:** `Tests/App/Services/PDSRecordServiceTests.m`

**Purpose:** Record CRUD, atomic batch writes, validation.

#### How It Works

**Record creation with validation:**

```objc
NSDictionary *record = @{
    @"$type": @"app.bsky.feed.post",
    @"text": @"Hello World",
    @"createdAt": @"2025-01-01T00:00:00Z"
};

NSDictionary *result = [service putRecordForDID:@"did:plc:abc"
                                    collection:@"app.bsky.feed.post"
                                           rkey:@"abc123"
                                         record:record
                                validationMode:PDSValidationModeRequired
                                         error:&error];

XCTAssertNotNil(result[@"cid"]);
```

**Atomic batch writes:**

```objc
NSArray *writes = @[
    @{@"action": @"create", @"collection": @"app.bsky.feed.post", @"rkey": @"1", @"value": record1},
    @{@"action": @"create", @"collection": @"app.bsky.feed.post", @"rkey": @"2", @"value": record2},
    @{@"action": @"delete", @"collection": @"app.bsky.feed.post", @"rkey": @"old"}
];

NSDictionary *commit = [service applyWritesForDID:@"did:plc:abc"
                                          writes:writes
                                        swapCommit:nil
                                             error:&error];

XCTAssertNotNil(commit[@"cid"]);  // New commit CID
XCTAssertNotNil(commit[@"rev"]);  // New revision
```

**Optimistic locking with swapCommit:**

```objc
// Client A and B both have commit CID "xyz"
// Client A writes first
[service applyWritesForDID:@"did:plc:abc" writes:writesA swapCommit:@"xyz" error:nil];

// Client B tries to write - should fail
NSDictionary *result = [service applyWritesForDID:@"did:plc:abc" writes:writesB swapCommit:@"xyz" error:&error];
XCTAssertNil(result);  // Commit CID changed, swap failed
```

---

### PDSRepositoryServiceTests
**File:** `Tests/App/Services/PDSRepositoryServiceTests.m`

**Purpose:** CAR export, delta sync, repository content retrieval.

#### How It Works

**Full CAR export:**

```objc
NSData *carData = [service getRepoContentsForDID:@"did:plc:abc" since:nil error:nil];

CARReader *reader = [[CARReader alloc] initWithData:carData error:nil];
XCTAssertNotNil(reader.rootCID);
XCTAssertGreaterThan(reader.blockCount, 0);
```

**Delta sync:**

```objc
// Get full snapshot
NSData *full = [service getRepoContentsForDID:@"did:plc:abc" since:nil error:nil];

// Make changes...

// Get delta since last revision
NSData *delta = [service getRepoContentsForDID:@"did:plc:abc" since:lastRev error:nil];

XCTAssertLessThan(delta.length, full.length, "Delta should be smaller");
```

---

### PDSBlobServiceTests
**File:** `Tests/App/Services/PDSBlobServiceTests.m`

**Purpose:** Blob upload, retrieval, deletion, DID isolation.

#### How It Works

**Upload with CID:**

```objc
NSData *blobData = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
NSDictionary *result = [service uploadBlob:blobData
                                       did:@"did:plc:abc"
                                   mimeType:@"text/plain"
                                      error:&error];

NSString *cid = result[@"cid"];  // SHA-256 based
```

**DID isolation enforcement:**

```objc
// Upload as user A
NSDictionary *blob = [service uploadBlob:data did:@"did:plc:alice" ...];

// Try to retrieve as user B - should fail
NSData *stolen = [service getBlobWithCID:blob[@"cid"] did:@"did:plc:bob" error:&error];
XCTAssertNil(stolen);
XCTAssertNotNil(error);  // Access denied
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSAccountServiceTests
./build/tests/AllTests -only-testing:AllTests/PDSRecordServiceTests
./build/tests/AllTests -only-testing:AllTests/PDSRepositoryServiceTests
./build/tests/AllTests -only-testing:AllTests/PDSBlobServiceTests
```

## Related Documentation

- [Folder README](README) - Application tests overview
- [Test Index](../README) - Main test documentation index
- [Controller Tests](controller) - Application lifecycle
- [Admin Tests](admin) - Admin operations
- [Database Tests](../03-database/README) - Actor stores and pools
- [Repository Tests](../01-repository/README) - MST and CAR
- [OAuth Tests](../00-identity-auth/oauth) - Session management
- [Integration Tests](../06-integration/e2e) - E2E service flows
