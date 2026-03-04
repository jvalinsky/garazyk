---
title: JWT Tokens
---

# JWT Tokens

## Overview

<!-- Image placeholder: JWT Token Flow -->

*Complete JWT token lifecycle including minting, validation, and refresh operations*

JWT (JSON Web Tokens) are used for:
- **Access tokens** — Short-lived tokens for API access
- **Refresh tokens** — Long-lived tokens for obtaining new access tokens
- **DPoP proofs** — Binding tokens to client keys

## Token Types

### Access Tokens

**Purpose:** Authenticate API requests

**Lifetime:** 1 hour (configurable)

**Scope:** Specific permissions (e.g., `atproto_repo`)

**Example Payload:**
```json
{
  "iss": "did:web:pds.example.com",
  "sub": "did:plc:user123",
  "iat": 1234567890,
  "exp": 1234571490,
  "scope": "atproto_repo"
}
```

### Refresh Tokens

**Purpose:** Obtain new access tokens

**Lifetime:** 30 days (configurable)

**Scope:** `atproto_refresh`

**Example Payload:**
```json
{
  "iss": "did:web:pds.example.com",
  "sub": "did:plc:user123",
  "iat": 1234567890,
  "exp": 1237159890,
  "scope": "atproto_refresh"
}
```

## Token Generation

### Creating Access Tokens

The `JWTMinter` class handles token generation with proper signing and encoding:

```objc
// In JWTMinter.m (ATProtoPDS/Sources/Auth/JWT.m)
- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
             dpopKeyThumbprint:(nullable NSString *)jkt
                           error:(NSError **)error {
    // 1. Create payload with standard claims
    JWTPayload *payload = [[JWTPayload alloc] init];
    payload.iss = self.issuer;
    payload.sub = did;
    payload.aud = self.audience;
    payload.did = did;
    payload.handle = handle;
    payload.scope = [scopes componentsJoinedByString:@" "];
    payload.iat = [NSDate date];
    payload.exp = [NSDate dateWithTimeIntervalSinceNow:self.defaultExpiration];
    payload.jti = [[NSUUID UUID] UUIDString];
    
    // 2. Add DPoP key thumbprint if provided (for DPoP binding)
    if (jkt) {
        payload.cnf = @{@"jkt": jkt};
    }

    // 3. Create header with algorithm and key ID
    JWTHeader *header = [[JWTHeader alloc] init];
    header.alg = self.signingAlgorithm;
    header.typ = @"at+jwt";

    // 4. Sign the payload using configured key manager
    NSData *signatureData = [self signData:[NSString stringWithFormat:@"%@.%@", 
        [JWT base64URLEncodeData:[NSJSONSerialization dataWithJSONObject:[header toDictionary] 
            options:0 error:error] error:error] ?: @"", 
        [JWT base64URLEncodeData:[NSJSONSerialization dataWithJSONObject:[payload toDictionary] 
            options:0 error:error] error:error] ?: @""] error:error];
    NSString *signature = [JWT base64URLEncodeData:signatureData error:error];

    // 5. Return complete JWT
    return [JWT jwtWithHeader:header payload:payload signature:signature error:error];
}
```

**Source:** `ATProtoPDS/Sources/Auth/JWT.m` lines 280-310

### Creating Refresh Tokens

Refresh tokens have longer expiration (30 days) and are used to obtain new access tokens:

```objc
// In JWTMinter.m (ATProtoPDS/Sources/Auth/JWT.m)
- (JWT *)mintRefreshTokenForDID:(NSString *)did
                         handle:(NSString *)handle
                         scopes:(NSArray<NSString *> *)scopes
                           error:(NSError **)error {
    // 1. Create payload with refresh token claims
    JWTPayload *payload = [[JWTPayload alloc] init];
    payload.iss = self.issuer;
    payload.sub = did;
    payload.aud = self.audience;
    payload.did = did;
    payload.handle = handle;
    payload.scope = [scopes componentsJoinedByString:@" "];
    payload.iat = [NSDate date];
    payload.exp = [NSDate dateWithTimeIntervalSinceNow:86400 * 30];  // 30 days
    payload.jti = [[NSUUID UUID] UUIDString];

    // 2. Create header
    JWTHeader *header = [[JWTHeader alloc] init];
    header.alg = self.signingAlgorithm;
    header.typ = @"refresh+jwt";

    // 3. Sign and return
    NSData *signatureData = [self signData:[NSString stringWithFormat:@"%@.%@", 
        [JWT base64URLEncodeData:[NSJSONSerialization dataWithJSONObject:[header toDictionary] 
            options:0 error:error] error:error] ?: @"", 
        [JWT base64URLEncodeData:[NSJSONSerialization dataWithJSONObject:[payload toDictionary] 
            options:0 error:error] error:error] ?: @""] error:error];
    NSString *signature = [JWT base64URLEncodeData:signatureData error:error];

    return [JWT jwtWithHeader:header payload:payload signature:signature error:error];
}
```

**Source:** `ATProtoPDS/Sources/Auth/JWT.m` lines 312-335

## Token Verification

### Verifying Access Tokens

The `JWTVerifier` class validates JWT structure, signature, and claims:

```objc
// In JWTVerifier.m (ATProtoPDS/Sources/Auth/JWT.m)
- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error {
    // 1. Check algorithm is allowed
    if (self.allowedAlgorithms && ![self.allowedAlgorithms containsObject:jwt.header.alg ?: @""]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidAlgorithm
                                     userInfo:@{NSLocalizedDescriptionKey: @"Algorithm not allowed"}];
        }
        return NO;
    }

    // 2. Prepare data for signature verification
    NSData *signingInputData = [jwt.signingInput dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signatureData = [JWT base64URLDecode:jwt.encodedSignature error:error];
    if (!signatureData) return NO;

    // 3. Verify signature based on algorithm
    BOOL verified = NO;
    NSString *alg = jwt.header.alg ?: @"";
    if ([alg isEqualToString:@"ES256K"]) {
        // ES256K (secp256k1) signature verification
        if (self.publicKey) {
            Secp256k1 *secp = [Secp256k1 shared];
            unsigned char hash[32];
            CC_SHA256(signingInputData.bytes, (CC_LONG)signingInputData.length, hash);
            NSData *hashData = [NSData dataWithBytes:hash length:32];
            verified = [secp verifySignature:signatureData forHash:hashData withPublicKey:self.publicKey error:error];
        } else if (self.keyManager) {
            NSString *kid = jwt.header.kid;
            if (kid) {
                verified = [self.keyManager verifySignature:signatureData forData:signingInputData withKeyID:kid error:error];
            } else {
                // Legacy path: use active key if no kid specified
                id<PDSKeyPair> active = [self.keyManager getActiveKeyPair:error];
                if (active) {
                    verified = [self.keyManager verifySignature:signatureData forData:signingInputData withKeyID:active.keyID error:error];
                }
            }
        }
    } else {
        // Other algorithms (ES256, etc.) require key manager with kid
        if (!self.keyManager) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorNoPublicKey
                                         userInfo:@{NSLocalizedDescriptionKey: @"No key manager configured"}];
            }
            return NO;
        }
        NSString *kid = jwt.header.kid;
        if (!kid) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorInvalidHeader
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing 'kid' in header"}];
            }
            return NO;
        }
        verified = [self.keyManager verifySignature:signatureData forData:signingInputData withKeyID:kid error:error];
    }

    if (!verified) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT signature"}];
        }
        return NO;
    }

    // 4. Validate claims (expiration, issuer, audience, etc.)
    if (![self validateClaims:jwt.payload ofJWT:jwt error:error]) {
        return NO;
    }
    
    return YES;
}
```

**Source:** `ATProtoPDS/Sources/Auth/JWT.m` lines 150-220

### Validating Claims

Claims validation ensures the token is still valid and meets requirements:

```objc
// In JWTVerifier.m (ATProtoPDS/Sources/Auth/JWT.m)
- (BOOL)validateClaims:(JWTPayload *)payload ofJWT:(JWT *)jwt error:(NSError **)error {
    NSDate *now = [NSDate date];

    // 1. Check expiration
    if (payload.exp && [payload.exp compare:now] == NSOrderedAscending) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorTokenExpired
                                     userInfo:@{NSLocalizedDescriptionKey: @"Token has expired"}];
        }
        return NO;
    }

    // 2. Check not-before time
    if (payload.nbf && [payload.nbf compare:now] == NSOrderedDescending) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorTokenNotYetValid
                                     userInfo:@{NSLocalizedDescriptionKey: @"Token is not yet valid"}];
        }
        return NO;
    }

    // 3. Verify issuer
    if (self.expectedIssuer && payload.iss && ![payload.iss isEqualToString:self.expectedIssuer]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidIssuer
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid issuer"}];
        }
        return NO;
    }

    // 4. Verify audience
    if (self.expectedAudience && payload.aud && ![payload.aud isEqualToString:self.expectedAudience]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidAudience
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid audience"}];
        }
        return NO;
    }

    // 5. Verify subject is present
    if (!payload.sub && !payload.did && !self.allowMissingSubject) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorMissingRequiredClaim
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing subject claim"}];
        }
        return NO;
    }

    return YES;
}
```

**Source:** `ATProtoPDS/Sources/Auth/JWT.m` lines 222-270

## Token Refresh Flow

### Refreshing Access Tokens

```objc
// In PDSAccountService.m
- (void)refreshTokenWithRefreshToken:(NSString *)refreshToken 
                          completion:(void (^)(NSString *accessToken, NSError *error))completion {
    
    // 1. Verify refresh token
    NSDictionary *payload = [self.jwtVerifier verifyJWT:refreshToken error:nil];
    if (!payload) {
        NSError *error = [NSError errorWithDomain:@"Auth" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        completion(nil, error);
        return;
    }
    
    // 2. Verify scope is "atproto_refresh"
    if (![payload[@"scope"] isEqualToString:@"atproto_refresh"]) {
        NSError *error = [NSError errorWithDomain:@"Auth" code:2 
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid token scope"}];
        completion(nil, error);
        return;
    }
    
    // 3. Check if token is in revocation list
    NSString *userDID = payload[@"sub"];
    if ([self isTokenRevoked:refreshToken forDID:userDID]) {
        NSError *error = [NSError errorWithDomain:@"Auth" code:3 
            userInfo:@{NSLocalizedDescriptionKey: @"Token has been revoked"}];
        completion(nil, error);
        return;
    }
    
    // 4. Mint new access token
    NSString *accessToken = [self.jwtMinter mintAccessToken:userDID 
                                                      scope:@"atproto_repo"
                                                 expiresIn:3600
                                                      error:nil];
    
    completion(accessToken, nil);
}
```

## Token Revocation

### Revoking Tokens

```objc
// In PDSAccountService.m
- (void)revokeToken:(NSString *)token 
            forDID:(NSString *)did
        completion:(void (^)(NSError *error))completion {
    
    // 1. Extract JTI (JWT ID) from token
    NSDictionary *payload = [self.jwtVerifier verifyJWT:token error:nil];
    NSString *jti = payload[@"jti"];
    
    // 2. Add to revocation list
    [self.serviceDatabases addToRevocationList:jti forDID:did];
    
    completion(nil);
}

- (BOOL)isTokenRevoked:(NSString *)token forDID:(NSString *)did {
    NSDictionary *payload = [self.jwtVerifier verifyJWT:token error:nil];
    NSString *jti = payload[@"jti"];
    
    return [self.serviceDatabases isInRevocationList:jti forDID:did];
}
```

## Token Storage

### Secure Storage

```objc
// In PDSAccountService.m
- (void)storeAccessToken:(NSString *)token 
                 forDID:(NSString *)did {
    // Store in secure database (encrypted)
    [self.serviceDatabases storeToken:token 
                              forDID:did 
                              type:@"access"];
}

- (void)storeRefreshToken:(NSString *)token 
                  forDID:(NSString *)did {
    // Store in secure database (encrypted)
    [self.serviceDatabases storeToken:token 
                              forDID:did 
                              type:@"refresh"];
}
```

## Token Claims

### Standard Claims

| Claim | Description | Example |
|-------|-------------|---------|
| `iss` | Issuer | `did:web:pds.example.com` |
| `sub` | Subject (user DID) | `did:plc:user123` |
| `iat` | Issued at (timestamp) | `1234567890` |
| `exp` | Expiration (timestamp) | `1234571490` |
| `scope` | Token scope | `atproto_repo` |

### Custom Claims

```json
{
  "iss": "did:web:pds.example.com",
  "sub": "did:plc:user123",
  "iat": 1234567890,
  "exp": 1234571490,
  "scope": "atproto_repo",
  "jti": "unique-token-id",
  "permissions": ["read:records", "write:records"]
}
```

## Best Practices

1. **Short expiration** — Access tokens should expire quickly (1 hour)
2. **Long refresh tokens** — Refresh tokens can be longer-lived (30 days)
3. **Secure storage** — Store tokens securely (encrypted)
4. **HTTPS only** — Always use HTTPS for token transmission
5. **Revocation** — Implement token revocation for logout
6. **Rotation** — Rotate signing keys periodically
7. **Validation** — Always validate tokens before use

## See Also

**Basic Topics:**
- [OAuth 2.0 with DPoP](oauth2-dpop) — OAuth implementation
- [Key Rotation](key-rotation) — Key management
- [Authentication Helpers](../04-network-layer/auth-helpers) — Auth verification

**Advanced Topics:**
- [Secrets Management](secrets-management) — Key storage and rotation
- [Security Best Practices](security-best-practices) — Defense in depth
