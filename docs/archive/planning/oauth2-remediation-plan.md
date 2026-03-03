# OAuth2 AT Protocol Spec Remediation Plan

Reference: [OAuth2 Spec Compliance Report](oauth2-spec-compliance-report)

---

## Phase 1: Interop Blockers (Critical)

These prevent any standard AT Protocol client from authenticating. Must be fixed first.

### 1.1 Dynamic Client Metadata Fetching
**Report ref**: Critical #1  
**Files**: `OAuth2Handler.m` (`validateClient:`)  
**Current**: Server checks database, then accepts inline `client_metadata` from PAR body. Never fetches from the `client_id` URL.  
**Plan**:
1. When `validateClient:` finds no database entry and no inline `client_metadata`, treat `client_id` as an HTTPS URL and fetch it with a hardened HTTP client (SSRF protection, redirect rejection, timeout ≤5s, response size cap ≤256KB).
2. Validate `Content-Type: application/json` and HTTP 200 (not 2xx or redirect).
3. Validate that the `client_id` field in the fetched JSON exactly matches the URL used to fetch it.
4. Run the fetched document through the existing `validateClientMetadata:` pipeline.
5. Cache validated metadata for a short TTL (≤10 minutes per spec recommendation) keyed by `client_id` URL. Use an in-memory `NSMutableDictionary` with TTL expiry on the serial auth queue.
6. Continue to accept inline `client_metadata` from PAR body as a fallback (some clients send it).
7. Add a `PDSOAuthClientMetadataFetcher` class that encapsulates the fetch + validation + cache logic, using `NSURLConnection` (for GNUstep compat, not `NSURLSession`).

**Tests**:
- Unit test: mock HTTP response → validate parsing, caching, TTL expiry
- Unit test: reject non-200, non-JSON, redirect, oversized responses
- Unit test: reject `client_id` mismatch between URL and JSON body
- Integration test: register a real client metadata URL, complete full OAuth flow

### 1.2 Scope Constants & `atproto` Scope Enforcement
**Report ref**: Moderate #7, #8  
**Files**: `OAuth2.m` (scope constants), `OAuth2.m:1256` (fallback scope), `OAuth2Handler.m` (PAR + authorize), `OAuthServerMetadata.m`  
**Current**: Defines custom scopes (`atproto:identify`, `atproto:signin`, etc.). Does not enforce `atproto` scope inclusion.  
**Plan**:
1. Add `OAuth2ScopeAtproto = @"atproto"` constant alongside the existing custom scopes (keep custom scopes for backwards compat but add the standard one).
2. Add `OAuth2ScopeTransitionGeneric = @"transition:generic"`, `OAuth2ScopeTransitionChatBsky = @"transition:chat.bsky"`, `OAuth2ScopeTransitionEmail = @"transition:email"`.
3. In PAR handler: validate that `scope` parameter includes `atproto`. Reject with `invalid_scope` if missing.
4. In `handleAuthorizationRequest:`: validate `atproto` scope is present.
5. In token response: ensure `scope` always includes `atproto`.
6. Change default fallback scope from `OAuth2ScopeIdentify` to `@"atproto"` at `OAuth2.m:1256`.
7. Add `transition:email` to `scopes_supported` in `OAuthServerMetadata.m`.

**Tests**:
- Unit test: PAR rejects request without `atproto` scope
- Unit test: token response always contains `atproto` in scope
- Unit test: custom scopes still accepted alongside `atproto`

### 1.3 PKCE Made Mandatory + Ban `plain` Method
**Report ref**: Critical #2, Moderate #10  
**Files**: `OAuth2.m:1192-1216` (token exchange), `OAuth2.m:1366-1379` (verifier check), `OAuth2Handler.m:1824-1832` (PAR)  
**Current**: PKCE skipped if client doesn't send `code_challenge`. `plain` method accepted.  
**Plan**:
1. In PAR handler: require `code_challenge` for **all** client types (remove the `isPublicClient` guard at line 1824). Require `code_challenge_method=S256`.
2. In `handleAuthorizationRequest:`: require `code_challenge` and `code_challenge_method`.
3. In `processAuthorizationCodeGrant:`: reject token request if stored `code_challenge` exists but `code_verifier` is missing. Also reject if no `code_challenge` was stored (means it was never provided — shouldn't happen after step 1, but defense in depth).
4. In `verifyCodeVerifier:challenge:method:`: remove the `plain` branch. Return `NO` for any method other than `S256`.
5. Add `code_challenge` reuse tracking: store SHA-256 of recent challenges in memory (ring buffer, 24h TTL). Reject duplicates. (Report ref: Moderate #9)

**Tests**:
- Unit test: PAR rejects request without `code_challenge`
- Unit test: PAR rejects `code_challenge_method=plain`
- Unit test: token exchange fails if `code_verifier` missing
- Unit test: duplicate `code_challenge` rejected within window

---

## Phase 2: DPoP Nonce Fixes (Critical)

These cause failures for any client making concurrent requests or following the spec strictly.

### 2.1 DPoP Nonce TTL: 10 Minutes → 5 Minutes
**Report ref**: Critical #3  
**Files**: `PDSNonceManager.m:45`  
**Plan**:
1. Change nonce expiration from `600` to `300` seconds.
2. Extract the TTL to a constant `kDPoPNonceTTLSeconds = 300`.

### 2.2 DPoP Nonces: One-Time Use → Reusable Until Expiry
**Report ref**: Critical #4  
**Files**: `PDSNonceManager.m:55-71`  
**Current**: `validateNonce:` removes the nonce after first use.  
**Plan**:
1. Change `validateNonce:` to check expiry without removing the nonce. A nonce is valid as long as it hasn't expired.
2. Implement nonce rotation: `PDSNonceManager` maintains a "current" nonce and an "previous" nonce. `generateNonce` rotates: previous = current, current = new. `validateNonce:` accepts either current or previous (this gives clients a grace window during rotation).
3. Add a rotation timer: auto-rotate every ~2.5 minutes (half the 5-minute TTL), so the previous nonce is still valid for ~2.5 minutes after rotation.
4. On every response that involves DPoP, include the current nonce in the `DPoP-Nonce` header (report ref: Low #14).

**Tests**:
- Unit test: same nonce valid for multiple validations
- Unit test: nonce expires after 5 minutes
- Unit test: previous nonce accepted during grace period
- Unit test: nonce older than one rotation cycle rejected

### 2.3 `DPoP-Nonce` Header on Token Responses
**Report ref**: Low #14  
**Files**: `OAuth2Handler.m` (token endpoint handler)  
**Plan**:
1. After successful token response construction (line ~1632), call `attachDPoPNonceToResponseIfMissing:` to set `DPoP-Nonce`.
2. Also attach on error responses from token endpoint.
3. Also attach on all PDS resource server responses (XRPC endpoints) that use DPoP auth.

---

## Phase 3: Confidential Client Auth (Critical)

### 3.1 JWT Bearer Client Assertion Verification
**Report ref**: Critical #5, Low #16  
**Files**: `OAuth2Handler.m:1763-1780` (PAR), `OAuth2Handler.m:1505-1590` (token endpoint)  
**Current**: PAR checks `client_secret` from form body. Spec forbids `client_secret` entirely.  
**Plan**:
1. Remove `client_secret` validation path from PAR and token handlers entirely.
2. For confidential clients (`token_endpoint_auth_method=private_key_jwt`):
   - Extract `client_assertion_type` and `client_assertion` from request body.
   - Validate `client_assertion_type` is `urn:ietf:params:oauth:client-assertion-type:jwt-bearer`.
   - Parse the `client_assertion` JWT.
   - Verify signature against the client's public key from `jwks` in client metadata (or fetched from `jwks_uri`).
   - Validate JWT claims: `iss` = `client_id`, `sub` = `client_id`, `aud` = token endpoint URL, `exp` not expired, `iat` recent, `jti` unique.
3. For public clients (`token_endpoint_auth_method=none`): no client authentication beyond `client_id` matching.
4. Enforce client assertion on **all** token requests (initial + refresh) for confidential clients.
5. Add `PDSOAuthClientAssertionVerifier` class encapsulating JWT assertion parsing, signature verification, and claim validation.

**Tests**:
- Unit test: valid JWT assertion accepted
- Unit test: wrong signature rejected
- Unit test: expired assertion rejected
- Unit test: `aud` mismatch rejected
- Unit test: `jti` replay rejected
- Unit test: public client with assertion rejected
- Unit test: confidential client without assertion rejected
- Integration test: full flow with confidential client

---

## Phase 4: Metadata & Format Fixes (Moderate)

### 4.1 Protected Resource Metadata Format
**Report ref**: Moderate #6  
**Files**: `OAuth2Handler.m:966-977`  
**Current**: Returns `authorization_servers` as array of objects.  
**Plan**:
1. Change to flat array of URL strings per `draft-ietf-oauth-resource-metadata`:
   ```objc
   @{
     @"resource": issuer,
     @"authorization_servers": @[ issuer ],
     @"scopes_supported": @[ @"atproto", @"transition:generic", @"transition:chat.bsky" ],
     @"bearer_methods_supported": @[ @"header" ],
     @"resource_documentation": @"https://atproto.com/specs/oauth"
   }
   ```
2. Remove `protected_resources` nested object and `access_token_types_supported`.

**Tests**:
- Unit test: validate response JSON structure matches spec

### 4.2 JWT Signing Algorithm Audit
**Report ref**: Low #17  
**Files**: `OAuth2.m:1004,1023`  
**Current**: `JWTMinter.signingAlgorithm = @"ES256K"` (secp256k1).  
**Plan**:
1. Investigate whether `ES256K` is intentional for AT Protocol's secp256k1 identity keys vs. OAuth DPoP/token signing.
2. AT Protocol DPoP spec mandates `ES256` (P-256). The JWTMinter used for OAuth token signing should use `ES256`.
3. If `ES256K` is needed for other purposes (repo signing, PLC operations), create a separate key/minter for OAuth.
4. Decision: either switch OAuth JWTMinter to `ES256` with a P-256 key, or confirm that downstream consumers accept `ES256K` tokens.

### 4.3 Add `Cache-Control` to Metadata Endpoints
**Report ref**: Low #15  
**Files**: `OAuth2Handler.m:948-951, 979-981`  
**Plan**:
1. Add `Cache-Control: max-age=3600` to authorization server metadata and protected resource metadata responses.
2. Add `Cache-Control: max-age=3600` to JWKS endpoint.

---

## Phase 5: Robustness & Security Hardening (Moderate/Low)

### 5.1 Authorization Code Replay Protection
**Report ref**: Moderate #11  
**Files**: `OAuth2.m:1158-1218`  
**Plan**:
1. Use `dispatch_sync` on `authorizationQueue` for the entire code lookup + removal + token issuance sequence to prevent TOCTOU races.
2. If a code is presented that was already consumed, revoke all sessions created from that code (spec requirement).
3. Track consumed codes with their associated `session_id` in a short-lived map (10 min TTL matching code lifetime).

### 5.2 Session Persistence
**Report ref**: Moderate #12  
**Files**: `OAuth2Server` (`activeSessions` dictionary)  
**Plan**:
1. Create an `oauth_sessions` SQLite table: `session_id TEXT PRIMARY KEY, did TEXT, handle TEXT, scope TEXT, access_token_hash BLOB, refresh_token_hash BLOB, dpop_jkt TEXT, created_at TEXT, expires_at TEXT, refresh_expires_at TEXT`.
2. Store hashes (SHA-256) of tokens, not plaintext.
3. On token exchange/refresh: insert/update rows.
4. On startup: load valid sessions from database.
5. On revoke: delete row.
6. Periodic cleanup of expired sessions.

### 5.3 `code_challenge` Reuse Prevention
**Report ref**: Moderate #9  
**Files**: `OAuth2.m` or new utility class  
**Plan**:
1. Maintain an in-memory set of SHA-256 hashes of `code_challenge` values seen in the last 24 hours.
2. On PAR / authorization request: hash the `code_challenge`, check against the set, reject if duplicate.
3. Periodic cleanup of entries older than 24 hours.
4. Cap the set size (e.g., 100K entries) to prevent memory exhaustion.

---

## Implementation Order

| Step | Phase | Item | Effort | Impact |
|------|-------|------|--------|--------|
| 1 | 1.3 | PKCE mandatory + ban `plain` | Small | Closes security gap |
| 2 | 2.1 | Nonce TTL 10m → 5m | Trivial | Spec compliance |
| 3 | 2.2 | Nonces reusable until expiry | Medium | Fixes concurrent requests |
| 4 | 1.2 | Scope constants + `atproto` enforcement | Small | Interop |
| 5 | 4.1 | Protected resource metadata format | Small | Interop |
| 6 | 2.3 | `DPoP-Nonce` on all DPoP responses | Small | Client compat |
| 7 | 1.1 | Dynamic client metadata fetching | Large | Third-party clients |
| 8 | 3.1 | JWT bearer assertion (confidential clients) | Large | Confidential client auth |
| 9 | 4.2 | JWT signing algorithm audit | Medium | Token verification |
| 10 | 5.1 | Auth code replay protection | Medium | Security |
| 11 | 4.3 | Cache-Control headers | Trivial | Correctness |
| 12 | 5.3 | `code_challenge` reuse prevention | Small | Security |
| 13 | 5.2 | Session persistence | Large | Reliability |

Steps 1–6 are quick wins that can ship together. Steps 7–8 are the two large pieces of new functionality. Step 13 (session persistence) is important for production reliability but not a spec compliance issue.
