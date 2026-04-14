# Bluesky Client OAuth/CORS Fix Design

## Overview

The PDS OAuth implementation currently requires clients to be pre-registered in the `oauth_clients` database table, which prevents standard ATProto clients (bsky.app, witchsky.app) from authenticating. The ATProto OAuth specification uses a different approach where clients provide metadata dynamically via the `client_metadata` parameter during authorization, eliminating the need for pre-registration.

This design updates the OAuth implementation to conform to the ATProto OAuth specification by:
- Supporting dynamic client metadata validation instead of database pre-registration
- Implementing proper redirect_uri validation per ATProto security requirements
- Adding OPTIONS handlers for OAuth endpoints to support CORS preflight requests
- Maintaining backward compatibility with existing registered clients

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when ATProto clients attempt OAuth authorization without being pre-registered in the database
- **Property (P)**: The desired behavior - ATProto clients should be able to authenticate by providing valid client_metadata
- **Preservation**: Existing registered clients and security features (PKCE, DPoP, CSRF) must continue to work unchanged
- **client_metadata**: JSON object containing client information (client_id, redirect_uris, client_name, etc.) provided during authorization per ATProto OAuth spec
- **Loopback Redirect**: Special redirect_uri pattern (http://127.0.0.1:* or http://[::1]:*) allowed for native/local clients per RFC 8252
- **Client ID URL**: ATProto requires client_id to be a valid HTTPS URL that serves client metadata at that location

## Bug Details

### Fault Condition

The bug manifests when an ATProto client attempts OAuth authorization without being pre-registered in the `oauth_clients` database table. The `validateClient` method in OAuth2Handler.m queries the database and rejects unknown clients with "unauthorized_client" error.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type OAuth2AuthorizationRequest
  OUTPUT: boolean
  
  RETURN input.clientID NOT IN database.oauth_clients
         AND input.clientID is valid HTTPS URL
         AND input.client_metadata is provided
         AND input.client_metadata contains valid ATProto client metadata
END FUNCTION
```

### Examples

- **bsky.app authorization**: Client provides `client_id=https://bsky.app` with `client_metadata` containing redirect_uris, but PDS returns "unauthorized_client" because bsky.app is not in the database
- **witchsky.app authorization**: Client provides `client_id=https://witchsky.app` with valid metadata, but PDS rejects it due to database lookup failure
- **Native app with loopback**: Client provides `client_id=https://example.com/app` with `redirect_uri=http://127.0.0.1:8080/callback`, but PDS rejects the HTTP redirect_uri even though it's a valid loopback per RFC 8252
- **Registered client**: Client exists in `oauth_clients` table - should continue to work exactly as before (preservation requirement)

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Existing registered OAuth clients in the database must continue to work exactly as before
- PKCE validation (code_challenge required, S256 method, code_verifier validation) must remain unchanged
- DPoP proof validation for token requests must remain unchanged
- CSRF protection (state parameter validation) must remain unchanged
- Token lifecycle operations (issuance, refresh, revocation) must remain unchanged
- Security validations (nonce, replay protection, signature verification) must remain unchanged

**Scope:**
All inputs that involve pre-registered clients (clients in `oauth_clients` table) should be completely unaffected by this fix. This includes:
- First-party clients registered by the PDS administrator
- Test clients used in the test suite
- Any client with a database entry in `oauth_clients`

## Hypothesized Root Cause

Based on the bug description and code analysis, the root causes are:

1. **Database-Only Client Validation**: The `validateClient` method in OAuth2Handler.m (line 97) only checks the database, with no fallback to dynamic client_metadata validation as required by ATProto OAuth spec

2. **Missing client_metadata Parameter Handling**: The authorization request parsing does not extract or validate the `client_metadata` parameter that ATProto clients provide

3. **Overly Strict redirect_uri Validation**: The `validateRedirectURI` method (line 115) requires exact match against database-registered URIs, but ATProto allows:
   - Loopback redirects (http://127.0.0.1:* or http://[::1]:*) for native apps per RFC 8252
   - Dynamic redirect_uris provided in client_metadata

4. **Missing OPTIONS Handlers**: OAuth endpoints (/oauth/authorize, /oauth/token, /oauth/par) lack OPTIONS handlers for CORS preflight requests, though CORS headers are already set on responses

5. **Client ID Format Validation**: No validation that client_id is a valid HTTPS URL as required by ATProto spec

## Correctness Properties

Property 1: Fault Condition - ATProto Client Authorization

_For any_ OAuth authorization request where the client_id is not in the database but provides valid client_metadata conforming to the ATProto OAuth specification, the fixed OAuth2Handler SHALL validate the client using the provided metadata and proceed with authorization, allowing standard ATProto clients to authenticate.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

Property 2: Preservation - Registered Client Behavior

_For any_ OAuth authorization request where the client_id exists in the oauth_clients database table, the fixed OAuth2Handler SHALL produce exactly the same validation and authorization behavior as the original implementation, preserving all existing client functionality and security checks.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `Garazyk/Sources/Auth/OAuth2Handler.m`

**Function**: `validateClient:error:`

**Specific Changes**:
1. **Add client_metadata Parameter Extraction**: In `handleAuthorizeRequest`, extract and parse the `client_metadata` parameter from query params
   - Parse JSON string to NSDictionary
   - Validate required fields per ATProto spec

2. **Implement Dual-Path Client Validation**: Modify `validateClient:error:` to support both database and metadata validation
   - First attempt: Query database (existing path)
   - If not found: Validate client_metadata if provided
   - Return unified client dictionary format

3. **Add Client Metadata Validation**: Create new method `validateClientMetadata:error:`
   - Validate client_id is HTTPS URL (required by ATProto)
   - Validate redirect_uris array is present and non-empty
   - Validate client_name is present (optional but recommended)
   - Validate grant_types if provided
   - Validate scope if provided
   - Return normalized client dictionary matching database format

4. **Update redirect_uri Validation**: Modify `validateRedirectURI:forClient:error:` to support ATProto patterns
   - Allow loopback redirects (http://127.0.0.1:* or http://[::1]:*) per RFC 8252
   - For non-loopback HTTP, maintain existing strict validation
   - For HTTPS, validate against client's redirect_uris list
   - Support wildcard port matching for loopback (http://127.0.0.1:8080 matches http://127.0.0.1:*)

5. **Add OPTIONS Handlers**: In `registerRoutesWithServer:`, add OPTIONS handlers for OAuth endpoints
   - /oauth/authorize - OPTIONS handler with CORS headers
   - /oauth/token - OPTIONS handler with CORS headers
   - /oauth/par - OPTIONS handler with CORS headers
   - /oauth/revoke - OPTIONS handler with CORS headers

**File**: `Garazyk/Sources/Auth/OAuth2Handler.h`

**Specific Changes**:
1. **Add client_metadata Property**: Add `client_metadata` property to OAuth2Handler interface for storing parsed metadata

**File**: `Garazyk/Sources/Auth/OAuth2.h`

**Specific Changes**:
1. **Add client_metadata Property**: Add `@property (nonatomic, copy, nullable) NSDictionary *clientMetadata;` to OAuth2AuthorizationRequest interface

### Implementation Details

**Client Metadata Validation Logic:**
```objc
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata error:(NSError **)error {
    // Validate client_id is HTTPS URL
    NSString *clientID = metadata[@"client_id"];
    if (!clientID || ![clientID hasPrefix:@"https://"]) {
        *error = [NSError errorWithDomain:@"OAuth2" code:400 
            userInfo:@{NSLocalizedDescriptionKey: @"client_id must be HTTPS URL"}];
        return nil;
    }
    
    // Validate redirect_uris
    NSArray *redirectURIs = metadata[@"redirect_uris"];
    if (!redirectURIs || ![redirectURIs isKindOfClass:[NSArray class]] || redirectURIs.count == 0) {
        *error = [NSError errorWithDomain:@"OAuth2" code:400 
            userInfo:@{NSLocalizedDescriptionKey: @"redirect_uris required"}];
        return nil;
    }
    
    // Return normalized client dictionary
    return @{
        @"client_id": clientID,
        @"redirect_uris": redirectURIs,
        @"client_name": metadata[@"client_name"] ?: clientID,
        @"grant_types": metadata[@"grant_types"] ?: @"authorization_code refresh_token",
        @"scope": metadata[@"scope"] ?: @"atproto"
    };
}
```

**Loopback Redirect Validation:**
```objc
- (BOOL)isLoopbackRedirect:(NSString *)redirectURI {
    NSURL *url = [NSURL URLWithString:redirectURI];
    if (![url.scheme isEqualToString:@"http"]) return NO;
    
    NSString *host = url.host;
    return [host isEqualToString:@"127.0.0.1"] || 
           [host isEqualToString:@"localhost"] ||
           [host isEqualToString:@"[::1]"];
}
```

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior.

### Exploratory Fault Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Write tests that simulate ATProto client authorization requests with client_metadata but no database registration. Run these tests on the UNFIXED code to observe failures and understand the root cause.

**Test Cases**:
1. **bsky.app Authorization Test**: Simulate authorization request with `client_id=https://bsky.app` and valid client_metadata (will fail on unfixed code with "unauthorized_client")
2. **Loopback Redirect Test**: Simulate authorization with `redirect_uri=http://127.0.0.1:8080/callback` (will fail on unfixed code with "Invalid redirect_uri")
3. **Missing client_metadata Test**: Simulate authorization without client_metadata and not in database (should fail with clear error)
4. **Invalid client_metadata Test**: Simulate authorization with malformed client_metadata (should fail with validation error)

**Expected Counterexamples**:
- validateClient returns nil because client_id not in database
- validateRedirectURI rejects loopback HTTP redirects
- No client_metadata parameter extraction occurs

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := handleAuthorizeRequest_fixed(input)
  ASSERT result.statusCode != 400
  ASSERT result.error != "unauthorized_client"
  ASSERT authorizationCodeGenerated(result)
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT handleAuthorizeRequest_original(input) = handleAuthorizeRequest_fixed(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all registered clients

**Test Plan**: Observe behavior on UNFIXED code first for registered clients, then write property-based tests capturing that behavior.

**Test Cases**:
1. **Registered Client Preservation**: Verify that clients in oauth_clients table continue to work identically
2. **PKCE Preservation**: Verify that PKCE validation continues to work for all clients
3. **DPoP Preservation**: Verify that DPoP proof validation continues to work
4. **Token Lifecycle Preservation**: Verify that token issuance, refresh, and revocation continue to work

### Unit Tests

- Test client_metadata parsing and validation with valid and invalid inputs
- Test loopback redirect_uri validation with various formats (127.0.0.1, localhost, [::1])
- Test HTTPS redirect_uri validation against client_metadata redirect_uris list
- Test dual-path client validation (database vs metadata)
- Test OPTIONS handlers return correct CORS headers

### Property-Based Tests

- Generate random client_metadata objects and verify validation logic handles all cases
- Generate random redirect_uris and verify loopback detection works correctly
- Generate random registered clients and verify preservation of existing behavior
- Test that all security validations (PKCE, DPoP, CSRF) continue to work across many scenarios

### Integration Tests

- Test full OAuth flow with bsky.app client_id and metadata
- Test full OAuth flow with witchsky.app client_id and metadata
- Test full OAuth flow with native app using loopback redirect
- Test that registered clients continue to work end-to-end
- Test CORS preflight requests to all OAuth endpoints
