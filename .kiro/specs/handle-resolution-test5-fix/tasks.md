# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Fault Condition** - Well-Known Endpoint Returns 404
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to concrete failing case(s) - requests to `/.well-known/atproto-did` with valid handles
  - Test that GET `/.well-known/atproto-did?handle=test5.garazyk.xyz` returns 404 with "No handler" message (from Fault Condition in design)
  - Test that requests for valid handles owned by the PDS return 404 instead of 200 with DID
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found to understand root cause (e.g., "GET /.well-known/atproto-did?handle=test5.garazyk.xyz returns 404 'No handler' instead of 200 'did:plc:5rpam44qoj2eeisejtxmke7e'")
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Other Endpoints Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs (requests to other endpoints)
  - Test OAuth .well-known endpoints: `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource` return expected responses
  - Test NodeInfo endpoint: `/.well-known/nodeinfo` returns expected response
  - Test XRPC methods: `com.atproto.server.describeServer` returns expected response
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3. Fix for missing .well-known/atproto-did route registration

  - [x] 3.1 Implement the fix in PDSHttpServerBuilder
    - Add new method `registerWellKnownRoutesWithServer:` to PDSHttpServerBuilder.m
    - Implement handler logic: extract handle parameter, validate it's owned by PDS, look up DID in database, return 200 with DID as plain text
    - Handle error cases: missing handle parameter (400), non-owned handle (404), handle not found in database (404)
    - Call `registerWellKnownRoutesWithServer:` from `configureServer:error:` after OAuth registration
    - Add PDS_LOG_DEBUG statement after registration for consistency
    - _Bug_Condition: isBugCondition(input) where input.method == "GET" AND input.path == "/.well-known/atproto-did" AND input.query["handle"] IS NOT NULL AND accountExistsForHandle(input.query["handle"]) AND routeHandlerNotRegistered("/.well-known/atproto-did")_
    - _Expected_Behavior: expectedBehavior(result) where result.statusCode == 200 AND result.body == expectedDID(input.query["handle"]) AND result.contentType == "text/plain"_
    - _Preservation: Preservation Requirements - OAuth endpoints, NodeInfo endpoint, XRPC methods, Admin UI, Explore UI, DNS fallback, rate limiting, SSRF protection, handle validation_
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Well-Known Endpoint Returns DID
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Other Endpoints Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
