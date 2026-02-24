# AT Protocol PDS Identity & Authentication Fixes - Bugfix Design

## Overview

This bugfix addresses two critical issues in the AT Protocol PDS that break federation and authentication:

**Issue A1: Synthetic DID Documents Without Verification Methods** - The `resolveDid` helper function in `XrpcMethodRegistry.m` constructs incomplete synthetic DID documents when PLC resolution fails, omitting the `verificationMethod` array entirely. This breaks signature verification and identity resolution across federation. The fix removes synthetic document construction and delegates all resolution to `DIDPLCResolver`, which already exists and correctly fetches complete DID documents from the PLC directory.

**Issue B1: Inconsistent Token Generation (JWT vs UUID)** - Three code paths in `PDSAccountService.m` generate refresh tokens as UUID strings instead of JWTs, while access tokens are correctly generated as JWTs. This creates inconsistency and breaks JWT-based refresh flows. The fix uses `JWTMinter.mintRefreshTokenForDID:handle:scopes:error:` (which already exists) for all refresh token generation.

Both fixes are minimal, targeted changes that leverage existing infrastructure without introducing new dependencies or architectural changes.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug
  - **C_A1**: `resolveDid` is called for a local account AND PLC resolution fails/unavailable
  - **C_B1**: Token generation occurs in `createAccount`, `loginWithAccount`, or `refreshAccessToken`
- **Property (P)**: The desired behavior when the bug condition holds
  - **P_A1**: Complete DID document with `verificationMethod` array is returned from PLC directory
  - **P_B1**: Both access and refresh tokens are generated as JWTs with proper error handling
- **Preservation**: Existing behavior that must remain unchanged
  - DID resolution for valid DIDs continues to work
  - Session token responses maintain same structure
  - Token storage and validation continues to work
- **resolveDid**: Static helper function in `XrpcMethodRegistry.m` (lines 200-231) that resolves DIDs
- **DIDPLCResolver**: Existing class in `Sources/PLC/DIDPLCResolver.m` that fetches DID documents from PLC directory
- **JWTMinter**: Existing class in `Sources/Auth/JWT.m` that generates signed JWT tokens
- **mintRefreshTokenForDID**: Existing method in `JWTMinter` that generates refresh tokens as JWTs
- **PLC Directory**: Centralized directory service for `did:plc` DIDs, run locally via `tool-plc`
- **Synthetic DID Document**: Incomplete DID document constructed locally without fetching from PLC directory

## Bug Details

### Fault Condition

**Issue A1: Synthetic DID Documents**

The bug manifests when `resolveDid` is called for a local account and PLC resolution fails or is unavailable. The function constructs a synthetic DID document with `@context`, `id`, `alsoKnownAs`, and `service` fields but omits the `verificationMethod` array entirely. This breaks federated consumers that need to verify signatures or resolve identity.

**Formal Specification:**
```
FUNCTION isBugCondition_A1(input)
  INPUT: input of type (did: String, plcAvailable: Boolean, didInPLC: Boolean)
  OUTPUT: boolean
  
  RETURN input.did STARTS_WITH "did:plc:"
         AND (NOT input.plcAvailable OR NOT input.didInPLC)
         AND localAccountExists(input.did)
         AND syntheticDocumentReturned(input.did)
END FUNCTION
```

**Issue B1: UUID Refresh Tokens**

The bug manifests when token generation occurs in `createAccount`, `loginWithAccount`, or `refreshAccessToken`. The code generates access tokens as JWTs using `JWTMinter.mintAccessTokenForDID` but generates refresh tokens as UUID strings using `[[NSUUID UUID] UUIDString]`.

**Formal Specification:**
```
FUNCTION isBugCondition_B1(input)
  INPUT: input of type (operation: String, minterAvailable: Boolean)
  OUTPUT: boolean
  
  RETURN input.operation IN ['createAccount', 'loginWithAccount', 'refreshAccessToken']
         AND input.minterAvailable
         AND accessTokenIsJWT(input.operation)
         AND refreshTokenIsUUID(input.operation)
END FUNCTION
```

### Examples

**Issue A1: Synthetic DID Documents**

- **Example 1**: Call `resolveDid("did:plc:abc123", dbs, config, &error)` when PLC directory is unreachable
  - **Expected**: Return `nil` with network error
  - **Actual**: Returns synthetic document `{@context, id, alsoKnownAs, service}` without `verificationMethod`
  
- **Example 2**: Call `resolveDid("did:plc:xyz789", dbs, config, &error)` when DID not found in PLC but exists locally
  - **Expected**: Return `nil` with "DID not found" error
  - **Actual**: Returns synthetic document without `verificationMethod`
  
- **Example 3**: Federated server attempts to verify signature from `did:plc:abc123`
  - **Expected**: Fetch DID document with `verificationMethod` array containing public key
  - **Actual**: Receives synthetic document without `verificationMethod`, signature verification fails

- **Edge Case**: Call `resolveDid("did:plc:valid123", dbs, config, &error)` when PLC directory is reachable and DID exists
  - **Expected**: Return complete DID document from PLC with `verificationMethod`
  - **Actual**: Works correctly (no bug in this path)

**Issue B1: UUID Refresh Tokens**

- **Example 1**: Call `createAccountForEmail:password:handle:did:error:` with valid credentials
  - **Expected**: Return `{did, handle, email, accessJwt: JWT, refreshJwt: JWT}`
  - **Actual**: Returns `{did, handle, email, accessJwt: JWT, refreshJwt: UUID}`
  
- **Example 2**: Call `loginWithAccount:password:error:` with valid credentials
  - **Expected**: Return `{did, handle, email, accessJwt: JWT, refreshJwt: JWT}`
  - **Actual**: Returns `{did, handle, email, accessJwt: JWT, refreshJwt: UUID}`
  
- **Example 3**: Call `refreshAccessToken:error:` with valid refresh token
  - **Expected**: Return `{accessJwt: JWT, refreshJwt: JWT, handle, did}`
  - **Actual**: Returns `{accessJwt: JWT, refreshJwt: UUID, handle, did}`

- **Edge Case**: Call any token generation method when `self.minter` is `nil`
  - **Expected**: Return error immediately without generating any tokens
  - **Actual**: Works correctly for access tokens (returns error), but would have generated UUID for refresh tokens

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- DID resolution for valid `did:plc` DIDs must continue to return HTTP 200 with complete DID document
- DID resolution for invalid DIDs must continue to return appropriate error responses
- DIDPLCResolver caching must continue to work for subsequent resolutions
- Session token responses must maintain same structure (did, handle, email, accessJwt, refreshJwt fields)
- Token storage and validation in session repository must continue to work
- Refresh token rotation (revoke old, generate new) must continue to work
- JWT minter must continue to generate valid JWTs with correct claims (DID, handle, scopes)

**Scope:**
All inputs that do NOT involve the specific bug conditions should be completely unaffected by this fix. This includes:
- DID resolution for `did:web` DIDs (continues to return unsupported error)
- DID resolution when PLC directory is reachable and DID exists (continues to work)
- Token generation when minter is properly configured (continues to work, but now consistent)
- Token validation and parsing (continues to work)
- Session management operations (continues to work)

## Hypothesized Root Cause

Based on the bug description and code analysis, the most likely issues are:

**Issue A1: Synthetic DID Documents**

1. **Premature Fallback Logic**: The `resolveDid` function attempts to be "helpful" by constructing a synthetic DID document when PLC resolution fails, but this synthetic document is incomplete and breaks downstream consumers. The function should simply delegate to `DIDPLCResolver` and propagate errors.

2. **Missing Verification Method Construction**: Even if synthetic documents were appropriate (they're not), the code doesn't attempt to fetch or include the account's actual signing key in the `verificationMethod` array. This would require querying the actor store for the signing key, which is complex and error-prone.

3. **Incorrect Error Handling**: The function treats PLC resolution failure as a recoverable condition that should return partial data, when it should be treated as an error that propagates to the caller.

4. **Redundant Logic**: The function duplicates DID resolution logic that already exists in `DIDPLCResolver`, which is well-tested and handles retries, caching, and error cases correctly.

**Issue B1: UUID Refresh Tokens**

1. **Incomplete JWT Migration**: The codebase migrated from opaque UUID tokens to JWTs (Phase 2 in AGENTS.md), but the migration was incomplete. Access tokens were migrated to use `JWTMinter.mintAccessTokenForDID`, but refresh tokens were left as UUIDs.

2. **Copy-Paste Pattern**: All three token generation sites use the same pattern: generate access token as JWT, generate refresh token as UUID. This suggests the code was copied before the JWT migration was complete.

3. **Unawareness of Existing Method**: The `JWTMinter.mintRefreshTokenForDID:handle:scopes:error:` method already exists (lines 565-583 in JWT.m) but is not being used. Developers may not have been aware of this method.

4. **Inconsistent Error Handling**: Access token generation correctly checks if `self.minter` is nil and returns an error, but refresh token generation would have proceeded with UUID generation regardless.

## Correctness Properties

Property 1: Fault Condition - DID Resolution Returns Complete Documents

_For any_ DID resolution request where the DID exists in the PLC directory, the fixed `resolveDid` function SHALL delegate to `DIDPLCResolver.resolveDID:error:` and return the complete DID document including the `verificationMethod` array with real key material, enabling signature verification and identity resolution across federation.

**Validates: Requirements 2.1, 2.2, 2.4**

Property 2: Fault Condition - DID Resolution Propagates Errors

_For any_ DID resolution request where the DID does not exist in the PLC directory or PLC is unreachable, the fixed `resolveDid` function SHALL return `nil` and propagate the error from `DIDPLCResolver`, not construct synthetic fallback documents.

**Validates: Requirements 2.3**

Property 3: Fault Condition - Consistent JWT Token Generation

_For any_ token generation operation (createAccount, loginWithAccount, refreshAccessToken), the fixed code SHALL generate both access tokens and refresh tokens as JWTs using `JWTMinter.mintAccessTokenForDID` and `JWTMinter.mintRefreshTokenForDID` respectively, ensuring consistency and JWT-based refresh flows.

**Validates: Requirements 2.5, 2.6, 2.7, 2.9**

Property 4: Fault Condition - Token Generation Error Handling

_For any_ token generation operation where `self.minter` is `nil`, the fixed code SHALL return an error immediately without generating any tokens (neither access nor refresh).

**Validates: Requirements 2.8**

Property 5: Preservation - DID Resolution for Valid DIDs

_For any_ DID resolution request where the DID is valid and exists in the PLC directory, the fixed code SHALL produce exactly the same result as the original code when PLC resolution succeeds, preserving existing DID resolution behavior.

**Validates: Requirements 3.1, 3.3**

Property 6: Preservation - Session Token Response Structure

_For any_ token generation operation that succeeds, the fixed code SHALL return session responses with the same structure (did, handle, email, accessJwt, refreshJwt fields) as the original code, preserving API compatibility.

**Validates: Requirements 3.5, 3.6, 3.7**

Property 7: Preservation - Token Storage and Validation

_For any_ token storage or validation operation, the fixed code SHALL continue to store and validate tokens correctly in the session repository, preserving existing session management behavior.

**Validates: Requirements 3.8, 3.9, 3.10**

## Fix Implementation

### Changes Required

**Issue A1: Synthetic DID Documents**

**File**: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

**Function**: `resolveDid` (lines 200-231)

**Specific Changes**:

1. **Remove Synthetic Document Construction**: Delete the entire fallback logic that constructs synthetic DID documents (lines 210-228)
   - Remove the `PDSDatabaseAccount *account = [dbs getAccountByDid:did error:nil];` query
   - Remove the synthetic document dictionary construction
   - Remove the conditional return of synthetic documents

2. **Simplify to Pure Delegation**: Replace the entire function body with direct delegation to `DIDPLCResolver`
   - Keep the initial DID format validation (lines 200-204)
   - Keep the `did:plc` prefix check (line 206)
   - Keep the PLC URL configuration (lines 207-209)
   - Keep the `DIDPLCResolver` initialization and resolution (lines 210-214)
   - Remove all code after line 214 (the fallback logic)
   - Return the result directly from `DIDPLCResolver` or propagate the error

3. **Preserve Unsupported DID Method Handling**: Keep the unsupported DID method error for non-`did:plc` DIDs (lines 233-238)

4. **Result**: The function becomes a thin wrapper that validates input, delegates to `DIDPLCResolver`, and returns the result

**Issue B1: UUID Refresh Tokens**

**File**: `ATProtoPDS/Sources/App/Services/PDSAccountService.m`

**Function**: `createAccountForEmail:password:handle:did:error:` (line 167)

**Specific Changes**:

1. **Replace UUID Generation with JWT**: Change line 167 from:
   ```objc
   NSString *refreshToken = [[NSUUID UUID] UUIDString];
   ```
   to:
   ```objc
   JWT *refreshJWT = [self.minter mintRefreshTokenForDID:resolvedDid handle:handle scopes:@[@"atproto"] error:nil];
   NSString *refreshToken = [refreshJWT encodedToken];
   if (!refreshToken) {
       if (error) *error = [NSError errorWithDomain:@"com.atproto.server" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"JWT minter unavailable"}];
       return nil;
   }
   ```

2. **Add Error Handling**: Ensure that if refresh token generation fails, the function returns an error (similar to access token handling)

**Function**: `loginWithAccount:password:error:` (line 270)

**Specific Changes**:

1. **Replace UUID Generation with JWT**: Change line 270 from:
   ```objc
   NSString *refreshToken = [[NSUUID UUID] UUIDString];
   ```
   to:
   ```objc
   JWT *refreshJWT = [self.minter mintRefreshTokenForDID:account.did handle:account.handle scopes:@[@"atproto"] error:nil];
   NSString *refreshToken = [refreshJWT encodedToken];
   if (!refreshToken) {
       if (error) *error = [NSError errorWithDomain:@"com.atproto.server" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"JWT minter unavailable"}];
       return nil;
   }
   ```

2. **Add Error Handling**: Ensure that if refresh token generation fails, the function returns an error

**Function**: `refreshAccessToken:error:` (line 335)

**Specific Changes**:

1. **Replace UUID Generation with JWT**: Change line 335 from:
   ```objc
   NSString *newRefreshToken = [[NSUUID UUID] UUIDString];
   ```
   to:
   ```objc
   JWT *refreshJWT = [self.minter mintRefreshTokenForDID:account.did handle:account.handle scopes:@[@"atproto"] error:nil];
   NSString *newRefreshToken = [refreshJWT encodedToken];
   if (!newRefreshToken) {
       if (error) *error = [NSError errorWithDomain:@"com.atproto.server" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"JWT minter unavailable"}];
       return nil;
   }
   ```

2. **Add Error Handling**: Ensure that if refresh token generation fails, the function returns an error

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bugs on unfixed code, then verify the fixes work correctly and preserve existing behavior.

### Exploratory Fault Condition Checking

**Goal**: Surface counterexamples that demonstrate the bugs BEFORE implementing the fixes. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Write tests that exercise the buggy code paths and assert the expected correct behavior. Run these tests on the UNFIXED code to observe failures and understand the root cause.

**Test Cases**:

**Issue A1: Synthetic DID Documents**

1. **PLC Unreachable Test**: Mock PLC directory to be unreachable, call `resolveDid` for a local account DID
   - **Expected on unfixed code**: Returns synthetic document without `verificationMethod`
   - **Assertion**: Verify that `verificationMethod` key is missing from returned document
   
2. **DID Not Found Test**: Mock PLC directory to return 404, call `resolveDid` for a local account DID
   - **Expected on unfixed code**: Returns synthetic document without `verificationMethod`
   - **Assertion**: Verify that `verificationMethod` key is missing from returned document
   
3. **Signature Verification Test**: Attempt to extract public key from synthetic DID document
   - **Expected on unfixed code**: No `verificationMethod` array, extraction fails
   - **Assertion**: Verify that signature verification cannot proceed

4. **PLC Available Test**: Mock PLC directory to return complete DID document, call `resolveDid`
   - **Expected on unfixed code**: Returns complete document with `verificationMethod` (no bug)
   - **Assertion**: Verify that `verificationMethod` array is present

**Issue B1: UUID Refresh Tokens**

1. **Create Account Token Test**: Call `createAccountForEmail:password:handle:did:error:` with valid credentials
   - **Expected on unfixed code**: Returns `refreshJwt` as UUID string
   - **Assertion**: Verify that `refreshJwt` is not a valid JWT (no dots, cannot parse)
   
2. **Login Token Test**: Call `loginWithAccount:password:error:` with valid credentials
   - **Expected on unfixed code**: Returns `refreshJwt` as UUID string
   - **Assertion**: Verify that `refreshJwt` is not a valid JWT
   
3. **Refresh Token Test**: Call `refreshAccessToken:error:` with valid refresh token
   - **Expected on unfixed code**: Returns new `refreshJwt` as UUID string
   - **Assertion**: Verify that new `refreshJwt` is not a valid JWT

4. **Access Token Consistency Test**: Verify that `accessJwt` is a valid JWT in all three operations
   - **Expected on unfixed code**: `accessJwt` is valid JWT (no bug)
   - **Assertion**: Verify that `accessJwt` can be parsed and has correct claims

**Expected Counterexamples**:
- Synthetic DID documents are missing `verificationMethod` arrays
- Refresh tokens are UUID strings, not JWTs
- Access tokens are JWTs (correct), but refresh tokens are not (inconsistent)

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Issue A1: Synthetic DID Documents**

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition_A1(input) DO
  result := resolveDid_fixed(input.did, dbs, config, &error)
  ASSERT result = nil OR result.verificationMethod IS NOT NULL
  ASSERT result = DIDPLCResolver.resolveDID(input.did)
END FOR
```

**Test Cases**:
1. **PLC Unreachable Test**: Mock PLC directory to be unreachable, call fixed `resolveDid`
   - **Expected**: Returns `nil` with network error (no synthetic document)
   
2. **DID Not Found Test**: Mock PLC directory to return 404, call fixed `resolveDid`
   - **Expected**: Returns `nil` with "DID not found" error (no synthetic document)
   
3. **Complete Document Test**: Mock PLC directory to return complete DID document, call fixed `resolveDid`
   - **Expected**: Returns complete document with `verificationMethod` array

**Issue B1: UUID Refresh Tokens**

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition_B1(input) DO
  result := tokenGenerationFunction_fixed(input)
  ASSERT result.accessJwt IS VALID JWT
  ASSERT result.refreshJwt IS VALID JWT
  ASSERT result.refreshJwt CAN BE PARSED
END FOR
```

**Test Cases**:
1. **Create Account Token Test**: Call fixed `createAccountForEmail:password:handle:did:error:`
   - **Expected**: Returns both `accessJwt` and `refreshJwt` as valid JWTs
   
2. **Login Token Test**: Call fixed `loginWithAccount:password:error:`
   - **Expected**: Returns both `accessJwt` and `refreshJwt` as valid JWTs
   
3. **Refresh Token Test**: Call fixed `refreshAccessToken:error:`
   - **Expected**: Returns both new `accessJwt` and new `refreshJwt` as valid JWTs

4. **JWT Parsing Test**: Parse refresh tokens and verify claims (DID, handle, scopes)
   - **Expected**: Refresh tokens have correct claims and can be verified

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition_A1(input) AND NOT isBugCondition_B1(input) DO
  ASSERT originalFunction(input) = fixedFunction(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for non-buggy inputs, then write property-based tests capturing that behavior.

**Test Cases**:

**Issue A1: Synthetic DID Documents**

1. **Valid DID Resolution Preservation**: Observe that valid DIDs resolve correctly on unfixed code, then verify this continues after fix
   - **Test**: Call `resolveDid` with valid `did:plc` DIDs that exist in PLC directory
   - **Expected**: Same complete DID document before and after fix
   
2. **Invalid DID Error Preservation**: Observe that invalid DIDs return errors on unfixed code, then verify this continues after fix
   - **Test**: Call `resolveDid` with invalid DID formats
   - **Expected**: Same error response before and after fix
   
3. **Unsupported DID Method Preservation**: Observe that `did:web` DIDs return unsupported error on unfixed code, then verify this continues after fix
   - **Test**: Call `resolveDid` with `did:web` DIDs
   - **Expected**: Same unsupported error before and after fix

4. **Caching Preservation**: Observe that DIDPLCResolver caching works on unfixed code, then verify this continues after fix
   - **Test**: Call `resolveDid` twice for same DID, verify second call uses cache
   - **Expected**: Same caching behavior before and after fix

**Issue B1: UUID Refresh Tokens**

1. **Session Response Structure Preservation**: Observe that session responses have correct structure on unfixed code, then verify this continues after fix
   - **Test**: Call token generation functions and verify response has did, handle, email, accessJwt, refreshJwt fields
   - **Expected**: Same response structure before and after fix (only refreshJwt content changes)
   
2. **Token Storage Preservation**: Observe that tokens are stored correctly on unfixed code, then verify this continues after fix
   - **Test**: Generate tokens and verify they are stored in session repository
   - **Expected**: Same storage behavior before and after fix
   
3. **Token Rotation Preservation**: Observe that refresh token rotation works on unfixed code, then verify this continues after fix
   - **Test**: Call `refreshAccessToken` and verify old token is revoked, new token is generated
   - **Expected**: Same rotation behavior before and after fix

4. **Minter Nil Error Preservation**: Observe that nil minter returns error on unfixed code, then verify this continues after fix
   - **Test**: Set `self.minter` to nil and call token generation functions
   - **Expected**: Same error response before and after fix

### Unit Tests

**Issue A1: Synthetic DID Documents**

- Test `resolveDid` with valid `did:plc` DIDs (should return complete document)
- Test `resolveDid` with invalid DID formats (should return error)
- Test `resolveDid` with `did:web` DIDs (should return unsupported error)
- Test `resolveDid` when PLC directory is unreachable (should return network error)
- Test `resolveDid` when DID not found in PLC (should return not found error)
- Test that returned DID documents have `verificationMethod` array

**Issue B1: UUID Refresh Tokens**

- Test `createAccountForEmail:password:handle:did:error:` returns JWT refresh tokens
- Test `loginWithAccount:password:error:` returns JWT refresh tokens
- Test `refreshAccessToken:error:` returns JWT refresh tokens
- Test that refresh tokens can be parsed and have correct claims
- Test that refresh tokens have correct expiration (30 days)
- Test that nil minter returns error for both access and refresh tokens

### Property-Based Tests

**Issue A1: Synthetic DID Documents**

- Generate random valid `did:plc` DIDs and verify resolution returns complete documents with `verificationMethod`
- Generate random invalid DID formats and verify resolution returns errors
- Generate random PLC availability scenarios and verify correct error handling

**Issue B1: UUID Refresh Tokens**

- Generate random account credentials and verify token generation returns JWTs for both access and refresh
- Generate random token refresh scenarios and verify new tokens are JWTs
- Generate random minter configurations and verify error handling is consistent

### Integration Tests

**Issue A1: Synthetic DID Documents**

- Test full DID resolution flow from XRPC endpoint to PLC directory
- Test signature verification using resolved DID documents
- Test federated identity resolution across multiple PDS instances
- Test DID resolution with PLC directory running locally via `tool-plc`

**Issue B1: UUID Refresh Tokens**

- Test full authentication flow (create account, login, refresh) with JWT tokens
- Test token refresh flow with JWT parsing and validation
- Test session management with JWT tokens stored in repository
- Test token rotation with JWT refresh tokens

## Risk Assessment

### Issue A1: Synthetic DID Documents

**Risk Level**: Medium

**Risks**:
1. **Breaking Change**: Removing synthetic documents may break code that depends on always receiving a DID document (even incomplete). However, this is unlikely because:
   - Synthetic documents were incomplete and unusable for signature verification
   - Federated consumers would have already been failing with synthetic documents
   - The fix makes behavior more predictable (always delegate to PLC)

2. **PLC Dependency**: The fix makes DID resolution fully dependent on PLC directory availability. However:
   - This is the correct behavior per AT Protocol specification
   - PLC directory is already required for account creation
   - Local PLC server (`tool-plc`) is available for development/testing

3. **Error Handling Changes**: Callers of `resolveDid` may not be prepared for `nil` returns. However:
   - The function already returns `nil` for unsupported DID methods
   - Callers should already be checking for `nil` and handling errors
   - The fix makes error handling more consistent

**Mitigation**:
- Thoroughly test all callers of `resolveDid` to ensure they handle `nil` returns
- Verify that PLC directory is running and accessible in all environments
- Add integration tests with local PLC server to catch issues early

### Issue B1: UUID Refresh Tokens

**Risk Level**: Low

**Risks**:
1. **Token Format Change**: Existing refresh tokens stored as UUIDs will become invalid after the fix. However:
   - This is a one-time migration issue
   - Users will need to re-authenticate once
   - New tokens will be JWTs and work correctly going forward

2. **Token Size Increase**: JWTs are larger than UUIDs (200+ bytes vs 36 bytes). However:
   - This is negligible for modern systems
   - JWTs provide better security and validation
   - Token storage and transmission can handle larger tokens

3. **JWT Parsing Overhead**: Parsing JWTs is more expensive than comparing UUID strings. However:
   - The overhead is minimal (microseconds)
   - JWTs enable stateless validation and better security
   - The consistency benefit outweighs the performance cost

**Mitigation**:
- Document the token format change in release notes
- Consider adding a migration script to invalidate old UUID refresh tokens
- Monitor token validation performance after deployment
- Add tests to verify JWT parsing and validation work correctly

### Overall Risk Assessment

Both fixes are low-risk, targeted changes that leverage existing infrastructure. The synthetic DID document fix has slightly higher risk due to error handling changes, but the benefits (correct federation, signature verification) far outweigh the risks. The UUID refresh token fix is very low risk and primarily affects token format, which is an internal implementation detail.

**Recommendation**: Proceed with both fixes. Deploy to development environment first, run full integration test suite, then deploy to production with monitoring.
