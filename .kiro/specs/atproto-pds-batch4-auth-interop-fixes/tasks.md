# Implementation Plan

- [ ] 1. Write bug condition exploration tests (BEFORE implementing fix)
  - **Property 1: Fault Condition** - DPoP Nonce Read from JWT Claim & OAuth Metadata Single Source
  - **CRITICAL**: These tests MUST FAIL on unfixed code - failure confirms the bugs exist
  - **DO NOT attempt to fix the tests or the code when they fail**
  - **NOTE**: These tests encode the expected behavior - they will validate the fixes when they pass after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bugs exist
  
  - [ ] 1.1 Write B2 exploration test: DPoP nonce read from JWT claim
    - **Scoped PBT Approach**: Test concrete failing case - DPoP proof with nonce in JWT claim (RFC 9449 compliant)
    - Create DPoP-authenticated request with valid nonce in JWT payload's `nonce` claim
    - Create DPoP proof JWT with `{"nonce": "test-nonce-123"}` in payload
    - Call `extractDIDFromAuthHeader` with the request
    - Assert that authentication succeeds (nonce is correctly extracted from JWT claim)
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test FAILS (nonce is read from request header instead of JWT claim)
    - Document counterexample: "extractDIDFromAuthHeader ignores nonce in JWT claim, reads from DPoP-Nonce request header instead"
    - _Requirements: 2.2, 2.3_
  
  - [ ] 1.2 Write B2 exploration test: Nonce in request header is ignored
    - **Scoped PBT Approach**: Test concrete case - DPoP proof without nonce in JWT, with nonce in request header
    - Create DPoP-authenticated request with nonce in `DPoP-Nonce` request header but NOT in JWT claim
    - Call `extractDIDFromAuthHeader` with the request
    - Assert that authentication fails or nonce is not validated (RFC 9449 non-compliant)
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test FAILS (nonce in request header is incorrectly used)
    - Document counterexample: "extractDIDFromAuthHeader accepts nonce from request header, violating RFC 9449"
    - _Requirements: 2.2, 2.3_
  
  - [ ] 1.3 Write B3 exploration test: OAuth metadata route duplication
    - **Scoped PBT Approach**: Test concrete failing case - .well-known metadata requests
    - Add logging to identify which handler processes OAuth metadata requests
    - Request `/.well-known/oauth-authorization-server`
    - Request `/.well-known/oauth-protected-resource`
    - Assert that only OAuth2Handler processes these requests (not HttpRouter)
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test FAILS (both HttpRouter and OAuth2Handler have route registrations)
    - Document counterexample: "HttpRouter has duplicate route registrations for .well-known paths (lines 277-374)"
    - _Requirements: 2.5, 2.6, 2.7_
  
  - [ ] 1.4 Write B3 exploration test: Metadata consistency
    - Request OAuth metadata multiple times
    - Verify all requests return consistent metadata
    - Verify metadata source is OAuth2Handler (not HttpRouter)
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: May pass or fail depending on route registration order
    - Document observation: "Metadata source depends on registration order in PDSHttpServerBuilder"
    - _Requirements: 2.5, 2.8_

- [ ] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - DPoP Authentication Flow & OAuth Metadata Content
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs
  - Write property-based tests capturing observed behavior patterns
  - Property-based testing generates many test cases for stronger guarantees
  
  - [ ] 2.1 Observe and test Bearer token authentication preservation
    - Observe: Bearer token authentication works on unfixed code
    - Write property-based test: for all Bearer token requests, authentication behavior is unchanged
    - Generate random Bearer token requests with valid/invalid tokens
    - Verify authentication results match unfixed code behavior
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES (confirms baseline behavior to preserve)
    - _Requirements: 3.1, 3.2_
  
  - [ ] 2.2 Observe and test DPoP validation failures preservation
    - Observe: DPoP validation failures (malformed proof, HTM mismatch, HTU mismatch, expired proof, thumbprint mismatch) work on unfixed code
    - Write property-based test: for all DPoP requests with validation failures (non-nonce), error handling is unchanged
    - Generate random DPoP requests with various validation failures
    - Verify error responses match unfixed code behavior
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES (confirms baseline error handling to preserve)
    - _Requirements: 3.2, 3.4_
  
  - [ ] 2.3 Observe and test suspended account rejection preservation
    - Observe: Suspended accounts are rejected on unfixed code
    - Write property-based test: for all requests from suspended accounts, rejection behavior is unchanged
    - Generate random requests from suspended accounts
    - Verify rejection responses match unfixed code behavior
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES (confirms baseline rejection to preserve)
    - _Requirements: 3.2_
  
  - [ ] 2.4 Observe and test OAuth metadata content preservation
    - Observe: OAuth2Handler serves metadata with correct structure on unfixed code
    - Write property-based test: for all OAuth metadata requests, content structure is unchanged
    - Request `/.well-known/oauth-authorization-server` from OAuth2Handler
    - Request `/.well-known/oauth-protected-resource` from OAuth2Handler
    - Verify metadata contains all required OAuth 2.0 fields
    - Verify CORS headers are present
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES (confirms baseline metadata to preserve)
    - _Requirements: 3.5, 3.6_
  
  - [ ] 2.5 Observe and test non-OAuth route preservation
    - Observe: Non-OAuth routes work through HttpRouter on unfixed code
    - Write property-based test: for all non-OAuth routes, routing behavior is unchanged
    - Generate random requests to non-OAuth paths
    - Verify requests are handled by HttpRouter
    - Run test on UNFIXED code
    - **EXPECTED OUTCOME**: Test PASSES (confirms baseline routing to preserve)
    - _Requirements: 3.7, 3.8_

- [ ] 3. Fix for DPoP nonce handling and OAuth metadata route duplication

  - [ ] 3.1 Implement B2 fix: DPoP nonce extraction from JWT claim
    - File: `Garazyk/Sources/Network/XrpcMethodRegistry.m`
    - Function: `extractDIDFromAuthHeader:jwtMinter:adminController:request:response:` (lines 5483-5641)
    - Remove incorrect nonce extraction from request header (lines 5536-5540)
    - Add JWT parsing to extract nonce from DPoP proof payload's `nonce` claim
    - Parse DPoP proof JWT (split on ".", base64URL decode payload, JSON parse)
    - Extract `nonce` claim from payload dictionary
    - Maintain nil-safety for missing or invalid nonces
    - Pass extracted nonce to `OAuth2DPoPProof.verifyProof` (no changes needed to verifyProof)
    - _Bug_Condition: isBugCondition_B2(request) where request has DPoP auth and extractDIDFromAuthHeader reads nonce from request.headers["DPoP-Nonce"] instead of DPoP_JWT.payload["nonce"]_
    - _Expected_Behavior: extractDIDFromAuthHeader reads nonce from DPoP proof JWT's nonce claim per RFC 9449 §4.3 (Requirements 2.2, 2.3)_
    - _Preservation: Bearer token authentication, DPoP validation failures, suspended account rejection continue to work identically (Requirements 3.1, 3.2, 3.3, 3.4)_
    - _Requirements: 2.2, 2.3, 3.1, 3.2, 3.3, 3.4_
  
  - [ ] 3.2 Implement B3 fix: Remove OAuth metadata route duplication
    - File: `Garazyk/Sources/Network/HttpRouter.m`
    - Method: `setupRoutes` (lines 277-374)
    - Remove GET `/.well-known/oauth-authorization-server` route registration (lines 277-314)
    - Remove OPTIONS `/.well-known/oauth-authorization-server` CORS preflight (lines 314-324)
    - Remove GET `/.well-known/oauth-protected-resource` route registration (lines 324-374)
    - Remove OPTIONS `/.well-known/oauth-protected-resource` CORS preflight (lines 374+)
    - Verify OAuth2Handler route registrations remain (OAuth2Handler.m lines 509-520)
    - Verify PDSHttpServerBuilder registers OAuth2Handler before HttpRouter
    - _Bug_Condition: isBugCondition_B3(request) where request.path is .well-known OAuth metadata and both HttpRouter and OAuth2Handler have route registrations_
    - _Expected_Behavior: All OAuth metadata requests are routed exclusively to OAuth2Handler (Requirements 2.5, 2.6, 2.7, 2.8)_
    - _Preservation: OAuth metadata content, CORS headers, non-OAuth routes continue to work identically (Requirements 3.5, 3.6, 3.7, 3.8)_
    - _Requirements: 2.5, 2.6, 2.7, 2.8, 3.5, 3.6, 3.7, 3.8_

  - [ ] 3.3 Verify B2 exploration tests now pass
    - **Property 1: Expected Behavior** - DPoP Nonce Read from JWT Claim
    - **IMPORTANT**: Re-run the SAME tests from task 1.1 and 1.2 - do NOT write new tests
    - The tests from task 1 encode the expected behavior
    - When these tests pass, they confirm the expected behavior is satisfied
    - Run test 1.1: DPoP nonce read from JWT claim
    - Run test 1.2: Nonce in request header is ignored
    - **EXPECTED OUTCOME**: Tests PASS (confirms B2 bug is fixed)
    - Verify nonce is correctly extracted from JWT payload's `nonce` claim
    - Verify nonce in request header is ignored
    - _Requirements: 2.2, 2.3_

  - [ ] 3.4 Verify B3 exploration tests now pass
    - **Property 1: Expected Behavior** - OAuth Metadata Single Source
    - **IMPORTANT**: Re-run the SAME tests from task 1.3 and 1.4 - do NOT write new tests
    - Run test 1.3: OAuth metadata route duplication
    - Run test 1.4: Metadata consistency
    - **EXPECTED OUTCOME**: Tests PASS (confirms B3 bug is fixed)
    - Verify only OAuth2Handler processes .well-known requests
    - Verify HttpRouter no longer has duplicate route registrations
    - Verify metadata is consistent across all requests
    - _Requirements: 2.5, 2.6, 2.7, 2.8_

  - [ ] 3.5 Verify preservation tests still pass
    - **Property 2: Preservation** - DPoP Authentication Flow & OAuth Metadata Content
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run test 2.1: Bearer token authentication preservation
    - Run test 2.2: DPoP validation failures preservation
    - Run test 2.3: Suspended account rejection preservation
    - Run test 2.4: OAuth metadata content preservation
    - Run test 2.5: Non-OAuth route preservation
    - **EXPECTED OUTCOME**: All tests PASS (confirms no regressions)
    - Confirm all preservation properties still hold after fixes
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

- [ ] 4. Checkpoint - Ensure all tests pass
  - Run all exploration tests (tasks 1.1-1.4) - should now PASS
  - Run all preservation tests (tasks 2.1-2.5) - should still PASS
  - Run full test suite: `./build/tests/AllTests`
  - Verify 0 failures
  - Test all 44 authenticated endpoints with DPoP + nonce
  - Test OAuth discovery flow using .well-known endpoints
  - Ask the user if questions arise
