---
title: OAuth2 Security Considerations
---

# OAuth2 Security Considerations

This document describes the security architecture, threat model, and mitigation strategies implemented in the ATProto PDS OAuth2 implementation.

## Implementation Files

| Component | File | Purpose |
|-----------|------|---------|
| Handler | `ATProtoPDS/Sources/Auth/OAuth2Handler.m` | Request validation, CSRF, PKCE enforcement |
| Core | `ATProtoPDS/Sources/Auth/OAuth2.m` | DPoP verification, token lifecycle |
| Replay Cache | `ATProtoPDS/Sources/Auth/PDSReplayCache.m` | JTI replay protection |
| Nonce Manager | `ATProtoPDS/Sources/Auth/PDSNonceManager.m` | DPoP nonce issuance/validation |

## Threat Model

### Attack Vectors Mitigated

| Attack | Mitigation | Implementation |
|--------|------------|----------------|
| Authorization Code Injection | PKCE (RFC 7636) | `OAuth2Handler.m:339-350` |
| CSRF on Authorization | State parameter + CSRF tokens | `OAuth2Handler.m:316-326`, `500-524` |
| Token Theft/Replay | DPoP binding (RFC 9449) | `OAuth2.m:727-927` |
| DPoP Proof Replay | JTI tracking | `PDSReplayCache.m:62-95` |
| Redirect URI Manipulation | Exact match validation | `OAuth2Handler.m:117-179` |
| Mix-up Attacks | Client validation during exchange | `OAuth2.m:1087-1093` |
| Code Interception | Single-use codes, 10-minute expiry | `OAuth2.m:1077-1085` |
| Timing Attacks | Constant-time comparison (via framework) | Signature verification |

---

## Security Features

### 1. CSRF Protection

**Authorization Endpoint:**

The `state` parameter is mandatory for all authorization requests:

```objc
// OAuth2Handler.m:316-326
NSString *state = params[@"state"];
if (!state || [state stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
        @"error": @"invalid_request",
        @"error_description": @"state parameter required for CSRF protection"
    }];
    return;
}
```

**Sign-In Endpoint:**

Double-submit cookie pattern for CSRF protection:

```objc
// OAuth2Handler.m:507-524
NSString *csrfHeader = [request headerForKey:@"X-CSRF-Token"];
NSString *csrfCookie = nil;
// ... extract cookie ...
if (!csrfHeader || !csrfCookie || ![csrfHeader isEqualToString:csrfCookie]) {
    response.statusCode = 403;
    [response setJsonBody:@{@"ok": @NO, @"error": @"Invalid CSRF token"}];
    return;
}
```

**Session Tokens:**

Consent sessions use single-use tokens stored in memory with 5-minute expiration:

```objc
// OAuth2Handler.m:546-553
NSString *sessionToken = [[NSUUID UUID] UUIDString];
@synchronized (sPendingConsents) {
    sPendingConsents[sessionToken] = @{
        @"did": result[@"did"],
        @"handle": handle,
        @"expires": [NSDate dateWithTimeIntervalSinceNow:300]
    };
}
```

### 2. PKCE Enforcement

Public clients (those without `client_secret`) must use PKCE with S256 method:

```objc
// OAuth2Handler.m:339-350
BOOL isPublicClient = (client[@"client_secret"] == nil);
if (isPublicClient && (!authRequest.codeChallenge || authRequest.codeChallenge.length == 0)) {
    response.statusCode = 400;
    [response setJsonBody:@{
        @"error": @"invalid_request",
        @"error_description": @"code_challenge required for public clients"
    }];
    return;
}
```

**Verification during token exchange:**

```objc
// OAuth2.m:1095-1119
if (request.codeVerifier && codeData[@"code_challenge"]) {
    NSString *expectedChallenge = codeData[@"code_challenge"];
    NSString *method = codeData[@"code_challenge_method"] ?: @"plain";
    
    if (![self verifyCodeVerifier:codeVerifier challenge:expectedChallenge method:method]) {
        // Reject invalid verifier
    }
}
```

### 3. DPoP Binding

All token requests require a valid DPoP proof header:

```objc
// OAuth2Handler.m:864-873
NSString *dpopProof = [request headerForKey:@"dpop"];
if (!dpopProof || dpopProof.length == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
        @"error": @"invalid_request",
        @"error_description": @"Missing DPoP proof"
    }];
    return NO;
}
```

**Proof validation includes:**

1. **Type and algorithm verification:**
   ```objc
   // OAuth2.m:763-771
   if (![typ isEqualToString:@"dpop+jwt"] || 
       ![alg isEqualToString:@"ES256"] || 
       ![jwk isKindOfClass:[NSDictionary class]]) {
       // Invalid header
   }
   ```text

2. **HTTP method binding:**
   ```objc
   // OAuth2.m:790-799
   NSString *normalizedMethod = [method uppercaseString];
   if (![htm isEqualToString:normalizedMethod]) {
       // htm mismatch
   }
   ```text

3. **URL binding:**
   ```objc
   // OAuth2.m:801-816
   if (![htu isEqualToString:expectedHTU]) {
       // htu mismatch
   }
   ```text

4. **Timestamp validation:**
   ```objc
   // OAuth2.m:853-880
   NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
   if (iat.doubleValue > now + 60) {
       // iat in future (60s tolerance)
   }
   if (now - iat.doubleValue > 300) {
       // iat too old (5 minutes)
   }
   ```text

5. **JTI replay prevention:**
   ```objc
   // OAuth2.m:882-891
   NSDate *jtiExpiration = [NSDate dateWithTimeIntervalSince1970:iat.doubleValue + 300];
   if (![[PDSReplayCache sharedCache] checkAndAddJTI:jti expiration:jtiExpiration]) {
       // jti reuse detected
   }
   ```text

6. **Nonce challenge support:**
   ```objc
   // OAuth2.m:818-851
   if (nonceRequired && proofNonce.length == 0) {
       // nonce required but missing
   }
   if (![[PDSNonceManager sharedManager] validateNonce:proofNonce]) {
       // nonce invalid or expired
   }
   ```text

7. **Token binding via cnf.jkt:**
   ```objc
   // OAuth2.m:1161-1167
   if (!request.dpopKeyThumbprint || request.dpopKeyThumbprint.length == 0) {
       // Missing DPoP key thumbprint
   }
   ```text

### 4. Redirect URI Validation

Exact match against registered URIs with scheme enforcement:

```objc
// OAuth2Handler.m:117-179
NSURL *url = [NSURL URLWithString:redirectURI];
if (!url) {
    // Invalid format
}

#ifndef DEBUG
// Production: require HTTPS
if (![url.scheme isEqualToString:@"https"]) {
    // Must use HTTPS in production
}
#else
// Development: allow HTTP for localhost only
if ([url.scheme isEqualToString:@"http"]) {
    if (![host isEqualToString:@"localhost"] && ![host isEqualToString:@"127.0.0.1"]) {
        // HTTP only for localhost
    }
}
#endif

// Exact match required
for (NSString *allowedURI in allowedURIs) {
    if ([redirectURI isEqualToString:allowedURI]) {
        return YES;
    }
}
```

### 5. Authorization Code Security

**Single-use enforcement:**
```objc
// OAuth2.m:1121
[self removeAuthorizationCode:request.code];
```

**10-minute expiration:**
```objc
// OAuth2.m:1077-1085
NSTimeInterval codeAge = [[NSDate date] timeIntervalSince1970] - [codeData[@"created_at"] doubleValue];
if (codeAge > 600) {
    [self removeAuthorizationCode:request.code];
    // Authorization code expired
}
```

**Client ID validation:**
```objc
// OAuth2.m:1087-1093
if (![codeData[@"client_id"] isEqualToString:request.clientID]) {
    // Client ID mismatch
}
```

### 6. Token Security

**JWT access tokens:**
- Signed with ES256K algorithm
- Short lifetime: 1 hour (`expires_in: 3600`)
- Bound to DPoP key via `cnf.jkt` claim

**Refresh token rotation:**
- New refresh token issued on each use
- Old token invalidated immediately

**Token response:**
```objc
// OAuth2Handler.m:697-705
NSMutableDictionary *tokenResp = [@{
    @"access_token": session.accessToken,
    @"token_type": @"DPoP",
    @"expires_in": @3600,
    @"scope": session.scope ?: @"atproto"
} mutableCopy];
if (session.refreshToken) tokenResp[@"refresh_token"] = session.refreshToken;
```

### 7. Replay Protection

The `PDSReplayCache` singleton provides JTI tracking:

```objc
// PDSReplayCache.m:62-95
- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration {
    // Check for existing non-expired entry
    if (sqlite3_step(selectStmt) == SQLITE_ROW) {
        double existingExpiry = sqlite3_column_double(selectStmt, 0);
        if (existingExpiry >= now) {
            // Replay detected
            return NO;
        }
    }
    
    // Insert new entry
    sqlite3_bind_text(insertStmt, 1, jti.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(insertStmt, 2, expiresAt);
    return YES;
}
```

**Configuration:**
- Storage: In-memory SQLite by default
- JTI tracking duration: 5 minutes from `iat`
- Automatic cleanup: Every 5 minutes

### 8. Nonce Management

Server-issued nonces for DPoP challenge-response:

```objc
// PDSNonceManager.m:30-52
- (NSString *)generateNonce {
    uint8_t randomBytes[24];
    SecRandomCopyBytes(kSecRandomDefault, sizeof(randomBytes), randomBytes);
    
    NSString *nonce = [data base64EncodedStringWithOptions:0];
    // Normalize for URL safety
    nonce = [nonce stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    nonce = [nonce stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    nonce = [nonce stringByReplacingOccurrencesOfString:@"=" withString:@""];
    
    NSDate *expiration = [NSDate dateWithTimeIntervalSinceNow:600]; // 10 minutes
    self.issuedNonces[nonce] = expiration;
    return nonce;
}
```

**Validation with one-time use:**
```objc
// PDSNonceManager.m:54-70
- (BOOL)validateNonce:(NSString *)nonce {
    NSDate *expiration = self.issuedNonces[nonce];
    if (expiration) {
        if ([expiration timeIntervalSinceNow] > 0) {
            isValid = YES;
        }
        // Nonces are one-time use
        [self.issuedNonces removeObjectForKey:nonce];
    }
    return isValid;
}
```

### 9. Clock Skew Tolerance

60-second tolerance for future timestamps in DPoP proof validation:

```objc
// OAuth2.m:853-861
NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
if (iat.doubleValue > now + 60) {
    // DPoP iat in future (beyond tolerance)
}
```

---

## Security Best Practices

### For Server Operators

1. **HTTPS Enforcement:**
   - Never deploy in production without HTTPS
   - Use proper TLS certificates
   - Enable HSTS headers

2. **Redirect URI Registration:**
   - Register exact URIs only
   - Avoid wildcard patterns
   - Use HTTPS URIs exclusively

3. **Client Registration:**
   - Enforce strong `client_secret` for confidential clients
   - Rotate secrets periodically
   - Use different redirect URIs per client

4. **Monitoring:**
   - Log DPoP proof validation failures
   - Monitor JTI replay detection
   - Alert on repeated CSRF token failures

### For Client Developers

1. **PKCE Usage:**
   - Always use PKCE for public clients
   - Use S256 method (not plain)
   - Generate cryptographically random verifiers (43-128 characters)

2. **State Parameter:**
   - Generate unique state per request
   - Validate state before processing callback
   - Use cryptographically random values

3. **DPoP Key Management:**
   - Generate new key pair per session
   - Store private key securely
   - Include nonce when challenged

4. **Token Storage:**
   - Store tokens securely (Keychain/Keystore)
   - Clear tokens on logout
   - Handle token rotation properly

---

## Configuration Recommendations

### Production Configuration

```yaml
oauth2:
  issuer: "https://your-pds.example.com"
  
  security:
    # Enforce HTTPS for all redirect URIs
    require_https: true
    
    # DPoP proof validity window
    dpop_max_age_seconds: 300
    
    # JTI replay cache duration
    jti_cache_seconds: 300
    
    # Nonce lifetime
    nonce_expiry_seconds: 600
    
    # Authorization code lifetime
    auth_code_expiry_seconds: 600
    
    # Access token lifetime
    access_token_expiry_seconds: 3600
    
    # Clock skew tolerance
    clock_skew_seconds: 60
```

### Development Configuration

```yaml
oauth2:
  issuer: "http://localhost:3000"
  
  security:
    # Allow HTTP for localhost testing
    require_https: false
    
    # Relaxed timings for debugging
    dpop_max_age_seconds: 600
```

---

## Error Responses

### Security-Related Errors

| Error Code | Description | HTTP Status |
|------------|-------------|-------------|
| `invalid_request` | Missing state parameter | 400 |
| `invalid_request` | Missing code_challenge for public client | 400 |
| `invalid_request` | Missing DPoP proof | 400 |
| `invalid_dpop_proof` | DPoP validation failed | 400 |
| `use_dpop_nonce` | Server nonce required | 400 |
| `invalid_grant` | Authorization code expired or invalid | 400 |
| `invalid_client` | Invalid client credentials | 401 |
| `access_denied` | CSRF validation failed | 403 |

### DPoP Nonce Challenge

When a DPoP nonce is required, the server responds with:

```http
HTTP/1.1 400 Bad Request
WWW-Authenticate: DPoP error="use_dpop_nonce"
DPoP-Nonce: <server-issued-nonce>
Content-Type: application/json

{
  "error": "use_dpop_nonce",
  "error_description": "DPoP nonce required"
}
```

The client must retry with the provided nonce in the DPoP proof payload.

---

## Security Checklist

### Pre-Deployment

- [ ] HTTPS enforced on all endpoints
- [ ] Redirect URIs registered exactly
- [ ] Client secrets are strong and rotated
- [ ] JWT signing keys are properly managed
- [ ] Replay cache is persistent (not in-memory) if multi-instance
- [ ] Nonce manager is properly configured for load-balanced deployments
- [ ] Logging configured for security events
- [ ] Rate limiting configured for token endpoint

### Ongoing Operations

- [ ] Monitor DPoP proof failures
- [ ] Monitor JTI replay detection
- [ ] Review client registrations periodically
- [ ] Rotate JWT signing keys annually
- [ ] Audit token usage patterns
- [ ] Update dependencies for security patches

---

## Related Documentation

This security document references concepts from all OAuth2 documentation:

- [Overview](README) - OAuth2 implementation overview
- [Architecture](architecture) - System architecture and components
- [Authorization Flow](authorization-flow) - Auth code flow security
- [Token Management](token-management) - Token security and rotation
- [DPoP](dpop) - DPoP proof security and replay protection
- [PKCE](pkce) - PKCE and code interception protection
- [Web UI](web-ui) - CSRF and session token security
- [Admin Auth](admin-auth) - Admin authentication security

---

## References

- [RFC 6749 - OAuth 2.0 Authorization Framework](https://tools.ietf.org/html/rfc6749)
- [RFC 7636 - PKCE for OAuth Public Clients](https://tools.ietf.org/html/rfc7636)
- [RFC 9449 - OAuth 2.0 Demonstrating Proof-of-Possession (DPoP)](https://tools.ietf.org/html/rfc9449)
- [OAuth 2.0 Security Best Current Practice](https://tools.ietf.org/html/draft-ietf-oauth-security-topics)
- [ATProto OAuth 2.0 Specification](https://atproto.com/specs/auth)
