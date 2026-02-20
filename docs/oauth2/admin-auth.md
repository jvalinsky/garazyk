# Admin Authentication

Admin authentication provides a separate authentication mechanism for PDS administrators, distinct from user OAuth 2.0 flows. This document describes the admin login flow, JWT validation, and endpoint protection.

## Overview

Admin authentication uses a simple password-based login that issues JWT tokens, without requiring OAuth 2.0 flows, PKCE, or DPoP. This is designed for:

- Administrative dashboard access
- Server management operations
- Moderation tools
- System health monitoring

## Authentication Flow

```
┌─────────┐                    ┌─────────┐                    ┌─────────┐
│  Admin  │                    │   PDS   │                    │  Data   │
│  Client │                    │ Server  │                    │  Dir    │
└────┬────┘                    └────┬────┘                    └────┬────┘
     │                              │                              │
     │  POST /admin/login           │                              │
     │  {"password": "..."}         │                              │
     │─────────────────────────────>│                              │
     │                              │                              │
     │                              │  Verify password             │
     │                              │  (plain or PBKDF2)           │
     │                              │                              │
     │                              │  Generate JWT                │
     │                              │  (scope: admin)              │
     │                              │                              │
     │  {"token": "eyJ..."}         │                              │
     │<─────────────────────────────│                              │
     │                              │                              │
     │  GET /admin/users            │                              │
     │  Authorization: Bearer eyJ...│                              │
     │─────────────────────────────>│                              │
     │                              │                              │
     │                              │  Validate JWT                │
     │                              │  Check scope="admin"         │
     │                              │  Check iat >= min_iat        │
     │                              │                              │
     │  {"users": [...]}            │                              │
     │<─────────────────────────────│                              │
     │                              │                              │
     │  POST /admin/logout          │                              │
     │  Authorization: Bearer eyJ...│                              │
     │─────────────────────────────>│                              │
     │                              │                              │
     │                              │  Update min_iat              │
     │                              │─────────────────────────────>│
     │                              │                              │
     │  {"message": "Logged out"}   │                              │
     │<─────────────────────────────│                              │
     │                              │                              │
```

## Password Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `PDS_ADMIN_PASSWORD` | Admin password (plain text or hashed) | Yes* |
| `PDS_ADMIN_PASSWORD_FILE` | Path to file containing password | Yes* |

*One of `PDS_ADMIN_PASSWORD` or `PDS_ADMIN_PASSWORD_FILE` is required.

### Plain Text Password

```bash
export PDS_ADMIN_PASSWORD="your-secure-password"
```

### File-Based Password (Docker Secrets)

```bash
export PDS_ADMIN_PASSWORD_FILE="/run/secrets/admin_password"
```

The file contents are trimmed of whitespace, making this compatible with Docker secrets and Kubernetes.

### PBKDF2 Hashed Password

For production, use PBKDF2-SHA256 hashed passwords:

```
pbkdf2:<iterations>:<base64-salt>:<base64-hash>
```

Example:
```
pbkdf2:100000:7kN9xQZ3mP4vR2sT8wY6uI==:aB1cD2eF3gH4iJ5kL6mN7oP8qR9sT0uV==
```

**Generating a PBKDF2 hash:**

```bash
# Using Python
python3 -c "
import base64, hashlib, os
password = 'your-secure-password'
salt = os.urandom(16)
iterations = 100000
hash_val = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, iterations)
print(f'pbkdf2:{iterations}:{base64.b64encode(salt).decode()}:{base64.b64encode(hash_val).decode()}')
"
```

## JWT Structure

### Header

```json
{
  "alg": "ES256",
  "typ": "JWT"
}
```

### Payload

```json
{
  "iss": "https://pds.example.com",
  "sub": "did:web:pds.example.com",
  "aud": "https://pds.example.com",
  "scope": "admin",
  "iat": 1700000000,
  "exp": 1700003600
}
```

| Claim | Description |
|-------|-------------|
| `iss` | PDS issuer URL |
| `sub` | Admin DID (`did:web:{host}`) |
| `aud` | Audience (same as issuer) |
| `scope` | Always `"admin"` |
| `iat` | Issued at timestamp |
| `exp` | Expiration timestamp |

### Token Lifetime

| Variable | Default | Range |
|----------|---------|-------|
| `PDS_ADMIN_TOKEN_TTL_SECONDS` | 3600 (1 hour) | 60 - 86400 |

## JWT Validation

Validation occurs in `PDSAdminAuth.m:227-327`:

### Validation Steps

1. **Extract token from headers**
   - `Authorization: Bearer {token}` (primary)
   - `X-Admin-Token: {token}` (alternative, can be disabled)

2. **Parse JWT structure**
   - Must be valid 3-part JWT
   - Header and payload must be valid JSON

3. **Verify required claims**
   - `iss` (issuer) must be present
   - `aud` (audience) must be present

4. **Check admin scope**
   - Scope string must contain `"admin"`
   - Uses constant-time comparison for security

5. **Verify signature**
   - Uses server's signing key via `JWTVerifier`
   - Supports ES256, ES256K, RS256 algorithms

6. **Validate issuer/audience**
   - `iss` must match `PDS_ISSUER`
   - `aud` must match `PDS_ISSUER`

7. **Check minimum issued-at**
   - Token `iat` must be >= `minimumTokenIssuedAt`
   - Rejects tokens invalidated by logout-all

### Scope Check Implementation

```objc
static BOOL PDSScopesContainAdmin(NSString *scopeString) {
    if (scopeString.length == 0) return NO;
    NSArray<NSString *> *parts = [scopeString componentsSeparatedByCharactersInSet:
                                   [NSCharacterSet whitespaceCharacterSet]];
    for (NSString *part in parts) {
        if (part.length == 0) continue;
        if ([part isEqualToString:@"admin"]) return YES;
    }
    return NO;
}
```

## Minimum Issued-At (Logout-All)

The minimum issued-at mechanism enables logout-all functionality:

### How It Works

1. On logout, `minimumTokenIssuedAt` is set to current time
2. Value is persisted to `.admin_min_iat` file in data directory
3. On server restart, persisted value is loaded
4. All tokens with `iat < minimumTokenIssuedAt` are rejected

### Implementation

```objc
- (void)logout {
    self.adminToken = nil;
    NSDate *now = [NSDate date];
    self.minimumTokenIssuedAt = now;
    PDSAdminAuthPersistMinIAT(self.dataDirectory, now);
}
```

### File Location

```
{PDS_DATA_DIRECTORY}/.admin_min_iat
```

The file contains a floating-point timestamp:

```
1700000000.000000
```

## Admin Endpoints

### Login Endpoint

```http
POST /admin/login HTTP/1.1
Host: pds.example.com
Content-Type: application/json

{"password": "admin-password"}
```

**Success Response:**

```json
{
  "message": "Login successful",
  "token": "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Error Response (invalid password):**

```json
{
  "error": "Invalid admin password"
}
```

**Error Response (password not configured):**

```json
{
  "error": "Admin password not configured (set PDS_ADMIN_PASSWORD or PDS_ADMIN_PASSWORD_FILE)"
}
```

### Protected Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/admin` | GET | Admin dashboard index |
| `/admin/users` | GET | List all accounts |
| `/admin/invites` | GET/POST | List or create invite codes |
| `/admin/invites/disable` | POST | Disable an invite code |
| `/admin/blobs` | GET | List blob storage |
| `/admin/metrics` | GET | Server metrics (JSON or Prometheus) |
| `/admin/health` | GET | Health check |
| `/admin/logout` | POST | Logout (invalidates all tokens) |

## Endpoint Protection

### HTTP Handler Protection

`PDSAdminHandler.m:61-69`:

```objc
- (NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                 path:(NSString *)path
                              headers:(NSDictionary *)headers
                                 body:(NSData *)body {
    PDSAdminAuth *auth = [PDSAdminAuth sharedAuth];

    if (![path isEqualToString:@"/admin/login"] && 
        ![auth isAuthenticatedWithRequest:headers]) {
        return [self jsonResponseWithStatus:401 body:@{@"error": @"Unauthorized"}];
    }
    // ... handle request
}
```

### XRPC Endpoint Protection

`XrpcMethodRegistry.m:87-121`:

```objc
static BOOL authorizeAdminRequest(HttpRequest *request, HttpResponse *response,
                                  PDSServiceDatabases *serviceDatabases,
                                  JWTMinter *jwtMinter,
                                  id<PDSAdminController> adminController) {
    // ... initial auth header extraction ...
    
    PDSAdminAuth *adminAuth = [PDSAdminAuth sharedAuth];
    NSError *authError = nil;
    if (![adminAuth isAuthenticatedWithRequest:request.headers]) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{
            @"error": @"Forbidden",
            @"message": @"Admin privileges required (valid admin token)"
        }];
        return NO;
    }
    return YES;
}
```

Protected XRPC methods include:
- `admin.disableAccount`
- `admin.enableAccount`
- `admin.getInviteCodes`
- `admin.createInviteCode`
- `admin.disableInviteCodes`
- `admin.getAccountInfo`
- `admin.updateAccountEmail`
- `admin.deleteAccount`

## Configuration Reference

### Required for Production

| Variable | Description |
|----------|-------------|
| `PDS_ISSUER` | PDS issuer URL (e.g., `https://pds.example.com`) |
| `PDS_ENV=production` | Enables production mode checks |

### Optional Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PDS_ADMIN_PASSWORD` | - | Admin password |
| `PDS_ADMIN_PASSWORD_FILE` | - | Path to password file |
| `PDS_ADMIN_TOKEN_TTL_SECONDS` | 3600 | Token lifetime in seconds |
| `PDS_DISABLE_X_ADMIN_TOKEN_HEADER` | false | Disable `X-Admin-Token` header |
| `PDS_REQUIRE_ISSUER` | false | Require issuer (alternative to `PDS_ENV`) |

## Admin vs User OAuth Comparison

| Feature | User OAuth | Admin Auth |
|---------|-----------|------------|
| **Flow** | Authorization Code + PKCE | Password only |
| **Credentials** | Handle + Password | Password only |
| **Token Type** | DPoP-bound JWT | Bearer JWT |
| **Scope** | `atproto`, `atproto:repo_read`, etc. | `admin` |
| **Identity** | User DID (`did:plc:...`) | Server DID (`did:web:...`) |
| **Consent Screen** | Required | N/A |
| **PKCE** | Required | N/A |
| **DPoP Proof** | Required for every request | Not used |
| **Refresh Token** | Yes | No (re-login required) |
| **Token Revocation** | Per-session | Logout-all only |
| **Client Registration** | Required | N/A |

## Security Considerations

### Constant-Time Comparison

Password and scope comparisons use constant-time algorithms to prevent timing attacks:

```objc
static BOOL PDSConstantTimeEqualStrings(NSString *a, NSString *b) {
    NSData *aData = [a dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bData = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (aData.length != bData.length) return NO;
    
    const uint8_t *aBytes = aData.bytes;
    const uint8_t *bBytes = bData.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < aData.length; i++) {
        diff |= (uint8_t)(aBytes[i] ^ bBytes[i]);
    }
    return diff == 0;
}
```

### Production Requirements

When `PDS_ENV=production`:

1. `PDS_ISSUER` must be configured
2. Password should use PBKDF2 hashing
3. Use `PDS_ADMIN_PASSWORD_FILE` with secrets management
4. Disable `X-Admin-Token` header: `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1`

### Token Binding

Unlike user OAuth, admin tokens are not DPoP-bound. This means:

- Tokens can be used from any client
- Token theft is more severe
- Short TTL is recommended (default: 1 hour)
- Use HTTPS exclusively in production

### Logout-All Behavior

- Single logout invalidates all issued tokens
- Implemented via minimum `iat` check
- Survives server restarts via file persistence
- Provides emergency token revocation

## Implementation Files

| File | Purpose |
|------|---------|
| `Admin/PDSAdminAuth.h/m` | Admin JWT authentication |
| `Admin/PDSAdminHandler.m` | Admin HTTP endpoints |
| `Network/XrpcMethodRegistry.m` | `authorizeAdminRequest` function |
| `Auth/JWT.h/m` | JWT parsing and verification |
| `Auth/JWTVerifier.h/m` | JWT signature verification |

## Related Documentation

- [Token Management](./token-management.md) - User token lifecycle (compare with admin tokens)
- [Security](./security.md) - Security considerations
- [Overview](./README.md) - User OAuth2 authentication flows
