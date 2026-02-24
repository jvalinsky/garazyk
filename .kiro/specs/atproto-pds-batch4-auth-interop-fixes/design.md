# ATProto PDS Batch 4 Auth Interop Fixes - Bugfix Design

## Overview

This design addresses two critical authentication and OAuth interoperability bugs in the ATProto PDS:

1. **Issue B2 - DPoP Nonce Handling**: The `extractDIDFromAuthHeader` method incorrectly reads DPoP nonces from the HTTP request header (`DPoP-Nonce`) instead of from the DPoP proof JWT's `nonce` claim, violating RFC 9449 §4.3. This affects 44 call sites across all authenticated endpoints and breaks standards-compliant OAuth clients.

2. **Issue B3 - OAuth Metadata Route Duplication**: OAuth .well-known metadata routes are registered in both `HttpRouter.m` (lines 277-374) and `OAuth2Handler.m`, creating divergent metadata sources and potential inconsistencies.

The fixes ensure RFC 9449 compliance for DPoP authentication and establish OAuth2Handler as the single source of truth for OAuth metadata.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug
  - **B2**: DPoP-authenticated requests where nonce is read from request header instead of JWT claim
  - **B3**: OAuth metadata requests that may be served by HttpRouter instead of OAuth2Handler
- **Property (P)**: The desired correct behavior
  - **B2**: Nonces are read from DPoP proof JWT's `nonce` claim per RFC 9449 §4.3
  - **B3**: All OAuth metadata requests are served exclusively by OAuth2Handler
- **Preservation**: Existing behaviors that must remain unchanged
  - DPoP authentication flow continues to work correctly
  - OAuth metadata continues to be served with correct content
  - All 44 authenticated endpoints continue to function
- **RFC 9449**: OAuth 2.0 Demonstrating Proof-of-Possession at the Application Layer (DPoP) specification
- **extractDIDFromAuthHeader**: Method in `XrpcMethodRegistry.m` that validates auth headers and extracts DIDs
- **OAuth2DPoPProof.verifyProof**: Method in `OAuth2.m` that validates DPoP proof JWTs (lines 728-900)
- **PDSNonceManager**: Singleton that generates and validates server-issued nonces


## Bug Details

### Issue B2: DPoP Nonce Handling

#### Fault Condition

The bug manifests when a client sends a DPoP-authenticated request with a nonce. The `extractDIDFromAuthHeader` method reads the nonce from the HTTP request header (`DPoP-Nonce`) instead of from the DPoP proof JWT's `nonce` claim, violating RFC 9449 §4.3.

**Formal Specification:**
```
FUNCTION isBugCondition_B2(request)
  INPUT: request of type HttpRequest with DPoP authentication
  OUTPUT: boolean
  
  RETURN request.authHeader STARTS_WITH "DPoP "
         AND request.headers["DPoP"] EXISTS
         AND extractDIDFromAuthHeader reads nonce from request.headers["DPoP-Nonce"]
         AND NOT reads nonce from DPoP_JWT.payload["nonce"]
END FUNCTION
```

#### Root Cause Analysis

**Location**: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`, lines 5536-5540

```objective-c
NSString *requestedNonce = [request headerForKey:@"DPoP-Nonce"];
if (requestedNonce.length == 0) {
    requestedNonce = nil;
}
```

**Problem**: The code reads the nonce from the HTTP request header `DPoP-Nonce`. According to RFC 9449 §4.3:

- **Server → Client**: Server sends nonce in `DPoP-Nonce` HTTP response header
- **Client → Server**: Client includes nonce in DPoP proof JWT's `nonce` claim

The current implementation has the directionality backwards. It's reading from the request header (client-to-server) when it should be reading from the JWT payload claim.

**Correct Flow per RFC 9449 §4.3**:
1. Server generates nonce and sends in `DPoP-Nonce` response header (401 response)
2. Client receives nonce from response header
3. Client includes nonce in DPoP proof JWT's `nonce` claim
4. Server validates nonce by reading from JWT's `nonce` claim

**Current (Incorrect) Flow**:
1. Server generates nonce and sends in `DPoP-Nonce` response header ✓
2. Client receives nonce from response header ✓
3. Client includes nonce in DPoP proof JWT's `nonce` claim ✓
4. Server reads nonce from request header `DPoP-Nonce` ✗ (WRONG)

**Impact**: Standards-compliant OAuth clients that correctly include nonces in the JWT claim will have their nonces ignored, causing authentication failures or unnecessary roundtrips.


#### Examples

**Example 1: Standards-Compliant Client (Currently Broken)**
- Client receives 401 with `DPoP-Nonce: abc123` response header
- Client creates DPoP proof JWT with `{"nonce": "abc123"}` in payload
- Client sends request with `DPoP` header containing the JWT
- Server reads nonce from `DPoP-Nonce` request header (empty/missing)
- Server rejects request or issues new nonce unnecessarily

**Example 2: Non-Compliant Client (Currently Works by Accident)**
- Client receives 401 with `DPoP-Nonce: abc123` response header
- Client creates DPoP proof JWT without nonce claim
- Client sends request with `DPoP-Nonce: abc123` request header (wrong)
- Server reads nonce from `DPoP-Nonce` request header
- Server accepts request (but violates RFC 9449)

**Example 3: After Fix (Correct Behavior)**
- Client receives 401 with `DPoP-Nonce: abc123` response header
- Client creates DPoP proof JWT with `{"nonce": "abc123"}` in payload
- Client sends request with `DPoP` header containing the JWT
- Server reads nonce from DPoP JWT's `nonce` claim
- Server validates nonce and accepts request

### Issue B3: OAuth Metadata Route Duplication

#### Fault Condition

OAuth .well-known metadata routes are registered in both `HttpRouter.m` and `OAuth2Handler.m`, creating potential for divergent metadata depending on which handler processes the request.

**Formal Specification:**
```
FUNCTION isBugCondition_B3(request)
  INPUT: request of type HttpRequest for OAuth metadata
  OUTPUT: boolean
  
  RETURN request.path IN [
           "/.well-known/oauth-authorization-server",
           "/.well-known/oauth-protected-resource"
         ]
         AND HttpRouter has route registration for request.path
         AND OAuth2Handler has route registration for request.path
         AND metadata_source is ambiguous
END FUNCTION
```

#### Root Cause Analysis

**Locations**:
- `ATProtoPDS/Sources/Network/HttpRouter.m`, lines 277-374 (4 route registrations)
- `ATProtoPDS/Sources/Auth/OAuth2Handler.m`, lines 509-520 (2 route registrations)

**Problem**: Both components register handlers for the same OAuth metadata paths:
- `GET /.well-known/oauth-authorization-server`
- `GET /.well-known/oauth-protected-resource`
- `OPTIONS` variants for CORS preflight

**HttpRouter Implementation** (lines 277-374):
- Creates `OAuthServerMetadata` inline
- Uses `strongSelf.baseURL` for configuration
- Hardcoded metadata structure

**OAuth2Handler Implementation** (lines 509-520):
- Uses `self.oauthServer.issuer` for configuration
- Delegates to `OAuthServerMetadata` class
- More flexible and maintainable

**Divergence Risk**:
1. Different base URL sources (`baseURL` vs `issuer`)
2. Different metadata generation logic
3. Updates to one handler don't affect the other
4. Route precedence depends on registration order


#### Examples

**Example 1: Metadata Inconsistency**
- HttpRouter serves metadata with `baseURL = "http://localhost:2583"`
- OAuth2Handler serves metadata with `issuer = "https://pds.example.com"`
- Client receives different metadata depending on routing order
- OAuth flow breaks due to endpoint URL mismatches

**Example 2: Update Propagation Failure**
- Developer updates OAuth2Handler metadata logic
- HttpRouter still serves old metadata structure
- Some clients get updated metadata, others get stale metadata
- Intermittent OAuth failures

**Example 3: After Fix (Correct Behavior)**
- Only OAuth2Handler registers .well-known routes
- All metadata requests go to OAuth2Handler
- Single source of truth for OAuth metadata
- Consistent metadata across all requests

## Expected Behavior

### Issue B2: DPoP Nonce Handling (Correct Behavior)

**2.1** WHEN the server requires a DPoP nonce THEN the system SHALL issue the nonce in the `DPoP-Nonce` response header (server-to-client direction)

**2.2** WHEN a client sends a DPoP-authenticated request with a nonce THEN the system SHALL read the nonce from the DPoP proof JWT's `nonce` claim (not from request headers)

**2.3** WHEN validating DPoP proofs THEN the system SHALL verify the `nonce` claim in the JWT payload matches the server-issued nonce per RFC 9449 §4.3

**2.4** WHEN a DPoP proof is missing a required nonce THEN the system SHALL return 401 with a new nonce in the `DPoP-Nonce` response header

**Implementation Note**: The `OAuth2DPoPProof.verifyProof` method (lines 728-900 in OAuth2.m) already correctly reads nonces from the JWT payload claim (line 833: `NSString *proofNonce = payload[@"nonce"];`). The bug is only in `extractDIDFromAuthHeader`, which passes the wrong nonce value to `verifyProof`.

### Issue B3: OAuth Metadata Route Duplication (Correct Behavior)

**2.5** WHEN OAuth metadata is requested via .well-known paths THEN the system SHALL route requests to OAuth2Handler as the single source of truth

**2.6** WHEN .well-known/oauth-authorization-server is requested THEN the system SHALL return metadata exclusively from OAuth2Handler

**2.7** WHEN .well-known/oauth-protected-resource is requested THEN the system SHALL return metadata exclusively from OAuth2Handler

**2.8** WHEN OAuth2Handler metadata logic is updated THEN the system SHALL serve the updated metadata without requiring changes to HttpRouter

### Preservation Requirements

**Unchanged Behaviors:**

**3.1** WHEN a client sends a valid DPoP proof with correct nonce THEN the system SHALL CONTINUE TO successfully authenticate the request

**3.2** WHEN extractDIDFromAuthHeader is called from any of the 44 call sites THEN the system SHALL CONTINUE TO extract and validate DIDs correctly

**3.3** WHEN PDSNonceManager generates and validates nonces THEN the system SHALL CONTINUE TO use the existing nonce storage and validation logic

**3.4** WHEN DPoP proof validation fails for reasons other than nonce THEN the system SHALL CONTINUE TO return appropriate error responses

**3.5** WHEN OAuth clients request .well-known metadata THEN the system SHALL CONTINUE TO return valid OAuth 2.0 authorization server metadata

**3.6** WHEN OAuth2Handler serves metadata THEN the system SHALL CONTINUE TO include all required OAuth 2.0 metadata fields

**3.7** WHEN non-OAuth routes are processed THEN the system SHALL CONTINUE TO route requests correctly through HttpRouter

**3.8** WHEN PDSHttpServerBuilder wires up handlers THEN the system SHALL CONTINUE TO initialize OAuth2Handler and HttpRouter correctly


## Hypothesized Root Cause

### Issue B2: DPoP Nonce Handling

Based on code analysis, the root cause is a misunderstanding of RFC 9449 §4.3 nonce flow directionality:

1. **Incorrect Assumption**: Developer assumed nonces flow in request headers (both directions)
   - Server sends nonce in `DPoP-Nonce` response header ✓
   - Client sends nonce in `DPoP-Nonce` request header ✗

2. **Correct RFC 9449 Flow**: Nonces use different channels for each direction
   - Server → Client: `DPoP-Nonce` HTTP response header
   - Client → Server: `nonce` claim in DPoP proof JWT payload

3. **Evidence**: The `OAuth2DPoPProof.verifyProof` method correctly reads from JWT payload (line 833), but `extractDIDFromAuthHeader` passes the wrong nonce value from request headers (line 5536)

4. **Why It Wasn't Caught**: The bug is subtle because:
   - The nonce validation logic in `verifyProof` is correct
   - The bug is in the nonce extraction before calling `verifyProof`
   - Tests may have used non-compliant clients that send nonces in request headers

### Issue B3: OAuth Metadata Route Duplication

Based on code analysis, the root cause is architectural evolution without cleanup:

1. **Initial Implementation**: HttpRouter handled all routes including OAuth metadata (lines 277-374)

2. **OAuth2Handler Addition**: OAuth2Handler was added later with its own route registrations (lines 509-520)

3. **Missing Cleanup**: When OAuth2Handler was added, the HttpRouter registrations were not removed

4. **Route Precedence**: The actual handler depends on registration order in `PDSHttpServerBuilder`:
   - If HttpRouter registers first, it handles .well-known requests
   - If OAuth2Handler registers first, it handles .well-known requests

5. **Why It Wasn't Caught**: Both handlers return similar metadata, so the duplication doesn't cause immediate failures, only potential inconsistencies


## Correctness Properties

Property 1: Fault Condition - DPoP Nonce Read from JWT Claim

_For any_ DPoP-authenticated request where a nonce is required, the fixed extractDIDFromAuthHeader function SHALL read the nonce from the DPoP proof JWT's `nonce` claim (not from the `DPoP-Nonce` request header), and SHALL pass this nonce to OAuth2DPoPProof.verifyProof for validation per RFC 9449 §4.3.

**Validates: Requirements 2.2, 2.3**

Property 2: Fault Condition - OAuth Metadata Single Source

_For any_ request to `/.well-known/oauth-authorization-server` or `/.well-known/oauth-protected-resource`, the fixed system SHALL route the request exclusively to OAuth2Handler, ensuring a single source of truth for OAuth metadata.

**Validates: Requirements 2.5, 2.6, 2.7**

Property 3: Preservation - DPoP Authentication Flow

_For any_ DPoP-authenticated request with a valid nonce in the JWT claim, the fixed extractDIDFromAuthHeader function SHALL produce the same authentication result as the original function would have produced if the nonce had been in the request header, preserving the DPoP authentication flow for all 44 authenticated endpoints.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

Property 4: Preservation - OAuth Metadata Content

_For any_ OAuth metadata request, the fixed system SHALL return metadata with the same structure and required fields as the original OAuth2Handler implementation, preserving OAuth 2.0 compliance and client compatibility.

**Validates: Requirements 3.5, 3.6, 3.7, 3.8**

## Fix Implementation

### Issue B2: DPoP Nonce Handling

#### Changes Required

**File**: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

**Function**: `extractDIDFromAuthHeader:jwtMinter:adminController:request:response:` (lines 5483-5641)

**Specific Changes**:

1. **Remove Incorrect Nonce Extraction** (lines 5536-5540):
   ```objective-c
   // REMOVE THIS:
   NSString *requestedNonce = [request headerForKey:@"DPoP-Nonce"];
   if (requestedNonce.length == 0) {
       requestedNonce = nil;
   }
   ```

2. **Parse DPoP Proof JWT to Extract Nonce** (insert after line 5535):
   ```objective-c
   // Parse DPoP proof JWT to extract nonce from payload
   NSString *requestedNonce = nil;
   NSArray<NSString *> *dpopParts = [dpopProof componentsSeparatedByString:@"."];
   if (dpopParts.count == 3) {
       NSError *parseError = nil;
       NSData *payloadData = [JWT base64URLDecode:dpopParts[1] error:&parseError];
       if (payloadData) {
           NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData 
                                                                   options:0 
                                                                     error:&parseError];
           if ([payload isKindOfClass:[NSDictionary class]]) {
               requestedNonce = payload[@"nonce"];
               if (![requestedNonce isKindOfClass:[NSString class]]) {
                   requestedNonce = nil;
               }
           }
       }
   }
   ```

3. **Rationale**: 
   - Extract nonce directly from DPoP proof JWT's payload claim
   - Use existing JWT base64URL decoding utility
   - Maintain nil-safety for missing or invalid nonces
   - No changes needed to `OAuth2DPoPProof.verifyProof` (already correct)

**Impact**: Affects all 44 authenticated endpoints that call `extractDIDFromAuthHeader`


### Issue B3: OAuth Metadata Route Duplication

#### Changes Required

**File**: `ATProtoPDS/Sources/Network/HttpRouter.m`

**Method**: `setupRoutes` (lines 277-374)

**Specific Changes**:

1. **Remove OAuth Authorization Server Metadata Route** (lines 277-314):
   ```objective-c
   // DELETE THIS ENTIRE BLOCK:
   [self addRoute:@"GET"
            pattern:@"/.well-known/oauth-authorization-server"
            handler:^(HttpRequest *request, HttpResponse *response) {
       // ... (entire handler implementation)
   }];
   ```

2. **Remove OAuth Authorization Server CORS Preflight** (lines 314-324):
   ```objective-c
   // DELETE THIS ENTIRE BLOCK:
   [self addRoute:@"OPTIONS"
            pattern:@"/.well-known/oauth-authorization-server"
            handler:^(HttpRequest *request, HttpResponse *response) {
       // ... (entire handler implementation)
   }];
   ```

3. **Remove OAuth Protected Resource Metadata Route** (lines 324-374):
   ```objective-c
   // DELETE THIS ENTIRE BLOCK:
   [self addRoute:@"GET"
            pattern:@"/.well-known/oauth-protected-resource"
            handler:^(HttpRequest *request, HttpResponse *response) {
       // ... (entire handler implementation)
   }];
   ```

4. **Remove OAuth Protected Resource CORS Preflight** (lines 374+):
   ```objective-c
   // DELETE THIS ENTIRE BLOCK:
   [self addRoute:@"OPTIONS"
            pattern:@"/.well-known/oauth-protected-resource"
            handler:^(HttpRequest *request, HttpResponse *response) {
       // ... (entire handler implementation)
   }];
   ```

**Rationale**:
- OAuth2Handler already registers these routes (lines 509-520 in OAuth2Handler.m)
- OAuth2Handler has proper issuer configuration and metadata generation
- Removing HttpRouter registrations establishes OAuth2Handler as single source of truth
- No changes needed to OAuth2Handler (already correct)

**Verification**:
- Ensure `PDSHttpServerBuilder` registers OAuth2Handler routes before HttpRouter
- Confirm .well-known requests are handled by OAuth2Handler
- Verify metadata consistency across all requests

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bugs on unfixed code, then verify the fixes work correctly and preserve existing behavior.

### Exploratory Fault Condition Checking

**Goal**: Surface counterexamples that demonstrate the bugs BEFORE implementing the fixes. Confirm or refute the root cause analysis.

#### Issue B2: DPoP Nonce Handling

**Test Plan**: Write tests that create DPoP-authenticated requests with nonces in the JWT claim (RFC 9449 compliant) and verify the nonce is correctly validated. Run these tests on the UNFIXED code to observe failures.

**Test Cases**:
1. **RFC-Compliant Nonce in JWT Claim**: Create DPoP proof with `nonce` in payload, verify authentication succeeds (will fail on unfixed code)
2. **Nonce in Request Header Only**: Create DPoP proof without `nonce` in payload, send `DPoP-Nonce` request header, verify authentication succeeds (will succeed on unfixed code, demonstrating the bug)
3. **Nonce Mismatch**: Create DPoP proof with `nonce: "abc"` in payload, server expects `nonce: "xyz"`, verify authentication fails with `use_dpop_nonce` error
4. **Missing Nonce When Required**: Create DPoP proof without `nonce` claim, verify server returns 401 with new nonce in response header

**Expected Counterexamples**:
- Test 1 fails on unfixed code (nonce in JWT claim is ignored)
- Test 2 succeeds on unfixed code (nonce in request header is used)
- After fix: Test 1 succeeds, Test 2 fails

#### Issue B3: OAuth Metadata Route Duplication

**Test Plan**: Write tests that request OAuth metadata and verify which handler processes the request. Run these tests on the UNFIXED code to observe route duplication.

**Test Cases**:
1. **Authorization Server Metadata Request**: Request `/.well-known/oauth-authorization-server`, verify response contains correct issuer and endpoints
2. **Protected Resource Metadata Request**: Request `/.well-known/oauth-protected-resource`, verify response contains correct resource and authorization servers
3. **Route Handler Identification**: Add logging to identify which handler (HttpRouter vs OAuth2Handler) processes the request
4. **Metadata Consistency**: Request metadata multiple times, verify consistent responses

**Expected Counterexamples**:
- Both HttpRouter and OAuth2Handler have route registrations
- Depending on registration order, either handler may process requests
- Potential for inconsistent metadata if handlers have different configurations


### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

#### Issue B2: DPoP Nonce Handling

**Pseudocode:**
```
FOR ALL dpop_request WHERE nonce_in_jwt_claim(dpop_request) DO
  nonce := extract_nonce_from_jwt(dpop_request.dpop_proof)
  result := extractDIDFromAuthHeader_fixed(dpop_request)
  ASSERT nonce_passed_to_verifyProof(nonce)
  ASSERT authentication_succeeds(result) OR valid_error_returned(result)
END FOR
```

**Test Cases**:
1. Valid DPoP proof with nonce in JWT claim → authentication succeeds
2. Valid DPoP proof with expired nonce in JWT claim → 401 with new nonce
3. Valid DPoP proof with invalid nonce in JWT claim → 401 with new nonce
4. Valid DPoP proof without nonce when required → 401 with new nonce
5. Malformed DPoP proof → authentication fails with appropriate error

#### Issue B3: OAuth Metadata Route Duplication

**Pseudocode:**
```
FOR ALL metadata_request WHERE is_oauth_metadata_path(metadata_request.path) DO
  handler := identify_handler(metadata_request)
  ASSERT handler = OAuth2Handler
  ASSERT NOT handler = HttpRouter
END FOR
```

**Test Cases**:
1. Request `/.well-known/oauth-authorization-server` → OAuth2Handler processes
2. Request `/.well-known/oauth-protected-resource` → OAuth2Handler processes
3. OPTIONS preflight for authorization server → OAuth2Handler processes
4. OPTIONS preflight for protected resource → OAuth2Handler processes

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

#### Issue B2: DPoP Nonce Handling

**Pseudocode:**
```
FOR ALL request WHERE NOT is_dpop_authenticated(request) DO
  ASSERT extractDIDFromAuthHeader_original(request) = extractDIDFromAuthHeader_fixed(request)
END FOR

FOR ALL dpop_request WHERE dpop_validation_fails_for_other_reasons(dpop_request) DO
  ASSERT extractDIDFromAuthHeader_original(dpop_request) = extractDIDFromAuthHeader_fixed(dpop_request)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for non-DPoP requests and DPoP requests with other validation failures, then write property-based tests capturing that behavior.

**Test Cases**:
1. **Bearer Token Authentication**: Verify Bearer token authentication continues to work identically
2. **Invalid DPoP Proof Format**: Verify malformed DPoP proofs are rejected identically
3. **DPoP HTM Mismatch**: Verify HTTP method mismatches are rejected identically
4. **DPoP HTU Mismatch**: Verify URL mismatches are rejected identically
5. **Expired DPoP Proof**: Verify expired proofs are rejected identically
6. **DPoP Thumbprint Mismatch**: Verify thumbprint mismatches are rejected identically
7. **Suspended Account**: Verify suspended accounts are rejected identically

#### Issue B3: OAuth Metadata Route Duplication

**Pseudocode:**
```
FOR ALL request WHERE NOT is_oauth_metadata_path(request.path) DO
  ASSERT HttpRouter_original(request) = HttpRouter_fixed(request)
END FOR

FOR ALL metadata_request WHERE is_oauth_metadata_path(metadata_request.path) DO
  metadata_original := get_metadata_from_oauth2handler(metadata_request)
  metadata_fixed := get_metadata_after_fix(metadata_request)
  ASSERT metadata_original = metadata_fixed
END FOR
```

**Test Plan**: Observe OAuth2Handler metadata on UNFIXED code, then verify the same metadata is served after removing HttpRouter registrations.

**Test Cases**:
1. **Non-OAuth Routes**: Verify all non-OAuth routes continue to work through HttpRouter
2. **OAuth Metadata Content**: Verify metadata content is identical to OAuth2Handler's original output
3. **CORS Headers**: Verify CORS headers are present and correct
4. **Metadata Structure**: Verify all required OAuth 2.0 metadata fields are present
5. **Endpoint URLs**: Verify endpoint URLs match the configured issuer


### Unit Tests

#### Issue B2: DPoP Nonce Handling

- Test nonce extraction from DPoP proof JWT payload
- Test nonce validation with PDSNonceManager
- Test nonce mismatch error handling
- Test missing nonce when required
- Test nonce in request header is ignored (after fix)
- Test all 44 authenticated endpoints with DPoP + nonce

#### Issue B3: OAuth Metadata Route Duplication

- Test authorization server metadata endpoint
- Test protected resource metadata endpoint
- Test CORS preflight for both endpoints
- Test metadata consistency across multiple requests
- Test that HttpRouter no longer handles .well-known paths
- Test that OAuth2Handler is the exclusive handler

### Property-Based Tests

#### Issue B2: DPoP Nonce Handling

- Generate random DPoP proofs with valid nonces in JWT claims, verify authentication succeeds
- Generate random DPoP proofs with invalid nonces, verify authentication fails with correct error
- Generate random non-DPoP requests, verify authentication behavior is unchanged
- Generate random DPoP proofs with various validation failures, verify error handling is unchanged

#### Issue B3: OAuth Metadata Route Duplication

- Generate random OAuth metadata requests, verify all are handled by OAuth2Handler
- Generate random non-OAuth requests, verify all are handled by HttpRouter
- Generate random metadata requests with various headers, verify consistent responses
- Generate random issuer configurations, verify metadata reflects correct issuer

### Integration Tests

#### Issue B2: DPoP Nonce Handling

- Full OAuth flow with DPoP authentication and nonce handling
- Test nonce issuance in 401 response
- Test nonce inclusion in subsequent DPoP proof
- Test nonce validation and authentication success
- Test nonce expiration and reissuance
- Test all authenticated XRPC methods with DPoP + nonce

#### Issue B3: OAuth Metadata Route Duplication

- Full OAuth discovery flow using .well-known endpoints
- Test client discovers authorization endpoint from metadata
- Test client discovers token endpoint from metadata
- Test client discovers JWKS endpoint from metadata
- Test metadata consistency across server restarts
- Test metadata updates when issuer configuration changes

## Risk Assessment

### Issue B2: DPoP Nonce Handling

**Risk Level**: Medium

**Risks**:
1. **Breaking Change**: Clients that incorrectly send nonces in request headers will break
   - **Mitigation**: This is correct behavior per RFC 9449; non-compliant clients should be fixed
   - **Impact**: Low (most OAuth clients follow RFC 9449)

2. **JWT Parsing Overhead**: Adding JWT parsing in extractDIDFromAuthHeader
   - **Mitigation**: Minimal overhead (single base64 decode + JSON parse)
   - **Impact**: Negligible performance impact

3. **Regression in Non-DPoP Auth**: Changes might affect Bearer token authentication
   - **Mitigation**: Changes are isolated to DPoP branch (line 5502: `if (isDPoP)`)
   - **Impact**: Low (well-isolated code path)

**Benefits**:
- RFC 9449 compliance
- Interoperability with standards-compliant OAuth clients
- Correct nonce flow directionality

### Issue B3: OAuth Metadata Route Duplication

**Risk Level**: Low

**Risks**:
1. **Route Registration Order Dependency**: If OAuth2Handler isn't registered, .well-known routes won't work
   - **Mitigation**: Verify PDSHttpServerBuilder registers OAuth2Handler
   - **Impact**: Low (OAuth2Handler is always registered)

2. **Metadata Content Changes**: Removing HttpRouter routes might expose differences in metadata
   - **Mitigation**: OAuth2Handler metadata is more complete and correct
   - **Impact**: Low (OAuth2Handler metadata is the authoritative source)

3. **CORS Configuration**: CORS headers might differ between handlers
   - **Mitigation**: OAuth2Handler includes proper CORS headers
   - **Impact**: Low (OAuth2Handler CORS is correct)

**Benefits**:
- Single source of truth for OAuth metadata
- Easier maintenance and updates
- Consistent metadata across all requests
- Reduced code duplication

## Implementation Order

1. **Issue B2 (DPoP Nonce)**: Implement first
   - Higher impact (affects all authenticated endpoints)
   - More critical for RFC compliance
   - Independent of Issue B3

2. **Issue B3 (Route Duplication)**: Implement second
   - Lower risk
   - Simpler change (deletion only)
   - Can be verified independently

3. **Integration Testing**: After both fixes
   - Test full OAuth flow with DPoP + nonce
   - Test metadata discovery and OAuth flow
   - Test all authenticated endpoints
