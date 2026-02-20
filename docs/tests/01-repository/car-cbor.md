# CAR & CBOR Tests

Tests for CAR file format and DAG-CBOR encoding.

## Test Classes

### CARInteropTests
**File:** `Tests/Repository/CARInteropTests.m`

**Purpose:** CAR (Content Addressable aRchive) v1 format reading, writing, and block lookup.

#### How It Works

**CAR v1 format structure:**

```
[varint header-length][header][blocks...]
header = { "roots": [<cid>...], "version": 1 }
block = [varint cid-length][cid][bytes]
```

**Manual CAR construction for testing:**

```objc
NSMutableData *carData = [NSMutableData data];

// Header: {"roots":[],"version":1}
NSData *headerData = [NSJSONSerialization dataWithJSONObject:@{
    @"roots": @[],
    @"version": @1
} options:0 error:nil];
uint64_t headerLen = headerData.length;
[carData appendBytes:&headerLen length:sizeof(uint64_t)];
[carData appendData:headerData];

// Block
NSData *blockData = [@"test block content" dataUsingEncoding:NSUTF8StringEncoding];
CID *cid = [CID cidWithSHA256OfData:blockData];
// ... encode cid and data
```

**Round-trip verification:**

```objc
CARWriter *writer = [[CARWriter alloc] init];
[writer putBlock:cid data:blockData];
NSData *carData = [writer serialize];

CARReader *reader = [[CARReader alloc] initWithData:carData error:nil];
NSData *readData = [reader getBlock:cid];
XCTAssertEqualObjects(readData, blockData, "Round-trip must preserve data");
```

#### Why It Matters

| Feature | Purpose |
|---------|---------|
| Root CID list | Entry points for traversal |
| Block CID = SHA-256(content) | Content-addressed storage |
| Varint encoding | Efficient size encoding |

CAR files are the standard transport format for ATProto repository sync.

| Method | What It Verifies |
|--------|------------------|
| `testCARv1HeaderParsing` | Header correctly parsed |
| `testCARv1RoundTrip` | Write → read preserves data |
| `testCARv1BlockLookup` | CID-based block retrieval |

---

### ATProtoDagCBORTests
**File:** `Tests/Core/ATProtoDagCBORTests.m`

**Purpose:** DAG-CBOR encoding/decoding with canonical ordering and CID links.

#### How It Works

**Canonical map ordering** - keys sorted by length then lexicographically:

```objc
NSDictionary *map = @{
    @"z": @1,      // Length 1
    @"aa": @2,     // Length 2
    @"bb": @3,     // Length 2
    @"ccc": @4     // Length 3
};
NSData *encoded = [DagCBOR encodeMap:map error:nil];

// Encoding order: "z", "aa", "bb", "ccc" (length-first, then lex)
```

**CID encoding as CBOR tag 42:**

```objc
CID *cid = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
NSDictionary *map = @{@"$link": cid.stringValue};
NSData *encoded = [DagCBOR encodeMap:map error:nil];

// Decoded back to CID object
CBORValue *decoded = [CBORValue decodeFromData:encoded error:nil];
XCTAssertTrue(decoded.isCIDLink);
```

**Float rejection** (DAG-CBOR restriction):**

```objc
NSData *data = [DagCBOR encodeValue:@3.14 error:&error];
XCTAssertNil(data, "Floats must be rejected in DAG-CBOR");
```

#### Why It Matters

| Property | Why It's Required |
|----------|-------------------|
| Canonical ordering | Deterministic hashes for signatures |
| CID as tag 42 | IPLD compatibility |
| No floats | Precision issues across implementations |

**Canonical encoding is critical** for signature verification. If the same data encodes differently, the signature breaks.

| Method | What It Verifies |
|--------|------------------|
| `testCanonicalMapOrdering` | Length-first, then lex |
| `testEncodeCIDLink` | Tag 42 for CIDs |
| `testRejectFloats` | Floats rejected |
| `testConvert$LinkToCID` | JSON interop |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/CARInteropTests
./build/tests/AllTests -only-testing:AllTests/ATProtoDagCBORTests
```

## References

- [CAR v1 Spec](https://ipld.io/specs/transport/car/carv1/)
- [DAG-CBOR Spec](https://ipld.io/specs/codecs/dag-cbor/spec/)

## Related Documentation

- [Folder README](README.md) - Repository tests overview
- [Test Index](../README.md) - Main test documentation index
- [MST Tests](mst.md) - Merkle Search Tree tests
- [Primitives Tests](primitives.md) - Core data type tests
- [Database Tests](../03-database/README.md) - Actor store persistence
- [Integration Tests](../06-integration/README.md) - E2E repository operations
- [Characterization Tests](../08-characterization/characterization.md) - Reference compliance
- [Security Hardening](../05-security/hardening.md) - CBOR parser security
