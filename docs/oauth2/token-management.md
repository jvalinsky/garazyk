# OAuth 2.0 Token Management

This document describes the token lifecycle, JWT structure, and session management in the ATProto PDS OAuth 2.0 implementation.

## Overview

The PDS implements OAuth 2.0 with DPoP (Demonstrating Proof-of-Possession) for secure token binding. The system uses three token types:

1. **Access Tokens** - Short-lived JWTs for API authentication
2. **Refresh Tokens** - Long-lived opaque tokens for obtaining new access tokens
3. **Authorization Codes** - Single-use codes exchanged for tokens

## Token Types

### Access Token (JWT)

Access tokens are signed JWTs bound to the user's DPoP key.

| Property | Value |
|----------|-------|
| **Algorithm** | ES256K (secp256k1) or ES256 (P-256) |
| **Issuer** | PDS issuer URL (e.g., `https://pds.example.com`) |
| **Subject** | User's DID (e.g., `did:plc:abc123`) |
| **Lifetime** | 1 hour (3600 seconds) |
| **Format** | JWT with DPoP binding via `cnf.jkt` claim |

#### JWT Header

```json
{
  "alg": "ES256K",
  "typ": "at+jwt",
  "kid": "key-identifier"
}
```

#### JWT Payload (Claims)

| Claim | Description | Required |
|-------|-------------|----------|
| `iss` | PDS issuer URL | Yes |
| `sub` | User's DID | Yes |
| `did` | User's DID (ATProto-specific) | Yes |
| `handle` | User's handle (ATProto-specific) | Yes |
| `scope` | Granted OAuth scope | Yes |
| `iat` | Issued at timestamp | Yes |
| `exp` | Expiration timestamp | Yes |
| `jti` | Unique token identifier | Yes |
| `cnf` | Confirmation claim for DPoP binding | When DPoP used |

#### DPoP Binding

When DPoP is used, the access token includes a confirmation claim:

```json
{
  "cnf": {
    "jkt": "base64url-encoded-thumbprint"
  }
}
```

The `jkt` (JWK thumbprint) binds the token to a specific public key, preventing token theft.

### Refresh Token

| Property | Value |
|----------|-------|
| **Format** | UUID (opaque string) |
| **Lifetime** | 30 days (2,592,000 seconds) |
| **Rotation** | New token issued on each use |
| **Storage** | Session-based (in-memory or SQLite) |

Refresh tokens can be configured via the `PDS_REFRESH_TOKEN_TTL_DAYS` environment variable.

### Authorization Code

| Property | Value |
|----------|-------|
| **Format** | UUID |
| **Lifetime** | 10 minutes (600 seconds) |
| **Usage** | Single use - deleted after exchange |
| **PKCE** | Required for public clients |

#### Authorization Code Data

```json
{
  "client_id": "app.example.com",
  "redirect_uri": "https://app.example.com/callback",
  "scope": "atproto",
  "code_challenge": "base64url-sha256",
  "code_challenge_method": "S256",
  "login_hint_did": "did:plc:abc123",
  "dpop_jwk": {...},
  "created_at": 1700000000
}
```

## Token Response Format

Successful token responses follow OAuth 2.0 format with ATProto extensions:

```json
{
  "access_token": "eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJhdCtqd3QifQ...",
  "token_type": "DPoP",
  "expires_in": 3600,
  "refresh_token": "550e8400-e29b-41d4-a716-446655440000",
  "scope": "atproto",
  "sub": "did:plc:abc123"
}
```

| Field | Description |
|-------|-------------|
| `access_token` | JWT access token |
| `token_type` | Always "DPoP" for ATProto |
| `expires_in` | Seconds until expiration (3600) |
| `refresh_token` | Opaque refresh token |
| `scope` | Granted scopes |
| `sub` | User's DID |

## Token Lifecycle

### 1. Authorization Code Flow

```
┌─────────┐     ┌─────────┐     ┌─────────┐
│  Client │     │   PDS   │     │  User   │
└────┬────┘     └────┬────┘     └────┬────┘
     │               │               │
     │ 1. GET /oauth/authorize      │
     │──────────────>│               │
     │               │ 2. Login Page │
     │               │──────────────>│
     │               │               │
     │               │ 3. Credentials│
     │               │<──────────────│
     │               │               │
     │               │ 4. Consent    │
     │               │<──────────────│
     │               │               │
     │ 5. Redirect with code         │
     │<──────────────│               │
     │               │               │
     │ 6. POST /oauth/token          │
     │──────────────>│               │
     │               │               │
     │ 7. Token Response             │
     │<──────────────│               │
     │               │               │
```

### 2. Authorization Code Exchange

**Request:**

```http
POST /oauth/token HTTP/1.1
Host: pds.example.com
Content-Type: application/x-www-form-urlencoded
DPoP: eyJ...

grant_type=authorization_code
&code=550e8400-e29b-41d4-a716-446655440000
&redirect_uri=https://app.example.com/callback
&client_id=app.example.com
&code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
```

**Supported Grant Types:**
- `authorization_code` - Standard authorization code exchange
- `refresh_token` - Token refresh
- `urn:ietf:params:oauth:grant-type:dpop` - DPoP-bound token grant

**Optional Parameters:**
- `tfa_code` - TOTP code when two-factor authentication is enabled

**Implementation** (`OAuth2.m:1051-1175`):

1. Retrieve authorization code data from storage
2. Verify code hasn't expired (600 second max age)
3. Validate client ID matches
4. Verify PKCE code verifier against challenge
5. Delete authorization code (single use)
6. Check 2FA status if enabled
7. Create session with DPoP key binding
8. Return token response

### 3. Access Token Usage

Access tokens are used with DPoP proofs for API calls:

```http
GET /xrpc/com.atproto.sync.getRepo HTTP/1.1
Host: pds.example.com
Authorization: DPoP eyJ...
DPoP: eyJ...
```

**DPoP Proof Verification** (`OAuth2.m:712-927`):

1. Parse JWT structure (3 parts)
2. Verify header: `typ=dpop+jwt`, `alg=ES256`, `jwk` present
3. Verify claims: `htm`, `htu`, `jti`, `iat`
4. Validate `htm` matches HTTP method
5. Validate `htu` matches request URL
6. Check `iat` is within 5 minutes
7. Verify nonce if required
8. Check for JTI replay
9. Verify ECDSA signature
10. Extract thumbprint for token binding

### 4. Token Refresh

When the access token expires, use the refresh token:

```http
POST /oauth/token HTTP/1.1
Host: pds.example.com
Content-Type: application/x-www-form-urlencoded
DPoP: eyJ...

grant_type=refresh_token
&refresh_token=550e8400-e29b-41d4-a716-446655440000
&scope=atproto
```

**Implementation** (`OAuth2.m:1177-1213`):

1. Find session by refresh token
2. Verify refresh token hasn't expired (30 day TTL)
3. Optionally narrow scope
4. Delete old session
5. Create new session with new tokens
6. Return new token response

**Token Rotation:**

Each refresh issues a new refresh token, invalidating the previous one. This limits the window for token theft.

### 5. Token Revocation

Tokens can be revoked explicitly:

```http
POST /oauth/revoke HTTP/1.1
Host: pds.example.com
Content-Type: application/x-www-form-urlencoded

token=eyJ...
&client_id=app.example.com
```

**Implementation** (`OAuth2Handler.m:716-771`):

1. Validate client authentication
2. Find session by access or refresh token
3. Remove session from storage
4. Return success (even if token not found, for security)

## Session Storage

### In-Memory Storage

`PDSMemorySessionStorage` provides thread-safe in-memory session storage:

- Dictionary keyed by access token
- Serial dispatch queue for thread safety
- Index by DID for user session lookup

### SQLite Storage

`PDSSQLiteSessionStorage` provides persistent session storage:

```sql
CREATE TABLE sessions (
  session_id TEXT PRIMARY KEY,
  did TEXT NOT NULL,
  handle TEXT NOT NULL,
  scope TEXT NOT NULL,
  access_token TEXT UNIQUE NOT NULL,
  refresh_token TEXT UNIQUE,
  access_token_expires_at REAL NOT NULL,
  refresh_token_expires_at REAL,
  dpop_key_thumbprint TEXT,
  token_type TEXT DEFAULT 'Bearer',
  created_at REAL NOT NULL
);
```

**Indexes:**
- `idx_sessions_did` - Fast lookup by user
- `idx_sessions_access_token` - Token validation
- `idx_sessions_refresh_token` - Refresh flow

### SessionStore API

```objc
@interface SessionStore : NSObject

@property NSTimeInterval accessTokenLifetime;   // Default: 3600
@property NSTimeInterval refreshTokenLifetime;  // Default: 2592000

- (Session *)createSessionForDID:(NSString *)did
                          handle:(NSString *)handle
                           scope:(NSString *)scope
                         dpopJWK:(NSDictionary *)dpopJWK
                           error:(NSError **)error;

- (Session *)getSessionByAccessToken:(NSString *)token error:(NSError **)error;
- (Session *)getSessionByRefreshToken:(NSString *)token error:(NSError **)error;

- (BOOL)refreshSession:(NSString *)sessionID
                 scope:(NSString *)newScope
               dpopJWK:(NSDictionary *)dpopJWK
           newSession:(Session **)newSession
                 error:(NSError **)error;

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error;

@end
```

## Session Model

```objc
@interface Session : NSObject

@property (readonly) NSString *sessionID;
@property (readonly) NSString *did;
@property (readonly) NSString *handle;
@property (readonly) NSString *accessToken;
@property (readonly) NSString *refreshToken;
@property (readonly) NSString *tokenType;
@property (readonly) NSString *scope;
@property (readonly) NSDate *createdAt;
@property (readonly) NSDate *accessTokenExpiresAt;
@property (readonly) NSDate *refreshTokenExpiresAt;
@property NSString *dpopKeyThumbprint;

- (NSDictionary *)toTokenResponse;
- (BOOL)isAccessTokenValid;
- (BOOL)isRefreshTokenValid;
- (NSString *)refreshAccessToken;

@end
```

## JWT Minting

The `JWTMinter` class handles token creation:

```objc
@interface JWTMinter : NSObject

@property NSString *issuer;
@property NSString *signingAlgorithm;     // Default: ES256
@property NSTimeInterval defaultExpiration; // Default: 3600
@property id<PDSKeyManager> keyManager;

- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
             dpopKeyThumbprint:(NSString *)jkt
                          error:(NSError **)error;

- (JWT *)mintRefreshTokenForDID:(NSString *)did
                         handle:(NSString *)handle
                         scopes:(NSArray<NSString *> *)scopes
                           error:(NSError **)error;

- (NSDictionary *)toJWKS;

@end
```

**Algorithm Usage:**
- `JWTMinter` defaults to ES256 (P-256) for token signing
- `OAuth2Server` uses ES256K (secp256k1) for ATProto compliance

### Key Management

Keys are managed via `PDSKeyManager` protocol:

```objc
@protocol PDSKeyManager <NSObject>

- (id<PDSKeyPair>)getActiveKeyPair:(NSError **)error;
- (NSData *)signData:(NSData *)data withKeyID:(NSString *)keyID error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature
               forData:(NSData *)data
             withKeyID:(NSString *)keyID
                 error:(NSError **)error;
- (NSDictionary *)toJWKS;

@end
```

## JWT Verification

The `JWTVerifier` class validates tokens:

```objc
@interface JWTVerifier : NSObject

@property NSString *expectedIssuer;
@property NSString *expectedAudience;
@property NSArray<NSString *> *allowedAlgorithms;
@property NSDate *clockOffset;
@property id<PDSKeyManager> keyManager;
@property BOOL allowMissingSubject;

- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error;

@end
```

**Verification Steps:**

1. Check algorithm is allowed
2. Verify signature using key manager
3. Validate expiration (`exp`)
4. Validate not-before (`nbf`)
5. Validate issuer (`iss`)
6. Validate audience (`aud`)
7. Ensure subject or DID present

## Error Handling

### OAuth 2.0 Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `invalid_request` | 400 | Missing or invalid parameter |
| `invalid_client` | 401 | Client authentication failed |
| `invalid_grant` | 400 | Invalid authorization code or refresh token |
| `unauthorized_client` | 401 | Client not authorized for grant type |
| `unsupported_grant_type` | 400 | Grant type not supported |
| `invalid_scope` | 400 | Requested scope invalid |
| `interaction_required` | 400 | User interaction required (e.g., 2FA) |
| `mfa_required` | 400 | Two-factor authentication required |
| `use_dpop_nonce` | 400 | DPoP nonce required |

### JWT Error Codes

| Code | Description |
|------|-------------|
| `JWTErrorInvalidFormat` | Token not three parts |
| `JWTErrorInvalidHeader` | Header JSON invalid |
| `JWTErrorInvalidPayload` | Payload JSON invalid |
| `JWTErrorInvalidSignature` | Signature verification failed |
| `JWTErrorTokenExpired` | Token past expiration |
| `JWTErrorTokenNotYetValid` | Token before nbf |
| `JWTErrorInvalidIssuer` | Issuer mismatch |
| `JWTErrorNoPublicKey` | No key for verification |

### Session Error Codes

| Code | Description |
|------|-------------|
| `SessionErrorInvalidToken` | Token format invalid |
| `SessionErrorTokenExpired` | Token has expired |
| `SessionErrorSessionNotFound` | Session doesn't exist |
| `SessionErrorRevoked` | Session was revoked |

## Security Considerations

### DPoP Binding

- Every token request requires a valid DPoP proof
- Access tokens are bound to the DPoP key via `cnf.jkt`
- API requests must include matching DPoP proof
- JTI replay prevention (5 minute window)

### PKCE (RFC 7636)

- Required for public clients (no client secret)
- Supports `S256` and `plain` methods
- Code verifier must be 43-128 characters
- Prevents authorization code interception

### Token Rotation

- Refresh token rotation on every use
- Previous refresh token immediately invalid
- Limits impact of token theft

### Clock Skew

- Configurable clock skew tolerance
- Applied during token validation
- Default: 0 seconds (strict)

## Implementation Files

| File | Purpose |
|------|---------|
| `Session.h/m` | Session model and storage |
| `JWT.h/m` | JWT parsing, minting, verification |
| `OAuth2.h/m` | OAuth 2.0 server implementation |
| `OAuth2Handler.h/m` | HTTP endpoint handlers |
| `PDSKeyManagerFactory.h/m` | Key manager creation |
| `PDSReplayCache.h/m` | JTI replay prevention |
| `PDSNonceManager.h/m` | DPoP nonce management |

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PDS_ISSUER` | PDS issuer URL | From config |
| `PDS_REFRESH_TOKEN_TTL_DAYS` | Refresh token lifetime in days | 30 |

### Session Store Configuration

```objc
SessionStore *store = [[SessionStore alloc] initWithDatabasePath:@"/path/to/sessions.db"];
store.accessTokenLifetime = 3600;      // 1 hour
store.refreshTokenLifetime = 2592000;  // 30 days
store.minter = jwtMinter;
```

## Related Documentation

- [DPoP](./dpop) - DPoP proof verification and token binding
- [Authorization Flow](./authorization-flow) - Code generation and exchange
- [Security](./security) - Security considerations for token handling
- [Overview](./README) - OAuth2 implementation overview
