# Cryptography Implementation Strengthening Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Strengthen the cryptography implementation across the ATProtoPDS codebase to eliminate weak algorithms, improve key management, and ensure compliance with modern security standards.

**Architecture:** Audit existing cryptographic usage, identify weaknesses (SHA-1, weak algorithms), implement stronger alternatives (SHA-256, AES-GCM), and add proper key rotation and validation. Focus on JWT signing, password hashing, and data encryption.

**Tech Stack:** Objective-C, CommonCrypto framework, secp256k1 library.

## Current Cryptography Assessment

**Existing Implementation:**
- Password hashing: SHA-256 with salt (basic implementation)
- JWT signing: RS256, ES256 algorithms supported
- Key management: Basic key generation via secp256k1
- HMAC: SHA-1 based (potentially weak)

**Identified Issues:**
- HMAC-SHA1 usage (should be SHA-256)
- No explicit algorithm validation in some areas
- Key rotation not implemented
- No entropy validation for random generation

## Implementation Tasks

### Task 1: Upgrade HMAC Implementation from SHA-1 to SHA-256
**Files:**
- Modify: `ATProtoPDS/Sources/Auth/CryptoUtils.m`
- Test: `ATProtoPDS/Tests/Auth/CryptoTests.m`

**Current Issue:** `HMACSHA1` method uses SHA-1, which is cryptographically weak.

**Step 1: Add HMAC-SHA256 method**
```objective-c
+ (NSData *)HMACSHA256:(NSData *)data key:(NSData *)key {
    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, hmac);
    return [NSData dataWithBytes:hmac length:CC_SHA256_DIGEST_LENGTH];
}
```

**Step 2: Update existing HMAC usage**
Find and replace `HMACSHA1` calls with `HMACSHA256` in:
- Admin authentication
- TOTP generation
- Any other HMAC usage

**Step 3: Add test for HMAC-SHA256**
```objective-c
- (void)testHMACSHA256 {
    NSData *key = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [@"message" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hmac = [CryptoUtils HMACSHA256:data key:key];
    XCTAssertNotNil(hmac);
    XCTAssertEqual(hmac.length, CC_SHA256_DIGEST_LENGTH);
}
```

### Task 2: Implement Argon2 Password Hashing
**Files:**
- Modify: `ATProtoPDS/Sources/App/PDSController.m` (hashPassword method)
- Test: `ATProtoPDS/Tests/Database/PDSControllerTests.m`

**Current Issue:** Simple SHA-256 hashing is insufficient for passwords.

**Step 1: Implement Argon2id password hashing**
```objective-c
- (NSData *)hashPasswordArgon2:(NSString *)password salt:(NSData *)salt {
    // Use CommonCrypto PBKDF2 as Argon2 substitute until proper library available
    // Parameters: 10000 iterations, 256-bit output
    NSMutableData *derivedKey = [NSMutableData dataWithLength:32];
    CCKeyDerivationPBKDF(kCCPBKDF2, password.UTF8String, password.length,
                        salt.bytes, salt.length, kCCPRFHmacAlgSHA256,
                        10000, derivedKey.mutableBytes, derivedKey.length);
    return derivedKey;
}
```

**Step 2: Update password verification**
Modify password verification to use new hashing method.

**Step 3: Add migration for existing passwords**
Implement gradual migration of existing SHA-256 hashes to Argon2.

### Task 3: Implement Key Rotation Framework
**Files:**
- Create: `ATProtoPDS/Sources/Auth/KeyRotationManager.h`
- Create: `ATProtoPDS/Sources/Auth/KeyRotationManager.m`
- Modify: `ATProtoPDS/Sources/Auth/JWT.m`
- Test: `ATProtoPDS/Tests/Auth/KeyRotationTests.m`

**Step 1: Create KeyRotationManager class**
```objective-c
@interface KeyRotationManager : NSObject
- (instancetype)initWithKeyStore:(id)keyStore;
- (SecKeyRef)currentSigningKey;
- (NSArray<SecKeyRef> *)allValidKeys;
- (BOOL)rotateKeys;
@end
```

**Step 2: Integrate with JWT signing**
Modify JWT.m to use KeyRotationManager for key selection.

**Step 3: Add key rotation API endpoint**
Create admin endpoint for manual key rotation.

### Task 4: Strengthen Random Number Generation
**Files:**
- Modify: `ATProtoPDS/Sources/Auth/CryptoUtils.m`
- Test: `ATProtoPDS/Tests/Auth/CryptoTests.m`

**Current Issue:** Basic random byte generation may not be cryptographically secure.

**Step 1: Use SecRandomCopyBytes for cryptographic randomness**
```objective-c
+ (NSData *)secureRandomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes) != 0) {
        return nil; // Fallback to less secure method if needed
    }
    return data;
}
```

**Step 2: Update salt generation**
Replace `generateSalt` method with secure random generation.

**Step 3: Add entropy validation test**
```objective-c
- (void)testSecureRandomGeneration {
    NSData *random1 = [CryptoUtils secureRandomBytes:32];
    NSData *random2 = [CryptoUtils secureRandomBytes:32];
    XCTAssertNotNil(random1);
    XCTAssertNotNil(random2);
    XCTAssertFalse([random1 isEqualToData:random2]); // Should be unique
}
```

### Task 5: Implement Certificate Pinning for HTTPS
**Files:**
- Create: `ATProtoPDS/Sources/Network/SSLPinningManager.h`
- Create: `ATProtoPDS/Sources/Network/SSLPinningManager.m`
- Modify: `ATProtoPDS/Sources/Network/HttpServer.m`
- Test: `ATProtoPDS/Tests/Network/SSLPinningTests.m`

**Step 1: Create SSL pinning manager**
Implement certificate pinning for external HTTPS connections.

**Step 2: Integrate with HttpServer**
Add pinning validation to outgoing HTTPS requests.

**Step 3: Add pinning bypass for development**
Include configuration option to disable pinning in development.

## Testing Strategy

### Unit Tests
- Test each cryptographic function individually
- Verify algorithm outputs match expected values
- Test edge cases and error conditions

### Integration Tests
- End-to-end JWT signing/verification with new algorithms
- Password hashing/verification flow
- Key rotation scenarios

### Security Testing
- Algorithm strength validation
- Timing attack resistance
- Memory safety verification

## Migration Strategy

**Backward Compatibility:**
- Existing SHA-256 passwords will be migrated gradually
- Old HMAC-SHA1 signatures remain valid during transition
- JWT verification accepts both old and new algorithms

**Rollback Plan:**
- Feature flags to disable new cryptography
- Database migration rollback scripts
- Configuration to revert to old algorithms

## Security Compliance

**Target Standards:**
- NIST SP 800-63B (Password Hashing)
- RFC 8725 (SHA-256 for HMAC)
- OWASP Cryptographic Storage Cheat Sheet

**Audit Trail:**
- All cryptographic operations logged with security level
- Key rotation events tracked
- Failed decryption attempts monitored

## Performance Considerations

**Expected Impact:**
- Password hashing: ~10x slower (acceptable for security)
- HMAC operations: Minimal impact
- JWT verification: No significant change
- Key rotation: Occasional background operation

## Implementation Timeline

| Task | Estimated Effort | Risk Level |
|------|------------------|------------|
| HMAC Upgrade | Low (2 hours) | Low |
| Argon2 Passwords | Medium (4 hours) | Medium |
| Key Rotation | High (8 hours) | Medium |
| Secure Random | Low (1 hour) | Low |
| SSL Pinning | Medium (4 hours) | Low |

**Total Estimated Effort:** 19 hours
**Priority:** P1 (Security hardening)

---

## Related Documentation

- [Archive Index](./README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Security Docs](../../security/README) - Security-related documentation</content>
<parameter name="filePath">docs/plans/2026-01-09-cryptography-strengthening.md