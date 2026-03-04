---
title: OAuth 2.0 Implementation
---

# OAuth 2.0 Implementation

ATProtoPDS implements OAuth 2.0 with DPoP (Demonstrating Proof-of-Possession) for ATProto authentication, following the [ATProto OAuth 2.0 profile](https://atproto.com/specs/auth) with PKCE, DPoP binding, and JWT access tokens.

## Overview

The PDS acts as an OAuth 2.0 Authorization Server, supporting:

- **Authorization Code Flow** with PKCE (RFC 7636)
- **DPoP** (RFC 9449) for token binding
- **JWT Access Tokens** with ES256K signatures
- **Pushed Authorization Requests (PAR)** (RFC 9126)
- **Token Refresh** with refresh tokens
- **Two-Factor Authentication** (TOTP)

## Architecture

```

+-------------------+     +------------------+     +-------------------+
|     Client App    |     |   ATProtoPDS     |     |     Database      |
+-------------------+     +------------------+     +-------------------+
         |                        |                         |
         |  1. Authorization      |                         |
         |     Request (PKCE)     |                         |
         |----------------------->|                         |
         |                        |                         |
         |  2. User Sign-in       |                         |
         |     & Consent          |                         |
         |<---------------------->|                         |
         |                        |                         |
         |  3. Authorization Code |                         |
         |<-----------------------|                         |
         |                        |                         |
         |  4. Token Exchange     |                         |
         |     (DPoP Proof)       |                         |
         |----------------------->|                         |
         |                        |  Validate & Store      |
         |                        |------------------------>|
         |                        |                         |
         |  5. Access/Refresh     |                         |
         |     Tokens             |                         |
         |<-----------------------|                         |
         |                        |                         |
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/oauth/authorize` | GET | Authorization page (sign-in + consent screen) |
| `/oauth/authorize/sign-in` | POST | Credential validation for sign-in |
| `/oauth/authorize/confirm` | POST | Consent decision (allow/deny) |
| `/oauth/token` | POST | Token exchange (authorization_code, refresh_token) |
| `/oauth/revoke` | POST | Token revocation |
| `/oauth/par` | POST | Pushed Authorization Requests |
| `/oauth/jwks` | GET | JSON Web Key Set for token verification |
| `/.well-known/oauth-authorization-server` | GET | Server metadata (RFC 8414) |
| `/.well-known/oauth-protected-resource` | GET | Protected resource metadata |

## Authorization Flow

```

┌─────────┐                    ┌─────────┐                    ┌─────────┐
│  Client │                    │   PDS   │                    │   User  │
└────┬────┘                    └────┬────┘                    └────┬────┘
     │                              │                              │
     │  GET /oauth/authorize        │                              │
     │  ?client_id=...              │                              │
     │  &redirect_uri=...           │                              │
     │  &scope=atproto              │                              │
     │  &state=...                  │                              │
     │  &code_challenge=...         │                              │
     │  &code_challenge_method=S256 │                              │
     │─────────────────────────────>│                              │
     │                              │  Serve authorize.html        │
     │<─────────────────────────────│                              │
     │                              │                              │
     │                              │  POST /oauth/authorize/sign-in
     │                              │  handle=alice.test           │
     │                              │  password=***                │
     │                              │<─────────────────────────────│
     │                              │  session_token               │
     │                              │─────────────────────────────>│
     │                              │                              │
     │                              │  POST /oauth/authorize/confirm
     │                              │  decision=allow              │
     │                              │  session_token=...           │
     │                              │<─────────────────────────────│
     │                              │                              │
     │  302 redirect_uri?code=...   │                              │
     │  &state=...                  │                              │
     │<─────────────────────────────│                              │
     │                              │                              │
     │  POST /oauth/token           │                              │
     │  grant_type=authorization_code│                              │
     │  code=...                    │                              │
     │  code_verifier=...           │                              │
     │  DPoP: <proof>               │                              │
     │─────────────────────────────>│                              │
     │                              │                              │
     │  access_token (JWT)          │                              │
     │  refresh_token               │                              │
     │  token_type=DPoP             │                              │
     │<─────────────────────────────│                              │
     │                              │                              │
```

## Key Components

### OAuth2Handler.m

HTTP route handler for all `/oauth/*` endpoints. Manages:

- Route registration with the HTTP server
- Request validation (client_id, redirect_uri, state)
- DPoP proof verification
- CSRF protection for sign-in
- Authorization page rendering

### OAuth2.m

Core OAuth2Server implementation:

- Authorization code generation and validation
- Token request processing
- PKCE verification
- Session creation with DPoP binding
- Token refresh logic

### Session.m

Session and token lifecycle management:

- JWT access token minting (via `JWTMinter`)
- Refresh token generation
- Token expiration tracking
- Storage backends (memory and SQLite)

### JWT.m

JWT implementation:

- Token parsing and encoding
- ES256K signature verification
- Claim validation (iss, sub, exp, iat)
- Access token minting with DPoP confirmation (`cnf.jkt`)

### DPoPUtil.m

DPoP proof utilities:

- Proof generation with ES256
- Proof verification
- JWK thumbprint calculation
- Replay protection

### PKCEUtil.m

PKCE utilities:

- Code verifier generation (32 random bytes, base64url)
- Code challenge generation (SHA256 hash of verifier)
- Challenge verification

## Token Structure

### Access Token (JWT)

```json
{
  "header": {
    "alg": "ES256K",
    "typ": "at+jwt",
    "kid": "key-id"
  },
  "payload": {
    "iss": "https://pds.example.com",
    "sub": "did:plc:abc123",
    "did": "did:plc:abc123",
    "handle": "alice.example.com",
    "scope": "atproto",
    "iat": 1700000000,
    "exp": 1700003600,
    "jti": "uuid",
    "cnf": {
      "jkt": "dpop-key-thumbprint"
    }
  }
}
```

### Token Response

```json
{
  "access_token": "eyJhbGciOiJFUzI1NksiLC...",
  "token_type": "DPoP",
  "expires_in": 3600,
  "refresh_token": "uuid-refresh-token",
  "scope": "atproto",
  "sub": "did:plc:abc123"
}
```

## Scopes

| Scope | Description |
|-------|-------------|
| `atproto` | Full access to account |
| `atproto:identify` | Identity verification |
| `atproto:signin` | Sign-in capability |
| `atproto:profile` | Access to profile information |
| `atproto:repo_read` | Read repository |
| `atproto:repo_write` | Write to repository |

## DPoP Binding

All token requests require a DPoP proof header:

```

DPoP: eyJhbGciOiJFUzI1NiIsInR5cCI6ImRwb3Arand0IiwiandrIjp7Imt0eSI6IkVDIiwiY3J2IjoiUC0yNTYiLCJ4Ijoi...","htm":"POST","htu":"https://pds.example.com/oauth/token","iat":1700000000,"jti":"uuid"}}
```

The proof binds tokens to a specific public key, preventing token theft.

## Quick Start

### Client Registration

Register a client in the database:

```sql
INSERT INTO oauth_clients (client_id, client_name, redirect_uris, client_type)
VALUES ('my-app', 'My Application', '["https://app.example.com/callback"]', 'public');
```

### Authorization Request

```

GET /oauth/authorize?
    client_id=my-app&
    redirect_uri=https://app.example.com/callback&
    response_type=code&
    scope=atproto&
    state=random-state&
    code_challenge=S256-hash-of-verifier&
    code_challenge_method=S256
```

### Token Exchange

```bash
curl -X POST https://pds.example.com/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "DPoP: <dpop-proof>" \
  -d "grant_type=authorization_code" \
  -d "code=<authorization-code>" \
  -d "redirect_uri=https://app.example.com/callback" \
  -d "client_id=my-app" \
  -d "code_verifier=<pkce-verifier>"
```

### Token Refresh

```bash
curl -X POST https://pds.example.com/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "DPoP: <dpop-proof>" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=<refresh-token>" \
  -d "client_id=my-app"
```

## Server Metadata

### Authorization Server Metadata

```

GET /.well-known/oauth-authorization-server
```

Returns RFC 8414 compliant metadata including:

- `issuer` - PDS issuer URL
- `authorization_endpoint` - Authorization URL
- `token_endpoint` - Token exchange URL
- `jwks_uri` - Public key endpoint
- `scopes_supported` - Available scopes
- `code_challenge_methods_supported` - PKCE methods

### JWKS

```

GET /oauth/jwks
```

Returns the server's public keys for JWT verification:

```json
{
  "keys": [
    {
      "kty": "EC",
      "crv": "secp256k1",
      "alg": "ES256K",
      "use": "sig",
      "kid": "key-id",
      "x": "...",
      "y": "..."
    }
  ]
}
```

## Security Features

- **PKCE** - Prevents authorization code interception
- **DPoP** - Binds tokens to client's public key
- **CSRF Protection** - State parameter + CSRF tokens for web flows
- **Short-lived Access Tokens** - 1 hour expiration
- **Nonce-based Replay Protection** - For DPoP proofs
- **Redirect URI Exact Match** - Prevents open redirect attacks

## Related Documentation

### OAuth2 Documentation
- [Architecture](architecture) - System architecture and component overview
- [Authorization Flow](authorization-flow) - Auth code flow with sign-in and consent
- [Token Management](token-management) - JWT tokens, sessions, and lifecycle
- [DPoP](dpop) - DPoP proof-of-possession implementation
- [PKCE](pkce) - PKCE code exchange security
- [Web UI](web-ui) - Consent screen and authorization UI
- [Security](security) - Security considerations and threat model
- [Admin Auth](admin-auth) - Admin authentication (separate from OAuth)

### Other Documentation
- [Developer Guide](../guides/development/DEVELOPER_GUIDE) - General development setup
- [Architecture](../architecture/ARCHITECTURE_ANALYSIS) - System architecture
- [Security Plan](../security/SECURITY_PLAN) - Security overview

## References

- [ATProto OAuth 2.0 Profile](https://atproto.com/specs/auth)
- [RFC 6749 - OAuth 2.0](https://datatracker.ietf.org/doc/html/rfc6749)
- [RFC 7636 - PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [RFC 9449 - DPoP](https://datatracker.ietf.org/doc/html/rfc9449)
- [RFC 9126 - PAR](https://datatracker.ietf.org/doc/html/rfc9126)
