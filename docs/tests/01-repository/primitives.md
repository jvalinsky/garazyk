# Core Primitives Tests

Tests for fundamental data types: CIDs, TIDs, DIDs, handles, and validation.

## Test Classes

### ATProtoCoreTests
**File:** `Tests/Core/ATProtoCoreTests.m`

**Purpose:** Core ATProto primitives including CID, TID, CBOR, MST, and JWT.

#### How It Works

**CID creation and verification:**

```objc
CID *cid = [CID cidWithSHA256OfData:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]];
XCTAssertNotNil(cid.stringValue);  // "bafyrei..."
XCTAssertEqual(cid.codec, 0x71);   // dag-cbor

// CID equality
CID *cid2 = [CID cidFromString:cid.stringValue];
XCTAssertEqualObjects(cid, cid2);
```

**TID generation and ordering:**

```objc
NSString *tid1 = [TID generate];
NSString *tid2 = [TID generate];

XCTAssertEqual(tid1.length, 14);
XCTAssertNotEqualObjects(tid1, tid2, "TIDs must be unique");

// Later TIDs sort after earlier ones
XCTAssert([tid2 compare:tid1] > 0, "TIDs must be time-ordered");
```

**CBOR encoding:**

```objc
NSDictionary *map = @{@"key": @"value", @"number": @42};
NSData *encoded = [CBOR encodeMap:map error:nil];

NSDictionary *decoded = [CBOR decodeMapFromData:encoded error:nil];
XCTAssertEqualObjects(decoded[@"key"], @"value");
```

#### Why It Matters

| Primitive | Use Case |
|-----------|----------|
| CID | Content-addressed references |
| TID | Time-ordered record keys |
| CBOR | Binary serialization |

| Method | What It Verifies |
|--------|------------------|
| `testCIDCreation` | CID with multihash/codec |
| `testTIDUniqueness` | 100 unique TIDs |
| `testTIDOrdering` | Monotonicity |
| `testCBORRoundTrip` | Encode → decode preserves data |

---

### Base58Tests
**File:** `Tests/Core/Base58Tests.m`

**Purpose:** Base58 (Bitcoin alphabet) encoding and decoding.

#### How It Works

```objc
// Encode
NSData *data = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
NSString *encoded = [Base58 encode:data];
XCTAssertEqualObjects(encoded, @"StV1DL6CwTryKyV");

// Decode
NSData *decoded = [Base58 decode:encoded];
XCTAssertEqualObjects(decoded, data);

// Invalid characters rejected
decoded = [Base58 decode:@"0OIl"];  // Contains invalid chars
XCTAssertNil(decoded);
```

#### Why It Matters

Base58 avoids ambiguous characters (0, O, I, l) making it suitable for human-readable identifiers like did:key.

---

### DIDValidationTests
**File:** `Tests/Core/DIDValidationTests.m`

**Purpose:** DID validation for PLC and Web methods.

#### How It Works

**did:plc validation:**

```objc
XCTAssertTrue([DIDValidator isValidPLC:@"did:plc:z72i7hdynmk6r22z27h6tvurm"]);
// 24-char base32lower after prefix

XCTAssertFalse([DIDValidator isValidPLC:@"did:plc:tooShort"]);
XCTAssertFalse([DIDValidator isValidPLC:@"did:plc:INVALIDCHARS12345678"]);  // Uppercase
```

**did:web validation:**

```objc
XCTAssertTrue([DIDValidator isValidWeb:@"did:web:example.com"]);
XCTAssertTrue([DIDValidator isValidWeb:@"did:web:localhost"]);

XCTAssertFalse([DIDValidator isValidWeb:@"did:web:.onion"]);   // Forbidden TLD
XCTAssertFalse([DIDValidator isValidWeb:@"did:web:192.168.1.1"]); // Private IP
```

#### Why It Matters

| DID Type | Rules |
|----------|-------|
| did:plc | 24-char base32lower |
| did:web | Valid hostname, no .onion/.exit |

---

### RecordPathValidationTests
**File:** `Tests/Core/RecordPathValidationTests.m`

**Purpose:** Record path, NSID, TID, and record key validation.

#### How It Works

```objc
// Valid paths
XCTAssertTrue([RecordPathValidator isValidPath:@"app.bsky.feed.post/abc123"]);

// Invalid paths
XCTAssertFalse([RecordPathValidator isValidPath:@"/leading/slash"]);
XCTAssertFalse([RecordPathValidator isValidPath:@"collection/."]);      // . is reserved
XCTAssertFalse([RecordPathValidator isValidPath:@"collection/.."]);     // .. is reserved

// NSID validation
XCTAssertTrue([NSIDValidator isValid:@"app.bsky.feed.post"]);
XCTAssertFalse([NSIDValidator isValid:@"App.Bsky.Feed.Post"]);  // Uppercase
```

#### Why It Matters

| Component | Rules |
|-----------|-------|
| Collection (NSID) | Lowercase, dotted |
| Record key | Printable ASCII, not `.` or `..` |
| Max length | 512 characters total |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ATProtoCoreTests
./build/tests/AllTests -only-testing:AllTests/Base58Tests
./build/tests/AllTests -only-testing:AllTests/DIDValidationTests
./build/tests/AllTests -only-testing:AllTests/RecordPathValidationTests
```

## Related Documentation

- [Folder README](README) - Repository tests overview
- [Test Index](../README) - Main test documentation index
- [MST Tests](mst) - Merkle Search Tree tests
- [CAR & CBOR Tests](car-cbor) - CAR file format tests
- [Identity Resolution Tests](../00-identity-auth/identity-resolution) - DID resolution
- [XRPC Tests](../02-network/xrpc) - NSID validation in XRPC
- [Validation Tests](../05-security/validation) - Input validation security
