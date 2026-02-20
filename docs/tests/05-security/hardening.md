# Security Hardening Tests

Tests for input validation, CBOR security, and production hardening.

## Test Classes

### ProductionSecurityTests
**File:** `Tests/Security/ProductionSecurityTests.m`

**Purpose:** Production security hardening including admin auth and handle restrictions.

#### How It Works

Integration tests against production security components (`PDSAuthzManager`, `ATProtoHandleValidator`):

```objc
// Test that heuristic admin auth is removed
PDSAuthzManager *authz = [[PDSAuthzManager alloc] initWithAdminDIDs:@[]];
BOOL allowed = [authz isAuthorizedForAdminOperation:request error:&error];
XCTAssertFalse(allowed, @"Should reject heuristic-based admin auth");
XCTAssertNotNil(error, @"Should return error explaining rejection");
```

#### Why It Matters

**Privilege Escalation Prevention:** Old heuristic-based admin auth (e.g., "if handle starts with 'admin.'") was a security hole. Only JWT-based authentication with explicit admin DID whitelist is now allowed.

**Reserved Namespace Protection:** Prevents impersonation attacks where someone registers `admin.example.com` to appear official.

| Method | Security Property |
|--------|-------------------|
| `testAdminAuthHardening` | JWT required, no heuristics |
| `testHandleReservation` | `admin.*` handles rejected |

---

### CBORSecurityTests
**File:** `Tests/Security/CBORSecurityTests.m`

**Purpose:** CBOR decoder robustness against malicious input.

#### How It Works

**Direct binary crafting** - Tests construct malicious CBOR payloads at the byte level:

```objc
// Create deeply nested array (10000 levels)
NSMutableData *data = [NSMutableData data];
for (int i = 0; i < 10000; i++) {
    uint8_t arrayStart = 0x9F; // indefinite array
    [data appendBytes:&arrayStart length:1];
}
// No crash = test passes
CBORValue *decoded = [CBORValue decodeFromData:data error:nil];
```

**Timing assertions** detect DoS vectors:

```objc
CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
CBORValue *decoded = [CBORValue decodeFromData:maliciousData error:nil];
CFAbsoluteTime duration = CFAbsoluteTimeGetCurrent() - start;
XCTAssertNil(decoded, @"Should reject oversized allocation");
XCTAssertLessThan(duration, 1.0, @"Must fast-fail, not allocate 4GB");
```

#### Why It Matters

| Attack Vector | Test | Defense |
|---------------|------|---------|
| Stack overflow | `testDeeplyNestedArrays` | Recursive depth limiting |
| Memory exhaustion | `testLargeArrayAllocation` | Lazy parsing, no pre-allocation |
| Buffer overread | `testBufferOverread` | Bounds checking on all reads |

**CBOR "zip bombs"** claim huge array/map sizes but have minimal data. A naive decoder would allocate 4GB for a payload claiming `UINT32_MAX` elements. The test verifies fast-fail behavior.

| Method | What It Verifies |
|--------|------------------|
| `testDeeplyNestedArrays` | No crash on 10000-deep nesting |
| `testDeeplyNestedMaps` | No crash on 10000-deep maps |
| `testLargeArrayAllocation` | Fast-fail for UINT32_MAX elements |
| `testLargeMapAllocation` | Fast-fail for huge maps |
| `testBufferOverread` | Truncated data returns nil, not crash |

---

### PDSInputValidatorTests
**File:** `Tests/Security/PDSInputValidatorTests.m`

**Purpose:** Input sanitization for all external inputs.

#### How It Works

**Singleton pattern** with programmatic malicious input construction:

```objc
PDSInputValidator *validator = [PDSInputValidator sharedValidator];

// SQL injection test
NSError *error = nil;
NSString *result = [validator sanitizeSQLInput:@"1; DROP TABLE users" error:&error];
XCTAssertNil(result, @"SQL injection should be rejected");
XCTAssertNotNil(error);

// Path traversal test
result = [validator sanitizePathInput:@"../etc/passwd" error:&error];
XCTAssertNil(result, @"Path traversal should be rejected");

// Null byte injection
BOOL valid = [validator stringContainsNullBytes:@"hello\x00world"];
XCTAssertTrue(valid, @"Null bytes should be detected");
```

#### Why It Matters

| Injection Type | Test | Consequence if Missed |
|----------------|------|----------------------|
| SQL | `testSanitizeSQLInput` | Database compromise |
| Path traversal | `testSanitizePathInput` | Arbitrary file read/write |
| XSS | `testSanitizeJSONField` | Client-side script execution |
| Null byte | `testNullByteDetection` | C string truncation, bypass filters |

**Null-byte attacks** exploit C string semantics. `"admin\x00evil"` becomes `"admin"` when passed to C APIs, potentially bypassing checks.

| Method | What It Verifies |
|--------|------------------|
| `testIdentifierValidationBasics` | NSID/DID/handle/AT-URI format |
| `testNullByteDetection` | Detect embedded nulls |
| `testSanitizeSQLInput` | SQL injection blocked |
| `testSanitizePathInput` | Path traversal blocked |
| `testSanitizeJSONField` | XSS prevention |
| `testLimitAndCursorValidation` | Pagination bounds |

---

### SecurityHardeningTests
**File:** `Tests/Network/SecurityHardeningTests.m`

**Purpose:** Token rotation and DPoP nonce security.

#### How It Works

Tests the complete token lifecycle with rotation verification:

```objc
// Store original token
NSString *originalRefreshToken = session.refreshToken;

// Perform refresh
[self.server refreshAccessToken:originalRefreshToken completion:^(NSString *accessToken, NSError *error) {
    // Token should have changed
    XCTAssertNotEqualObjects(session.refreshToken, originalRefreshToken);
    
    // Old token should no longer work
    [self.server refreshAccessToken:originalRefreshToken completion:^(NSString *token, NSError *error) {
        XCTAssertNotNil(error, @"Old token should be revoked");
    }];
}];
```

#### Why It Matters

**Token rotation** is the primary defense against refresh token theft. If an attacker steals a token:
1. They can use it once
2. The legitimate client's next refresh fails
3. The legitimate client detects the breach

| Method | Security Property |
|--------|-------------------|
| `testRefreshTokenRotation` | Tokens rotate on each use |
| `testDPoPNonceChallenge` | Server issues nonce challenges |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ProductionSecurityTests
./build/tests/AllTests -only-testing:AllTests/CBORSecurityTests
./build/tests/AllTests -only-testing:AllTests/PDSInputValidatorTests
./build/tests/AllTests -only-testing:AllTests/SecurityHardeningTests
```

## Security Checklist

- [ ] Input validation on all external data
- [ ] SQL injection prevention  
- [ ] Path traversal prevention
- [ ] XSS prevention in JSON
- [ ] CBOR parser hardening (depth limits, lazy allocation)
- [ ] Token rotation
- [ ] DPoP nonce challenges
- [ ] Null-byte detection
