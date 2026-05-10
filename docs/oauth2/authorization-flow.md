---
title: OAuth2 Authorization Flow
---

# OAuth2 Authorization Flow

This document describes the OAuth2 authorization code flow implementation in the PDS, including user authentication, consent, and authorization code generation.

## Overview

The PDS implements a three-phase OAuth2 authorization flow:

1. **PAR Phase**: Client pushes authorization parameters to the PDS, gets back a `request_uri`
2. **Sign-In Phase**: User authenticates with handle/password on the authorize page
3. **Consent Phase**: User reviews and approves the authorization request

Authorization requests use **Pushed Authorization Requests (PAR, RFC 9126)** — the client POSTs the full authorization request to `/oauth/par` and the browser is redirected to the authorize page with only `client_id` and `request_uri`. This prevents large authorization requests from being reflected through the browser URL.

## Sequence Diagram

```

┌─────────┐     ┌──────────┐     ┌───────────────┐     ┌────────────┐     ┌──────────┐
│  User   │     │  Client  │     │ OAuth2Handler │     │ OAuth2Server│     │ Database │
└────┬────┘     └────┬─────┘     └───────┬───────┘     └──────┬─────┘     └────┬─────┘
     │               │                   │                    │                │
     │ 1. GET /oauth/authorize           │                    │                │
     │               │                   │                    │                │
     │               │ client_id, redirect_uri,               │                │
     │               │ state, code_challenge, scope           │                │
     │               │──────────────────>│                    │                │
     │               │                   │                    │                │
     │               │                   │ validateClient()   │                │
     │               │                   │─────────────────────────────────────>│
     │               │                   │                    │                │
     │               │                   │ validateRedirectURI()              │
     │               │                   │─────────────────────────────────────>│
     │               │                   │                    │                │
     │               │                   │ PKCE check (public clients)        │
     │               │                   │                    │                │
     │ 2. authorize.html (with CSRF)     │                    │                │
     │<──────────────────────────────────│                    │                │
     │               │                   │                    │                │
     │ 3. POST /oauth/authorize/sign-in  │                    │                │
     │─────────────────────────────────>│                    │                │
     │               │                   │                    │                │
     │               │                   │ CSRF validation    │                │
     │               │                   │                    │                │
     │               │                   │ PDSAccountService.login()          │
     │               │                   │─────────────────────────────────────>│
     │               │                   │                    │                │
     │               │                   │ create session_token (5min expiry) │
     │               │                   │ store in sPendingConsents          │
     │               │                   │                    │                │
     │ {ok: true, did: "...", session_token: "..."}           │                │
     │<──────────────────────────────────│                    │                │
     │               │                   │                    │                │
     │ 4. User sees consent screen       │                    │                │
     │               │                   │                    │                │
     │ 5. POST /oauth/authorize/confirm  │                    │                │
     │─────────────────────────────────>│                    │                │
     │               │                   │                    │                │
     │               │                   │ validate session_token              │
     │               │                   │                    │                │
     │               │                   │ handleAuthorizationRequest()       │
     │               │                   │───────────────────>│                │
     │               │                   │                    │                │
     │               │                   │                    │ generate code │
     │               │                   │                    │ store code data
     │               │                   │                    │ (10min expiry)│
     │               │                   │                    │                │
     │               │                   │ authorization URL  │                │
     │               │                   │<───────────────────│                │
     │               │                   │                    │                │
     │ 302 redirect to redirect_uri?code=...&state=...       │                │
     │<──────────────────────────────────│                    │                │
     │               │                   │                    │                │
     │ 6. Client receives authorization code                  │                │
     │──────────────>│                   │                    │                │
     │               │                   │                    │                │
     │               │ POST /oauth/token (exchange code for token)            │
     │               │──────────────────>│                    │                │
```

## Endpoints

### 0. POST /oauth/par

Pushed Authorization Request (RFC 9126). Client sends the full authorization request to this endpoint instead of reflecting it through the browser.

**Request:**

```
POST /oauth/par
Content-Type: application/json (atcute library) or application/x-www-form-urlencoded

{
  "client_id": "http://127.0.0.1:8080/client-metadata.json",
  "redirect_uri": "http://127.0.0.1:8080/",
  "response_type": "code",
  "scope": "atproto transition:generic",
  "state": "...",
  "code_challenge": "...",
  "code_challenge_method": "S256",
  "response_mode": "fragment",
  "login_hint": "luna.test"
}
```

**Validation:**

1. Parses body as JSON (if starts with `{`) or form-url-encoded.
2. Extracts `client_id`, validates client via `validatedClientForClientID:`.
3. Validates redirect URI, response type, PKCE challenge.
4. Generates a UUID `request_uri` (urn:ietf:params:oauth:request_uri:<uuid>) and stores the request parameters mapped to it in memory (10-minute TTL).

**Response (201):**

```json
{
  "request_uri": "urn:ietf:params:oauth:request_uri:A57B4DF3-788A-5000-5B5C-A58BB6C1A6C9",
  "expires_in": 600
}
```

### 1. GET /oauth/authorize

Displays the authorization page with sign-in form.

**Request Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `client_id` | Yes | OAuth client identifier |
| `redirect_uri` | Yes | URI to redirect after authorization |
| `state` | Yes | CSRF protection token |
| `response_type` | Yes | Must be `code` |
| `scope` | No | Requested scopes (default: `atproto`) |
| `code_challenge` | Required for public clients | PKCE challenge |
| `code_challenge_method` | No | PKCE method (default: `S256`) |
| `nonce` | No | OIDC nonce |
| `login_hint` | No | Pre-filled handle |

**Validation Steps:**

1. **Client Validation** (`validateClient`):
   - Looks up `client_id` in `oauth_clients` table
   - Returns `unauthorized_client` error if not found

2. **Redirect URI Validation** (`validateRedirectURI`):
   - Exact match against client's registered URIs
   - HTTPS required in production
   - HTTP allowed for localhost in debug builds

3. **State Parameter**:
   - Required for CSRF protection
   - Must not be empty or whitespace

4. **PKCE Enforcement**:
   - Public clients (no `client_secret`) must provide `code_challenge`
   - Confidential clients may optionally use PKCE

**Response:**

- HTTP 200 with `authorize.html` template
- Sets `csrf_token` cookie (HttpOnly, SameSite=Strict)
- Template variables substituted with HTML escaping

### 2. POST /oauth/authorize/sign-in

Authenticates the user and creates a consent session.

**Request:**

```

POST /oauth/authorize/sign-in
Content-Type: application/x-www-form-urlencoded
X-CSRF-Token: <csrf_token from cookie>

handle=<user-handle>&password=<user-password>
```

**CSRF Validation:**
- `X-CSRF-Token` header must match `csrf_token` cookie
- Returns 403 with `Invalid CSRF token` on mismatch

**Authentication:**
- Calls `PDSAccountService.loginWithIdentifier:password:`
- Validates handle/password against stored credentials

**Success Response (200):**

```json
{
  "ok": true,
  "did": "did:plc:abc123...",
  "session_token": "uuid-session-token"
}
```

**Error Responses:**

| Status | Error |
|--------|-------|
| 403 | Invalid CSRF token |
| 400 | Missing handle or password |
| 401 | Invalid credentials |
| 500 | Authentication service unavailable |

**Session Token Storage:**

```objc
sPendingConsents[sessionToken] = @{
    @"did": result[@"did"],
    @"handle": handle,
    @"expires": [NSDate dateWithTimeIntervalSinceNow:300]  // 5 minutes
};
```

### 3. POST /oauth/authorize/confirm

Processes user consent decision and generates authorization code.

**Request:**

```

POST /oauth/authorize/confirm
Content-Type: application/x-www-form-urlencoded

client_id=<client_id>&
state=<state>&
scope=<scope>&
redirect_uri=<redirect_uri>&
response_type=<response_type>&
code_challenge=<code_challenge>&
code_challenge_method=<code_challenge_method>&
nonce=<nonce>&
login_hint=<login_hint>&
session_token=<session_token>&
decision=<allow|deny>
```

**Deny Flow:**

If `decision=deny`:
- Redirects to `redirect_uri?error=access_denied&error_description=User denied the authorization request&state=...`
- Returns 403 if no `redirect_uri` provided

**Allow Flow:**

1. Validates `session_token` exists in `sPendingConsents`
2. Checks token not expired (5-minute window)
3. Removes used token (single-use)
4. Calls `OAuth2Server.handleAuthorizationRequest`

**Authorization Code Generation:**

Code data stored in memory:

```objc
codeData = {
    @"client_id": request.clientID,
    @"redirect_uri": request.redirectURI,
    @"scope": request.scope,
    @"state": request.state,
    @"code_challenge": request.codeChallenge,
    @"code_challenge_method": request.codeChallengeMethod,
    @"nonce": request.nonce,
    @"login_hint_did": did,  // resolved from login_hint
    @"created_at": timestamp
};
```

**Success Response:**

HTTP 302 redirect to:
```

redirect_uri?code=<authorization-code>&state=<state>
```

**Error Responses:**

| Status | Error | Description |
|--------|-------|-------------|
| 403 | `access_denied` | Missing/expired session token |
| 400 | `invalid_request` | Authorization generation failed |

## Authorization Code Lifecycle

### Storage

- In-memory dictionary with thread-safe access via `dispatch_queue_t`
- Key: UUID authorization code
- Value: Code data dictionary

### Lifetime

- 10 minutes from creation
- Enforced during token exchange (`codeAge > 600`)

### Single Use

- Code removed immediately after successful token exchange
- Prevents replay attacks

## Request/Response Formats

### Authorization Request (Internal)

```objc
OAuth2AuthorizationRequest {
    clientID: NSString
    redirectURI: NSString
    responseType: NSString  // "code"
    scope: NSString
    state: NSString
    codeChallenge: NSString
    codeChallengeMethod: NSString  // "S256" or "plain"
    nonce: NSString
    loginHint: NSString
    dpopJWK: NSDictionary
}
```

### Authorization Code Data

```json
{
  "client_id": "app.example.com",
  "redirect_uri": "https://app.example.com/callback",
  "scope": "atproto",
  "state": "xyz123",
  "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
  "code_challenge_method": "S256",
  "login_hint_did": "did:plc:abc123",
  "created_at": 1708123456.789
}
```

### 4. POST /oauth/token

Exchanges an authorization code for DPoP-bound access and refresh tokens.

**Request (atcute library sends JSON):**

```
POST /oauth/token
Content-Type: application/json

{
  "grant_type": "authorization_code",
  "code": "<authorization-code>",
  "redirect_uri": "http://127.0.0.1:8080/",
  "code_verifier": "<pkce-verifier>",
  "client_id": "http://127.0.0.1:8080/client-metadata.json"
}
```

**Content-Type Handling:**

The server accepts both `application/json` and `application/x-www-form-urlencoded`:

```objc
if ([body hasPrefix:@"{"]) {
    params = [NSJSONSerialization JSONObjectWithData:request.body ...];
}
if (!params) {
    params = [self parseFormUrlEncodedString:body];
}
```

The atcute OAuth browser client (`@atcute/oauth-browser-client`) sends JSON. Clients sending form-url-encoded (RFC 6749 style) are also supported.

**Validation (in order):**

1. **Client validation**: Looks up `client_id` in database or fetches dynamically from URL.
2. **Client authentication**: Supports `none` (public clients), `client_secret_basic`, `client_secret_post`, and `private_key_jwt`. Public clients (like the E2E test client) need no secret — just an existing client record.
3. **DPoP proof validation**: Validates the `DPoP` HTTP header. Verifies JWK thumbprint, method/URL binding, nonce freshness. Returns `use_dpop_nonce` error if nonce is stale.
4. **Authorization code validation**: Checks the code exists in memory, isn't expired (10-minute TTL), matches `client_id` and `redirect_uri`.
5. **PKCE verification**: Computes `BASE64URL(SHA256(code_verifier))` and compares against stored `code_challenge` (constant-time).
6. **Token generation**: Issues a DPoP-bound access token (JWT) with `cnf.jkt` thumbprint, plus a refresh token.

**Success Response (200):**

```json
{
  "access_token": "dpop-bound-jwt...",
  "token_type": "DPoP",
  "expires_in": 7200,
  "refresh_token": "v2.refresh...",
  "scope": "atproto transition:generic",
  "sub": "did:plc:abc123..."
}
```

**Error Responses:**

| Status | Error | Description |
|--------|-------|-------------|
| 401 | `invalid_client` | Missing/invalid client_id or client auth |
| 400 | `invalid_grant` | Expired/used authorization code |
| 400 | `invalid_grant` | PKCE verifier mismatch |
| 503 | `server_error` | Client validation timeout |

## Dynamic Client Discovery

Clients with loopback URLs (127.0.0.1, localhost) or HTTPS URLs are discovered dynamically — the PDS fetches the `client_id` URL to retrieve `client-metadata.json`:

```objc
if ([clientID hasPrefix:@"https://"] || [self isLoopbackURL:clientID]) {
    [self fetchClientMetadataFromURL:clientID completion:...];
}
```

This is how clients like `http://127.0.0.1:8080/client-metadata.json` work without pre-registration.

## CSS Serving Architecture

The authorize page (`authorize.html`) uses shared CSS from the DesignSystem at `/css/shared/system.css`. This CSS is served via a dedicated route handler:

1. **Route**: `OAuth2Handler.m` registers `addHandlerForPath:@"/css/"` → `handleCSSRequest:response:`.
2. **Path resolution**: `sharedCSSPath` checks three locations:
   - `dataDirectory/Shared/DesignSystem/css` (runtime data dir)
   - `/usr/share/atprotopds/assets/css` (Docker install path)
   - CWD-based dev paths (fallback)
3. **Files served**: `system.css` (with `@import` of `tokens.css`, `reset.css`, `layout.css`, `components.css`, `utilities.css`).
4. **Content type**: `text/css; charset=utf-8`.

**Docker deployment**: CSS files are staged into `staging/css-shared/` by `stage-docker-binaries.sh` and copied to `/usr/share/atprotopds/assets/css` in `Dockerfile.local`.

## authorize.html Step Transition

The authorize page uses a two-step UI: sign-in (`#auth-step-signin`) then consent (`#auth-step-consent`).

**CSS visibility model:**

```css
.hidden { display: none !important; }
```

The consent step starts with `class="hidden"` so only the sign-in form is visible.

**JS transition (after successful sign-in):**

```javascript
// Correct — overrides !important by removing the class
document.getElementById('auth-step-signin').classList.add('hidden');
document.getElementById('auth-step-consent').classList.remove('hidden');
```

**Why style.display doesn't work:**

The `.hidden` class uses `display: none !important`. Setting `element.style.display = 'block'` does NOT override `!important`. The JS must use `classList.remove('hidden')` / `classList.add('hidden')`.

## Error Codes

| Error | HTTP Status | Description |
|-------|-------------|-------------|
| `invalid_request` | 400 | Missing required parameters |
| `unauthorized_client` | 400 | Unknown client_id |
| `access_denied` | 302/403 | User denied consent |
| `invalid_grant` | 400 | Invalid/expired authorization code |
| `unsupported_response_type` | 400 | Response type not "code" |
| `server_error` | 500 | Internal server error |

## Security Considerations

### CSRF Protection

1. **State Parameter**: Required on all authorization requests
2. **CSRF Token**: Cookie-to-header validation on sign-in
   - Cookie: HttpOnly, SameSite=Strict
   - Header: `X-CSRF-Token`

### PKCE (RFC 7636)

Required for public clients:
- Prevents authorization code interception
- `code_challenge` = `BASE64URL(SHA256(code_verifier))`
- Default method: `S256`

### Redirect URI Validation

- Exact match required (no wildcard patterns)
- HTTPS enforced in production
- HTTP allowed only for localhost in development

### Session Token Security

- UUID-based, single-use tokens
- 5-minute expiry window
- Stored in memory only (not persisted)
- Thread-safe access via synchronized blocks

### Authorization Code Security

- UUID-based (128-bit entropy)
- 10-minute lifetime
- Single use (deleted after exchange)
- Bound to client_id and redirect_uri

### DPoP Integration

Authorization codes can store DPoP JWK:
- Enables sender-constrained tokens
- Thumbprint bound to access token
- Verified during token exchange

## Implementation Files

| File | Purpose |
|------|---------|
| `Garazyk/Sources/Auth/OAuth2Handler.m` | HTTP endpoint handlers |
| `Garazyk/Sources/Auth/OAuth2.m` | Authorization server logic |
| `Garazyk/Sources/Auth/Assets/authorize.html` | Web UI template |

## Related Documentation

- [Token Management](token-management) - Token exchange, refresh, and JWT structure
- [Web UI](web-ui) - Consent screen and sign-in page implementation
- [Security](security) - Security considerations for authorization flows
- [PKCE](pkce) - PKCE code challenge/verifier implementation
- [DPoP](dpop) - DPoP proof validation for token binding
- [Overview](README) - OAuth2 implementation overview
