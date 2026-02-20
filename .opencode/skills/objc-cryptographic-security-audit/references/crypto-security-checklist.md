# Cryptographic Security Checklist

Use this checklist while validating candidates from `scan_crypto.sh`.

## Weak algorithms
- Verify MD5 is NOT used for security purposes (passwords, signatures, auth).
- Verify SHA1 is NOT used for security purposes (may be OK for checksums).
- Verify no DES, 3DES, RC4, or Blowfish for encryption.
- Confirm AES-256-GCM or ChaCha20-Poly1305 for symmetric encryption.
- Confirm SHA256+ for HMAC and signatures.

## Key management
- Verify no hardcoded encryption keys in source.
- Verify keys are generated with `SecRandomCopyBytes` or `SecKeyGeneratePair`.
- Verify keys are stored in Keychain, not in files or defaults.
- Verify key rotation procedures exist.
- Verify different keys for different purposes (encryption vs signing).

## IV and nonce handling
- Verify IVs are randomly generated per encryption, not hardcoded.
- Verify IVs are never reused with the same key.
- Verify GCM nonces are unique (counter or random).
- Verify IV/nonce is prepended to ciphertext, not stored separately.

## Timing attacks
- Verify secret comparison uses constant-time algorithm.
- Use `CCHmac` with timing-safe comparison for password/token validation.
- Verify no `strcmp`, `memcmp`, or `isEqualToString` for secrets.
- Consider timing-safe comparison for DPoP proof validation.

## Random number generation
- Verify `SecRandomCopyBytes` for all security-sensitive randomness.
- Verify no `rand()`, `random()`, or `srand()` for security contexts.
- `arc4random()` is acceptable for non-crypto purposes.
- Verify token/nonce generation uses crypto-secure random.

## Mode of operation
- Verify no ECB mode for encryption (pattern leakage).
- Verify CBC mode has proper IV handling.
- Prefer GCM or CCM modes (authenticated encryption).
- Verify padding is handled correctly.

## Common fixes
```objc
// BAD: Timing-vulnerable comparison
if ([token isEqualToString:expectedToken]) { ... }

// GOOD: Constant-time comparison via HMAC
uint8_t computedHMAC[CC_SHA256_DIGEST_LENGTH];
CCHmac(kCCHmacAlgSHA256, key, keyLen, token, tokenLen, computedHMAC);
if (memcmp(computedHMAC, expectedHMAC, sizeof(computedHMAC)) == 0) { ... }

// BAD: Insecure random
int code = rand() % 1000000;

// GOOD: Secure random
uint32_t code;
SecRandomCopyBytes(kSecRandomDefault, sizeof(code), (uint8_t *)&code);
code = code % 1000000;
```
