---
title: Actor Store Tests
---

# Actor Store Tests

Tests for per-user SQLite databases storing accounts, records, blocks, and blobs.

## Test Classes

### ActorStoreTests
**File:** `Tests/Database/ActorStore/ActorStoreTests.m`

**Purpose:** Per-actor SQLite storage operations for accounts, records, blocks, blobs, transactions, and signing keys.

#### How It Works

**Temp directory isolation** ensures each test has a clean database:

```objc
- (void)setUp {
    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.store = [[PDSActorStore alloc] initWithDID:@"did:plc:test" path:self.tempURL.path];
    [self.store openWithError:nil];
}

- (void)tearDown {
    [self.store close];
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
}
```

**Transaction testing** verifies atomicity:

```objc
[self.store transactWithBlock:^(PDSActorStoreTransaction *txn, BOOL *rollback) {
    [txn putRecord:record1 collection:@"app.bsky.feed.post" rkey:@"abc"];
    [txn putRecord:record2 collection:@"app.bsky.feed.post" rkey:@"def"];
    // If either fails, set *rollback = YES
}];
```

**Signing key generation** produces did:key format:

```objc
[self.store generateSigningKey:&error];
NSString *didKey = self.store.signingKeyDidKey; // "did:key:zQ3sh..."
NSData *compressed = self.store.signingKey;     // 33 bytes (secp256k1 compressed)
```

#### Why It Matters

| Operation | Why It's Critical |
|-----------|-------------------|
| Record CRUD | ATProto repository data storage |
| Block storage | MST nodes referenced by CID |
| Blob isolation | Prevents cross-actor data leakage |
| Transaction atomicity | MST consistency requires all-or-nothing writes |
| Signing keys | Required for commit signatures |

| Method | What It Verifies |
|--------|------------------|
| `testStoreInitialization` | Store opens with correct DID/path |
| `testAccountCreation` | Create/fetch accounts by DID |
| `testRecordOperations` | CRUD on ATProto records |
| `testBlockOperations` | Block storage (put/get/count/delete) |
| `testTransaction` | Atomic multi-record writes |
| `testSigningKeyGeneration` | secp256k1 key, did:key format |
| `testListBlobsExcludesOtherDids` | DID isolation for blobs |

---

### DatabasePoolTests
**File:** `Tests/Database/Pool/DatabasePoolTests.m`

**Purpose:** LRU eviction, concurrent access, and pooled store lifecycle.

#### How It Works

**Configurable pool size** tests eviction behavior:

```objc
PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:tempDir 
                                                             maxSize:3]; // Only 3 stores
```

**Concurrent access testing** uses dispatch groups:

```objc
dispatch_group_t group = dispatch_group_create();
for (int i = 0; i < 10; i++) {
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        PDSActorStore *store = [pool acquireStoreForDID:dids[i] error:nil];
        // ... use store ...
        [pool releaseStoreForDID:dids[i]];
    });
}
dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
```

**Eviction verification:**

```objc
// Fill pool to capacity
for (int i = 0; i < 3; i++) {
    [pool acquireStoreForDID:dids[i] error:nil];
}
XCTAssertEqual(pool.size, 3);

// Acquire 4th - should evict LRU
[pool acquireStoreForDID:dids[3] error:nil];
XCTAssertEqual(pool.size, 3); // Still at max
XCTAssertNil([pool getStoreForDID:dids[0]]); // First was evicted
```

#### Why It Matters

| Feature | Why It's Critical |
|---------|-------------------|
| Max size enforcement | Prevents unbounded file descriptors |
| LRU eviction | Memory control under load |
| Thread safety | Multi-request production workloads |
| Same instance for same DID | Transaction consistency |

| Method | What It Verifies |
|--------|------------------|
| `testPoolInitialization` | Correct directory, max size |
| `testSameStoreReturned` | Caching works |
| `testEviction` | LRU eviction enforced |
| `testConcurrentAccessPatterns` | Thread safety |
| `testPoolExhaustionHandling` | Graceful behavior at limit |

---

### ServiceDatabasesTests
**File:** `Tests/Database/Service/ServiceDatabasesTests.m`

**Purpose:** Multi-pool service database manager for accounts, invites, DID cache.

#### How It Works

**Three-pool configuration:**

```objc
PDSServiceDatabases *services = [[PDSServiceDatabases alloc] initWithDirectory:dir];
// services.pool - accounts, invites
// services.didCache - DID document cache
// services.sequencer - event sequencing
```

**Persistence verification via close/reopen:**

```objc
[services reserveHandle:@"test.example.com" error:nil];
[services closeAll];

// Reopen
services = [[PDSServiceDatabases alloc] initWithDirectory:dir];
BOOL reserved = [services isHandleReserved:@"test.example.com"];
XCTAssertTrue(reserved, @"Handle reservation survives restart");
```

**DID cache with TTL:**

```objc
[services cacheDIDDocument:document forDID:@"did:plc:abc"];
DIDDocument *cached = [services getDIDDocumentForDID:@"did:plc:abc"];
XCTAssertNotNil(cached);

// After TTL expires
cached = [services getDIDDocumentForDID:@"did:plc:abc"];
XCTAssertNil(cached, @"Expired entries return nil");
```

#### Why It Matters

| Feature | Why It's Critical |
|---------|-------------------|
| Handle reservation persistence | TOCTOU race prevention |
| DID caching with TTL | Latency vs freshness balance |
| Invite code lifecycle | Invite-only onboarding enforcement |

| Method | What It Verifies |
|--------|------------------|
| `testAccountCreation` | Create/fetch by DID |
| `testInviteCodeOperations` | Create/get/use flow |
| `testReservedHandlePersistsAcrossReopen` | Persistence |
| `testDIDCachingExpiry` | TTL enforcement |

---

### DatabaseMigrationTests
**File:** `Tests/Database/DatabaseMigrationTests.m`

**Purpose:** Database schema migration testing.

---

### MultiTenantDatabaseTests
**File:** `Tests/Database/MultiTenantDatabaseTests.m`

**Purpose:** Multi-tenant database isolation testing.

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ActorStoreTests
./build/tests/AllTests -only-testing:AllTests/DatabasePoolTests
./build/tests/AllTests -only-testing:AllTests/ServiceDatabasesTests
```

## Actor Store Schema

```sql
-- Records (ATProto repository data)
CREATE TABLE records (
    collection TEXT,    -- e.g., "app.bsky.feed.post"
    rkey TEXT,         -- record key
    cid TEXT,          -- content identifier
    value BLOB,        -- CBOR-encoded record
    indexedAt INTEGER,
    PRIMARY KEY (collection, rkey)
);

-- Blocks (MST nodes)
CREATE TABLE blocks (
    cid TEXT PRIMARY KEY,
    data BLOB          -- CBOR-encoded MST node
);

-- Blobs (binary large objects)
CREATE TABLE blobs (
    cid TEXT PRIMARY KEY,
    mime TEXT,
    size INTEGER,
    data BLOB
);
```

## Related Documentation

- [Folder README](README) - Database tests overview
- [Test Index](../README) - Main test documentation index
- [Pool Integration Tests](pool-integration) - Connection pooling
- [Service Databases Tests](service-databases) - Global service databases
- [Repository Tests](../01-repository/mst) - MST persistence in actor store
- [Blob Tests](../04-application/blob) - Blob storage tests
- [Services Tests](../04-application/services) - Business services
- [Characterization Tests](../08-characterization/characterization) - Actor store compliance
