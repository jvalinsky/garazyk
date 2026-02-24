# AT Protocol PDS Batch 1 Trivial Fixes - Bugfix Design

## Overview

This design addresses four trivial spec compliance and code quality issues in the ATProto PDS implementation. These are quick fixes (<1 hour total) that improve interoperability with crawlers, remove debug pollution from production logs, and clean up placeholder code.

The bugs are:
1. **sync.getHead CID encoding bug** - Returns block data instead of CID bytes, breaking crawler compatibility
2. **Debug fprintf pollution** - Five fprintf(stderr, ...) calls pollute production logs
3. **Placeholder verification key** - Synthetic DID documents include "zQ3sh..." placeholder instead of omitting the field
4. **repo.importRepo stub** - Already correctly returns 501 (no changes needed, documentation only)

All fixes are isolated, low-risk changes with clear preservation requirements.

## Glossary

- **Bug_Condition (C)**: The condition that triggers each bug
- **Property (P)**: The desired behavior when the bug condition holds
- **Preservation**: Existing behavior that must remain unchanged by the fix
- **getRepoRoot**: Method in `PDSRepositoryService.m` that retrieves repository root data
- **sync.getHead**: XRPC endpoint that returns the CID of a repository's current head commit
- **resolveDid**: Helper function in `XrpcMethodRegistry.m` that constructs synthetic DID documents
- **CID**: Content Identifier - IPLD addressing format using base32 encoding
- **Block Data**: The actual content bytes of an IPLD block (commit object, MST node, etc.)
- **CID Bytes**: The raw bytes of a CID (multihash + codec + version)

## Bug Details

### Bug 1: sync.getHead Returns Block Data Instead of CID

#### Fault Condition

The bug manifests when `PDSRepositoryService.getRepoRoot` is called. The method fetches the root CID bytes from the database, then incorrectly fetches and returns the block data for that CID instead of returning the CID bytes themselves. This causes `com.atproto.sync.getHead` to base32-encode block data (commit object bytes) instead of CID bytes, producing an invalid CID string.

**Formal Specification:**
```
FUNCTION isBugCondition_syncGetHead(input)
  INPUT: input of type { did: String }
  OUTPUT: boolean
  
  RETURN input.did is a valid DID
         AND repository exists for input.did
         AND getRepoRoot is called
END FUNCTION
```

#### Examples

- **Bug manifestation**: Client calls `com.atproto.sync.getHead` for `did:plc:abc123`
  - Current behavior: Returns `{"root": "bafyreib..."}`  where the base32 string encodes block data (commit object)
  - Expected behavior: Returns `{"root": "bafyreib..."}` where the base32 string encodes CID bytes
  - Impact: Crawlers cannot parse the returned value as a valid CID, breaking sync protocol

- **Root cause location**: `PDSRepositoryService.m` lines 114-119
  ```objc
  NSData *rootCidBytes = [reader getRepoRootForDid:did error:blockError];
  if (rootCidBytes) {
      NSData *blockData = [reader getBlockForCID:rootCidBytes forDid:did error:blockError];
      if (blockData) {
          rootData = blockData;  // BUG: Should return rootCidBytes, not blockData
      }
  }
  ```

### Bug 2: Debug fprintf Calls in Production Code

#### Fault Condition

The bug manifests when XRPC handlers or helper functions execute. Five fprintf(stderr, ...) debug statements remain in production code, polluting stderr with debug messages that should use structured logging (PDS_LOG_* macros).

**Formal Specification:**
```
FUNCTION isBugCondition_fprintfDebug(input)
  INPUT: input of type { handler: String, params: Dictionary }
  OUTPUT: boolean
  
  RETURN input.handler IN ['resolveDid', 'com.atproto.identity.resolveDid', 'com.atproto.sync.getBlocks']
         AND handler is invoked
END FUNCTION
```

#### Examples

- **resolveDid helper function** (lines 186-195):
  - Current: Writes "[resolveDid] Resolving DID: did:plc:abc" to stderr
  - Expected: No stderr output (use PDS_LOG_* if needed)

- **com.atproto.identity.resolveDid handler** (line 5669):
  - Current: Writes "[resolveDid] Handler invoked" to stderr
  - Expected: No stderr output

- **com.atproto.sync.getBlocks handler** (line 5944):
  - Current: Writes "[getBlocks] Handler invoked" to stderr
  - Expected: No stderr output

- **Impact**: Production logs are polluted with unstructured debug messages, making it harder to parse structured logs and potentially leaking sensitive information (DIDs, handles)

### Bug 3: Placeholder Public Key in Synthetic DID Documents

#### Fault Condition

The bug manifests when the `resolveDid` helper function constructs a synthetic DID document for an account. The function includes a `verificationMethod` array with a placeholder `publicKeyMultibase` value of "zQ3sh..." instead of omitting the field entirely.

**Formal Specification:**
```
FUNCTION isBugCondition_placeholderKey(input)
  INPUT: input of type { did: String }
  OUTPUT: boolean
  
  RETURN input.did is a valid DID
         AND account exists for input.did
         AND resolveDid helper is called
         AND synthetic DID document is constructed
END FUNCTION
```

#### Examples

- **Current behavior** (lines 217-224):
  ```objc
  @"verificationMethod": @[
      @{
          @"id": [NSString stringWithFormat:@"%@#atproto", did],
          @"type": @"Multikey",
          @"controller": did,
          @"publicKeyMultibase": @"zQ3sh...", // Placeholder
      }
  ],
  ```

- **Expected behavior**: Omit the `verificationMethod` array entirely from synthetic DID documents
  - Rationale: Synthetic documents are temporary fallbacks; they should not include placeholder cryptographic material
  - Real verification methods should come from PLC directory resolution, not synthetic documents

- **Impact**: Clients may attempt to use the placeholder key for verification, leading to cryptographic failures

### Bug 4: repo.importRepo Stub Behavior (No Changes Needed)

#### Current Behavior

The `com.atproto.repo.importRepo` endpoint correctly returns HTTP 501 with error "NotImplemented" (lines 4760-4802). This is the proper stub behavior until full implementation is added.

**Formal Specification:**
```
FUNCTION isBugCondition_importRepo(input)
  INPUT: input of type { did: String, carData: Data }
  OUTPUT: boolean
  
  RETURN false  // No bug - stub behavior is correct
END FUNCTION
```

#### Examples

- **Current behavior**: Returns `{"error": "NotImplemented", "message": "repo.importRepo is not yet supported"}`
- **Expected behavior**: Same (no changes needed)
- **Documentation purpose**: This item is included in the bugfix spec to document that the 501 stub is intentional and correct

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- `com.atproto.sync.getHead` must continue to return HTTP 200 with JSON response containing "root" field for valid DIDs
- `com.atproto.sync.getHead` must continue to return HTTP 404 with error "RepoNotFound" for invalid/missing DIDs
- All other methods using `PDSRepositoryService.getRepoRoot` must continue to function correctly (they expect CID bytes, not block data)
- `com.atproto.identity.resolveDid` must continue to return DID documents with correct structure (id, alsoKnownAs, service fields)
- The `resolveDid` helper function must continue to return account DID, handle, and didDoc dictionary
- All XRPC handlers must continue to use PDS_LOG_* macros for structured logging
- `com.atproto.repo.importRepo` must continue to require authentication and return 501
- `com.atproto.sync.getBlocks` must continue to function correctly after debug output removal

**Scope:**
All inputs that do NOT trigger the specific bug conditions should be completely unaffected by these fixes. This includes:
- All other XRPC endpoints and handlers
- Database operations and transaction handling
- Authentication and authorization flows
- Repository operations other than getRepoRoot
- DID resolution for DIDs with real PLC directory entries

## Hypothesized Root Cause

Based on the bug analysis, the root causes are:

1. **sync.getHead CID Bug**: Copy-paste error or misunderstanding of method contract
   - The `getRepoRoot` method name suggests it should return the root CID
   - The implementation fetches CID bytes correctly but then unnecessarily fetches and returns block data
   - Likely cause: Developer confusion between "root CID" and "root block" concepts
   - Evidence: Other callers of `getRepoRoot` (in PDSRecordService.m, PDSController.m) expect CID bytes and use `[CID cidFromBytes:]` to parse the result

2. **fprintf Debug Statements**: Leftover debugging code from development
   - The fprintf calls follow a consistent pattern: `fprintf(stderr, "[functionName] message\n", ...)`
   - This suggests they were added during development for quick debugging
   - The codebase has proper structured logging (PDS_LOG_* macros) that should be used instead
   - Likely cause: Debug statements were never removed before commit

3. **Placeholder Verification Key**: Incomplete implementation of synthetic DID documents
   - The placeholder "zQ3sh..." suggests the developer knew a real key was needed but didn't implement key extraction
   - The comment "// Placeholder" confirms this was intentional temporary code
   - Likely cause: Synthetic DID document feature was implemented as a quick fallback without proper key handling
   - Correct approach: Omit verificationMethod entirely for synthetic documents (they're temporary fallbacks)

4. **repo.importRepo Stub**: Intentional stub behavior (no bug)
   - The 501 response is correct per HTTP semantics for unimplemented endpoints
   - The handler includes proper validation (auth, content-type, content-length) before returning 501
   - This is proper stub implementation that can be upgraded to full implementation later

## Correctness Properties

Property 1: Fault Condition - sync.getHead Returns Valid CID String

_For any_ input where a repository exists for the given DID, the fixed `getRepoRoot` method SHALL return CID bytes (not block data), and `com.atproto.sync.getHead` SHALL base32-encode those CID bytes to produce a valid CID string that can be parsed by crawlers and sync clients.

**Validates: Requirements 2.1, 2.2**

Property 2: Fault Condition - No Debug fprintf Output

_For any_ input where XRPC handlers or helper functions are invoked, the fixed code SHALL NOT write debug messages to stderr using fprintf, ensuring clean production logs.

**Validates: Requirements 2.3, 2.4, 2.5**

Property 3: Fault Condition - Synthetic DID Documents Omit Placeholder Keys

_For any_ input where a synthetic DID document is constructed, the fixed `resolveDid` helper function SHALL omit the `verificationMethod` array entirely, preventing clients from attempting to use placeholder cryptographic material.

**Validates: Requirements 2.6**

Property 4: Preservation - Existing Functionality Unchanged

_For any_ input that does NOT involve the specific bug conditions (sync.getHead, resolveDid, getBlocks handlers), the fixed code SHALL produce exactly the same behavior as the original code, preserving all existing functionality including error handling, authentication, and response formats.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File 1**: `ATProtoPDS/Sources/App/Services/PDSRepositoryService.m`

**Function**: `getRepoRoot` (lines 103-122)

**Specific Changes**:
1. **Remove block data fetch**: Delete lines 117-119 that fetch block data
   - Current code:
     ```objc
     NSData *blockData = [reader getBlockForCID:rootCidBytes forDid:did error:blockError];
     if (blockData) {
         rootData = blockData;
     }
     ```
   - Fixed code:
     ```objc
     rootData = rootCidBytes;
     ```

2. **Simplify logic**: The method should directly return CID bytes from the database
   - This aligns with the method name `getRepoRoot` (returns root CID, not root block)
   - This aligns with caller expectations (all callers use `[CID cidFromBytes:]` on the result)

**File 2**: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

**Function**: `resolveDid` helper (lines 185-230)

**Specific Changes**:
1. **Remove fprintf debug statements**: Delete lines 186, 189, 191, 195
   - Line 186: `fprintf(stderr, "[resolveDid] Resolving DID: %s\n", did.UTF8String);`
   - Line 189: `fprintf(stderr, "[resolveDid] Account not found for DID: %s\n", did.UTF8String);`
   - Line 191: `fprintf(stderr, "[resolveDid] DB Error: %s\n", (*error).description.UTF8String);`
   - Line 195: `fprintf(stderr, "[resolveDid] Found account handle: %s\n", account.handle.UTF8String);`

2. **Remove verificationMethod from synthetic DID document**: Delete lines 217-224
   - Remove the entire `@"verificationMethod": @[...]` entry from the dictionary
   - Keep all other fields: @context, id, alsoKnownAs, service

**Function**: `registerComAtprotoIdentityResolveDid` handler (lines 5669-5700)

**Specific Changes**:
3. **Remove fprintf debug statement**: Delete line 5669
   - Line 5669: `fprintf(stderr, "[resolveDid] Handler invoked\n");`

**Function**: `registerComAtprotoSyncGetBlocks` handler (lines 5944-6000)

**Specific Changes**:
4. **Remove fprintf debug statement**: Delete line 5944
   - Line 5944: `fprintf(stderr, "[getBlocks] Handler invoked\n");`

**File 3**: No changes needed for `com.atproto.repo.importRepo`
- The 501 stub behavior is correct and intentional
- This item is documentation-only

### Risk Assessment

**Low Risk Changes:**
- All four fixes are isolated, single-line or small deletions
- No complex logic changes or refactoring required
- No changes to database schema, authentication, or critical paths

**Specific Risks:**
1. **sync.getHead fix**: Very low risk
   - Change is a simple variable assignment swap
   - All callers already expect CID bytes (they use `[CID cidFromBytes:]`)
   - The bug was causing incorrect behavior; fix restores correct behavior

2. **fprintf removal**: Minimal risk
   - Removing output statements cannot break functionality
   - No code depends on stderr output
   - Structured logging (PDS_LOG_*) remains available if needed

3. **verificationMethod removal**: Low risk
   - Removing a placeholder field improves correctness
   - No code should depend on placeholder "zQ3sh..." key
   - Real verification methods come from PLC directory, not synthetic documents

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bugs on unfixed code, then verify the fixes work correctly and preserve existing behavior.

### Exploratory Fault Condition Checking

**Goal**: Surface counterexamples that demonstrate the bugs BEFORE implementing the fixes. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Write tests that call the affected methods and handlers, capturing their output and behavior. Run these tests on the UNFIXED code to observe failures and understand the root causes.

**Test Cases**:
1. **sync.getHead CID Encoding Test**: Call `com.atproto.sync.getHead` for a repository with known root CID (will fail on unfixed code)
   - Expected counterexample: Returned CID string does not match the actual root CID
   - Verification: Parse returned CID, compare to expected CID from database
   - Root cause confirmation: getRepoRoot returns block data instead of CID bytes

2. **fprintf Output Capture Test**: Invoke resolveDid, identity.resolveDid, and sync.getBlocks handlers while capturing stderr (will fail on unfixed code)
   - Expected counterexample: stderr contains "[resolveDid] ...", "[getBlocks] ..." messages
   - Verification: Capture stderr during handler execution, assert it's empty
   - Root cause confirmation: fprintf statements are present in production code

3. **Synthetic DID Document Structure Test**: Call resolveDid helper for an account, inspect returned DID document (will fail on unfixed code)
   - Expected counterexample: DID document contains verificationMethod with "zQ3sh..." placeholder
   - Verification: Parse DID document, check for verificationMethod field
   - Root cause confirmation: Placeholder key is included in synthetic documents

4. **repo.importRepo Stub Test**: Call `com.atproto.repo.importRepo` with valid CAR data (will pass on unfixed code)
   - Expected behavior: Returns 501 with "NotImplemented" error
   - Verification: This is correct stub behavior, no fix needed

**Expected Counterexamples**:
- sync.getHead returns invalid CID strings that cannot be parsed
- stderr contains debug messages during handler execution
- Synthetic DID documents contain placeholder verification methods
- Possible causes: Variable assignment error, leftover debug code, incomplete implementation

### Fix Checking

**Goal**: Verify that for all inputs where the bug conditions hold, the fixed functions produce the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition_syncGetHead(input) DO
  result := getRepoRoot_fixed(input.did)
  ASSERT result is CID bytes (not block data)
  ASSERT [CID base32Encode:result] produces valid CID string
  ASSERT parsed CID matches database root CID
END FOR

FOR ALL input WHERE isBugCondition_fprintfDebug(input) DO
  stderr_before := capture_stderr()
  invoke_handler_fixed(input)
  stderr_after := capture_stderr()
  ASSERT stderr_after == stderr_before (no new output)
END FOR

FOR ALL input WHERE isBugCondition_placeholderKey(input) DO
  didDoc := resolveDid_fixed(input.did)
  ASSERT didDoc does NOT contain "verificationMethod" key
  ASSERT didDoc contains "id", "alsoKnownAs", "service" keys
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug conditions do NOT hold, the fixed functions produce the same result as the original functions.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition_syncGetHead(input) DO
  ASSERT getRepoRoot_original(input) = getRepoRoot_fixed(input)
END FOR

FOR ALL handler WHERE handler NOT IN ['resolveDid', 'identity.resolveDid', 'sync.getBlocks'] DO
  ASSERT handler_original(input) = handler_fixed(input)
END FOR

FOR ALL did WHERE did has real PLC directory entry DO
  ASSERT resolveDid_original(did) = resolveDid_fixed(did)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for non-affected endpoints and inputs, then write property-based tests capturing that behavior.

**Test Cases**:
1. **Other getRepoRoot Callers Preservation**: Verify that PDSRecordService, PDSController, and other callers of getRepoRoot continue to work correctly after fix
2. **Error Handling Preservation**: Verify that sync.getHead returns 404 for missing DIDs, handles database errors correctly
3. **DID Document Structure Preservation**: Verify that resolveDid continues to return correct id, alsoKnownAs, service fields
4. **Other Handler Preservation**: Verify that handlers not affected by fprintf removal continue to work correctly

### Unit Tests

- Test sync.getHead with valid DID returns valid CID string
- Test sync.getHead with invalid DID returns 404 error
- Test getRepoRoot returns CID bytes that can be parsed with [CID cidFromBytes:]
- Test resolveDid helper returns DID document without verificationMethod field
- Test resolveDid helper returns DID document with correct id, alsoKnownAs, service fields
- Test identity.resolveDid handler returns 200 with valid DID document
- Test sync.getBlocks handler processes requests correctly
- Test repo.importRepo continues to return 501 (no changes)
- Test that stderr is not polluted during handler execution

### Property-Based Tests

- Generate random DIDs and verify sync.getHead returns parseable CID strings for existing repos
- Generate random account data and verify resolveDid produces valid DID documents without placeholder keys
- Generate random handler inputs and verify no fprintf output is produced
- Generate random repository states and verify getRepoRoot callers (PDSRecordService, PDSController) continue to work correctly

### Integration Tests

- Test full sync protocol flow: getHead → getBlocks → verify CID chain
- Test identity resolution flow: resolveDid → verify DID document structure
- Test repository operations that depend on getRepoRoot: createRecord, putRecord, deleteRecord
- Test that crawlers can successfully parse sync.getHead responses
- Test that PLC directory integration continues to work for real DID resolution
