# DPoP (Demonstrating Proof-of-Possession) Implementation

DPoP (RFC 9449) binds OAuth 2.0 access tokens to a public/private key pair, preventing token theft and misuse. This document describes the DPoP implementation in ATProtoPDS.

## Implementation Files

| File | Purpose |
|------|---------|
| `Sources/Auth/OAuth2.m` | `OAuth2DPoPProof` class |
| `Sources/Auth/DPoPUtil.m` | Helper utilities for proof creation/verification |
| `Sources/Auth/OAuth2Handler.m` | Request-level DPoP validation |
| `Sources/Auth/PDSNonceManager.h/m` | Server-side nonce generation and validation |
| `Sources/Auth/PDSReplayCache.h/m` | JTI replay protection with SQLite backend |

## DPoP Proof Structure

A DPoP proof is a JWT with specific header and payload claims.

### Header

```json
{
  "typ": "dpop+jwt",
  "alg": "ES256",
  "jwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "base64url-encoded-x-coordinate",
    "y": "base64url-encoded-y-coordinate"
  }
}
```

**Header Fields:**

| Field | Value | Description |
|-------|-------|-------------|
| `typ` | `dpop+jwt` | Media type identifying DPoP proof |
| `alg` | `ES256` | ECDSA with P-256 and SHA-256 |
| `jwk` | Object | Public key in JWK format (no private key material) |

### Payload

```json
{
  "jti": "unique-identifier",
  "htm": "POST",
  "htu": "https://pds.example/oauth/token",
  "iat": 1234567890,
  "nonce": "server-provided-nonce"
}
```

**Payload Claims:**

| Claim | Required | Description |
|-------|----------|-------------|
| `jti` | Yes | Unique JWT ID for replay protection |
| `htm` | Yes | HTTP method (uppercase) |
| `htu` | Yes | HTTP URL (scheme, host, path, query; no fragment) |
| `iat` | Yes | Issued-at timestamp (Unix seconds) |
| `exp` | No | Expiration timestamp |
| `nonce` | Conditional | Server-provided nonce (required after challenge) |
| `ath` | No | Access token hash (for resource requests) |

## Verification Algorithm

The `verifyProof:method:url:nonce:requireNonce:outThumbprint:error:` method implements verification in 14 steps.

### Step-by-Step Verification

```
1. Parse JWT into 3 parts (header.payload.signature)
   └─ Fail if not exactly 3 dot-separated parts

2. Base64URL decode header, payload, and signature
   └─ Fail on decoding errors

3. Parse header and payload as JSON
   └─ Fail on JSON parsing errors

4. Validate header claims:
   - typ == "dpop+jwt"
   - alg == "ES256"
   - jwk exists and is a dictionary
   └─ Fail on mismatch

5. Extract required payload claims (htm, htu, jti, iat)
   └─ Fail if any missing

6. Normalize and verify htm (HTTP method)
   - Compare uppercase method strings
   └─ Fail on mismatch

7. Normalize and verify htu (HTTP URL)
   - Remove fragment from request URL
   - Compare scheme (case-insensitive), host (case-insensitive), path, query
   └─ Fail on mismatch

8. Validate nonce (if provided or required)
   - Check proof contains nonce claim
   - Verify nonce matches expected value
   - Validate via PDSNonceManager
   └─ Fail on mismatch or invalid nonce

9. Validate iat not in future
   - Allow +60 seconds clock skew tolerance
   └─ Fail if iat > now + 60s

10. Validate exp claim (if present)
    └─ Fail if exp < now

11. Validate iat not too old
    - Maximum age: 300 seconds (5 minutes)
    └─ Fail if now - iat > 300s

12. Check jti replay protection
    - Use PDSReplayCache with SQLite backend
    └─ Fail if jti seen before (not expired)

13. Verify cryptographic signature
    - Convert raw signature (r||s) to DER format
    - Use SecKeyVerifySignature with ES256
    └─ Fail on signature mismatch

14. Return JWK thumbprint
    - RFC 7638 thumbprint for token binding
    └─ Fail on thumbprint calculation error
```

### Code Reference

```objc
+ (BOOL)verifyProof:(NSString *)dpopJwt
             method:(NSString *)method
                url:(NSURL *)url
              nonce:(nullable NSString *)nonce
       requireNonce:(BOOL)requireNonce
      outThumbprint:(NSString * _Nullable * _Nullable)thumbprint
                error:(NSError **)error;
```

**Nonce Requirement:** The implementation enforces `requireNonce:YES` in `validateDPoPForRequest` (`OAuth2Handler.m:918`).

## Nonce Challenge Flow

DPoP nonces prevent replay attacks across sessions and provide freshness guarantees.

### Server-to-Client Challenge

```
Client                                Server
  │                                     │
  │  POST /oauth/token                  │
  │  DPoP: eyJ0eXAiOiJk...              │
  │  (no nonce in proof)                │
  │                                    │
  │────────────────────────────────────▶│
  │                                     │
  │                     400 Bad Request │
  │      DPoP-Nonce: abc123             │
  │      WWW-Authenticate: DPoP error="use_dpop_nonce"
  │      {"error": "use_dpop_nonce"}    │
  │                                     │
  │◀────────────────────────────────────│
  │                                     │
  │  POST /oauth/token                  │
  │  DPoP: eyJ0eXAiOiJk...(with nonce)  │
  │  DPoP-Nonce: abc123                 │
  │                                     │
  │────────────────────────────────────▶│
  │                                     │
  │                    200 OK + tokens  │
  │                                     │
  │◀────────────────────────────────────│
```

### Nonce Generation

`PDSNonceManager` generates cryptographically secure nonces:

```objc
// PDSNonceManager.m:30-52
- (NSString *)generateNonce {
    uint8_t randomBytes[24];
    SecRandomCopyBytes(kSecRandomDefault, sizeof(randomBytes), randomBytes);
    NSData *data = [NSData dataWithBytes:randomBytes length:sizeof(randomBytes)];
    NSString *nonce = [data base64EncodedStringWithOptions:0];
    // Normalize for URL safety
    nonce = [nonce stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    nonce = [nonce stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    nonce = [nonce stringByReplacingOccurrencesOfString:@"=" withString:@""];
    
    // Store with 10-minute expiration
    NSDate *expiration = [NSDate dateWithTimeIntervalSinceNow:600];
    // ...
    return nonce;
}
```

**Nonce Properties:**
- 24 random bytes (192 bits of entropy)
- Base64URL encoded (32 characters)
- One-time use
- 10-minute expiration

### Nonce Validation

```objc
// PDSNonceManager.m:54-70
- (BOOL)validateNonce:(NSString *)nonce {
    // Check nonce exists and hasn't expired
    // Nonces are single-use; removed after validation
    NSDate *expiration = self.issuedNonces[nonce];
    if (expiration && [expiration timeIntervalSinceNow] > 0) {
        [self.issuedNonces removeObjectForKey:nonce];
        return YES;
    }
    return NO;
}
```

## Replay Protection

`PDSReplayCache` prevents JTI reuse using SQLite.

### Database Schema

```sql
CREATE TABLE jti_cache (
  jti TEXT PRIMARY KEY,
  expires_at REAL NOT NULL
);
CREATE INDEX idx_jti_cache_expires_at ON jti_cache(expires_at);
```

### Check-and-Add Operation

```objc
// PDSReplayCache.m:62-95
- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration {
    // 1. Check if non-expired entry exists
    // 2. If exists: replay detected, return NO
    // 3. If not: insert new entry, return YES
    
    // Entry expires at iat + 300 seconds
}
```

**Replay Protection Properties:**
- In-memory SQLite by default
- WAL mode for concurrency
- Automatic cleanup every 5 minutes
- JTI expiration aligned with proof max age (5 minutes)

## JWK Thumbprint (RFC 7638)

The JWK thumbprint uniquely identifies a public key for token binding.

### Calculation

```objc
+ (nullable NSString *)jwkThumbprint:(NSDictionary *)jwk error:(NSError **)error {
    // 1. Extract required members for key type:
    //    EC: crv, kty, x, y
    //    RSA: e, kty, n
    
    // 2. Sort keys lexicographically
    
    // 3. Build canonical JSON:
    //    {"crv":"P-256","kty":"EC","x":"...","y":"..."}
    
    // 4. SHA-256 hash
    
    // 5. Base64URL encode
}
```

### Canonical JSON Construction

For EC keys, the canonical form uses only these members in alphabetical order:

```json
{"crv":"P-256","kty":"EC","x":"mqM...","y":"8JJ..."}
```

**Important:** JSON keys must be sorted lexicographically, and string values must be properly escaped for JSON.

### Token Binding

The thumbprint appears in the access token's `cnf` (confirmation) claim:

```json
{
  "sub": "did:plc:abc123",
  "cnf": {
    "jkt": "sha-256-thumbprint-of-jwk"
  }
}
```

When a client makes a request with an access token, the server verifies that the DPoP proof's JWK thumbprint matches the `cnf.jkt` claim in the token.

## Signature Handling

### Raw vs DER Format

- **DPoP JWT Signature:** Raw format (r || s), 64 bytes for P-256
- **Apple Security Framework:** Expects DER-encoded ASN.1 format

### DER to Raw Conversion (Verification)

```objc
+ (nullable NSData *)ecdsaRawSignatureFromDER:(NSData *)der
                                 expectedSize:(size_t)expectedSize
                                        error:(NSError **)error {
    // Parse ASN.1 DER structure:
    // 0x30 [length]           - SEQUENCE
    //   0x02 [length] [r]     - INTEGER (r)
    //   0x02 [length] [s]     - INTEGER (s)
    
    // Strip leading zeros from r and s
    // Left-pad to expectedSize (32 bytes each)
    // Concatenate: r (32 bytes) || s (32 bytes)
}
```

### Raw to DER Conversion (Signing)

```objc
+ (nullable NSData *)ecdsaDERSignatureFromRaw:(NSData *)raw error:(NSError **)error {
    // Split raw signature into r (first 32 bytes) and s (last 32 bytes)
    // Strip leading zeros
    // Add leading zero if high bit set (to ensure positive integer)
    // Build DER: 0x30 [len] 0x02 [r_len] [r] 0x02 [s_len] [s]
}
```

### Signature Verification

```objc
SecKeyRef publicKey = [self createPublicKeyFromJWK:jwk error:error];
NSData *derSignature = [self ecdsaDERSignatureFromRaw:signatureData error:error];

BOOL verified = SecKeyVerifySignature(publicKey,
                                      kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                      (__bridge CFDataRef)signingData,
                                      (__bridge CFDataRef)derSignature,
                                      NULL);
```

## Integration with OAuth2Handler

### Request Validation

```objc
- (BOOL)validateDPoPForRequest:(HttpRequest *)request
                       response:(HttpResponse *)response
                  outThumbprint:(NSString **)outThumbprint {
    // 1. Extract DPoP header
    NSString *dpopProof = [request headerForKey:@"dpop"];
    
    // 2. Construct URL from request (scheme, host, path, query)
    NSURL *dpopURL = ...;
    
    // 3. Verify proof (nonce required)
    if (![OAuth2DPoPProof verifyProof:dpopProof
                               method:request.methodString
                                  url:dpopURL
                                nonce:requestedNonce
                         requireNonce:YES
                        outThumbprint:&dpopThumbprint
                                error:&dpopError]) {
        // 4. Handle nonce challenge
        if ([dpopError.userInfo[@"use_dpop_nonce"] boolValue]) {
            NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
            [response setHeader:nonce forKey:@"DPoP-Nonce"];
            [response setHeader:@"DPoP error=\"use_dpop_nonce\"" forKey:@"WWW-Authenticate"];
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"use_dpop_nonce"}];
            return NO;
        }
        // 5. Return other errors
        // ...
    }
    // 6. Return thumbprint for token binding
    *outThumbprint = dpopThumbprint;
    return YES;
}
```

## Error Codes

| Error | HTTP Status | Description |
|-------|-------------|-------------|
| `invalid_dpop_proof` | 400 | Proof validation failed |
| `use_dpop_nonce` | 400 | Nonce challenge; retry with provided nonce |
| `invalid_request` | 400 | Missing DPoP header |

## Security Considerations

### Key Requirements
- ES256 (ECDSA P-256 SHA-256) only
- Public key must be in JWK format in header
- Private key never transmitted

### Timing Constraints
- `iat` must not be in the future (+60s tolerance)
- `iat` must not be older than 5 minutes
- `exp` honored if present

### Replay Prevention
- JTI must be unique within the proof's lifetime
- Nonce required after server challenge
- Nonce is single-use

### URL Normalization
- Fragment removed from URL
- Scheme and host compared case-insensitively
- Path and query compared exactly

## Related Documentation

- [Token Management](./token-management) - JWT tokens and DPoP binding via cnf.jkt
- [Security](./security) - Security considerations for DPoP implementation
- [Authorization Flow](./authorization-flow) - DPoP in token exchange
- [Overview](./README) - OAuth2 implementation overview

## References

- [RFC 9449: OAuth 2.0 Demonstrating Proof-of-Possession at the Application Layer](https://www.rfc-editor.org/rfc/rfc9449)
- [RFC 7638: JSON Web Key (JWK) Thumbprint](https://www.rfc-editor.org/rfc/rfc7638)
- [RFC 7518: JSON Web Algorithms (JWA)](https://www.rfc-editor.org/rfc/rfc7518)
