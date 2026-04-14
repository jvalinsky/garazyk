# Implementation Plan

- [ ] 1. Write bug condition exploration tests
  - **Property 1: Fault Condition** - Batch 1 Trivial Bugs
  - **CRITICAL**: These tests MUST FAIL on unfixed code - failure confirms the bugs exist
  - **DO NOT attempt to fix the tests or the code when they fail**
  - **NOTE**: These tests encode the expected behavior - they will validate the fixes when they pass after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bugs exist
  - **Scoped PBT Approach**: For deterministic bugs, scope properties to concrete failing cases to ensure reproducibility
  - Test implementation details from Fault Condition specifications in design
  - The test assertions should match the Expected Behavior Properties from design
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests FAIL (this is correct - it proves the bugs exist)
  - Document counterexamples found to understand root causes
  - Mark task complete when tests are written, run, and failures are documented
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [ ] 1.1 Test sync.getHead CID encoding bug
    - Create test repository with known root CID
    - Call `com.atproto.sync.getHead` for the repository
    - Parse returned CID string and compare to expected root CID from database
    - **Expected failure**: Returned CID string does not match actual root CID (returns block data encoded as CID)
    - Document counterexample: specific CID mismatch observed
    - _Bug_Condition: isBugCondition_syncGetHead(input) where input.did is valid and repository exists_
    - _Expected_Behavior: Returns valid CID string that matches database root CID_

  - [ ] 1.2 Test fprintf debug pollution
    - Capture stderr before and after invoking resolveDid helper
    - Capture stderr before and after invoking com.atproto.identity.resolveDid handler
    - Capture stderr before and after invoking com.atproto.sync.getBlocks handler
    - **Expected failure**: stderr contains "[resolveDid] ...", "[getBlocks] ..." debug messages
    - Document counterexample: specific debug messages observed in stderr
    - _Bug_Condition: isBugCondition_fprintfDebug(input) where handler is invoked_
    - _Expected_Behavior: No debug output to stderr_

  - [ ] 1.3 Test placeholder verification key in synthetic DID documents
    - Call resolveDid helper for an account without PLC directory entry
    - Parse returned DID document structure
    - Check for verificationMethod field
    - **Expected failure**: DID document contains verificationMethod with "zQ3sh..." placeholder
    - Document counterexample: placeholder key found in synthetic DID document
    - _Bug_Condition: isBugCondition_placeholderKey(input) where synthetic DID document is constructed_
    - _Expected_Behavior: DID document omits verificationMethod field entirely_

  - [ ] 1.4 Verify repo.importRepo stub behavior (baseline test)
    - Call `com.atproto.repo.importRepo` with valid CAR data
    - **Expected success**: Returns 501 with "NotImplemented" error
    - This confirms correct stub behavior (no fix needed)
    - _Bug_Condition: false (no bug - stub behavior is correct)_
    - _Expected_Behavior: Returns 501 NotImplemented_

- [ ] 2. Write preservation property tests (BEFORE implementing fixes)
  - **Property 2: Preservation** - Non-Buggy Behavior
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

  - [ ] 2.1 Test sync.getHead error handling preservation
    - Observe: sync.getHead returns 404 for invalid/missing DIDs on unfixed code
    - Observe: sync.getHead returns 200 with JSON response for valid DIDs on unfixed code
    - Write property-based test: for all invalid DIDs, returns 404 with "RepoNotFound" error
    - Write property-based test: for all valid DIDs, returns 200 with "root" field
    - Verify tests pass on UNFIXED code
    - _Preservation: Error handling and response format unchanged_

  - [ ] 2.2 Test getRepoRoot caller preservation
    - Observe: PDSRecordService methods (createRecord, putRecord, deleteRecord) work correctly on unfixed code
    - Observe: PDSController methods using getRepoRoot work correctly on unfixed code
    - Write property-based test: for all repository operations, callers can parse getRepoRoot result with [CID cidFromBytes:]
    - Verify tests pass on UNFIXED code
    - _Preservation: All getRepoRoot callers continue to function correctly_

  - [ ] 2.3 Test DID document structure preservation
    - Observe: resolveDid returns DID documents with id, alsoKnownAs, service fields on unfixed code
    - Observe: DID documents have correct structure and values on unfixed code
    - Write property-based test: for all accounts, DID document contains required fields (id, alsoKnownAs, service)
    - Write property-based test: for all accounts, DID document id matches account DID
    - Verify tests pass on UNFIXED code
    - _Preservation: DID document structure and required fields unchanged_

  - [ ] 2.4 Test unaffected handler preservation
    - Observe: Handlers not affected by fprintf removal work correctly on unfixed code
    - Observe: Structured logging (PDS_LOG_*) continues to work on unfixed code
    - Write property-based test: for all handlers not in [resolveDid, identity.resolveDid, sync.getBlocks], behavior unchanged
    - Verify tests pass on UNFIXED code
    - _Preservation: All other XRPC handlers function correctly_

  - [ ] 2.5 Test repo.importRepo stub preservation
    - Observe: repo.importRepo returns 501 with proper authentication check on unfixed code
    - Write test: repo.importRepo requires authentication and returns 501
    - Verify test passes on UNFIXED code
    - _Preservation: Stub behavior remains correct (no changes)_

- [ ] 3. Fix for Batch 1 Trivial Bugs

  - [ ] 3.1 Implement sync.getHead CID encoding fix
    - File: `Garazyk/Sources/App/Services/PDSRepositoryService.m`
    - Function: `getRepoRoot` (lines 103-122)
    - Remove block data fetch (lines 117-119)
    - Change `rootData = blockData;` to `rootData = rootCidBytes;`
    - Simplify logic to directly return CID bytes from database
    - _Bug_Condition: isBugCondition_syncGetHead(input) where input.did is valid and repository exists_
    - _Expected_Behavior: Returns CID bytes (not block data), sync.getHead produces valid CID string_
    - _Preservation: Error handling, response format, and other getRepoRoot callers unchanged_
    - _Requirements: 2.1, 2.2, 3.1, 3.2_

  - [ ] 3.2 Implement fprintf debug pollution removal
    - File: `Garazyk/Sources/Network/XrpcMethodRegistry.m`
    - Function: `resolveDid` helper (lines 185-230)
    - Remove fprintf statements at lines 186, 189, 191, 195
    - Function: `registerComAtprotoIdentityResolveDid` handler (line 5669)
    - Remove fprintf statement at line 5669
    - Function: `registerComAtprotoSyncGetBlocks` handler (line 5944)
    - Remove fprintf statement at line 5944
    - _Bug_Condition: isBugCondition_fprintfDebug(input) where handler is invoked_
    - _Expected_Behavior: No debug output to stderr_
    - _Preservation: Handler functionality, structured logging (PDS_LOG_*), and error handling unchanged_
    - _Requirements: 2.3, 2.4, 2.5, 3.3, 3.4, 3.7_

  - [ ] 3.3 Implement placeholder verification key removal
    - File: `Garazyk/Sources/Network/XrpcMethodRegistry.m`
    - Function: `resolveDid` helper (lines 217-224)
    - Remove entire `@"verificationMethod": @[...]` entry from DID document dictionary
    - Keep all other fields: @context, id, alsoKnownAs, service
    - _Bug_Condition: isBugCondition_placeholderKey(input) where synthetic DID document is constructed_
    - _Expected_Behavior: DID document omits verificationMethod field entirely_
    - _Preservation: DID document structure (id, alsoKnownAs, service) and real PLC directory resolution unchanged_
    - _Requirements: 2.6, 3.5, 3.6_

  - [ ] 3.4 Verify bug condition exploration tests now pass
    - **Property 1: Expected Behavior** - Batch 1 Trivial Bugs Fixed
    - **IMPORTANT**: Re-run the SAME tests from task 1 - do NOT write new tests
    - The tests from task 1 encode the expected behavior
    - When these tests pass, it confirms the expected behavior is satisfied
    - Run bug condition exploration tests from step 1
    - **EXPECTED OUTCOME**: Tests PASS (confirms bugs are fixed)
    - _Requirements: Expected Behavior Properties from design (2.1, 2.2, 2.3, 2.4, 2.5, 2.6)_

  - [ ] 3.5 Verify preservation tests still pass
    - **Property 2: Preservation** - Non-Buggy Behavior Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fixes (no regressions)
    - _Requirements: Preservation Requirements from design (3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8)_

- [ ] 4. Checkpoint - Ensure all tests pass
  - Run full test suite: `./build/tests/AllTests`
  - Verify bug condition exploration tests pass (task 1 tests)
  - Verify preservation tests pass (task 2 tests)
  - Verify no regressions in existing test suite
  - Ask user if questions arise
