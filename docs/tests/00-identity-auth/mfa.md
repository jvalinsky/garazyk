---
title: MFA Tests
---

# MFA Tests

Tests for multi-factor authentication including TOTP, WebAuthn/Passkeys, and YubiKey.

## Test Classes

### TOTPTests
**File:** `Tests/Auth/TOTPTests.m`

**Purpose:** TOTP (Time-based One-Time Password) generation and verification per RFC 6238.

#### How It Works

**Base32 encoding/decoding** (RFC 4648):

```objc
NSDictionary *testCases = @{
    @"": @"",
    @"f": @"MY======",
    @"fo": @"MZXQ====",
    @"foobar": @"MZXW6YTBOI======"
};

NSData *data = [@"foobar" dataUsingEncoding:NSUTF8StringEncoding];
NSString *result = [Base32Utils base32StringFromData:data];
XCTAssertEqualObjects(result, @"MZXW6YTBOI======");
```

**TOTP generation:**

```objc
NSData *secretData = [@"12345678901234567890" dataUsingEncoding:NSUTF8StringEncoding];
TOTPGenerator *gen = [[TOTPGenerator alloc] initWithSecret:secretData];

NSString *code = [gen generateOTP];
XCTAssertEqual(code.length, 6, @"Default is 6 digits");

// Same code within same time window
NSString *code2 = [gen generateOTP];
XCTAssertEqualObjects(code, code2, @"Consistent within interval");
```

**Time window tolerance:**

```objc
NSString *code = [gen generateOTP];
XCTAssertTrue([TOTPService verifyCode:code secret:base32Secret]);

// Previous interval also valid (within window)
NSDate *prevDate = [NSDate dateWithTimeIntervalSinceNow:-30];
NSString *prevCode = [gen generateOTPForDate:prevDate];
XCTAssertTrue([TOTPService verifyCode:prevCode secret:base32Secret]);
```

#### Why It Matters

| Feature | Security Property |
|---------|-------------------|
| Time-based codes | Codes expire after 30 seconds |
| Window tolerance | Clock skew handling |
| 6-digit default | Balance of security and usability |

**TOTP prevents replay attacks** - a captured code is useless after 30-60 seconds.

| Method | What It Verifies |
|--------|------------------|
| `testBase32Encoding` | RFC 4648 compliance |
| `testTOTPGeneration` | Consistent codes per interval |
| `testTOTPServiceVerification` | Time window tolerance |

---

### WebAuthnVerifierTests
**File:** `Tests/Auth/WebAuthnVerifierTests.m`

**Purpose:** WebAuthn/Passkey registration and assertion verification per W3C spec.

#### How It Works

**Registration verification:**

```objc
// Construct attestation object
NSMutableData *authData = [NSMutableData dataWithLength:37];
uint8_t *bytes = authData.mutableBytes;
bytes[32] = 0x40; // Flag: has attested credential data

// Append credential ID and public key
[authData appendData:aaguid];
[authData appendBytes:&credLen length:2];
[authData appendData:credentialId];
[authData appendData:publicKey];

NSDictionary *result = [WebAuthnVerifier verifyRegistrationResponse:response
                                                          challenge:challenge
                                                             origin:origin
                                                              error:&error];
XCTAssertEqualObjects(result[@"credentialId"], credentialId);
```

**Authenticator data structure:**

```

Bytes 0-31:   RP ID hash (SHA-256)
Byte 32:      Flags (0x40 = attested credential data present)
Bytes 33-36:  Sign counter
Bytes 37-52:  AAGUID
Bytes 53-54:  Credential ID length
Bytes 55+:    Credential ID + Public key
```

#### Why It Matters

| Check | Purpose |
|-------|---------|
| `type: webauthn.create` | Registration vs assertion |
| `type: webauthn.get` | Assertion verification |
| Challenge verification | Prevents replay attacks |
| Origin verification | Prevents phishing |

**WebAuthn is phishing-resistant** - credentials are bound to origin.

| Method | What It Verifies |
|--------|------------------|
| `testRegistrationSuccessParsesAuthData` | Correct parsing |
| `testRegistrationRejectsMissingAuthData` | Error 1006 |
| `testRegistrationRejectsShortAuthData` | Error 1007 |
| `testAssertionRejectsInvalidType` | Wrong type rejected |

---

### YubiKeyOATHTests
**File:** `Tests/Auth/YubiKeyOATHTests.m`

**Purpose:** YubiKey OATH manager with software TOTP fallback.

#### How It Works

```objc
TOTPService *service = [[TOTPService alloc] initWithSecret:secretData];

// Hardware unavailable - falls back to software
NSString *token = [service generateTOTPToken:&error];
XCTAssertNotNil(token);
XCTAssertEqual(token.length, 6);

// Hardware-specific operations
BOOL success = [service setOATHSecret:secret error:&error];
XCTAssertFalse(success, @"Hardware operations return NotImplemented");
```

#### Why It Matters

Hardware security keys provide superior protection, but software fallback ensures functionality when hardware is unavailable.

| Method | What It Verifies |
|--------|------------------|
| `testSoftwareTotpFallbackProducesToken` | Fallback works |
| `testSetOATHSecretNotImplemented` | Hardware gracefully degrades |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/TOTPTests
./build/tests/AllTests -only-testing:AllTests/WebAuthnVerifierTests
./build/tests/AllTests -only-testing:AllTests/YubiKeyOATHTests
```

## MFA Flow

```

1. Registration:
   User presents WebAuthn credential OR TOTP secret
   Server stores credential ID / secret

2. Verification:
   User provides OTP from authenticator
   Server validates against stored credential

3. Fallback:
   Software TOTP when hardware unavailable
```

## Related Documentation

- [Folder README](README) - Identity & authentication tests overview
- [Test Index](../README) - Main test documentation index
- [OAuth2 Documentation](../../oauth2/README) - OAuth2 flows
- [Security Hardening](../05-security/hardening) - Production security
- [Security Tests](../05-security/README) - Security test documentation
