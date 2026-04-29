# Repository Protocol Compliance Report

**Date**: 2026-04-20
**Spec Reference**: https://atproto.com/specs/repository
**Reference Implementation**: `reference/atproto/packages/repo/`

---

## Summary

| Area | Status | Notes |
|------|--------|-------|
| MST Structure | ✅ Compliant | Key-depth algorithm matches reference |
| MST Node Serialization | ✅ Compliant | DAG-CBOR format correct |
| CAR v1 Format | ✅ Compliant | Header and block encoding match spec |
| DAG-CBOR Encoding | ✅ Compliant | Tag 42 CID-links, canonical ordering |
| TID Generation | ✅ Compliant | 53-bit timestamp, base32-sortable |
| Commit Structure | ✅ Compliant | did, version, data, rev, prev, sig |

---

## ✅ Compliant Sections

### MST Key-Depth Computation

**Spec**: Keys are hashed with SHA-256 and leading zeros counted with 2-bit granularity.

**Reference** (`reference/atproto/packages/repo/src/mst/util.ts:23-38`):
```typescript
export const leadingZerosOnHash = async (key: string | Uint8Array) => {
  const hash = await sha256(key)
  let leadingZeros = 0
  for (let i = 0; i < hash.length; i++) {
    const byte = hash[i]
    if (byte < 64) leadingZeros++
    if (byte < 16) leadingZeros++
    if (byte < 4) leadingZeros++
    if (byte === 0) {
      leadingZeros++
    } else {
      break
    }
  }
  return leadingZeros
}
```

**Implementation** (`Garazyk/Sources/Repository/MST.m:426-462`):
```objc
+ (uint32_t)keyDepthFromBytes:(const uint8_t *)bytes length:(NSUInteger)len {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, (CC_LONG)len, hash);

    uint32_t depth = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];
        if (byte == 0) {
            depth += 4;
            continue;
        }
        if ((byte & 0xC0) == 0) {
            depth++;
            if ((byte & 0x30) == 0) {
                depth++;
                if ((byte & 0x0C) == 0) {
                    depth++;
                }
            }
        }
        break;
    }
    return depth;
}
```

**Verification**: Python comparison of both algorithms produced identical results across test cases including multi-byte zero sequences.

---

### DAG-CBOR CID-Link Encoding

**Spec**: CIDs are encoded as CBOR tag 42 with byte string containing `0x00 || CID_BYTES`.

**Implementation** (`Garazyk/Sources/Core/ATProtoDagCBOR.m:430-442`):
```objc
+ (BOOL)_encodeCIDLink:(CID *)cid toData:(NSMutableData *)data error:(NSError **)error {
    // CID-link: tag 42 with byte string containing 0x00 || CID bytes
    NSMutableData *cidBytes = [NSMutableData dataWithCapacity:1 + cid.bytes.length];
    uint8_t marker = 0x00;
    [cidBytes appendBytes:&marker length:1];
    [cidBytes appendData:cid.bytes];

    // Encode tag 42
    uint8_t tagByte = 0xD8; // Major type 6, additional info 24
    uint8_t tagValue = 42;
    [data appendBytes:&tagByte length:1];
    [data appendBytes:&tagValue length:1];
    // ... encode byte string with length
}
```

**Decoding** (`Garazyk/Sources/Core/ATProtoDagCBOR.m:655-693`):
- Correctly validates tag 42 byte string
- Strips leading `0x00` marker
- Returns CID object

---

### CAR v1 Format

**Spec**: CAR v1 header is CBOR-encoded `{ "version": 1, "roots": [...] }` followed by varint-length-prefixed blocks.

**Implementation** (`Garazyk/Sources/Repository/CAR.m`):

**Header Parsing**:
- Correctly reads varint header length
- Parses CBOR header with `version: 1` and `roots` array
- Extracts root CIDs from tagged CBOR

**Block Reading**:
- Reads varint block length
- Extracts CID bytes (first 36 bytes for CIDv1 + sha2-256)
- Decodes block content

**Block Writing**:
- Correct varint encoding for header length
- CBOR header encoding
- Varint block lengths with CID bytes + data

---

### TID Generation

**Spec**: TIDs are 13-character base32-sortable strings encoding 53-bit microsecond timestamps. First character must be in range `234567ab` to ensure timestamp fits in 53 bits.

**Implementation** (`Garazyk/Sources/Core/TID.m`):

- 13-character length validation ✅
- Base32-sortable alphabet: `234567abcdefghijklmnopqrstuvwxyz` ✅
- High-bit restriction: first char in `234567ab` ✅
- Microsecond timestamp encoding ✅

**Validation** (`Garazyk/Sources/Core/ATProtoValidator.m:99-125`):
```objc
static NSString * const alphabet = @"234567abcdefghijklmnopqrstuvwxyz";
static NSString * const allowedFirstChars = @"234567ab";
```

---

### Commit Structure

**Spec**: Repository commits contain:
- `did`: Repository DID
- `version`: Format version (currently 3)
- `data`: Root MST CID (optional for tombstone)
- `rev`: TID revision
- `prev`: Previous commit CID (null for genesis)
- `sig`: secp256k1 signature

**Implementation** (`Garazyk/Sources/Repository/RepoCommit.m`):

```objc
commitDict[@"did"] = self.did;
commitDict[@"version"] = @(self.version);
if (self.dataCID) {
    commitDict[@"data"] = self.dataCID;
}
commitDict[@"rev"] = self.rev;
if (self.prevCID) {
    commitDict[@"prev"] = self.prevCID;
}
if (includeSignature && self.signature) {
    commitDict[@"sig"] = self.signature;
}
```

**CID Computation**:
- Serialized to DAG-CBOR
- SHA-256 hash
- CIDv1 with codec `0x71` (dag-cbor) ✅

---

## ⚠️ Gaps

### Key Validation in MST

**Location**: `MST.m` put operations

**Issue**: Reference implementation validates MST keys with `ensureValidMstKey`:
```typescript
export const isValidMstKey = (str: string): boolean => {
  const split = str.split('/')
  return (
    str.length <= 1024 &&
    split.length === 2 &&
    split[0].length > 0 &&
    split[1].length > 0 &&
    isValidChars(split[0]) &&
    isValidChars(split[1])
  )
}
```

**Status**: Need to verify if garazyk's MST puts validate key format.

---

### MST Rebalancing Tests

**Test Coverage**: `MSTRebalancingTests.m` exists but needs verification against reference test cases.

**Reference Tests**: `reference/atproto/packages/repo/tests/mst.test.ts`

**Gap**: Need interop tests comparing MST structure with reference implementation for same operations.

---

## 🔴 Violations

**None identified** in Repository Protocol area.

---

## Test Coverage

| Test File | Coverage Area | Status |
|-----------|---------------|--------|
| `MSTPersistenceTests.m` | CAR import/export | Exists |
| `MSTRebalancingTests.m` | Tree rotations | Exists |
| `MSTInteropTests.m` | Cross-implementation | Exists |
| `MSTCharacterizationTests.m` | Behavior verification | Exists |
| `CARTests.m` | CAR format | Not checked |

**Recommendation**: Run MST interop tests comparing output with reference test vectors.

---

## References

### Code Locations
- **MST**: `Garazyk/Sources/Repository/MST.m`, `MST.h`
- **CAR**: `Garazyk/Sources/Repository/CAR.m`, `CAR.h`
- **DAG-CBOR**: `Garazyk/Sources/Core/ATProtoDagCBOR.m`
- **TID**: `Garazyk/Sources/Core/TID.m`
- **Commit**: `Garazyk/Sources/Repository/RepoCommit.m`

### Reference Files
- `reference/atproto/packages/repo/src/mst/mst.ts`
- `reference/atproto/packages/repo/src/mst/util.ts`
- `reference/atproto/packages/repo/src/car.ts`
- `reference/atproto/packages/repo/src/repo.ts`
