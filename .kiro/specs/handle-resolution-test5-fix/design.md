# Handle Resolution .well-known Endpoint Bugfix Design

## Overview

The PDS at pds.garazyk.xyz is missing the `/.well-known/atproto-did` route handler, causing handle resolution to fail with 404 errors. The route handler exists in `PDSCLIServeCommand.m` but is not registered in `PDSHttpServerBuilder.m`, which is used by the production Docker deployment. This fix will add a new method `registerWellKnownRoutesWithServer:` to PDSHttpServerBuilder that registers the `.well-known/atproto-did` endpoint, ensuring it's available in all deployment modes.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when a client requests `GET /.well-known/atproto-did` for a handle owned by the PDS
- **Property (P)**: The desired behavior when the bug condition holds - the endpoint should return 200 with the DID as plain text
- **Preservation**: Existing handle resolution behavior via DNS TXT records and other .well-known endpoints (OAuth, NodeInfo, did.json) that must remain unchanged
- **PDSHttpServerBuilder**: The class in `ATProtoPDS/Sources/Network/PDSHttpServerBuilder.m` that configures HTTP routes for production deployment
- **HandleResolver**: The class in `ATProtoPDS/Sources/Identity/HandleResolver.m` that attempts HTTPS resolution via `/.well-known/atproto-did` before falling back to DNS TXT
- **PDSServiceDatabases**: The database service that provides access to account data for DID lookup

## Bug Details

### Fault Condition

The bug manifests when a client (including HandleResolver) requests the `/.well-known/atproto-did` endpoint for a handle that exists in the PDS database. The PDSHttpServerBuilder does not register this route, causing the HTTP server to return 404 with the message "No handler for GET /.well-known/atproto-did".

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type HttpRequest
  OUTPUT: boolean
  
  RETURN input.method == "GET"
         AND input.path == "/.well-known/atproto-did"
         AND input.query["handle"] IS NOT NULL
         AND accountExistsForHandle(input.query["handle"])
         AND routeHandlerNotRegistered("/.well-known/atproto-did")
END FUNCTION
```

### Examples

- **Example 1**: Client requests `GET https://pds.garazyk.xyz/.well-known/atproto-did?handle=test5.garazyk.xyz`
  - Expected: 200 with body `did:plc:5rpam44qoj2eeisejtxmke7e`
  - Actual: 404 with `{"error":"Not Found","message":"No handler for GET /.well-known/atproto-did"}`

- **Example 2**: HandleResolver attempts to resolve `test5.garazyk.xyz`
  - Expected: HTTPS resolution succeeds, returns DID, no DNS fallback needed
  - Actual: HTTPS resolution fails with 404, falls back to DNS TXT (which also fails if not configured)

- **Example 3**: Client requests `GET https://pds.garazyk.xyz/.well-known/atproto-did?handle=nonexistent.garazyk.xyz`
  - Expected: 404 with appropriate error message (handle not found)
  - Actual: 404 with "No handler" message (route not registered)

- **Edge Case**: Client requests `GET https://pds.garazyk.xyz/.well-known/atproto-did` without handle parameter
  - Expected: 400 with error message "Missing handle parameter"

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- OAuth .well-known endpoints (`/.well-known/oauth-authorization-server`, `/.well-known/oauth-protected-resource`) must continue to work
- NodeInfo .well-known endpoint (`/.well-known/nodeinfo`) must continue to work
- Server DID document endpoint (`/.well-known/did.json`) in CLI mode must continue to work
- DNS TXT fallback in HandleResolver must continue to work when HTTPS resolution fails
- All other HTTP routes (XRPC, OAuth, Admin, Explore) must continue to work

**Scope:**
All HTTP requests that do NOT target `/.well-known/atproto-did` should be completely unaffected by this fix. This includes:
- All XRPC method calls
- OAuth authorization and token endpoints
- Admin UI and API endpoints
- Explore UI endpoints
- Other .well-known endpoints

## Hypothesized Root Cause

Based on the bug description and code analysis, the root cause is:

1. **Missing Route Registration**: The `PDSHttpServerBuilder.configureServer:error:` method does not call any method to register .well-known routes for handle resolution
   - OAuth2Handler registers its own .well-known routes in `registerRoutesWithServer:`
   - NodeInfoHandler registers its .well-known route in `registerRoutesWithServer:`
   - But there is no equivalent for the atproto-did endpoint

2. **CLI-Only Implementation**: The route handler exists in `PDSCLIServeCommand.m` (lines 268-300) but is only registered when using the CLI serve command
   - Production Docker deployment uses PDSHttpServerBuilder
   - CLI serve command directly calls `[httpServer addRoute:@"GET" path:@"/.well-known/atproto-did" ...]`

3. **Architectural Gap**: There is no dedicated handler class (like OAuth2Handler or NodeInfoHandler) for identity-related .well-known endpoints
   - The fix should follow the pattern of other handlers by creating a registration method in PDSHttpServerBuilder

## Correctness Properties

Property 1: Fault Condition - Handle Resolution Returns DID

_For any_ HTTP GET request to `/.well-known/atproto-did` with a valid handle parameter that exists in the PDS database, the fixed server SHALL return HTTP 200 with the account's DID as plain text in the response body.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Preservation - Other Endpoints Unchanged

_For any_ HTTP request that does NOT target `/.well-known/atproto-did`, the fixed server SHALL produce exactly the same response as the original server, preserving all existing functionality for XRPC methods, OAuth endpoints, Admin UI, Explore UI, and other .well-known endpoints.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `ATProtoPDS/Sources/Network/PDSHttpServerBuilder.m`

**Method**: Add new method `registerWellKnownRoutesWithServer:`

**Specific Changes**:
1. **Add Method Declaration**: Add method signature to PDSHttpServerBuilder.h (if needed for public API)

2. **Implement Route Registration Method**: Add new method after `registerNodeInfoRoutesWithServer:`
   ```objc
   - (void)registerWellKnownRoutesWithServer:(HttpServer *)server {
       // Register /.well-known/atproto-did endpoint for handle resolution
       // Implementation based on PDSCLIServeCommand.m lines 268-300
   }
   ```

3. **Call from configureServer**: Add call to new method in `configureServer:error:` after OAuth registration
   ```objc
   // Register .well-known routes (handle resolution)
   [self registerWellKnownRoutesWithServer:server];
   ```

4. **Implement Handler Logic**: The handler must:
   - Extract `handle` query parameter from request
   - Validate handle parameter is present and non-empty (return 400 if missing)
   - Check if handle is owned by this PDS using `config.availableUserDomains`
   - Return 404 if handle is not owned by this PDS
   - Look up DID for handle in database using `serviceDatabases`
   - Return 200 with DID as plain text if found
   - Return 404 if handle exists in domain but not in database

5. **Add Logging**: Add PDS_LOG_DEBUG statement after registration for consistency with other route registration methods

### Implementation Details

The handler implementation should closely follow the existing code in `PDSCLIServeCommand.m` but adapted for PDSHttpServerBuilder's architecture:

- Use `self.serviceDatabases` to access the database
- Use `self.configuration` or `[PDSConfiguration sharedConfiguration]` for config access
- Follow the same validation logic: check availableUserDomains, look up account by handle
- Return plain text response (not JSON) for successful DID resolution
- Return JSON error responses for error cases (consistent with other endpoints)

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior.

### Exploratory Fault Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Write integration tests that make HTTP requests to `/.well-known/atproto-did` with valid handles. Run these tests on the UNFIXED code to observe 404 failures and confirm the route is not registered.

**Test Cases**:
1. **Valid Handle Test**: Request `/.well-known/atproto-did?handle=test5.garazyk.xyz` (will fail with 404 on unfixed code)
2. **Missing Handle Test**: Request `/.well-known/atproto-did` without handle parameter (will fail with 404 "No handler" instead of 400 "Missing parameter")
3. **Non-Owned Handle Test**: Request `/.well-known/atproto-did?handle=external.example.com` (will fail with 404 "No handler" instead of 404 "Not owned")
4. **HandleResolver Integration Test**: Use HandleResolver to resolve a handle (will fail with 404 on unfixed code)

**Expected Counterexamples**:
- All requests return 404 with message "No handler for GET /.well-known/atproto-did"
- Possible causes: route not registered in PDSHttpServerBuilder, method not called from configureServer

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL request WHERE isBugCondition(request) DO
  response := handleWellKnownAtprotoDid_fixed(request)
  ASSERT response.statusCode == 200
  ASSERT response.body == expectedDID(request.query["handle"])
  ASSERT response.contentType == "text/plain"
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed server produces the same result as the original server.

**Pseudocode:**
```
FOR ALL request WHERE NOT isBugCondition(request) DO
  ASSERT handleRequest_original(request) = handleRequest_fixed(request)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for other endpoints, then write property-based tests capturing that behavior.

**Test Cases**:
1. **OAuth Endpoints Preservation**: Verify `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource` continue to work
2. **NodeInfo Preservation**: Verify `/.well-known/nodeinfo` continues to work
3. **XRPC Methods Preservation**: Verify XRPC methods continue to work (sample: `com.atproto.server.describeServer`)
4. **Admin UI Preservation**: Verify admin endpoints continue to work
5. **Explore UI Preservation**: Verify explore endpoints continue to work

### Unit Tests

- Test route registration: verify `registerWellKnownRoutesWithServer:` is called during server configuration
- Test handler with valid handle: verify 200 response with correct DID
- Test handler with missing handle parameter: verify 400 response
- Test handler with non-owned handle: verify 404 response
- Test handler with owned but non-existent handle: verify 404 response
- Test database lookup logic: verify correct account retrieval by handle

### Property-Based Tests

- Generate random valid handles owned by PDS and verify correct DID resolution
- Generate random invalid handles and verify appropriate error responses
- Generate random HTTP requests to other endpoints and verify unchanged behavior
- Test with various database states (empty, single account, multiple accounts)

### Integration Tests

- Test full handle resolution flow: create account, resolve handle via .well-known endpoint
- Test HandleResolver integration: verify HandleResolver successfully resolves handles via HTTPS
- Test production deployment scenario: verify Docker container serves .well-known endpoint
- Test interaction with DNS fallback: verify DNS is not attempted when HTTPS succeeds
