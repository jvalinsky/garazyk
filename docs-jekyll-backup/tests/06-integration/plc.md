# PLC Directory Tests

Tests for PLC DID operations, server, and key parsing.

## CI Integration

The `plc-integration-tests` job in `.github/workflows/ci.yml` runs PLC-specific tests after the main build passes:

```yaml
- name: Run PLC-specific tests
  run: |
    ctest --test-dir build --output-on-failure -R "PLC|DID|Identity"
```

## Test Classes

### PDSPLCIntegrationTests
**File:** `Tests/Integration/PDSPLCIntegrationTests.m`

**Purpose:** PLC DID integration testing.

---

### PLCServerTests
**File:** `Tests/PLC/PLCServerTests.m`

**Purpose:** Local PLC server for development/testing.

#### How It Works

**Local PLC server:**

```objc
PLCServer *server = [[PLCServer alloc] initWithPort:2584];
[server startWithError:nil];

// Register DID
NSDictionary *doc = [server createDIDWithKey:publicKey handle:@"user.example.com"];

// Resolve DID
NSDictionary *resolved = [server resolveDID:doc[@"id"]];
XCTAssertEqualObjects(resolved[@"id"], doc[@"id"]);
```

---

### PLCStoreTests
**File:** `Tests/PLC/PLCStoreTests.m`

**Purpose:** PLC operation storage.

#### How It Works

```objc
PLCStore *store = [[PLCStore alloc] initWithDatabasePath:dbPath];

// Store operation
PLCOperation *op = [[PLCOperation alloc] initWithType:PLCOperationTypeCreate
                                                  did:@"did:plc:abc"
                                              keyBytes:publicKey
                                              handle:@"user.example.com"];
[store putOperation:op error:nil];

// Get DID operations
NSArray *ops = [store getOperationsForDID:@"did:plc:abc" error:nil];
XCTAssertEqual(ops.count, 1);
```

---

### PLCOperationTests
**File:** `Tests/PLC/PLCOperationTests.m`

**Purpose:** PLC operation creation and verification.

---

### PLCAuditorTests
**File:** `Tests/PLC/PLCAuditorTests.m`

**Purpose:** PLC operation audit logging.

---

### PLCCacheDirectoryTests
**File:** `Tests/PLC/PLCCacheDirectoryTests.m`

**Purpose:** PLC document caching.

---

### PLCDIDKeyTests
**File:** `Tests/PLC/PLCDIDKeyTests.m`

**Purpose:** did:key parsing from PLC documents.

#### How It Works

**Base58btc decoding:**

```objc
// did:key:zQ3sh... → extract public key
NSString *didKey = @"did:key:zQ3shZc2QzApp2oymGvQbzP8eKheVshBHbU4ZYjeXqwSKEn6N";

NSData *keyBytes = [PLCDIDKey publicKeyFromDidKey:didKey error:nil];
XCTAssertEqual(keyBytes.length, 33);  // Compressed secp256k1
```

---

### PLCRotationKeyManager (Integration)
**File:** `Sources/PLC/PLCRotationKeyManager.m`

**Purpose:** Server-level rotation key management for PLC operations.

#### How It Works

- Generates and persists a secp256k1 key for signing PLC operations
- Key stored at `data/plc_rotation_key.bin`
- Used by `signPlcOperation` and account registration

---

### signPlcOperation / submitPlcOperation (E2E)
**Purpose:** End-to-end PLC operation signing and submission.

#### Validation Checks

| Check | Error Code |
|-------|------------|
| Server rotation key in rotationKeys | `InvalidRequest` |
| services.atproto_pds.type correct | `InvalidRequest` |
| services.atproto_pds.endpoint matches | `InvalidRequest` |
| alsoKnownAs contains handle | `InvalidRequest` |
| prev matches last op CID | `InvalidRequest` |
| Account tombstoned | `AccountTombstoned` |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSPLCIntegrationTests
./build/tests/AllTests -only-testing:AllTests/PLCServerTests
./build/tests/AllTests -only-testing:AllTests/PLCDIDKeyTests
```

## PLC Operation Types

| Type | Purpose |
|------|---------|
| create | Initialize DID document |
| update | Modify verification methods |
| tombstone | Deactivate DID |

## Related Documentation

- [Folder README](README.md) - Integration tests overview
- [Test Index](../README.md) - Main test documentation index
- [E2E Tests](e2e.md) - End-to-end flows
- [Federation Tests](federation.md) - Cross-PDS communication
- [Identity Resolution Tests](../00-identity-auth/identity-resolution.md) - DID resolution
- [JWT & Crypto Tests](../00-identity-auth/jwt-crypto.md) - Secp256k1 keys
- [Primitives Tests](../01-repository/primitives.md) - DID validation
