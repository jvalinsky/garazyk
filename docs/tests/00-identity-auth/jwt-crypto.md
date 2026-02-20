# JWT & Cryptography Tests

Tests for JSON Web Token handling, cryptographic primitives, and key management.

## Test Classes

### JWTTests
**File:** `Tests/Auth/JWTTests.m`

**Purpose:** JWT parsing, creation, signing, and verification with ES256K (secp256k1).

#### How It Works

**Key pair generation** for signing:

```objc
self.minter = [[JWTMinter alloc] init];
self.minter.signingAlgorithm = @"ES256K";
Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
self.minter.privateKey = keyPair.privateKey;
self.verifier.publicKey = keyPair.publicKey;
```

**Token verification flow:**

```objc
// Create signed token
NSDictionary *payload = @{
    @"sub": @"did:plc:user",
    @"iss": @"test.issuer",
    @"aud": @"test.audience",
    @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970])
};
NSString *token = [self.minter signPayload:payload error:nil];

// Parse and verify
JWT *jwt = [JWT jwtWithToken:token error:nil];
BOOL verified = [self.verifier verifyJWT:jwt error:nil];
XCTAssertTrue(verified);
```

**Algorithm enforcement:**

```objc
// Create unsigned JWT with "none" algorithm
JWTHeader *header = [[JWTHeader alloc] init];
header.alg = @"none";
JWT *jwt = [JWT jwtWithHeader:header payload:payload signature:@"" error:nil];

self.verifier.allowedAlgorithms = @[@"RS256", @"ES256"];
BOOL verified = [self.verifier verifyJWT:jwt error:&error];
XCTAssertFalse(verified, @"'none' algorithm must be rejected");
```

#### Why It Matters

| Property | How It's Enforced |
|----------|-------------------|
| Issuer verification | `expectedIssuer` must match `iss` claim |
| Audience verification | `expectedAudience` must match `aud` claim |
| Expiration | `exp` claim checked against current time |
| Not-before | `nbf` claim prevents early token use |
| Algorithm restriction | `allowedAlgorithms` prevents `none` attack |

**The `none` algorithm attack** is a classic JWT vulnerability where an attacker sets `alg: none` to bypass signature verification.

| Method | What It Verifies |
|--------|------------------|
| `testJWTVerificationWithValidToken` | Happy path |
| `testJWTVerificationWithExpiredToken` | `exp` enforcement |
| `testJWTVerificationRejectsNoneAlgorithm` | Algorithm restriction |
| `testJWTNotBeforeClaim` | `nbf` enforcement |

---

### CryptoTests
**File:** `Tests/Auth/CryptoTests.m`

**Purpose:** Core cryptographic primitives (SHA256, HMAC, random bytes) with test vectors.

#### How It Works

**RFC 4231 test vectors** ensure correct HMAC implementation:

```objc
// RFC 4231 Test Case 1
const unsigned char keyBytes[] = {0x0b, 0x0b, 0x0b, ...}; // 20 bytes of 0x0b
NSData *key = [NSData dataWithBytes:keyBytes length:20];
NSData *data = [@"Hi There" dataUsingEncoding:NSUTF8StringEncoding];
NSData *hmac = [CryptoUtils hmacSHA256WithKey:key data:data];

NSString *hex = [CryptoUtils hexStringFromData:hmac];
XCTAssertEqualObjects(hex, @"b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
```

**Randomness verification:**

```objc
NSData *r1 = [CryptoUtils randomBytes:16];
NSData *r2 = [CryptoUtils randomBytes:16];
XCTAssertNotEqualObjects(r1, r2, @"Random bytes must be unique");
```

#### Why It Matters

| Primitive | Use Case |
|-----------|----------|
| SHA-256 | CID computation, password hashing |
| HMAC-SHA256 | Message authentication, DPoP |
| Random bytes | Session IDs, nonces, salts |

Using RFC test vectors ensures cross-implementation compatibility.

---

### KeyManagerSecurityTests
**File:** `Tests/Auth/KeyManagerSecurityTests.m`

**Purpose:** Validates JWK encoding uses proper base64url without padding.

#### How It Works

```objc
// JWK components must use base64url encoding
JWK *jwk = [keyManager exportPublicKeyAsJWK];

// Verify no padding characters
XCTAssertFalse([jwk.n containsString:@"+"], @"No + in base64url");
XCTAssertFalse([jwk.n containsString:@"/"], @"No / in base64url");
XCTAssertFalse([jwk.n containsString:@"="], @"No padding in base64url");
```

#### Why It Matters

JWKs are embedded in JWTs. Padding characters would break URL-safe encoding required by the spec.

---

### PDSOpenSSLKeyManagerTests
**File:** `Tests/Auth/PDSOpenSSLKeyManagerTests.m`

**Purpose:** OpenSSL-based key manager for Linux/GNUstep compatibility.

#### How It Works

```objc
// Generate secp256k1 key
NSData *privateKey = [keyManager generatePrivateKey];

// Export as compressed public key (33 bytes)
NSData *publicKey = [keyManager publicKeyFromPrivateKey:privateKey];
XCTAssertEqual(publicKey.length, 33);

// Create did:key from compressed key
NSString *didKey = [keyManager didKeyFromPublicKey:publicKey];
XCTAssertTrue([didKey hasPrefix:@"did:key:z"]);
```

#### Why It Matters

macOS uses Security.framework, but Linux/GNUstep needs OpenSSL. Tests ensure both paths produce identical keys.

---

### PDSReplayCacheTests
**File:** `Tests/Auth/PDSReplayCacheTests.m`

**Purpose:** SQLite-backed replay cache for JWT JTI deduplication.

#### How It Works

```objc
PDSReplayCache *cache = [[PDSReplayCache alloc] initWithDatabasePath:dbPath];

// First use - accepted
BOOL seen = [cache checkAndRecordJTI:@"unique-id-123" expiration:3600 error:nil];
XCTAssertFalse(seen, @"First use should succeed");

// Replay - rejected
seen = [cache checkAndRecordJTI:@"unique-id-123" expiration:3600 error:nil];
XCTAssertTrue(seen, @"Replay should be detected");
```

#### Why It Matters

JWTs with `jti` claim can only be used once within their expiration window. Without replay protection, an attacker could replay a captured token.

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/JWTTests
./build/tests/AllTests -only-testing:AllTests/CryptoTests
./build/tests/AllTests -only-testing:AllTests/PDSReplayCacheTests
```

## Security Considerations

1. **Algorithm Restriction**: Never accept `none` algorithm
2. **Claim Validation**: Always verify `iss`, `aud`, `exp`, `nbf`
3. **Replay Protection**: Use JTI cache to prevent token replay
4. **Key Derivation**: Derive public key from private for consistency

## Related Documentation

- [Folder README](README.md) - Identity & authentication tests overview
- [Test Index](../README.md) - Main test documentation index
- [OAuth2 Token Management](../../oauth2/token-management.md) - Token lifecycle
- [OAuth2 Security](../../oauth2/security.md) - OAuth2 security model
- [Security Hardening Tests](../05-security/hardening.md) - Token security testing
- [Repository Tests](../01-repository/README.md) - MST signing with secp256k1
