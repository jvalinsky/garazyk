# DAG-CBOR Canonical Encoding Fix Design

## Overview

The PDS computes incorrect CIDs for records because `ATProtoCBORSerialization` sorts map keys lexicographically by string value instead of by their CBOR-encoded byte representation. The DAG-CBOR canonical encoding specification requires keys to be sorted by encoded byte length first, then lexicographically. This causes CID mismatches when external clients (like pdsls.dev) re-encode the same record content using correct canonical encoding.

The fix involves replacing the incorrect string-based sorting in `ATProtoCBORSerialization.m` with the correct CBOR-byte-based sorting that already exists in `CBOREncoder` (in `CBOR.m`).

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when a record contains map keys that sort differently under string comparison vs CBOR-byte comparison
- **Property (P)**: The desired behavior - CIDs computed by the PDS match CIDs computed by external clients using canonical DAG-CBOR encoding
- **Preservation**: All existing CBOR encoding/decoding functionality that must remain unchanged
- **ATProtoCBORSerialization**: The class in `ATProtoPDS/Sources/Core/ATProtoCBORSerialization.m` that converts JSON objects to CBOR data for CID computation
- **CBOREncoder**: The class in `ATProtoPDS/Sources/Repository/CBOR.m` that has correct canonical key sorting logic
- **Canonical DAG-CBOR**: CBOR encoding with deterministic map key ordering (by encoded byte length, then lexicographic)
- **CID**: Content Identifier - a cryptographic hash of canonically-encoded content

## Bug Details

### Fault Condition

The bug manifests when a record contains map keys that sort differently under string comparison versus CBOR-encoded byte comparison. The `cborValueFromObject:` method in `ATProtoCBORSerialization` sorts keys using `NSLiteralSearch` string comparison, which does not match the DAG-CBOR canonical encoding specification.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type NSDictionary (record to encode)
  OUTPUT: boolean
  
  keys := input.allKeys
  stringSort := sortKeysLexicographically(keys)
  cborByteSort := sortKeysByCBOREncodedBytes(keys)
  
  RETURN stringSort != cborByteSort
         AND recordIsBeingEncodedForCID(input)
END FUNCTION
```

### Examples

- **Example 1**: Record with keys `{"text": "...", "$type": "...", "createdAt": "..."}` 
  - String sort: `["$type", "createdAt", "text"]` ($ comes before letters)
  - CBOR byte sort: `["text", "$type"]` then `["createdAt"]` (5-byte keys before 9-byte keys)
  - Expected: CID matches external clients
  - Actual: CID differs due to different key ordering

- **Example 2**: Record with keys `{"a": 1, "bb": 2, "ccc": 3}`
  - String sort: `["a", "bb", "ccc"]`
  - CBOR byte sort: `["a", "bb", "ccc"]` (1-byte, 2-byte, 3-byte encoded keys)
  - Expected: CID matches (keys happen to sort the same way)
  - Actual: CID matches (no bug in this case)

- **Example 3**: Record with keys `{"z": 1, "aa": 2}`
  - String sort: `["aa", "z"]`
  - CBOR byte sort: `["z", "aa"]` (1-byte key before 2-byte key)
  - Expected: CID matches external clients
  - Actual: CID differs

- **Edge Case**: Empty map `{}`
  - Expected: Encodes correctly (no keys to sort)
  - Actual: Works correctly

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- CBOR decoding must continue to work exactly as before
- CBOR encoding for non-map types (arrays, strings, numbers, etc.) must remain unchanged
- The `CBOREncoder` class in `CBOR.m` must remain unchanged (it already has correct sorting)
- All existing callers of `ATProtoCBORSerialization` must continue to work without modification

**Scope:**
All inputs that do NOT involve map encoding should be completely unaffected by this fix. This includes:
- Arrays, strings, numbers, booleans, null values
- Nested structures where the parent is not a map
- CBOR decoding operations (only encoding is affected)

## Hypothesized Root Cause

Based on the bug description and code analysis, the root cause is:

1. **Incorrect Sorting Algorithm**: The `cborValueFromObject:` method in `ATProtoCBORSerialization.m` (lines 30-36) sorts keys using:
   ```objc
   NSArray *sortedKeys = [[json allKeys] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
       NSString *s1 = (NSString *)obj1;
       NSString *s2 = (NSString *)obj2;
       return [s1 compare:s2 options:NSLiteralSearch];
   }];
   ```
   This sorts by string value, not by CBOR-encoded byte representation.

2. **Correct Implementation Exists**: The `CBOREncoder` class in `CBOR.m` (lines 485-492) already has the correct sorting logic:
   ```objc
   NSArray *sortedKeys = [keys sortedArrayUsingComparator:^NSComparisonResult(CBORValue *key1, CBORValue *key2) {
       NSData *d1 = [key1 encode];
       NSData *d2 = [key2 encode];
       if (d1.length < d2.length) return NSOrderedAscending;
       if (d1.length > d2.length) return NSOrderedDescending;
       return memcmp(d1.bytes, d2.bytes, d1.length) < 0 ? NSOrderedAscending : NSOrderedDescending;
   }];
   ```

3. **Duplication Issue**: The codebase has two CBOR encoding implementations with different sorting behaviors, causing inconsistency.

## Correctness Properties

Property 1: Fault Condition - CID Computation Matches External Clients

_For any_ record dictionary where map keys sort differently under string comparison versus CBOR-byte comparison, the fixed `ATProtoCBORSerialization` SHALL produce CBOR data that, when hashed, generates the same CID as external clients using canonical DAG-CBOR encoding.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Preservation - Non-Map Encoding Unchanged

_For any_ input that is NOT a dictionary/map (arrays, strings, numbers, booleans, null, nested non-map structures), the fixed `ATProtoCBORSerialization` SHALL produce exactly the same CBOR bytes as the original implementation.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `ATProtoPDS/Sources/Core/ATProtoCBORSerialization.m`

**Function**: `+ (CBORValue *)cborValueFromObject:(id)obj`

**Specific Changes**:

1. **Replace String-Based Sorting**: Replace the current string comparison sorting (lines 30-36) with CBOR-byte-based sorting
   - Encode each key as a `CBORValue` first
   - Encode each `CBORValue` to bytes
   - Sort by byte length first, then lexicographically
   - This matches the logic in `CBOREncoder.encodeMap:toData:`

2. **Implementation Approach**: Use the same sorting comparator pattern as `CBOREncoder`:
   ```objc
   NSArray *sortedKeys = [[json allKeys] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
       CBORValue *key1 = [self cborValueFromObject:obj1];
       CBORValue *key2 = [self cborValueFromObject:obj2];
       NSData *d1 = [CBOREncoder encode:key1];
       NSData *d2 = [CBOREncoder encode:key2];
       if (d1.length < d2.length) return NSOrderedAscending;
       if (d1.length > d2.length) return NSOrderedDescending;
       return memcmp(d1.bytes, d2.bytes, d1.length) < 0 ? NSOrderedAscending : NSOrderedDescending;
   }];
   ```

3. **No Changes to CBOREncoder**: The `CBOREncoder` class already has correct sorting and should not be modified

4. **No Changes to Callers**: All existing callers of `ATProtoCBORSerialization.encodeDataWithJSONObject:error:` will automatically get correct CID computation

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code using known test vectors from the AT Protocol test suite, then verify the fix works correctly and preserves existing behavior.

### Exploratory Fault Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis using official AT Protocol test fixtures.

**Test Plan**: Use the existing `AtprotoInteropFixturesTests` which loads test vectors from `atproto/packages/dev-env/src/data-model-fixtures.json`. These fixtures contain JSON objects, their canonical CBOR encoding (base64), and expected CIDs. Run these tests on the UNFIXED code to observe failures.

**Test Cases**:
1. **Data Model Fixtures Test**: The existing `testDataModelFixtures` test (will fail on unfixed code)
   - Loads official AT Protocol test vectors
   - Compares our CBOR encoding against reference implementation
   - Verifies CID computation matches expected values
   - Expected failures: CBOR bytes mismatch, CID mismatch

2. **Key Ordering Test**: Create a new test with keys that expose the sorting bug
   - Input: `{"z": 1, "aa": 2}` (string sort: aa,z; byte sort: z,aa)
   - Expected: CBOR bytes match canonical encoding
   - Actual on unfixed: CBOR bytes differ due to wrong key order

3. **Record-Like Structure Test**: Test with typical AT Protocol record fields
   - Input: `{"text": "hello", "$type": "app.bsky.feed.post", "createdAt": "2024-01-01T00:00:00Z"}`
   - Expected: Keys sorted by byte length then lexicographically
   - Actual on unfixed: Keys sorted alphabetically by string

**Expected Counterexamples**:
- CBOR byte arrays differ from reference implementation
- CIDs computed from our encoding don't match expected CIDs
- Root cause: keys sorted by string value instead of CBOR-encoded bytes

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  cborData := ATProtoCBORSerialization.encodeDataWithJSONObject(input)
  cid := CID.cidWithDigest(sha256(cborData))
  externalCID := computeCIDUsingReferenceImplementation(input)
  ASSERT cid == externalCID
END FOR
```

**Test Plan**: Re-run the data model fixtures test after the fix and verify all assertions pass.

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT encodeDataWithJSONObject_original(input) = encodeDataWithJSONObject_fixed(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-map inputs

**Test Plan**: Capture CBOR output for various non-map inputs on UNFIXED code, then verify the fixed code produces identical output.

**Test Cases**:
1. **Array Preservation**: Verify arrays encode identically
   - Input: `[1, 2, 3]`, `["a", "b", "c"]`, nested arrays
   - Expected: Identical CBOR bytes before and after fix

2. **Primitive Preservation**: Verify primitives encode identically
   - Input: strings, numbers, booleans, null
   - Expected: Identical CBOR bytes before and after fix

3. **Nested Structure Preservation**: Verify nested structures encode identically when parent is not a map
   - Input: `[{"a": 1}, {"b": 2}]` (array of maps)
   - Expected: Maps within arrays use correct sorting, but array structure unchanged

4. **Empty Map Preservation**: Verify empty maps encode identically
   - Input: `{}`
   - Expected: Identical CBOR bytes (no keys to sort)

### Unit Tests

- Test key sorting with various key combinations (different lengths, special characters)
- Test that CIDs match reference implementation for known test vectors
- Test edge cases (empty maps, single-key maps, nested maps)
- Test that non-map types continue to encode correctly

### Property-Based Tests

- Generate random dictionaries with varying key lengths and verify CID computation is deterministic
- Generate random non-map structures and verify CBOR output is unchanged from original implementation
- Test that re-encoding decoded CBOR produces identical bytes (round-trip property)

### Integration Tests

- Test full record creation flow with `PDSRecordService.putRecord:` and verify CIDs match external verification
- Test PLC operation signing (which uses CBOR encoding) continues to work correctly
- Test that existing records can still be retrieved and decoded
