# AT Protocol PDS Batch 2 Sync Fixes - Bugfix Design

## Overview

This bugfix addresses two critical sync endpoint spec compliance issues that break AT Protocol federation. Issue A2 affects `com.atproto.sync.getHead`, which incorrectly returns base32-encoded block data instead of base32-encoded CID bytes, preventing crawlers from parsing repository heads. Issue C1 affects `com.atproto.sync.listRepos` and `com.atproto.sync.getRepoStatus`, which hardcode `active: true` regardless of actual account status, breaking moderation propagation across federated servers.

The root cause of Issue A2 is that `PDSRepositoryService.getRepoRoot` fetches the root CID bytes, then fetches the block data for that CID, and returns the block data instead of the CID bytes. The root cause of Issue C1 is that sync endpoint handlers construct response dictionaries with hardcoded `@YES` values for the `active` field instead of querying the database for actual account status.

The fix strategy is minimal and surgical: modify `getRepoRoot` to return CID bytes directly (removing the block data fetch), and modify sync endpoint handlers to query account takedown status using the existing `isAccountTakedownActive` API.

## Glossary

- **Bug_Condition_A2 (C_A2)**: The condition that triggers Issue A2 - when `sync.getHead` is called for any repository
- **Bug_Condition_C1 (C_C1)**: The condition that triggers Issue C1 - when `sync.listRepos` or `sync.getRepoStatus` is called for a taken down or suspended account
- **Property_A2 (P_A2)**: The desired behavior for C_A2 - `sync.getHead` returns a valid CID string (base32-encoded CID bytes)
- **Property_C1 (P_C1)**: The desired behavior for C_C1 - sync endpoints return `active: false` for taken down/suspended accounts
- **Preservation_A2**: Existing callers of `getRepoRoot` (in PDSRecordService, PDSController) must continue to receive CID bytes that can be parsed with `[CID cidFromBytes:]`
- **Preservation_C1**: Sync endpoints must continue to return correct values for all other fields (did, head, rev)
- **getRepoRoot**: The method in `PDSRepositoryService.m` (lines 103-122) that fetches repository root data
- **sync.getHead**: XRPC endpoint handler in `XrpcMethodRegistry.m` (lines 5052-5073) that returns repository head CID
- **sync.listRepos**: XRPC endpoint handler in `XrpcMethodRegistry.m` (around line 5126) that lists all repositories
- **sync.getRepoStatus**: XRPC endpoint handler in `XrpcMethodRegistry.m` (around line 5166) that returns repository status
- **isAccountTakedownActive**: Existing API in `PDSAdminController` that queries the `admin_takedowns` table to check if an account is taken down

## Bug Details

### Fault Condition - Issue A2

The bug manifests when `com.atproto.sync.getHead` is called for any repository. The `getRepoRoot` method fetches the root CID bytes from the database, then fetches the block data for that CID, and returns the block data. The sync.getHead handler then base32-encodes this block data (which is a commit object) instead of base32-encoding the CID bytes, producing an invalid CID string.

**Formal Specification:**
```
FUNCTION isBugCondition_A2(input)
  INPUT: input of type XRPCRequest for com.atproto.sync.getHead
  OUTPUT: boolean
  
  RETURN input.method == "com.atproto.sync.getHead"
         AND repositoryExists(input.did)
         AND getRepoRoot(input.did) returns block data instead of CID bytes
END FUNCTION
```

### Examples - Issue A2

- **Example 1**: Call `sync.getHead` for `did:plc:abc123` → System returns base32-encoded commit object (e.g., `bafyreib...` representing a commit block) instead of base32-encoded CID (e.g., `bafyreic...` representing the CID itself)
- **Example 2**: Crawler attempts to parse the returned string as a CID → Parsing succeeds but the CID points to the wrong data (commit object bytes instead of the actual CID)
- **Example 3**: Crawler uses the returned "CID" to fetch blocks → Gets incorrect data because the "CID" is actually the hash of commit block data, not the hash of the CID
- **Edge Case**: Call `sync.getHead` for non-existent repository → Should return error (this behavior is preserved)

### Fault Condition - Issue C1

The bug manifests when `com.atproto.sync.listRepos` or `com.atproto.sync.getRepoStatus` is called for an account that has been taken down or suspended. The handlers construct response dictionaries with hardcoded `@YES` for the `active` field (line 5126 in listRepos, line 5166 in getRepoStatus) instead of querying the database for actual account status.

**Formal Specification:**
```
FUNCTION isBugCondition_C1(input)
  INPUT: input of type XRPCRequest for sync.listRepos or sync.getRepoStatus
  OUTPUT: boolean
  
  RETURN (input.method == "com.atproto.sync.listRepos" OR input.method == "com.atproto.sync.getRepoStatus")
         AND EXISTS account WHERE account.did IN input.results
         AND isAccountTakedownActive(account.did) == true
         AND response.active == true (hardcoded)
END FUNCTION
```

### Examples - Issue C1

- **Example 1**: Account `did:plc:xyz789` is taken down via admin API → Call `sync.listRepos` → System returns `{did: "did:plc:xyz789", active: true, ...}` instead of `{did: "did:plc:xyz789", active: false, ...}`
- **Example 2**: Federated server queries `sync.getRepoStatus` for suspended account → Gets `active: true` → Fails to propagate moderation action
- **Example 3**: Account is genuinely active (no takedown) → Call `sync.listRepos` → System correctly returns `active: true` (this behavior is preserved)
- **Edge Case**: Call `sync.getRepoStatus` for non-existent account → Should return error (this behavior is preserved)

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors - Issue A2:**
- Other callers of `getRepoRoot` (PDSRecordService.m lines 381, PDSController.m line 514) must continue to receive CID bytes that can be parsed with `[CID cidFromBytes:]`
- `sync.getHead` must continue to return successful responses for valid repositories
- `sync.getHead` must continue to return error responses for non-existent repositories
- The database schema and storage format for repository roots must remain unchanged

**Unchanged Behaviors - Issue C1:**
- `sync.listRepos` must continue to return all other fields (did, head, rev) correctly
- `sync.getRepoStatus` must continue to return all other fields (did, rev) correctly
- Accounts that are genuinely active (no takedown/suspension) must continue to return `active: true`
- The pagination and filtering logic in `sync.listRepos` must remain unchanged

**Scope:**
All inputs that do NOT involve the specific buggy code paths should be completely unaffected by this fix. This includes:
- Other repository operations (createRecord, putRecord, deleteRecord)
- Other sync endpoints (sync.getBlocks, sync.getCheckout, sync.getRecord, sync.getRepo)
- Account creation and authentication flows
- Admin operations other than takedown status queries

## Hypothesized Root Cause

### Issue A2: sync.getHead returns wrong data type

Based on code analysis, the root cause is clear:

1. **Incorrect Data Fetch in getRepoRoot**: The method at `PDSRepositoryService.m:103-122` fetches root CID bytes (line 115), then fetches the block data for that CID (line 117), and returns the block data (line 119) instead of returning the CID bytes directly.

2. **Misunderstanding of Return Value**: The sync.getHead handler expects `getRepoRoot` to return CID bytes (which it then base32-encodes), but `getRepoRoot` actually returns block data, causing the handler to base32-encode commit object bytes instead of CID bytes.

3. **Inconsistent API Contract**: Other callers of `getRepoRoot` (PDSRecordService.m, PDSController.m) expect CID bytes and use `[CID cidFromBytes:]` to parse the result, which suggests the original intent was for `getRepoRoot` to return CID bytes, but the implementation was incorrectly changed to return block data.

### Issue C1: sync endpoints hardcode active status

Based on code analysis, the root cause is clear:

1. **Hardcoded Boolean Literal**: Line 5126 in `XrpcMethodRegistry.m` (sync.listRepos handler) constructs the response dictionary with `@"active": @YES` as a hardcoded literal.

2. **Hardcoded Boolean Literal**: Line 5166 in `XrpcMethodRegistry.m` (sync.getRepoStatus handler) constructs the response dictionary with `@YES, @"active"` as a hardcoded literal.

3. **Missing Database Query**: Neither handler queries the database for actual account status, despite the existence of the `isAccountTakedownActive` API (used elsewhere in the same file at lines 5609, 6086, 6115).

4. **Copy-Paste Error**: The pattern suggests these handlers were copied from a template or example that assumed all accounts are active, and the status check was never implemented.

## Correctness Properties

Property 1: Fault Condition A2 - sync.getHead Returns Valid CID String

_For any_ XRPC request to `com.atproto.sync.getHead` where a repository exists for the requested DID, the fixed handler SHALL return a base32-encoded CID string that can be parsed as a valid CID and represents the repository root commit CID (not the commit block data).

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Preservation A2 - Other getRepoRoot Callers Receive CID Bytes

_For any_ call to `getRepoRoot` from PDSRecordService or PDSController, the fixed method SHALL return CID bytes that can be successfully parsed with `[CID cidFromBytes:]`, preserving the existing behavior for all non-sync.getHead callers.

**Validates: Requirements 3.1, 3.2, 3.3**

Property 3: Fault Condition C1 - Sync Endpoints Return Correct Account Status

_For any_ XRPC request to `com.atproto.sync.listRepos` or `com.atproto.sync.getRepoStatus` where an account has been taken down or suspended, the fixed handlers SHALL query the database using `isAccountTakedownActive` and return `active: false` (or the appropriate status value) instead of hardcoded `active: true`.

**Validates: Requirements 2.4, 2.5, 2.6**

Property 4: Preservation C1 - Other Response Fields Remain Correct

_For any_ XRPC request to `com.atproto.sync.listRepos` or `com.atproto.sync.getRepoStatus`, the fixed handlers SHALL continue to return all other fields (did, head, rev) with the same values as before the fix, preserving existing functionality for non-status fields.

**Validates: Requirements 3.4, 3.5, 3.6**

## Fix Implementation

### Changes Required

**Issue A2: sync.getHead returns wrong data type**

**File**: `ATProtoPDS/Sources/App/Services/PDSRepositoryService.m`

**Function**: `getRepoRoot` (lines 103-122)

**Specific Changes**:
1. **Remove Block Data Fetch**: Delete lines 117-119 that fetch block data for the root CID
   - Current: `NSData *blockData = [reader getBlockForCID:rootCidBytes forDid:did error:blockError]; if (blockData) { rootData = blockData; }`
   - Fixed: Remove these lines entirely

2. **Return CID Bytes Directly**: Change line 119 to assign `rootCidBytes` instead of `blockData`
   - Current: `rootData = blockData;`
   - Fixed: `rootData = rootCidBytes;`

3. **Simplify Logic**: The method should now simply fetch and return the root CID bytes without any additional processing

**Pseudocode**:
```
FUNCTION getRepoRoot_fixed(did)
  store := getStoreForDid(did)
  IF store == nil THEN RETURN nil
  
  rootCidBytes := store.getRepoRootForDid(did)
  RETURN rootCidBytes  // Return CID bytes directly, not block data
END FUNCTION
```

**Issue C1: sync endpoints hardcode active status**

**File**: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

**Handler**: `com.atproto.sync.listRepos` (around line 5126)

**Specific Changes**:
1. **Query Account Status**: Before constructing the response dictionary, call `[adminController isAccountTakedownActive:account.did error:&error]`

2. **Use Queried Status**: Replace `@"active": @YES` with `@"active": @(!isTakedown)` (active is the inverse of takedown)

3. **Handle Query Errors**: If the status query fails, log a warning and default to `active: true` (fail-safe behavior)

**Handler**: `com.atproto.sync.getRepoStatus` (around line 5166)

**Specific Changes**:
1. **Query Account Status**: Before constructing the response dictionary, call `[adminController isAccountTakedownActive:did error:&error]`

2. **Use Queried Status**: Replace `@YES, @"active"` with `@(!isTakedown), @"active"` (active is the inverse of takedown)

3. **Handle Query Errors**: If the status query fails, log a warning and default to `active: true` (fail-safe behavior)

**Pseudocode**:
```
FUNCTION sync_listRepos_fixed(request)
  accounts := database.getAllAccounts()
  repos := []
  
  FOR EACH account IN accounts DO
    isTakedown := adminController.isAccountTakedownActive(account.did)
    latest := getLatestCommit(account.did)
    
    IF latest.head EXISTS THEN
      repos.append({
        did: account.did,
        head: latest.head,
        rev: latest.rev,
        active: NOT isTakedown  // Use queried status, not hardcoded true
      })
    END IF
  END FOR
  
  RETURN {repos: repos, cursor: ...}
END FUNCTION

FUNCTION sync_getRepoStatus_fixed(request)
  did := request.params.did
  isTakedown := adminController.isAccountTakedownActive(did)
  latest := getLatestCommit(did)
  
  RETURN {
    did: did,
    active: NOT isTakedown,  // Use queried status, not hardcoded true
    rev: latest.rev
  }
END FUNCTION
```

## Testing Strategy

### Validation Approach

The testing strategy follows a three-phase approach: first, surface counterexamples that demonstrate both bugs on unfixed code (exploratory fault condition checking); second, verify the fixes work correctly for buggy inputs (fix checking); third, verify existing behavior is preserved for non-buggy inputs (preservation checking).

### Exploratory Fault Condition Checking

**Goal**: Surface counterexamples that demonstrate both bugs BEFORE implementing the fix. Confirm the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan - Issue A2**: Write tests that call `sync.getHead` for a repository with a known commit, capture the returned string, attempt to parse it as a CID, and verify that the parsed CID does NOT match the actual repository root CID. Run these tests on the UNFIXED code to observe failures and confirm the bug.

**Test Cases - Issue A2**:
1. **Basic getHead Test**: Create a repository with one commit, call `sync.getHead`, verify the returned string is NOT a valid CID for the root commit (will fail on unfixed code - returns base32-encoded block data)
2. **CID Parsing Test**: Call `sync.getHead`, parse the returned string as a CID, verify the CID bytes do NOT match the actual root CID bytes (will fail on unfixed code)
3. **Block Data Detection Test**: Call `sync.getHead`, base32-decode the returned string, verify the decoded bytes are commit block data (not CID bytes) (will succeed on unfixed code, confirming the bug)
4. **Non-Existent Repo Test**: Call `sync.getHead` for non-existent DID, verify error response (should pass on unfixed code - this behavior is correct)

**Expected Counterexamples - Issue A2**:
- `sync.getHead` returns a base32-encoded string that decodes to commit block data (CBOR-encoded commit object)
- The returned string, when parsed as a CID, produces a CID that does NOT match the actual repository root CID
- Crawlers attempting to use the returned "CID" to fetch blocks will get incorrect data

**Test Plan - Issue C1**: Write tests that create an account, apply a takedown via admin API, call `sync.listRepos` and `sync.getRepoStatus`, and verify that both return `active: true` instead of `active: false`. Run these tests on the UNFIXED code to observe failures and confirm the bug.

**Test Cases - Issue C1**:
1. **listRepos Takedown Test**: Create account, apply takedown, call `sync.listRepos`, verify response includes `active: true` (will fail on unfixed code - should be false)
2. **getRepoStatus Takedown Test**: Create account, apply takedown, call `sync.getRepoStatus`, verify response includes `active: true` (will fail on unfixed code - should be false)
3. **listRepos Active Test**: Create account without takedown, call `sync.listRepos`, verify response includes `active: true` (should pass on unfixed code - this behavior is correct)
4. **Database Query Test**: Verify `isAccountTakedownActive` returns correct values for taken down and active accounts (should pass on unfixed code - the API works, it's just not being called)

**Expected Counterexamples - Issue C1**:
- `sync.listRepos` returns `active: true` for accounts with active takedowns in the `admin_takedowns` table
- `sync.getRepoStatus` returns `active: true` for accounts with active takedowns
- The `isAccountTakedownActive` API correctly returns `true` for taken down accounts, but sync handlers don't call it

### Fix Checking

**Goal**: Verify that for all inputs where the bug conditions hold, the fixed functions produce the expected behavior.

**Pseudocode - Issue A2**:
```
FOR ALL request WHERE isBugCondition_A2(request) DO
  response := sync_getHead_fixed(request)
  cidString := response.root
  
  // Verify the returned string is a valid CID
  cid := CID.parse(cidString)
  ASSERT cid IS NOT NULL
  
  // Verify the CID matches the actual repository root CID
  actualRootCidBytes := database.getRepoRootForDid(request.did)
  actualRootCid := CID.fromBytes(actualRootCidBytes)
  ASSERT cid.equals(actualRootCid)
  
  // Verify the returned string is NOT base32-encoded block data
  decodedBytes := base32Decode(cidString)
  ASSERT decodedBytes.length < 100  // CID bytes are ~36 bytes, commit blocks are much larger
END FOR
```

**Pseudocode - Issue C1**:
```
FOR ALL request WHERE isBugCondition_C1(request) DO
  IF request.method == "sync.listRepos" THEN
    response := sync_listRepos_fixed(request)
    FOR EACH repo IN response.repos DO
      isTakedown := adminController.isAccountTakedownActive(repo.did)
      ASSERT repo.active == NOT isTakedown
    END FOR
  ELSE IF request.method == "sync.getRepoStatus" THEN
    response := sync_getRepoStatus_fixed(request)
    isTakedown := adminController.isAccountTakedownActive(request.did)
    ASSERT response.active == NOT isTakedown
  END IF
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug conditions do NOT hold, the fixed functions produce the same results as the original functions.

**Pseudocode - Issue A2**:
```
FOR ALL caller WHERE caller IN [PDSRecordService, PDSController] DO
  FOR ALL did IN testDids DO
    originalResult := getRepoRoot_original(did)
    fixedResult := getRepoRoot_fixed(did)
    
    // Both should return CID bytes (after fix, getRepoRoot returns CID bytes)
    ASSERT fixedResult == originalResult OR fixedResult IS CID bytes
    
    // Both should be parseable with [CID cidFromBytes:]
    originalCid := CID.cidFromBytes(originalResult)
    fixedCid := CID.cidFromBytes(fixedResult)
    ASSERT originalCid IS NOT NULL
    ASSERT fixedCid IS NOT NULL
    
    // After fix, they should be equal (both return CID bytes)
    ASSERT fixedCid.equals(originalCid)
  END FOR
END FOR
```

**Testing Approach - Issue A2**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across different repository states
- It catches edge cases that manual unit tests might miss (empty repos, repos with many commits, repos with large blocks)
- It provides strong guarantees that the fix doesn't break existing callers

**Test Plan - Issue A2**: Observe behavior on UNFIXED code first for PDSRecordService and PDSController callers, then write property-based tests capturing that behavior. Note: The unfixed code has a bug in `getRepoRoot`, so we need to test that the fix makes it return CID bytes (which is what callers expect).

**Test Cases - Issue A2**:
1. **PDSRecordService Preservation**: Verify `applyWrites` with `swapCommit` continues to work correctly (uses `getRepoRoot` at line 381)
2. **PDSController Preservation**: Verify `describeRepo` continues to return correct root CID (uses `getRepoRoot` at line 514)
3. **CID Parsing Preservation**: Verify all callers can parse the result with `[CID cidFromBytes:]` (this should work after fix, may be broken before)
4. **Error Handling Preservation**: Verify `getRepoRoot` returns nil for non-existent DIDs (should work before and after)

**Pseudocode - Issue C1**:
```
FOR ALL request WHERE NOT isBugCondition_C1(request) DO
  originalResponse := sync_handler_original(request)
  fixedResponse := sync_handler_fixed(request)
  
  // All fields except 'active' should be identical
  ASSERT fixedResponse.did == originalResponse.did
  ASSERT fixedResponse.head == originalResponse.head
  ASSERT fixedResponse.rev == originalResponse.rev
  
  // For genuinely active accounts, 'active' should still be true
  IF NOT isAccountTakedownActive(request.did) THEN
    ASSERT fixedResponse.active == true
    ASSERT originalResponse.active == true
  END IF
END FOR
```

**Testing Approach - Issue C1**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across different account states
- It catches edge cases that manual unit tests might miss (accounts with no commits, accounts with many repos, pagination edge cases)
- It provides strong guarantees that the fix doesn't break existing fields

**Test Plan - Issue C1**: Observe behavior on UNFIXED code first for active accounts (no takedown), then write property-based tests capturing that behavior.

**Test Cases - Issue C1**:
1. **Active Account Preservation**: Verify `sync.listRepos` returns `active: true` for accounts without takedowns (should work before and after)
2. **Other Fields Preservation**: Verify `sync.listRepos` returns correct did, head, rev for all accounts (should work before and after)
3. **Pagination Preservation**: Verify `sync.listRepos` pagination logic is unchanged (should work before and after)
4. **getRepoStatus Preservation**: Verify `sync.getRepoStatus` returns correct did, rev for all accounts (should work before and after)

### Unit Tests

- Test `getRepoRoot` returns CID bytes (not block data) for valid repositories
- Test `getRepoRoot` returns nil for non-existent repositories
- Test `sync.getHead` returns valid CID strings that can be parsed
- Test `sync.listRepos` returns correct `active` field for taken down accounts
- Test `sync.listRepos` returns correct `active` field for active accounts
- Test `sync.getRepoStatus` returns correct `active` field for taken down accounts
- Test `sync.getRepoStatus` returns correct `active` field for active accounts
- Test error handling for database query failures in status checks

### Property-Based Tests

- Generate random repository states and verify `sync.getHead` returns valid CID strings
- Generate random account states (active, taken down, suspended) and verify sync endpoints return correct `active` field
- Generate random pagination parameters and verify `sync.listRepos` preserves pagination logic
- Test that all callers of `getRepoRoot` can parse the result with `[CID cidFromBytes:]`

### Integration Tests

- Test full sync flow: create repo, commit records, call `sync.getHead`, verify returned CID can be used to fetch blocks
- Test full moderation flow: create account, apply takedown, call `sync.listRepos`, verify `active: false`, remove takedown, verify `active: true`
- Test federated crawler scenario: call `sync.listRepos`, parse all returned CIDs, fetch blocks for each CID
- Test that existing XRPC endpoints (createRecord, putRecord, etc.) continue to work after fix
