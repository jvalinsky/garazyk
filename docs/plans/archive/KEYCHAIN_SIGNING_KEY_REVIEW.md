# Keychain Signing Key Implementation Review

**Review Date:** January 14, 2026 18:49 EST  
**Updated:** January 14, 2026 18:58 EST (research update)  
**Repository:** `/Users/jack/Software/objpds`  
**Branch:** `main`  
**Commit:** `39608062c9ac081039fed5e9d22cd56ac94421fb`  
**Worktree:** `/Users/jack/Software/objpds`  
**File Reviewed:** `ATProtoPDS/Sources/Database/ActorStore/ActorStore.m`

---

## Summary

The actor signing key implementation in `ActorStore.m` was reviewed against Apple's best practices. Follow-up research revealed important nuances about secp256k1 support on Apple platforms that affect our recommendations.

---

## Research Findings: Apple secp256k1 Limitations

> **Critical Discovery:** Apple's Security framework and CryptoKit do **not** natively support secp256k1. The `kSecAttrKeyTypeECSECPrimeRandom` attribute only supports **NIST P-256 (secp256r1)**, which is a different curve than secp256k1 used by ATProto.

**Implications:**
- Cannot use `kSecClassKey` with native EC key type for secp256k1
- Cannot use Secure Enclave (only supports P-256)
- Must store secp256k1 keys as raw data using `kSecClassGenericPassword`
- Third-party library (our `Secp256k1` wrapper with libsecp256k1) is required

**Sources:**
- Apple Developer Documentation: Secure Enclave only supports 256-bit EC keys (P-256)
- Stack Overflow/GitHub discussions confirm secp256k1 requires external libraries

---

## Issues Found (Revised)

### ✅ Acceptable: Using `kSecClassGenericPassword`

**Location:** Lines 982, 1035, 1044  
**Current Code:**
```objectivec
(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword
```

**Previous Assessment:** Marked as critical issue.

**Revised Assessment:** **This is actually correct** for secp256k1 keys. Since Apple doesn't support secp256k1 natively, we must store the raw 32-byte private key as opaque data. `kSecClassGenericPassword` is the appropriate choice per Apple's documentation on [Storing CryptoKit Keys in the Keychain](https://developer.apple.com/documentation/cryptokit/storing_cryptokit_keys_in_the_keychain) which states keys without `SecKey` corollaries should use generic password storage.

---

### 🔴 Critical: Memory Management Bug (Double Retain)

**Location:** Lines 1010-1013  
**Current Code:**
```objectivec
self.signingKey = (SecKeyRef)keyRef;  // Property setter retains
CFRetain(self.signingKey);             // Second retain - LEAK
CFRelease(keyRef);                      // Only releases original
return self.signingKey;
```

**Problem:** The property assignment already retains the key (assuming `strong` or `assign` with manual retain). Calling `CFRetain` again creates a memory leak.

**Fix:**
```objectivec
self.signingKey = (SecKeyRef)keyRef;
// keyRef is now owned by self.signingKey, no additional retain needed
return self.signingKey;
```

---

### 🔴 Critical: macOS Fallback Uses RSA Instead of secp256k1

**Location:** Lines 1094-1100  
**Current Code:**
```objectivec
NSDictionary *attributes = @{
    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
    (__bridge id)kSecAttrKeySizeInBits: @(2048),
    ...
};
```

**Problem:** The non-GNUstep (macOS) code path generates RSA 2048-bit keys instead of secp256k1 EC keys. This breaks compatibility with ATProto which requires secp256k1 signatures.

**Fix:** Use consistent secp256k1 key generation via `Secp256k1KeyPair`:
```objectivec
Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
```

---

### 🟡 Medium: Missing Application Tag

**Location:** Lines 981-987, 1043-1049  
**Current Code:** No `kSecAttrApplicationTag` specified.

**Problem:** Without a unique tag, keys are only identified by service/account. Best practice recommends a unique application-specific tag for reliable key lookup.

**Best Practice:**
```objectivec
(__bridge id)kSecAttrApplicationTag: [@"com.atproto.pds.signingkey" dataUsingEncoding:NSUTF8StringEncoding]
```

---

### 🟡 Medium: No Secure Enclave Option

**Location:** Key generation (lines 1071-1092)

**Problem:** Private keys are stored in software Keychain only. For iOS devices and Apple Silicon Macs, the Secure Enclave provides hardware-backed key protection where private keys never leave the secure hardware.

**Best Practice (optional enhancement):**
```objectivec
(__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave
```

Note: Secure Enclave only supports P-256, not secp256k1. This is informational only.

---

### 🟢 Low: Inconsistent Key Return Semantics

**Location:** Lines 964-1014  
**Current Code:**
```objectivec
if (self.signingKey) {
    CFRetain(self.signingKey);  // Caller must release
    return self.signingKey;
}
```

**Observation:** The caller is expected to release the returned `SecKeyRef`. This follows Core Foundation "Create Rule" semantics but should be documented in the header with `CF_RETURNS_RETAINED` or similar annotation.

---

## Recommended Fixes (Updated)

| Priority | Fix | Location | Status |
|----------|-----|----------|--------|
| 🔴 P0 | Remove double CFRetain | Line 1011 | **Action Required** |
| 🔴 P0 | Use secp256k1 on macOS fallback | Lines 1094-1100 | **Action Required** |
| ~~🔴 P1~~ | ~~Change to `kSecClassKey`~~ | ~~Lines 982, 1035, 1044~~ | **Not Needed** - secp256k1 not supported |
| 🟡 P2 | Add `kSecAttrApplicationTag` | Key queries | Recommended |
| 🟢 P3 | Document return semantics | Header file | Optional |
| ℹ️ Info | Secure Enclave | N/A | Not possible (secp256k1 unsupported) |

---

## References

- [Apple: Storing Keys in the Keychain](https://developer.apple.com/documentation/security/storing_keys_in_the_keychain)
- [Apple: Storing CryptoKit Keys in the Keychain](https://developer.apple.com/documentation/cryptokit/storing_cryptokit_keys_in_the_keychain)
- [Apple: Protecting Keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting_keys_with_the_secure_enclave)
- [Apple: SecKeyRef](https://developer.apple.com/documentation/security/seckeyref)

---

## Appendix: File Locations

| Component | Path |
|-----------|------|
| ActorStore implementation | `ATProtoPDS/Sources/Database/ActorStore/ActorStore.m` |
| ActorStore header | `ATProtoPDS/Sources/Database/ActorStore/ActorStore.h` |
| Secp256k1 wrapper | `ATProtoPDS/Sources/Auth/Secp256k1.m` |
| Key generation (GNUstep) | Lines 1071-1092 |
| Key generation (macOS) | Lines 1093-1150 |
| Key storage | Lines 1017-1069 |
| Key retrieval | Lines 964-1014 |

---

## Related Documentation

- [Archive Index](./README.md) - Index of all archived plans
- [Current Plans](../README.md) - Active implementation plans
- [Security Docs](../../security/README.md) - Security-related documentation
