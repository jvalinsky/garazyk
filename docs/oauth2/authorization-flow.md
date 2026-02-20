# OAuth2 Authorization Flow

This document describes the OAuth2 authorization code flow implementation in the PDS, including user authentication, consent, and authorization code generation.

## Overview

The PDS implements a two-phase OAuth2 authorization flow:

1. **Sign-In Phase**: User authenticates with handle/password
2. **Consent Phase**: User reviews and approves the authorization request

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
| `ATProtoPDS/Sources/Auth/OAuth2Handler.m` | HTTP endpoint handlers |
| `ATProtoPDS/Sources/Auth/OAuth2.m` | Authorization server logic |
| `ATProtoPDS/Sources/Auth/Assets/authorize.html` | Web UI template |

## Related Documentation

- [Token Management](./token-management.md) - Token exchange, refresh, and JWT structure
- [Web UI](./web-ui.md) - Consent screen and sign-in page implementation
- [Security](./security.md) - Security considerations for authorization flows
- [PKCE](./pkce.md) - PKCE code challenge/verifier implementation
- [DPoP](./dpop.md) - DPoP proof validation for token binding
- [Overview](./README.md) - OAuth2 implementation overview
