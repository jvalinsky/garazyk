---
title: Data Validation and Repair Plan
---

# Data Validation and Repair Plan

**Date:** January 11, 2026
**Status:** Draft

## 1. Problem Statement

Current data in the PDS databases does not conform to the AT Protocol specifications. This was identified by comparing generated identifiers against the official specs.

### Issues Identified

| Identifier | Current Format | Spec Requirement | Status |
|------------|----------------|------------------|--------|
| **DID** | `did:plc:UUID` (Uppercase, Hyphens)<br>Example: `did:plc:AF85A362-B87D-4858-BCE5-85BD4EFC6E1D` | `did:plc:24charBase32` (Lowercase, a-z0-9)<br>Regex: `^did:plc:[a-z0-9]{24}$` | 🔴 **Critical** |
| **CID** | Uppercase Base32<br>Example: `bAFKTO...` | Lowercase Base32 (CIDv1)<br>Example: `bafyrei...` | 🔴 **Critical** |
| **Handle** | `alice.test` | Valid syntax, but `.test` reserved for dev. | 🟡 **Warning** (Acceptable for dev) |
| **TID** | `223mc4a55jfg4` | 13-char Base32-sortable | 🟢 **Pass** |

## 2. Remediation Plan

### Phase 1: Implementation of Standard Generators
We need to update the generation logic to strictly follow the AT Protocol specs.

1.  **DID Generation (`PDSAccountService`)**
    -   Replace UUID generation with `did:plc` compatible generator.
    -   Algorithm: 24 characters from base32 alphabet (lowercase), no hyphens.

2.  **CID Generation (`PDSRecordService`, `PDSBlobService`)**
    -   Ensure `generateCIDForData` produces strictly lowercase base32 strings.
    -   Verify prefix `bafyrei` (CIDv1 + dag-cbor + sha2-256).

### Phase 2: Validation Logic
Add a centralized `ATProtoValidator` class to enforce formats.

1.  **Methods**:
    -   `validateDID:(NSString *)did`
    -   `validateHandle:(NSString *)handle`
    -   `validateCID:(NSString *)cid`
    -   `validateTID:(NSString *)tid`

2.  **Integration**:
    -   Call validation in `createAccount`, `putRecord`, etc.

### Phase 3: Testing
Add unit tests to verify compliance.

1.  **`IdentifierTests.m`**:
    -   Test DID generation matches regex.
    -   Test CID generation is lowercase.
    -   Test Validator rejects invalid formats (e.g., uppercase DIDs).

### Phase 4: Data Repair (Wipe & Regen)
Since the current data is fundamentally non-conforming (DIDs are primary keys), migration is not feasible. We will wipe and regenerate.

1.  **Wipe Script**:
    -   Stop server.
    -   Delete `data/`.

2.  **Regeneration Script**:
    -   Start server.
    -   Run account creation script (Alice, Bob, Charlie, Dana).
    -   Re-run interaction script (Follows, Posts).

## 3. Execution Steps

1.  Create `ATProtoValidator` class.
2.  Update `PDSAccountService` to use correct DID format.
3.  Update `PDSRecordService`/`PDSBlobService` to use correct CID format.
4.  Add `IdentifierTests` and verify all pass.
5.  Execute Wipe & Regen.
6.  Verify new data with `sqlite3` inspection.

---

## Technical Details

### Correct DID Generator (Objective-C)
```objectivec
- (NSString *)generatePlcIdentifier {
    static NSString *const kBase32Chars = @"abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *str = [NSMutableString stringWithCapacity:24];
    for (int i = 0; i < 24; i++) {
        uint32_t idx = arc4random_uniform((uint32_t)kBase32Chars.length);
        [str appendFormat:@"%C", [kBase32Chars characterAtIndex:idx]];
    }
    return [NSString stringWithFormat:@"did:plc:%@", str];
}
```

### Correct CID Generator
Ensure output is lowercase:
```objectivec
// After generating hex string
return [NSString stringWithFormat:@"bafyrei%@", [hashString lowercaseString]];
```

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
