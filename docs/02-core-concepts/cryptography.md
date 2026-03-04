---
title: Cryptography in AT Protocol
---

# Cryptography in AT Protocol

## Why This Matters

In a decentralized social network, there's no central authority to trust. Every server operator, every relay, every client could potentially be malicious. Cryptography is what makes trust unnecessary:

- **Authentication** — Prove you are who you claim to be without revealing your password
- **Authorization** — Ensure users can only modify their own data, even on untrusted servers
- **Integrity** — Detect any tampering with data, no matter how subtle
- **Non-repudiation** — Users can't deny creating content they signed

Without strong cryptography, decentralization would be impossible. Anyone could impersonate anyone else, modify others' posts, or forge entire social graphs.

## Real-World Threat Model

Consider these scenarios that cryptography prevents:

**Scenario 1: Malicious PDS Operator**
Alice's PDS operator decides to modify her posts to make her look bad. Without cryptography, this would be trivial. With cryptography, every post is signed with Alice's private key. Any modification breaks the signature, and other servers reject the tampered post.

**Scenario 2: Token Theft**
An attacker intercepts Alice's access token and tries to use it from their own device. Without DPoP, the token would work. With DPoP, the token is cryptographically bound to Alice's device's key pair. The attacker's requests fail signature verification.

**Scenario 3: Repository Corruption**
During migration, some of Alice's posts get corrupted. Without content addressing, this might go unnoticed. With CID-based verification, the receiving server detects the corruption immediately because the hash doesn't match.

## Overview

The AT Protocol uses cryptography for:
- **Authentication** — Verify user identity
- **Authorization** — Ensure users can only modify their own data
- **Integrity** — Detect tampering with data
- **Confidentiality** — Protect sensitive information

## Cryptographic Algorithms

### ECDSA P-256

**Purpose:** Digital signatures for commits and tokens

**Algorithm:** Elliptic Curve Digital Signature Algorithm with P-256 curve

**Key Size:** 256 bits (32 bytes)

**Usage:**
- Sign commits (repository state)
- Sign JWT tokens
- Sign DPoP proofs

**Why P-256?** The AT Protocol chose P-256 (also known as secp256r1) for several reasons:
- **Widely supported** — Available in all major cryptographic libraries and hardware security modules
- **NIST standardized** — Well-studied and trusted by security community
- **Efficient** — Fast signature generation and verification on modern hardware
- **Compact** — 256-bit keys provide strong security with reasonable size

**Trade-off:** Some prefer secp256k1 (used by Bitcoin) for its simpler mathematical properties, but P-256's broader hardware support and standardization make it more practical for a protocol targeting mainstream adoption.

### SHA-256

**Purpose:** Cryptographic hashing

**Output:** 256 bits (32 bytes)

**Usage:**
- Calculate CIDs (content identifiers)
- Hash passwords
- Verify data integrity

**Why SHA-256?** Despite newer hash functions like SHA-3 and BLAKE2 being available, SHA-256 remains the standard choice because:
- **Universal support** — Every platform has optimized SHA-256 implementations
- **Hardware acceleration** — Modern CPUs have SHA-256 instructions
- **Proven security** — No practical attacks after 20+ years of analysis
- **Standardization** — Required by many compliance frameworks

**Performance:** On modern hardware, SHA-256 can hash gigabytes per second, making it suitable for real-time content addressing.

### HMAC-SHA256

**Purpose:** Message authentication codes

**Usage:**
- Verify JWT signatures
- Authenticate API requests

**Why HMAC?** HMAC provides authenticated encryption without requiring public-key cryptography. It's faster than ECDSA for symmetric scenarios and provides the same security guarantees when both parties share a secret.

## JWT (JSON Web Tokens)

<!-- Image placeholder: Cryptography Flow -->

### Token Structure

A JWT consists of three parts separated by dots:

```

eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.
eyJpc3MiOiJkaWQ6d2ViOnBkcy5leGFtcGxlLmNvbSIsInN1YiI6ImRpZDpwbGM6dXNlcjEyMyIsImV4cCI6MTIzNDU2Nzg5MH0.
<signature>
```

**Header:**
```json
{
  "alg": "ES256",
  "typ": "JWT"
}
```

**Payload:**
```json
{
  "iss": "did:web:pds.example.com",
  "sub": "did:plc:user123",
  "exp": 1234567890,
  "iat": 1234567800,
  "scope": "atproto_refresh"
}
```

### JWT Generation

```objc
// In JWTMinter.m
- (NSString *)mintAccessToken:(NSString *)userDID 
                       scope:(NSString *)scope
                  expiresIn:(NSTimeInterval)expiresIn
                       error:(NSError **)error {
    // 1. Create header
    NSDictionary *header = @{
        @"alg": @"ES256",
        @"typ": @"JWT"
    };
    
    // 2. Create payload
    NSDate *now = [NSDate date];
    NSDictionary *payload = @{
        @"iss": self.issuerDID,
        @"sub": userDID,
        @"iat": @((long)[now timeIntervalSince1970]),
        @"exp": @((long)([now timeIntervalSince1970] + expiresIn)),
        @"scope": scope
    };
    
    // 3. Encode header and payload as base64url
    NSString *headerB64 = [self base64urlEncode:[ATProtoCBORSerialization encodeObject:header error:nil]];
    NSString *payloadB64 = [self base64urlEncode:[ATProtoCBORSerialization encodeObject:payload error:nil]];
    
    // 4. Create signature
    NSString *message = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [self signData:messageData withKey:self.signingKey];
    NSString *signatureB64 = [self base64urlEncode:signature];
    
    // 5. Combine into JWT
    NSString *jwt = [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
    
    return jwt;
}
```

### JWT Verification

```objc
// In JWTVerifier.m
- (NSDictionary *)verifyToken:(NSString *)token error:(NSError **)error {
    // 1. Split token into parts
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        *error = [NSError errorWithDomain:@"JWT" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        return nil;
    }
    
    NSString *headerB64 = parts[0];
    NSString *payloadB64 = parts[1];
    NSString *signatureB64 = parts[2];
    
    // 2. Decode header and payload
    NSData *headerData = [self base64urlDecode:headerB64];
    NSData *payloadData = [self base64urlDecode:payloadB64];
    
    NSDictionary *header = [ATProtoCBORSerialization decodeData:headerData error:error];
    NSDictionary *payload = [ATProtoCBORSerialization decodeData:payloadData error:error];
    
    if (!header || !payload) return nil;
    
    // 3. Verify signature
    NSString *message = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [self base64urlDecode:signatureB64];
    
    if (![self verifySignature:signature forData:messageData withKey:self.publicKey]) {
        *error = [NSError errorWithDomain:@"JWT" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature"}];
        return nil;
    }
    
    // 4. Check expiration
    NSNumber *exp = payload[@"exp"];
    if ([exp longValue] < [[NSDate date] timeIntervalSince1970]) {
        *error = [NSError errorWithDomain:@"JWT" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Token expired"}];
        return nil;
    }
    
    return payload;
}
```

## DPoP (Demonstration of Proof-of-Possession)

### What is DPoP?

DPoP is a mechanism to bind access tokens to a specific client's key pair. It prevents token theft by ensuring tokens can only be used by the client that created them.

### Why DPoP Matters

Traditional OAuth 2.0 bearer tokens are like cash—whoever holds the token can use it. If an attacker intercepts your access token (through network sniffing, malware, or a compromised server), they can impersonate you until the token expires.

DPoP solves this by making tokens more like credit cards: they're only useful if you can prove you're the legitimate owner. Each API request includes a DPoP proof—a JWT signed with your device's private key. Even if an attacker steals your access token, they can't generate valid DPoP proofs without your private key.

**Real-world impact:** In a decentralized network where you might interact with dozens of servers, DPoP ensures that a compromised relay or malicious PDS operator can't steal your credentials and impersonate you across the network.

### DPoP Proof Structure

A DPoP proof is a JWT that contains:
- **HTTP method** — GET, POST, etc.
- **HTTP URI** — The endpoint being accessed
- **Timestamp** — When the proof was created
- **Signature** — Signed with client's key

### DPoP Proof Example

```json
{
  "alg": "ES256",
  "typ": "dpop+jwt",
  "jwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "...",
    "y": "..."
  }
}
.
{
  "jti": "unique-id",
  "htm": "POST",
  "htu": "https://pds.example.com/xrpc/com.atproto.repo.createRecord",
  "iat": 1234567890
}
.
<signature>
```

### DPoP Verification

```objc
// In DPoPHandler.m
- (BOOL)verifyDPoPProof:(NSString *)proof 
              forMethod:(NSString *)method
                   uri:(NSString *)uri
                 error:(NSError **)error {
    // 1. Verify DPoP JWT signature
    NSDictionary *payload = [self verifyDPoPJWT:proof error:error];
    if (!payload) return NO;
    
    // 2. Verify HTTP method matches
    if (![payload[@"htm"] isEqualToString:method]) {
        *error = [NSError errorWithDomain:@"DPoP" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Method mismatch"}];
        return NO;
    }
    
    // 3. Verify URI matches
    if (![payload[@"htu"] isEqualToString:uri]) {
        *error = [NSError errorWithDomain:@"DPoP" code:2 userInfo:@{NSLocalizedDescriptionKey: @"URI mismatch"}];
        return NO;
    }
    
    // 4. Verify timestamp is recent (within 60 seconds)
    NSTimeInterval iat = [payload[@"iat"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (fabs(now - iat) > 60) {
        *error = [NSError errorWithDomain:@"DPoP" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Proof too old"}];
        return NO;
    }
    
    // 5. Check if JTI has been used before (replay protection)
    NSString *jti = payload[@"jti"];
    if ([self hasJTIBeenUsed:jti]) {
        *error = [NSError errorWithDomain:@"DPoP" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Proof already used"}];
        return NO;
    }
    
    // 6. Record JTI as used
    [self recordJTIAsUsed:jti];
    
    return YES;
}
```

## Key Rotation

### Why Key Rotation?

Key rotation is important for:
- **Security** — Limits damage if key is compromised
- **Compliance** — Many standards require regular rotation
- **Flexibility** — Allows changing signing algorithms

### When to Rotate Keys

**Scheduled rotation:** Rotate keys annually as a best practice, even if no compromise is suspected. This limits the window of exposure if a key was compromised without your knowledge.

**Emergency rotation:** Rotate immediately if:
- You suspect your private key was exposed
- A device with stored keys was lost or stolen
- A security vulnerability was discovered in your key storage
- You're migrating to new hardware or security modules

**Algorithm migration:** Rotate when upgrading to newer cryptographic algorithms (e.g., moving from RSA to ECDSA, or from P-256 to a post-quantum algorithm in the future).

### Design Considerations

The AT Protocol's key rotation design balances security with availability:

**Grace period:** Old keys remain valid for verification after rotation. This prevents breaking existing signatures and allows time for the new key to propagate across the network.

**Rotation keys vs. verification keys:** The DID document separates rotation keys (which can update the DID) from verification keys (which sign content). This allows you to rotate verification keys without needing to update rotation keys, reducing the risk of losing control of your DID.

**Audit trail:** Every key rotation is recorded in the PLC audit log, providing a complete history of your identity's cryptographic evolution.

### Key Rotation Flow

```

1. Generate new key pair
2. Publish new public key in DID document
3. Sign commits with new key
4. Old key remains valid for verification
5. After grace period, old key can be revoked
```

### Key Rotation in Code

```objc
// In KeyRotationManager.m
- (void)rotateKeys:(void (^)(NSError *error))completion {
    // 1. Generate new key pair
    NSData *newPrivateKey = [self generatePrivateKey];
    NSData *newPublicKey = [self derivePublicKey:newPrivateKey];
    
    // 2. Create new DID document
    NSDictionary *didDocument = @{
        @"id": self.did,
        @"publicKey": @[
            @{
                @"id": [NSString stringWithFormat:@"%@#key-1", self.did],
                @"type": @"EcdsaSecp256r1VerificationKey2019",
                @"publicKeyPem": [self encodePEM:newPublicKey],
                @"created": [NSDate date]
            }
        ]
    };
    
    // 3. Update DID document in PLC
    [self updateDIDDocument:didDocument completion:^(NSError *error) {
        if (error) {
            completion(error);
            return;
        }
        
        // 4. Store new key
        [self storePrivateKey:newPrivateKey];
        
        // 5. Update signing key
        self.signingKey = newPrivateKey;
        
        completion(nil);
    }];
}
```

## Commit Signing

### Signing a Commit

```objc
// In PDSRepositoryService.m
- (NSString *)signCommit:(NSDictionary *)commit error:(NSError **)error {
    // 1. Encode commit as DAG-CBOR
    NSData *commitData = [ATProtoCBORSerialization encodeObject:commit error:error];
    if (!commitData) return nil;
    
    // 2. Sign with user's private key
    NSData *signature = [self signData:commitData withKey:self.userPrivateKey];
    
    // 3. Encode signature as base64
    NSString *signatureB64 = [self base64Encode:signature];
    
    return signatureB64;
}
```

### Verifying a Commit

```objc
// In PDSRepositoryService.m
- (BOOL)verifyCommitSignature:(NSString *)signature 
                      commit:(NSDictionary *)commit
                   publicKey:(NSData *)publicKey
                       error:(NSError **)error {
    // 1. Encode commit as DAG-CBOR
    NSData *commitData = [ATProtoCBORSerialization encodeObject:commit error:error];
    if (!commitData) return NO;
    
    // 2. Decode signature from base64
    NSData *signatureData = [self base64Decode:signature];
    
    // 3. Verify signature with public key
    return [self verifySignature:signatureData forData:commitData withKey:publicKey];
}
```

## Password Hashing

### Secure Password Storage

```objc
// In PDSAccountService.m
- (NSString *)hashPassword:(NSString *)password error:(NSError **)error {
    // 1. Generate random salt
    NSData *salt = [self generateRandomBytes:16];
    
    // 2. Hash password with salt using PBKDF2
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *hash = [NSMutableData dataWithLength:32];
    
    int result = CCKeyDerivationPBKDF(
        kCCPBKDF2,
        passwordData.bytes,
        passwordData.length,
        salt.bytes,
        salt.length,
        kCCHmacAlgSHA256,
        100000,  // iterations
        hash.mutableBytes,
        hash.length
    );
    
    if (result != kCCSuccess) {
        *error = [NSError errorWithDomain:@"Crypto" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Hash failed"}];
        return nil;
    }
    
    // 3. Combine salt and hash
    NSMutableData *combined = [NSMutableData data];
    [combined appendData:salt];
    [combined appendData:hash];
    
    // 4. Encode as base64
    return [self base64Encode:combined];
}

- (BOOL)verifyPassword:(NSString *)password 
           againstHash:(NSString *)hash
                 error:(NSError **)error {
    // 1. Decode hash from base64
    NSData *combined = [self base64Decode:hash];
    
    // 2. Extract salt and hash
    NSData *salt = [combined subdataWithRange:NSMakeRange(0, 16)];
    NSData *storedHash = [combined subdataWithRange:NSMakeRange(16, 32)];
    
    // 3. Hash provided password with same salt
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *computedHash = [NSMutableData dataWithLength:32];
    
    CCKeyDerivationPBKDF(
        kCCPBKDF2,
        passwordData.bytes,
        passwordData.length,
        salt.bytes,
        salt.length,
        kCCHmacAlgSHA256,
        100000,
        computedHash.mutableBytes,
        computedHash.length
    );
    
    // 4. Compare hashes
    return [storedHash isEqualToData:computedHash];
}
```

## Best Practices

1. **Never log private keys** — Sensitive data
2. **Use secure random** — For nonces and salts
3. **Verify signatures** — Always verify before trusting data
4. **Rotate keys regularly** — Limit exposure window
5. **Use HTTPS** — Protect tokens in transit
6. **Validate timestamps** — Prevent replay attacks
7. **Use constant-time comparison** — Prevent timing attacks

## Next Steps

- **[Application Layer](../03-application-layer/pds-application)** — Service implementation
- **[Authentication](../06-authentication/jwt-tokens)** — Authentication details
- **[Repository Protocol](../07-repository-protocol/repository-basics)** — Repository operations
