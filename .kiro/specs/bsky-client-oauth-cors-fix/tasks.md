# Implementation Plan

## Summary

This implementation plan follows the bugfix requirements-first workflow to fix ATProto OAuth client_metadata support. The bug prevents standard ATProto clients (bsky.app, witchsky.app) from authenticating because they are not pre-registered in the database.

**Current Status**: Implementation and unit testing complete (tasks 1-3.9). Ready for integration testing on live PDS.

**What's Done**:
- ✅ Bug condition exploration test (Task 1) - All 4 test cases passing
- ✅ Preservation property tests (Task 2) - All 7 property tests passing
- ✅ client_metadata extraction and parsing (Task 3.1)
- ✅ Client metadata validation method (Task 3.2)
- ✅ Dual-path client validation (Task 3.3)
- ✅ Loopback redirect validation (Task 3.4)
- ✅ Redirect URI validation logic (Task 3.5)
- ✅ OPTIONS handlers for CORS (Task 3.6)
- ✅ Verification tests (Tasks 3.7-3.9) - All tests passing

**What's Next**:
- ⏭️ Integration testing on live PDS pds.garazyk.xyz (Task 4) - 5 subtasks
- ⏭️ Final checkpoint and deployment verification (Task 5)

**Key Files Modified**:
- `ATProtoPDS/Sources/Auth/OAuth2Handler.m` - Core OAuth handler with client_metadata support
- `ATProtoPDS/Sources/Auth/OAuth2Handler.h` - Added clientMetadata property
- `ATProtoPDS/Tests/Auth/OAuth2ATProtoClientTests.m` - Bug condition exploration tests
- `ATProtoPDS/Tests/Auth/OAuth2PreservationTests.m` - Preservation property tests
- `ATProtoPDS/Tests/Auth/OAuth2ClientMetadataValidationTests.m` - Unit tests for metadata validation

---

## Tasks

- [x] 1. Write bug condition exploration test
  - **Property 1: Fault Condition** - ATProto Client Authorization Without Database Registration
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to concrete failing cases (bsky.app, witchsky.app, loopback redirects)
  - Test that OAuth2Handler rejects ATProto clients providing valid client_metadata but not in database
  - Test cases:
    - bsky.app authorization with client_id=https://bsky.app and valid client_metadata
    - witchsky.app authorization with client_id=https://witchsky.app and valid client_metadata
    - Native app with loopback redirect_uri=http://127.0.0.1:8080/callback
    - Client with redirect_uri=http://[::1]:3000/callback (IPv6 loopback)
  - The test assertions should match Expected Behavior: authorization succeeds, no "unauthorized_client" error
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS with "unauthorized_client" error (this is correct - it proves the bug exists)
  - Document counterexamples found:
    - validateClient returns nil because client_id not in database
    - validateRedirectURI rejects loopback HTTP redirects
    - No client_metadata parameter extraction occurs
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Registered Client Behavior Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for registered clients (clients in oauth_clients table)
  - Write property-based tests capturing observed behavior patterns:
    - Registered clients continue to authenticate successfully
    - PKCE validation (code_challenge required, S256 method, code_verifier validation) works identically
    - DPoP proof validation for token requests works identically
    - CSRF protection (state parameter validation) works identically
    - Token lifecycle operations (issuance, refresh, revocation) work identically
    - Security validations (nonce, replay protection, signature verification) work identically
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 3. Fix for ATProto OAuth client_metadata support

  - [x] 3.1 Add client_metadata parameter extraction and parsing
    - In OAuth2Handler.m `handleAuthorizeRequest`, extract `client_metadata` query parameter
    - Parse JSON string to NSDictionary
    - Store in OAuth2AuthorizationRequest.clientMetadata property
    - Add `@property (nonatomic, copy, nullable) NSDictionary *clientMetadata;` to OAuth2.h OAuth2AuthorizationRequest interface
    - Handle JSON parsing errors gracefully
    - _Bug_Condition: isBugCondition(input) where input.clientID NOT IN database AND input.client_metadata is provided_
    - _Expected_Behavior: client_metadata is extracted and available for validation_
    - _Preservation: Registered clients don't provide client_metadata, so this is additive_
    - _Requirements: 2.1_

  - [x] 3.2 Implement client metadata validation method
    - Create new method `validateClientMetadata:error:` in OAuth2Handler.m
    - Validate client_id is HTTPS URL (required by ATProto spec)
    - Validate redirect_uris array is present, non-empty, and contains valid URIs
    - Validate client_name is present (optional but recommended)
    - Validate grant_types if provided (default to "authorization_code refresh_token")
    - Validate scope if provided (default to "atproto")
    - Return normalized client dictionary matching database format for consistency
    - Return nil with descriptive error for invalid metadata
    - _Bug_Condition: isBugCondition(input) where input.client_metadata contains valid ATProto client metadata_
    - _Expected_Behavior: validateClientMetadata returns normalized client dictionary_
    - _Preservation: This is a new method, doesn't affect existing paths_
    - _Requirements: 2.2, 2.3_

  - [x] 3.3 Implement dual-path client validation
    - Modify `validateClient:error:` in OAuth2Handler.m to support both database and metadata validation
    - First attempt: Query database (existing path - preserve this exactly)
    - If not found AND client_metadata provided: Call validateClientMetadata
    - If not found AND no client_metadata: Return existing "unauthorized_client" error
    - Return unified client dictionary format for both paths
    - Add `@property (nonatomic, strong, nullable) NSDictionary *clientMetadata;` to OAuth2Handler.h if needed for state
    - _Bug_Condition: isBugCondition(input) where input.clientID NOT IN database AND input.client_metadata is provided_
    - _Expected_Behavior: validateClient succeeds using client_metadata when database lookup fails_
    - _Preservation: Database lookup path unchanged, metadata path only activates when database returns nil_
    - _Requirements: 2.1, 2.2_

  - [x] 3.4 Implement loopback redirect validation
    - Create helper method `isLoopbackRedirect:` in OAuth2Handler.m
    - Detect http://127.0.0.1:* (IPv4 loopback)
    - Detect http://localhost:* (localhost alias)
    - Detect http://[::1]:* (IPv6 loopback)
    - Return YES for loopback patterns, NO otherwise
    - _Bug_Condition: isBugCondition(input) where redirect_uri is loopback pattern_
    - _Expected_Behavior: isLoopbackRedirect correctly identifies loopback URIs per RFC 8252_
    - _Preservation: This is a new helper method, doesn't affect existing validation_
    - _Requirements: 2.4_

  - [x] 3.5 Update redirect_uri validation logic
    - Modify `validateRedirectURI:forClient:error:` in OAuth2Handler.m
    - For loopback redirects (http://127.0.0.1:*, http://[::1]:*, http://localhost:*):
      - Allow if client's redirect_uris contains loopback pattern with wildcard port
      - Allow exact match
      - Support port wildcard matching (http://127.0.0.1:8080 matches http://127.0.0.1:*)
    - For non-loopback HTTP: Maintain existing strict validation (reject)
    - For HTTPS: Validate against client's redirect_uris list (exact match or pattern match)
    - Preserve existing validation logic for registered clients
    - _Bug_Condition: isBugCondition(input) where redirect_uri is loopback or in client_metadata.redirect_uris_
    - _Expected_Behavior: validateRedirectURI allows loopback redirects and client_metadata redirect_uris per ATProto spec_
    - _Preservation: Registered clients' redirect_uri validation unchanged (database path preserved)_
    - _Requirements: 2.4_

  - [x] 3.6 Add OPTIONS handlers for CORS preflight
    - In `registerRoutesWithServer:` in OAuth2Handler.m, add OPTIONS handlers:
      - /oauth/authorize - Return 204 with CORS headers (Access-Control-Allow-Origin, Access-Control-Allow-Methods, Access-Control-Allow-Headers)
      - /oauth/token - Return 204 with CORS headers
      - /oauth/par - Return 204 with CORS headers
      - /oauth/revoke - Return 204 with CORS headers
    - Use existing CORS header patterns from GET/POST handlers
    - Set Access-Control-Allow-Methods to match endpoint methods (GET, POST, OPTIONS)
    - Set Access-Control-Allow-Headers to include common OAuth headers (Authorization, Content-Type, DPoP, DPoP-Nonce)
    - _Bug_Condition: Not directly related to bug condition, but required for ATProto client compatibility_
    - _Expected_Behavior: OPTIONS requests return 204 with proper CORS headers_
    - _Preservation: OPTIONS handlers are new, don't affect existing GET/POST handlers_
    - _Requirements: 2.5 (implied by ATProto OAuth spec CORS requirements)_

  - [x] 3.7 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - ATProto Client Authorization Succeeds
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1: `./build/tests/AllTests --gtest_filter="OAuth2ATProtoClientTests.*"`
    - **EXPECTED OUTCOME**: All 4 test cases PASS (confirms bug is fixed):
      - testBskyAppAuthorizationWithClientMetadata - bsky.app authorization succeeds
      - testWitchskyAppAuthorizationWithClientMetadata - witchsky.app authorization succeeds
      - testNativeAppWithIPv4LoopbackRedirect - Loopback redirect_uri validation succeeds
      - testNativeAppWithIPv6LoopbackRedirect - IPv6 loopback redirect_uri validation succeeds
    - Document test results and any issues found
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 3.8 Verify preservation tests still pass
    - **Property 2: Preservation** - Registered Client Behavior Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2: `./build/tests/AllTests --gtest_filter="OAuth2PreservationTests.*"`
    - **EXPECTED OUTCOME**: All 7 property tests PASS (confirms no regressions):
      - testProperty_RegisteredClientAuthorizationSucceeds - Registered clients authenticate successfully
      - testProperty_PKCEValidationPreserved - PKCE validation works identically
      - testProperty_CSRFProtectionPreserved - CSRF protection works identically
      - testProperty_RedirectURIValidationPreserved - Redirect URI validation works identically
      - testProperty_ClientSecretValidationPreserved - Client secret validation works identically
      - testProperty_OAuthMetadataEndpointsPreserved - OAuth metadata endpoints work identically
      - testProperty_MultipleRegisteredClientsCoexist - Multiple clients coexist without interference
    - Confirm all tests still pass after fix (no regressions)
    - Document test results and any issues found
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

  - [x] 3.9 Run client metadata validation unit tests
    - **Validates: Requirements 2.2, 2.3**
    - Run unit tests for validateClientMetadata method: `./build/tests/AllTests --gtest_filter="OAuth2ClientMetadataValidationTests.*"`
    - **EXPECTED OUTCOME**: All 13 unit tests PASS:
      - testValidClientMetadataWithAllFields - Valid metadata with all fields accepted
      - testValidClientMetadataWithMinimalFields - Valid minimal metadata accepted
      - testMissingClientID - Missing client_id rejected
      - testClientIDNotHTTPS - Non-HTTPS client_id rejected
      - testClientIDInvalidURL - Invalid client_id URL rejected
      - testMissingRedirectURIs - Missing redirect_uris rejected
      - testEmptyRedirectURIsArray - Empty redirect_uris array rejected
      - testInvalidRedirectURI - Invalid redirect_uri rejected
      - testMultipleValidRedirectURIs - Multiple valid redirect_uris accepted
      - testGrantTypesAsArray - grant_types array converted to string
      - testGrantTypesAsString - grant_types string accepted
      - testNullMetadata - Null metadata rejected
      - testInvalidMetadataType - Invalid metadata type rejected
    - Document test results and any issues found
    - _Requirements: 2.2, 2.3_

- [ ] 4. Integration testing on live PDS

  **Remote VM Access**: The production PDS runs on the VM at `crimson-comet.exe.xyz`. Execute commands on the remote VM using SSH:
  ```bash
  ssh crimson-comet.exe.xyz "<command>"
  ```
  
  **Common Remote Commands**:
  - View PDS logs: `ssh crimson-comet.exe.xyz "docker compose logs -f pds"`
  - Query database: `ssh crimson-comet.exe.xyz "docker exec nspds sqlite3 /data/pds.db 'SELECT client_id FROM oauth_clients;'"`
  - Restart PDS: `ssh crimson-comet.exe.xyz "cd /home/exedev/objpds/docker/pds && docker compose restart pds"`
  - Check container status: `ssh crimson-comet.exe.xyz "docker ps"`

  - [ ] 4.1 Test bsky.app OAuth flow on pds.garazyk.xyz
    - **Goal**: Verify bsky.app can authenticate against the production PDS
    - **Prerequisites**: 
      - PDS deployed to pds.garazyk.xyz with updated OAuth2Handler
      - PDS accessible via HTTPS
      - Test account available on the PDS
    - **Test Steps**:
      1. Navigate to bsky.app in browser
      2. Attempt to add account with PDS URL: https://pds.garazyk.xyz
      3. Observe OAuth authorization flow (should redirect to PDS)
      4. Verify authorization request includes client_metadata parameter
      5. Complete authorization (sign in if needed)
      6. Verify redirect back to bsky.app with authorization code
      7. Verify token exchange succeeds (check browser network tab)
      8. Verify authenticated API calls work (timeline loads, can post, etc.)
    - **Expected Results**:
      - No "unauthorized_client" error
      - Authorization succeeds without pre-registering bsky.app in database
      - Full OAuth flow completes successfully
      - User can interact with PDS through bsky.app
    - **Troubleshooting**:
      - Check PDS logs: `ssh crimson-comet.exe.xyz "docker compose logs -f pds"`
      - Check browser console for errors
      - Verify CORS headers in network tab
    - Document any issues or unexpected behavior
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [ ] 4.2 Test witchsky.app OAuth flow on pds.garazyk.xyz
    - **Goal**: Verify witchsky.app can authenticate against the production PDS
    - **Prerequisites**: Same as 4.1
    - **Test Steps**:
      1. Navigate to witchsky.app in browser
      2. Attempt to add account with PDS URL: https://pds.garazyk.xyz
      3. Observe OAuth authorization flow
      4. Complete authorization
      5. Verify redirect back to witchsky.app with authorization code
      6. Verify token exchange succeeds
      7. Verify authenticated API calls work
    - **Expected Results**: Same as 4.1
    - **Troubleshooting**: Same as 4.1
    - Document any issues or unexpected behavior
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [ ] 4.3 Test native app with loopback redirect on pds.garazyk.xyz
    - **Goal**: Verify native apps using loopback redirects can authenticate
    - **Prerequisites**: 
      - Test script or native app that can initiate OAuth flow
      - Local HTTP server listening on loopback address (e.g., http://127.0.0.1:8080)
    - **Test Steps**:
      1. Create test OAuth client with loopback redirect_uri in client_metadata
      2. Initiate authorization request to https://pds.garazyk.xyz/oauth/authorize
      3. Include client_metadata with redirect_uris: ["http://127.0.0.1:8080/callback"]
      4. Complete authorization in browser
      5. Verify redirect to http://127.0.0.1:8080/callback with authorization code
      6. Exchange authorization code for access token
      7. Verify authenticated API calls work
    - **Expected Results**:
      - Loopback redirect_uri accepted (no "Invalid redirect_uri" error)
      - Authorization code delivered to local server
      - Token exchange succeeds
      - Access token works for API calls
    - **Test Script Example**:
      ```bash
      # Start local server
      python3 -m http.server 8080 --bind 127.0.0.1 &
      
      # Construct authorization URL with client_metadata
      CLIENT_METADATA='{"client_id":"https://example.com/app","redirect_uris":["http://127.0.0.1:8080/callback"]}'
      AUTH_URL="https://pds.garazyk.xyz/oauth/authorize?client_id=https://example.com/app&redirect_uri=http://127.0.0.1:8080/callback&response_type=code&state=test&code_challenge=test&code_challenge_method=S256&scope=atproto&client_metadata=$(echo -n "$CLIENT_METADATA" | jq -sRr @uri)"
      
      # Open in browser
      open "$AUTH_URL"
      ```
    - Document any issues or unexpected behavior
    - _Requirements: 2.4_

  - [ ] 4.4 Verify existing registered clients still work on pds.garazyk.xyz
    - **Goal**: Ensure backward compatibility - registered clients unaffected by changes
    - **Prerequisites**: 
      - At least one OAuth client registered in production database
      - If none exist, register a test client: `ssh crimson-comet.exe.xyz "docker exec nspds kaszlak oauth register-client --client-id test-client --redirect-uri https://example.com/callback"`
    - **Test Steps**:
      1. Query database to list registered clients: `ssh crimson-comet.exe.xyz "docker exec nspds sqlite3 /data/pds.db 'SELECT client_id FROM oauth_clients;'"`
      2. For each registered client, test full OAuth flow:
         - Initiate authorization with registered client_id
         - Complete authorization
         - Exchange code for token
         - Verify token works
      3. Verify PKCE validation still works (code_challenge required)
      4. Verify redirect_uri validation still works (must match registered URIs)
      5. Verify client_secret validation still works (if confidential client)
    - **Expected Results**:
      - All registered clients work exactly as before
      - No regressions in security validations
      - No changes to existing client behavior
    - Document any issues or unexpected behavior
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

  - [x] 4.5 Test CORS preflight requests on pds.garazyk.xyz
    - **Goal**: Verify OPTIONS handlers work correctly for browser-based OAuth flows
    - **Test Steps**:  - [ ] 4.5 Test CORS preflight requests on pds.garazyk.xyz
    - **Goal**: Verify OPTIONS handlers work correctly for browser-based OAuth flows
    - **Test Steps**:
      1. Send OPTIONS request to https://pds.garazyk.xyz/oauth/authorize
         ```bash
         curl -X OPTIONS https://pds.garazyk.xyz/oauth/authorize -i
         ```
      2. Verify response:
         - Status: 204 No Content
         - Header: Access-Control-Allow-Origin: *
         - Header: Access-Control-Allow-Methods: GET, POST, OPTIONS
         - Header: Access-Control-Allow-Headers: Authorization, Content-Type, DPoP, DPoP-Nonce
         - Header: Access-Control-Max-Age: 86400
      3. Repeat for other OAuth endpoints:
         - https://pds.garazyk.xyz/oauth/token
         - https://pds.garazyk.xyz/oauth/par
         - https://pds.garazyk.xyz/oauth/revoke
      4. Test browser preflight by initiating OAuth flow from different origin
    - **Expected Results**:
      - All OPTIONS requests return 204 with correct CORS headers
      - Browser preflight requests succeed
      - No CORS errors in browser console during OAuth flow
    - Document any issues or unexpected behavior
    - _Requirements: 2.5 (implied)_

- [ ] 5. Checkpoint - Ensure all tests pass and fix is complete
  - **Goal**: Final verification that the bug is fixed and no regressions introduced
  - **Test Execution**:
    1. Build all targets: `xcodebuild -scheme AllTests build`
    2. Run full test suite: `./build/tests/AllTests`
    3. Verify 0 failures in output
    4. Run bug condition exploration test specifically: `./build/tests/AllTests --gtest_filter="OAuth2ATProtoClientTests.*"`
    5. Run preservation property tests specifically: `./build/tests/AllTests --gtest_filter="OAuth2PreservationTests.*"`
    6. Run client metadata validation tests: `./build/tests/AllTests --gtest_filter="OAuth2ClientMetadataValidationTests.*"`
  - **Integration Test Review**:
    - Review results from task 4.1 (bsky.app integration)
    - Review results from task 4.2 (witchsky.app integration)
    - Review results from task 4.3 (loopback redirect integration)
    - Review results from task 4.4 (registered client preservation)
    - Review results from task 4.5 (CORS preflight)
  - **Acceptance Criteria Verification**:
    - ✓ ATProto clients (bsky.app, witchsky.app) can authenticate without database registration
    - ✓ client_metadata parameter is extracted and validated
    - ✓ Loopback redirects (http://127.0.0.1:*, http://[::1]:*) are allowed per RFC 8252
    - ✓ OPTIONS handlers return correct CORS headers
    - ✓ Existing registered clients work identically (no regressions)
    - ✓ PKCE validation preserved
    - ✓ DPoP validation preserved
    - ✓ CSRF protection preserved
    - ✓ Token lifecycle operations preserved
  - **Documentation**:
    - Document any issues found and how they were resolved
    - Document any edge cases discovered during testing
    - Document any deviations from the original design
  - **User Consultation**:
    - Ask user if any questions or concerns arise
    - Confirm all acceptance criteria are met
    - Get approval to proceed with deployment (if applicable)
  - **Next Steps** (if all checks pass):
    - Consider this bugfix complete
    - Deploy to production (pds.garazyk.xyz) if not already deployed
    - Monitor production logs for any issues
    - Close related GitHub issues (if any)
