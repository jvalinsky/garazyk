# Merkle Search Tree Tests

Tests for MST (Merkle Search Tree) operations, persistence, and repository commits.

## Test Classes

### MSTInteropTests
**File:** `Tests/Repository/MSTInteropTests.m`

**Purpose:** Verifies MST implementation matches Go/TypeScript reference implementations.

#### How It Works

**Reference Vectors:** Tests use pre-computed CID values from the Go implementation (`indigo/mst/mst_interop_test.go`). These vectors are the "ground truth" - if our Objective-C implementation produces different CIDs, it's wrong.

```objc
// Empty tree has a known root CID
MST *emptyMST = [[MST alloc] init];
XCTAssertEqualObjects(emptyMST.rootCID.stringValue, 
    @"bafyreie5737gdxlw5i64vzichcalba3z2v5n6icifvx5xytvske7mr3hpm");
```

**Depth Computation:** The core MST algorithm determines tree depth by counting leading zero bytes in SHA-256(key):

```objc
// "blue" → SHA-256 starts with 0x00 → depth 1
XCTAssertEqual([MST keyDepthBytes:[@"blue" dataUsingEncoding:NSUTF8StringEncoding]], 1);

// "b" → SHA-256 starts with 0x00 0x00 → depth 2  
XCTAssertEqual([MST keyDepthBytes:[@"b" dataUsingEncoding:NSUTF8StringEncoding]], 1);
```

**Layer Transitions:** Tests verify that inserting/deleting keys causes correct layer changes:

```objc
// Insert key that causes layer change from L0 to L2
[mst put:@"com.example.record/3jqfcqzm3fx2j" valueCID:cid1];
XCTAssertEqualObjects(mst.rootCID.stringValue, l2root);

// Delete same key causes layer collapse back to L0
[mst delete:@"com.example.record/3jqfcqzm3fx2j"];
XCTAssertEqualObjects(mst.rootCID.stringValue, l0root);
```

#### Why It Matters

**Protocol Interoperability:** Different PDS implementations (Go, TypeScript, Objective-C) must produce identical MST structures for the same data. A single bit difference in the root CID would cause:

1. Fork detection during sync
2. Signature verification failures
3. Network partitioning

**Deterministic Hashing:** MST relies on:
- SHA-256 for key depth (leading zeros)
- CBOR canonical encoding for node serialization
- Lexicographic key ordering

Any non-determinism breaks consensus.

**Test Methods:**

| Method | What It Verifies |
|--------|------------------|
| `testLeadingZeros` | Depth = count of SHA-256 leading zeros |
| `testInteropKnownMaps` | Root CIDs match reference vectors |
| `testInteropEdgeCasesTrimTop` | Layer collapse on deletion |
| `testInteropEdgeCasesInsertion` | Layer expansion on insertion |
| `testPrefixLen` | Common prefix computation |
| `testPutAndGet` | Basic CRUD operations |
| `testDeletion` | Delete returns tree to known state |
| `testListing` | Entries in sorted order |
| `testDiffFrom` | Detect additions/updates/deletions |

---

### MSTPersistenceTests
**File:** `Tests/Repository/MSTPersistenceTests.m`

**Purpose:** MST persistence layer loading from database-stored CAR blocks.

#### How It Works

**Round-trip test** creates MST, exports to CAR, stores in database, then loads back:

```objc
// 1. Create MST and add entries
MST *mst = [[MST alloc] init];
[mst put:@"app.bsky.feed.post/abc123" valueCID:cid1];

// 2. Export to CAR format
NSData *carData = [mst exportToCAR];

// 3. Store blocks in database
for (CID *cid in [carReader allCIDs]) {
    [db putBlock:cid data:blockData];
}

// 4. Load MST from database
MST *loaded = [MST loadFromDatabase:db forDID:did];
XCTAssertEqualObjects(loaded.rootCID, mst.rootCID);
```

**Real-world fixture** tests against actual repository data:

```objc
// Uses Tests/fixtures/greenground.repo.car
NSData *carData = [NSData dataWithContentsOfFile:fixturePath];
MST *mst = [MST loadFromCAR:carData];
XCTAssertGreaterThan(mst.entryCount, 0);
```

#### Why It Matters

**Persistence Correctness:** If the MST can't be faithfully reconstructed from stored blocks:
- Repository sync will fail
- Data loss on restart
- CID mismatches

**Test Methods:**

| Method | What It Verifies |
|--------|------------------|
| `testLoadMSTForDidReconstructsFromCAR` | Round-trip persistence |
| `testLoadMSTForDidReconstructsFromRealCARFixture` | Real-world data parsing |

---

### RepoCommitTests
**File:** `Tests/Repository/RepoCommitTests.m`

**Purpose:** Repository commit creation, CBOR serialization, and secp256k1 signing.

#### How It Works

**Commit Structure:**

```objc
RepoCommit *commit = [[RepoCommit alloc] init];
commit.did = @"did:plc:abc123";
commit.dataCID = mst.rootCID;  // Links to MST root
commit.rev = @"3jqfcqzm3fo2j"; // TID for ordering
commit.prev = previousCommitCID; // Links to history
```

**Signing with secp256k1:**

```objc
Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
NSData *signature = [commit signWithKey:keyPair.privateKey error:&error];
XCTAssertEqual(signature.length, 64); // r || s format
```

**Verification:**

```objc
BOOL valid = [commit verifySignatureWithKey:keyPair.publicKey error:&error];
XCTAssertTrue(valid);

// Tampering detected
commit.dataCID = differentCID;
valid = [commit verifySignatureWithKey:keyPair.publicKey error:&error];
XCTAssertFalse(valid);
```

#### Why It Matters

**Cryptographic Integrity:** Commits are the "blocks" of the repository chain. Each commit:
1. Links to previous commit (tamper-evident history)
2. Contains MST root (verifies entire repo state)
3. Signed by author's key (non-repudiation)

If any part of the repository is modified, the commit signature breaks.

**Test Methods:**

| Method | What It Verifies |
|--------|------------------|
| `testCommitCreation` | Basic structure |
| `testCommitSigning` | 64-byte secp256k1 signature |
| `testCommitSignatureVerification` | Valid signature accepted |
| `testCommitSignatureVerificationFailsWithWrongKey` | Wrong key rejected |
| `testCommitSignatureVerificationFailsOnTamperedData` | Tampering detected |
| `testCommitCID` | Deterministic CID computation |
| `testCommitParsingFromCAR` | Round-trip through CAR |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/MSTInteropTests
./build/tests/AllTests -only-testing:AllTests/MSTPersistenceTests
./build/tests/AllTests -only-testing:AllTests/RepoCommitTests
```

## MST Structure

```
MST
├── Depth = count of leading zeros in SHA-256(key)
├── Keys sorted lexicographically within each layer
├── Each node has CID linking to children
└── Root CID commits entire tree state

Example:
    Key: "app.bsky.feed.post/abc123"
    SHA-256: 0x00 0x00 0x5a ... (2 leading zeros)
    Depth: 2
    Layer: L2
```

## Key Algorithms

### Depth Computation
```
depth(key) = count_leading_zeros(SHA-256(key))
```

### Tree Structure
- Keys with depth 0 go in root layer
- Keys with depth 1 go one level down
- Higher depth = deeper in tree

### CID Computation
```
node_cid = CID(SHA-256(CBOR_encode(node)))
```

## References

- [ATProto Repository Spec](https://atproto.com/specs/repository)
- [MST Implementation Guide](https://atproto.com/specs/mst)
- [Go Reference](https://github.com/bluesky-social/indigo/tree/main/mst)
