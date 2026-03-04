---
title: Service Databases Tests
---

# Service Databases Tests

Tests for global service databases handling accounts, invite codes, DID cache, and handle reservations.

## Test Classes

### ServiceDatabasesTests
**File:** `Tests/Database/Service/ServiceDatabasesTests.m`

**Purpose:** Multi-pool service database manager for accounts, invites, DID cache, handle reservations.

#### How It Works

**Three-pool architecture:**

```objc
PDSServiceDatabases *services = [[PDSServiceDatabases alloc] initWithDirectory:dir];

// Main service pool - accounts, invites
PDSActorStore *accountStore = [services.pool acquireStoreForDID:@"did:plc:abc" error:nil];

// DID cache pool - cached DID documents
PDSActorStore *didCache = [services.didCache acquireStoreForDID:@"did:plc:xyz" error:nil];

// Sequencer pool - event ordering
PDSActorStore *sequencer = [services.sequencer acquireStoreForDID:@"events" error:nil];
```

**Invite code lifecycle:**

```objc
// Create invite code
NSString *code = [services createInviteCodeForAccount:@"did:plc:admin" 
                                            available:YES 
                                                uses:5 
                                                error:nil];

// Use invite code
BOOL used = [services useInviteCode:code forAccount:@"did:plc:newuser" error:nil];
XCTAssertTrue(used);

// Check availability
InviteCode *info = [services getInviteCode:code error:nil];
XCTAssertEqual(info.usesRemaining, 4);
```

**Handle reservation with persistence:**

```objc
// Reserve handle
[services reserveHandle:@"alice.example.com" error:nil];

// Verify reservation
BOOL reserved = [services isHandleReserved:@"alice.example.com"];
XCTAssertTrue(reserved);

// Close and reopen
[services closeAll];
services = [[PDSServiceDatabases alloc] initWithDirectory:dir];

// Reservation persists
reserved = [services isHandleReserved:@"alice.example.com"];
XCTAssertTrue(reserved, "Handle reservation must survive restart");
```

#### Why It Matters

| Feature | Why It's Critical |
|---------|-------------------|
| Handle reservation | Prevents TOCTOU races during registration |
| DID caching with TTL | Reduces network latency, ensures freshness |
| Invite codes | Enforces invite-only onboarding |

**TOCTOU vulnerability**: Without atomic handle reservation, two users could both check availability, then both claim the same handle.

| Method | What It Verifies |
|--------|------------------|
| `testAccountCreation` | Create/fetch by DID |
| `testInviteCodeOperations` | Create/get/use flow |
| `testReservedHandlePersistsAcrossReopen` | Persistence |
| `testDIDCachingExpiry` | TTL enforcement |

---

### ServiceDatabasesPruningTests
**File:** `Tests/ServiceDatabasesPruningTests.m`

**Purpose:** Time-based event pruning for database maintenance.

#### How It Works

```objc
// Insert old events
[services insertEvent:@"event1" data:data1 timestamp:now - 86400 * 7];  // 7 days ago
[services insertEvent:@"event2" data:data2 timestamp:now - 3600];        // 1 hour ago

// Prune events older than 24 hours
NSUInteger pruned = [services pruneEventsOlderThan:86400 error:nil];
XCTAssertEqual(pruned, 1);  // Only event1 pruned

// Verify recent event retained
Event *event = [services getEvent:@"event2"];
XCTAssertNotNil(event);
```

---

### PDSHealthCheckTests
**File:** `Tests/Database/Monitoring/PDSHealthCheckTests.m`

**Purpose:** Health status detection for databases.

#### How It Works

```objc
PDSHealthCheck *health = [[PDSHealthCheck alloc] initWithDatabasePath:dbPath];

// Healthy database
PDSHealthStatus *status = [health check];
XCTAssertEqual(status.status, PDSHealthStatusHealthy);

// Corrupt database
[corruptedData writeToURL:dbURL options:0 error:nil];
status = [health check];
XCTAssertEqual(status.status, PDSHealthStatusCritical);

// Missing database - auto-recreate
[[NSFileManager defaultManager] removeItemAtURL:dbURL error:nil];
status = [health check];
XCTAssertEqual(status.status, PDSHealthStatusHealthy);  // Re-created
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ServiceDatabasesTests
./build/tests/AllTests -only-testing:AllTests/ServiceDatabasesPruningTests
./build/tests/AllTests -only-testing:AllTests/PDSHealthCheckTests
```

## Service Database Schema

```sql
-- Accounts
CREATE TABLE accounts (
    did TEXT PRIMARY KEY,
    handle TEXT UNIQUE,
    email TEXT,
    passwordHash TEXT,
    createdAt INTEGER
);

-- Invite Codes
CREATE TABLE invite_codes (
    code TEXT PRIMARY KEY,
    available INTEGER,
    forAccount TEXT,
    createdBy TEXT,
    createdAt INTEGER
);

-- DID Cache
CREATE TABLE did_cache (
    did TEXT PRIMARY KEY,
    document TEXT,
    cachedAt INTEGER
);

-- Handle Reservations
CREATE TABLE reserved_handles (
    handle TEXT PRIMARY KEY,
    reservedAt INTEGER
);
```

## Related Documentation

- [Folder README](README) - Database tests overview
- [Test Index](../README) - Main test documentation index
- [Actor Store Tests](actor-store) - Per-user storage
- [Pool Integration Tests](pool-integration) - Connection pooling
- [Identity Resolution Tests](../00-identity-auth/identity-resolution) - DID caching
- [Admin Tests](../04-application/admin) - Admin invite code management
- [Security Tests](../05-security/README) - TOCTOU prevention
