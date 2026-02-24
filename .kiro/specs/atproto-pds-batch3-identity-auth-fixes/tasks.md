# Implementation Plan

## Overview

This task list implements fixes for two critical bugs in the AT Protocol PDS:
- **Issue A1**: Synthetic DID documents without verification methods
- **Issue B1**: Inconsistent token generation (JWT vs UUID)

The workflow follows the exploratory bugfix methodology: explore the bugs first with tests on unfixed code, write preservation tests, then implement the fixes and verify.

---

## Tasks

- [ ] 1. Write bug condition exploration tests (BEFORE implementing fix)
  - **Property 1: Fault Condition** - Synthetic DID Documents and UUID Refresh Tokens
  - **CRITICAL**: These tests MUST FAIL on unfixed code - failure confirms the bugs exist
  - **DO NOT attempt to fix the tests or the code when they fail**
  - **NOTE**: These tests encode the expected behavior - they will validate the fixes when they pass after implementation
  - **GOAL**: Surface counterexamples that demonstrate both bugs exist
  
  - [ ] 1.1 Test A1: Synthetic DID document missing verificationMethod
    - Create test in `ATProtoPDS/Tests/Network/XrpcMethodRegistryTests.m`
    - Mock PLC directory to be unreachable (network error)
    - Call `resolveDid` for a local account DID (e.g., "did:plc:test123")
    - **Expected on unfixed code**: Returns synthetic document WITHOUT `verificationMethod` array
    - Assert that result is non-nil (synthetic document returned)
    - Assert that `verificationMethod` key is missing from returned document
    - Document counterexample: "resolveDid returns incomplete DID document when PLC unreachable"
    - _Requirements: 2.1, 2.2, 2.3, 2.4_
  
  - [ ] 1.2 Test A1: DID not found returns synthetic document
    - Mock PLC directory to return 404 (DID not found)
    - Call `resolveDid` for a local account DID
    - **Expected on unfixed code**: Returns synthetic document WITHOUT `verificationMethod` array
    - Assert that result is non-nil (synthetic document returned instead of error)
    - Assert that `verificationMethod` key is missing
    - Document counterexample: "resolveDid returns synthetic document instead of propagating 404 error"
    - _Requirements: 2.3_
  
  - [ ] 1.3 Test B1: Create account returns UUID refresh token
    - Create test in `ATProtoPDS/Tests/App/Services/PDSAccountServiceTests.m`
    - Call `createAccountForEmail:password:handle:did:error:` with valid credentials
    - **Expected on unfixed code**: Returns `refreshJwt` as UUID string (not JWT)
    - Assert that `accessJwt` is a valid JWT (can be parsed, has 3 parts separated by dots)
    - Assert that `refreshJwt` is NOT a valid JWT (no dots, cannot be parsed)
    - Assert that `refreshJwt` matches UUID format (8-4-4-4-12 hex digits)
    - Document counterexample: "createAccount returns UUID refresh token instead of JWT"
    - _Requirements: 2.5, 2.6, 2.7_
  
  - [ ] 1.4 Test B1: Login returns UUID refresh token
    - Call `loginWithAccount:password:error:` with valid credentials
    - **Expected on unfixed code**: Returns `refreshJwt` as UUID string (not JWT)
    - Assert that `accessJwt` is a valid JWT
    - Assert that `refreshJwt` is NOT a valid JWT
    - Assert that `refreshJwt` matches UUID format
    - Document counterexample: "loginWithAccount returns UUID refresh token instead of JWT"
    - _Requirements: 2.5, 2.6, 2.7_
  
  - [ ] 1.5 Test B1: Refresh token returns UUID refresh token
    - Call `refreshAccessToken:error:` with valid refresh token
    - **Expected on unfixed code**: Returns new `refreshJwt` as UUID string (not JWT)
    - Assert that new `accessJwt` is a valid JWT
    - Assert that new `refreshJwt` is NOT a valid JWT
    - Assert that new `refreshJwt` matches UUID format
    - Document counterexample: "refreshAccessToken returns UUID refresh token instead of JWT"
    - _Requirements: 2.5, 2.6, 2.7_
  
  - [ ] 1.6 Run exploration tests on UNFIXED code
    - Run `./build/tests/AllTests` to execute all exploration tests
    - **EXPECTED OUTCOME**: Tests FAIL (this is correct - it proves the bugs exist)
    - Document all counterexamples found in test output
    - Mark task complete when tests are written, run, and failures are documented
    - **DO NOT proceed to fix implementation until failures are documented**

- [ ] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Non-Buggy DID Resolution and Token Behavior
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs
  - Write property-based tests capturing observed behavior patterns
  - Property-based testing generates many test cases for stronger guarantees
  
  - [ ] 2.1 Observe and test: Valid DID resolution continues to work
    - Create test in `ATProtoPDS/Tests/Network/XrpcMethodRegistryTests.m`
    - Mock PLC directory to return complete DID document with `verificationMethod` array
    - Call `resolveDid` with valid `did:plc` DID that exists in PLC
    - Observe on UNFIXED code: Returns complete DID document with all fields
    - Write property-based test: For all valid DIDs in PLC, resolution returns complete document
    - Assert that result has `@context`, `id`, `alsoKnownAs`, `service`, AND `verificationMethod`
    - Assert that `verificationMethod` array is non-empty
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES (confirms baseline behavior to preserve)
    - _Requirements: 3.1, 3.3_
  
  - [ ] 2.2 Observe and test: Invalid DID format returns error
    - Call `resolveDid` with invalid DID formats (e.g., "not-a-did", "did:invalid:123")
    - Observe on UNFIXED code: Returns nil with error
    - Write property-based test: For all invalid DID formats, resolution returns error
    - Assert that result is nil
    - Assert that error is non-nil with appropriate error code
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES
    - _Requirements: 3.2_
  
  - [ ] 2.3 Observe and test: Unsupported DID methods return error
    - Call `resolveDid` with `did:web` DIDs
    - Observe on UNFIXED code: Returns nil with "unsupported DID method" error
    - Write property-based test: For all non-`did:plc` DIDs, resolution returns unsupported error
    - Assert that result is nil
    - Assert that error message contains "unsupported"
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES
    - _Requirements: 3.4_
  
  - [ ] 2.4 Observe and test: Session response structure is preserved
    - Create test in `ATProtoPDS/Tests/App/Services/PDSAccountServiceTests.m`
    - Call `createAccountForEmail:password:handle:did:error:` with valid credentials
    - Observe on UNFIXED code: Returns dictionary with did, handle, email, accessJwt, refreshJwt keys
    - Write property-based test: For all successful token generation, response has required fields
    - Assert that response has exactly these keys: did, handle, email, accessJwt, refreshJwt
    - Assert that all values are non-nil strings
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES
    - _Requirements: 3.5, 3.6, 3.7_
  
  - [ ] 2.5 Observe and test: Token storage continues to work
    - Generate tokens via `createAccountForEmail:password:handle:did:error:`
    - Observe on UNFIXED code: Tokens are stored in session repository
    - Write property-based test: For all token generation, tokens are stored correctly
    - Query session repository for stored tokens
    - Assert that both access and refresh tokens are stored
    - Assert that tokens can be retrieved by DID
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES
    - _Requirements: 3.8, 3.9_
  
  - [ ] 2.6 Observe and test: Token rotation continues to work
    - Call `refreshAccessToken:error:` with valid refresh token
    - Observe on UNFIXED code: Old token is revoked, new tokens are generated
    - Write property-based test: For all token refresh, rotation works correctly
    - Assert that old refresh token is revoked (cannot be used again)
    - Assert that new access and refresh tokens are generated
    - Assert that new tokens are stored in session repository
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES
    - _Requirements: 3.10_
  
  - [ ] 2.7 Observe and test: Nil minter returns error
    - Set `self.minter` to nil in PDSAccountService
    - Call `createAccountForEmail:password:handle:did:error:`
    - Observe on UNFIXED code: Returns nil with "JWT minter unavailable" error
    - Write property-based test: For all token generation with nil minter, error is returned
    - Assert that result is nil
    - Assert that error is non-nil with appropriate message
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES
    - _Requirements: 2.8_
  
  - [ ] 2.8 Run preservation tests on UNFIXED code
    - Run `./build/tests/AllTests` to execute all preservation tests
    - **EXPECTED OUTCOME**: Tests PASS (confirms baseline behavior to preserve)
    - Mark task complete when tests are written, run, and passing on unfixed code

- [ ] 3. Fix for synthetic DID documents and UUID refresh tokens

  - [ ] 3.1 Implement Issue A1 fix: Remove synthetic DID document construction
    - Open `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
    - Locate `resolveDid` helper function (lines 200-231)
    - Keep initial DID format validation (lines 200-204)
    - Keep `did:plc` prefix check (line 206)
    - Keep PLC URL configuration (lines 207-209)
    - Keep DIDPLCResolver initialization and resolution (lines 210-214)
    - **DELETE lines 210-228**: Remove entire fallback logic that constructs synthetic documents
      - Remove `PDSDatabaseAccount *account = [dbs getAccountByDid:did error:nil];` query
      - Remove synthetic document dictionary construction
      - Remove conditional return of synthetic documents
    - Simplify function to return result directly from `DIDPLCResolver` or propagate error
    - Keep unsupported DID method error handling (lines 233-238)
    - Result: Function becomes thin wrapper that validates input and delegates to DIDPLCResolver
    - _Bug_Condition: isBugCondition_A1(input) where input.did starts with "did:plc:" AND (PLC unavailable OR DID not in PLC) AND localAccountExists(input.did)_
    - _Expected_Behavior: Returns nil with error OR returns complete DID document with verificationMethod array from PLC directory_
    - _Preservation: Valid DID resolution, invalid DID errors, unsupported DID method errors, caching behavior_
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4_
  
  - [ ] 3.2 Implement Issue B1 fix: Replace UUID with JWT in createAccount
    - Open `ATProtoPDS/Sources/App/Services/PDSAccountService.m`
    - Locate `createAccountForEmail:password:handle:did:error:` method
    - Find line 167: `NSString *refreshToken = [[NSUUID UUID] UUIDString];`
    - Replace with JWT generation:
      ```objc
      JWT *refreshJWT = [self.minter mintRefreshTokenForDID:resolvedDid handle:handle scopes:@[@"atproto"] error:nil];
      NSString *refreshToken = [refreshJWT encodedToken];
      if (!refreshToken) {
          if (error) *error = [NSError errorWithDomain:@"com.atproto.server" code:1
                                              userInfo:@{NSLocalizedDescriptionKey: @"JWT minter unavailable"}];
          return nil;
      }
      ```
    - Add error handling for refresh token generation failures
    - _Bug_Condition: isBugCondition_B1(input) where input.operation = 'createAccount' AND minterAvailable AND accessTokenIsJWT AND refreshTokenIsUUID_
    - _Expected_Behavior: Both accessJwt and refreshJwt are valid JWTs with proper error handling_
    - _Preservation: Session response structure, token storage, nil minter error handling_
    - _Requirements: 2.5, 2.6, 2.7, 2.8, 3.5, 3.6, 3.7, 3.8_
  
  - [ ] 3.3 Implement Issue B1 fix: Replace UUID with JWT in loginWithAccount
    - Locate `loginWithAccount:password:error:` method
    - Find line 270: `NSString *refreshToken = [[NSUUID UUID] UUIDString];`
    - Replace with JWT generation:
      ```objc
      JWT *refreshJWT = [self.minter mintRefreshTokenForDID:account.did handle:account.handle scopes:@[@"atproto"] error:nil];
      NSString *refreshToken = [refreshJWT encodedToken];
      if (!refreshToken) {
          if (error) *error = [NSError errorWithDomain:@"com.atproto.server" code:1
                                              userInfo:@{NSLocalizedDescriptionKey: @"JWT minter unavailable"}];
          return nil;
      }
      ```
    - Add error handling for refresh token generation failures
    - _Bug_Condition: isBugCondition_B1(input) where input.operation = 'loginWithAccount' AND minterAvailable AND accessTokenIsJWT AND refreshTokenIsUUID_
    - _Expected_Behavior: Both accessJwt and refreshJwt are valid JWTs with proper error handling_
    - _Preservation: Session response structure, token storage, nil minter error handling_
    - _Requirements: 2.5, 2.6, 2.7, 2.8, 3.5, 3.6, 3.7, 3.8_
  
  - [ ] 3.4 Implement Issue B1 fix: Replace UUID with JWT in refreshAccessToken
    - Locate `refreshAccessToken:error:` method
    - Find line 335: `NSString *newRefreshToken = [[NSUUID UUID] UUIDString];`
    - Replace with JWT generation:
      ```objc
      JWT *refreshJWT = [self.minter mintRefreshTokenForDID:account.did handle:account.handle scopes:@[@"atproto"] error:nil];
      NSString *newRefreshToken = [refreshJWT encodedToken];
      if (!newRefreshToken) {
          if (error) *error = [NSError errorWithDomain:@"com.atproto.server" code:1
                                              userInfo:@{NSLocalizedDescriptionKey: @"JWT minter unavailable"}];
          return nil;
      }
      ```
    - Add error handling for refresh token generation failures
    - _Bug_Condition: isBugCondition_B1(input) where input.operation = 'refreshAccessToken' AND minterAvailable AND accessTokenIsJWT AND refreshTokenIsUUID_
    - _Expected_Behavior: Both accessJwt and refreshJwt are valid JWTs with proper error handling_
    - _Preservation: Session response structure, token storage, token rotation, nil minter error handling_
    - _Requirements: 2.5, 2.6, 2.7, 2.8, 3.5, 3.6, 3.7, 3.9, 3.10_

  - [ ] 3.5 Verify bug condition exploration tests now pass
    - **Property 1: Expected Behavior** - Complete DID Documents and JWT Refresh Tokens
    - **IMPORTANT**: Re-run the SAME tests from task 1 - do NOT write new tests
    - The tests from task 1 encode the expected behavior
    - When these tests pass, it confirms the expected behavior is satisfied
    - Run `./build/tests/AllTests` to execute exploration tests from task 1
    - **EXPECTED OUTCOME**: Tests PASS (confirms bugs are fixed)
    - Verify test 1.1: `resolveDid` returns nil with error when PLC unreachable (no synthetic document)
    - Verify test 1.2: `resolveDid` returns nil with error when DID not found (no synthetic document)
    - Verify test 1.3: `createAccount` returns JWT refresh token (not UUID)
    - Verify test 1.4: `loginWithAccount` returns JWT refresh token (not UUID)
    - Verify test 1.5: `refreshAccessToken` returns JWT refresh token (not UUID)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [ ] 3.6 Verify preservation tests still pass
    - **Property 2: Preservation** - Non-Buggy DID Resolution and Token Behavior
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run `./build/tests/AllTests` to execute preservation tests from task 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Verify test 2.1: Valid DID resolution still returns complete documents
    - Verify test 2.2: Invalid DID format still returns error
    - Verify test 2.3: Unsupported DID methods still return error
    - Verify test 2.4: Session response structure is preserved
    - Verify test 2.5: Token storage continues to work
    - Verify test 2.6: Token rotation continues to work
    - Verify test 2.7: Nil minter still returns error
    - Confirm all tests still pass after fix (no regressions)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10_

- [ ] 4. Checkpoint - Ensure all tests pass
  - Run full test suite: `./build/tests/AllTests`
  - Verify 0 failures reported
  - Verify all exploration tests pass (bugs are fixed)
  - Verify all preservation tests pass (no regressions)
  - If any tests fail, investigate and fix before proceeding
  - Ask the user if questions arise about test failures or unexpected behavior

---

## Notes

- **Exploration tests** (task 1) MUST be run on unfixed code first to confirm bugs exist
- **Preservation tests** (task 2) MUST be run on unfixed code first to establish baseline
- **Implementation** (task 3) should only begin after tasks 1 and 2 are complete
- **Verification** (tasks 3.5 and 3.6) re-runs the same tests to confirm fixes work
- All tests use property-based testing where appropriate for stronger guarantees
- The workflow ensures systematic validation: explore → preserve → implement → validate
