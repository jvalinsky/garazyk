# Implementation Plan

- [ ] 1. Write bug condition exploration test
  - **Property 1: Fault Condition** - CID Mismatch Due to Incorrect Key Sorting
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists using official AT Protocol test fixtures
  - **Scoped PBT Approach**: Use existing `AtprotoInteropFixturesTests.testDataModelFixtures` which loads official test vectors from `atproto/packages/dev-env/src/data-model-fixtures.json`
  - Test that for records where keys sort differently under string vs CBOR-byte comparison, our CBOR encoding matches the reference implementation's canonical encoding
  - The test assertions should verify: CBOR bytes match reference AND computed CID matches expected CID
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found: which test vectors fail, what the CBOR byte differences are, what the CID mismatches are
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3_

- [ ] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Non-Map Encoding Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-map inputs (arrays, primitives, nested structures)
  - Write property-based tests capturing observed behavior patterns:
    - Arrays encode identically: `[1, 2, 3]`, `["a", "b", "c"]`, nested arrays
    - Primitives encode identically: strings, numbers, booleans, null
    - Nested structures where parent is not a map encode identically: `[{"a": 1}, {"b": 2}]`
    - Empty maps encode identically: `{}`
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [ ] 3. Fix DAG-CBOR canonical encoding in ATProtoCBORSerialization

  - [ ] 3.1 Implement the fix in ATProtoCBORSerialization.m
    - Replace string-based key sorting in `cborValueFromObject:` (lines 30-36) with CBOR-byte-based sorting
    - Use the same sorting comparator pattern as `CBOREncoder.encodeMap:toData:` (lines 485-492)
    - Sort keys by CBOR-encoded byte length first, then lexicographically using memcmp
    - Implementation approach:
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
    - Do NOT modify `CBOREncoder` class (it already has correct sorting)
    - Do NOT modify any callers of `ATProtoCBORSerialization`
    - _Bug_Condition: isBugCondition(input) where keys sort differently under string comparison vs CBOR-byte comparison_
    - _Expected_Behavior: For all records, CID computed by PDS matches CID computed by external clients using canonical DAG-CBOR encoding_
    - _Preservation: All non-map encoding (arrays, primitives, nested structures) produces identical CBOR bytes as original implementation_
    - _Requirements: 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4_

  - [ ] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - CID Computation Matches External Clients
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run `AtprotoInteropFixturesTests.testDataModelFixtures` on FIXED code
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - Verify: CBOR bytes match reference implementation AND CIDs match expected values
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Non-Map Encoding Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2 on FIXED code
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all preservation tests still pass after fix (arrays, primitives, nested structures, empty maps)

- [ ] 4. Checkpoint - Ensure all tests pass
  - Run full test suite: `./build/tests/AllTests`
  - Verify `AtprotoInteropFixturesTests` passes completely
  - Verify preservation tests pass
  - Verify no regressions in other CBOR-related tests
  - If any issues arise, document and ask user for guidance
