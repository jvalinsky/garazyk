---
title: Database Pool & Integration Tests
---

# Database Pool & Integration Tests

Tests for connection pooling and database integration utilities.

## Test Classes

### DatabasePoolTests
**File:** `Tests/Database/Pool/DatabasePoolTests.m`

**Purpose:** LRU eviction, concurrent access, and pooled store lifecycle.

#### How It Works

**Pool with max size:**

```objc
PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:tempDir maxSize:3];

// Acquire stores
PDSActorStore *store1 = [pool acquireStoreForDID:@"did:plc:a" error:nil];
PDSActorStore *store2 = [pool acquireStoreForDID:@"did:plc:b" error:nil];
PDSActorStore *store3 = [pool acquireStoreForDID:@"did:plc:c" error:nil];
XCTAssertEqual(pool.size, 3);

// 4th acquisition triggers LRU eviction
PDSActorStore *store4 = [pool acquireStoreForDID:@"did:plc:d" error:nil];
XCTAssertEqual(pool.size, 3);  // Still at max
XCTAssertNil([pool getStoreForDID:@"did:plc:a"]);  // LRU evicted
```

**Concurrent access testing:**

```objc
dispatch_group_t group = dispatch_group_create();
for (int i = 0; i < 100; i++) {
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *did = dids[i % 10];
        PDSActorStore *store = [pool acquireStoreForDID:did error:nil];
        // ... use store ...
        [pool releaseStoreForDID:did];
    });
}
dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
```

#### Why It Matters

| Feature | Why It's Critical |
|---------|-------------------|
| Max size enforcement | Prevents unbounded file descriptors |
| LRU eviction | Memory control under load |
| Thread safety | Multi-request production workloads |
| Same instance for same DID | Transaction consistency |

**Transaction consistency**: If the same DID gets different store instances within a transaction, changes could be lost.

---

### PDSDatabaseIntegrationTests
**File:** `Tests/Database/Integration/PDSDatabaseIntegrationTests.m`

**Purpose:** End-to-end database operations using test utilities.

#### How It Works

**Test factory utilities:**

```objc
// Create account via factory
PDSDatabaseAccount *account = [TestFactory createAccountWithDID:@"did:plc:test"];

// Create record via factory
PDSDatabaseRecord *record = [TestFactory createRecordWithCollection:@"app.bsky.feed.post"
                                                                rkey:@"abc123"
                                                                 cid:cid
                                                               value:@{@"text": @"hello"}];

// Verify schema
BOOL valid = [SchemaValidator validateDatabase:db error:nil];
XCTAssertTrue(valid);
```

---

### DatabaseMigrationTests
**File:** `Tests/Database/DatabaseMigrationTests.m`

**Purpose:** Database schema migration testing.

---

### MultiTenantDatabaseTests
**File:** `Tests/Database/MultiTenantDatabaseTests.m`

**Purpose:** Multi-tenant database isolation testing.

---

## Pool Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| Max Size | 100 | Maximum open stores |
| Timeout | 30s | Acquire timeout |
| Eviction | LRU | Eviction policy |

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/DatabasePoolTests
./build/tests/AllTests -only-testing:AllTests/PDSDatabaseIntegrationTests
```

## Related Documentation

- [Folder README](README) - Database tests overview
- [Test Index](../README) - Main test documentation index
- [Actor Store Tests](actor-store) - Per-user storage
- [Service Databases Tests](service-databases) - Global service databases
- [Application Tests](../04-application/README) - Application using pools
- <!-- Link placeholder: Concurrency Audit --> - Thread safety
