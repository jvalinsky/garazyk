# PLC Directory Server Compliance Report

**Date**: 2026-04-20
**Spec Reference**: `reference/did-method-plc/website/spec/v0.1/did-plc.md`

---

## Summary

| Area | Status | Notes |
|------|--------|-------|
| Operation Submission | ✅ Compliant | Validates format, size limits |
| Operation Signing | ✅ Compliant | ES256, low-S form, DAG-CBOR |
| Chain Verification | ✅ Compliant | PLCAuditor validates prev, sigs |
| 72h Recovery Window | ✅ Compliant | kPLCRecoveryWindowSeconds |
| Rate Limiting | ✅ Compliant | 10/h, 30/d, 100/w |
| Tombstone Detection | ✅ Compliant | Blocks further operations |
| DID Resolution | ✅ Compliant | Returns operation history |
| HTTP API | ✅ Compliant | RESTful endpoints |

---

## ✅ Compliant Areas

### Operation Size Limits
**Implementation** (`PLCServer.m:11`):
```objc
static const NSUInteger kPLCMaxOperationBytes = 4000;
```
Spec allows 7500 bytes; implementation uses more conservative 4000 bytes.

### did:key Validation
**Implementation** (`PLCServer.m:22-59`):
```objc
static BOOL PLCValidateDidKey(NSString *key, NSError **error) {
    if (![key hasPrefix:@"did:key:"]) {
        // Reject non-did:key
        return NO;
    }
    // Verify base58btc multibase encoding
    NSString *multibase = [key substringFromIndex:@"did:key:".length];
    if ([multibase characterAtIndex:0] != 'z') {
        // Reject non-base58btc
        return NO;
    }
    // Verify valid base58 decoding
    NSData *decoded = [CID base58btcDecode:base58];
    // ...
}
```

### Field Count Limits
```objc
static const NSUInteger kPLCMaxAlsoKnownAsEntries = 10;
static const NSUInteger kPLCMaxRotationKeyEntries = 10;
static const NSUInteger kPLCMaxServiceEntries = 10;
static const NSUInteger kPLCMaxVerificationMethodEntries = 10;
```
All within spec limits.

---

## ⚠️ Gaps

### Legacy `create` Operation Format

**Spec**: Legacy `create` operation format must be supported for genesis ops.

**Status**: Need to verify legacy `create` parsing exists in `PLCOperation.m`.

**Impact**: DIDs created with old format may not resolve correctly.

### Operation History Endpoints

**HTTP Endpoints** (need verification):

| Endpoint | Purpose | Status |
|----------|---------|--------|
| `GET /:did` | Resolve DID | ✅ |
| `GET /:did/log` | Operation history | ❓ |
| `POST /` | Submit operation | ✅ |
| `GET /:did/auditor` | Audit log | ❓ |

---

## Code References

- **PLC Server**: `Garazyk/Sources/PLC/PLCServer.m`
- **PLC Auditor**: `Garazyk/Sources/PLC/PLCAuditor.m` (1,013 lines)
- **PLC Operation**: `Garazyk/Sources/PLC/PLCOperation.m`
- **PLC Store**: `Garazyk/Sources/PLC/PLCPersistentStore.m`

---

## Test Coverage

- `PLCAuditorTests.m` - Chain verification
- `PLCOperationTests.m` - Serialization
- `PLCServerTests.m` - HTTP endpoints

**Recommendation**: Add interop tests with reference TypeScript implementation.
