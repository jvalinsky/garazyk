# Security & Crypto Compatibility

## The Problem
`objpds` imports `<Security/Security.h>` in critical files:
- `ActorStore.m`
- `KeyManager.h`
- `WebAuthnVerifier.m`
- `CryptoUtils.m`

It uses APIs like:
- `SecKeyRef`
- `SecRandomCopyBytes`
- `kSecAttr...` (Keychain constants)
- `CommonCrypto` (likely via standard headers or `Compat` layer).

## GNUstep Status
GNUstep does **NOT** have a `Security.framework`. There is no direct equivalent.

## Solution Strategy

### 1. `Compat/Security.h` Shim
We must create a header `Sources/Compat/Security.h` that mimics the Apple Security API just enough to compile.

**Example Shim Content:**
```c
#if defined(GNUSTEP)
#include <openssl/rand.h>

// Typedefs to opaque pointers or void*
typedef void* SecKeyRef;
typedef void* SecItemRef;

// Constants
static const void* kSecAttrLabel = "label";

// Functions
static inline int SecRandomCopyBytes(void *ignored, size_t count, uint8_t *bytes) {
    return RAND_bytes(bytes, (int)count) == 1 ? 0 : -1;
}
#endif
```

### 2. Crypto Implementation
For declared methods that actually *do* crypto (signing, verifying), we cannot just stub them. We need a backend.
- **OpenSSL**: The standard on Linux. `gnustep-base` usually links against it.
- **Implementation**: In `.m` files, we might need `#ifdef GNUSTEP` blocks that call OpenSSL functions directly instead of `SecKeyRawSign`.

### 3. Usage Audit
- **`WebAuthnVerifier`**: Likely uses `SecKey` to verify signatures. This is complex to port. Does it use `SecKeyVerifySignature`?
- **`CryptoUtils`**: Likely wrappers around hashing/signing.

**Recommendation**:
Start by stubbing types to fix compilation. Then, method functions that return `unimplemented` errors. Finally, implement actual OpenSSL bridges for the specific algorithms used (likely ES256/P256).
