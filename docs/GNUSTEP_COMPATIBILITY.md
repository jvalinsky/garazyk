# GNUstep Compatibility Research

**Date:** January 12, 2026
**Purpose:** Document GNUstep Foundation framework compatibility with Apple Cocoa APIs

## Executive Summary

GNUstep implements most of Apple's Foundation framework (from OpenStep/Cocoa), but **lacks several macOS-specific frameworks**:
- ✅ **NSLog** - Full support, including `%@` format specifiers
- ❌ **os/log.h** - NOT implemented (Apple's unified logging API)
- ❌ **Security framework** - NOT implemented (SecKeyRef, SecRandom, etc.)
- ❌ **CommonCrypto** - NOT implemented (but OpenSSL provides equivalent functionality)
- ✅ **Foundation (core)** - Full support via GNUstepBase

## GNUstep Foundation vs Apple Foundation

### Fully Implemented (No Compat Needed)

| Class/Framework | Status | Notes |
|-----------------|--------|-------|
| **NSLog** | ✅ FULL | Supports `%@` object formatting via `NSString stringWithFormat:` |
| **NSString** | ✅ FULL | All NSString methods |
| **NSArray/NSDictionary** | ✅ FULL | All collection methods |
| **NSData** | ✅ FULL | Most methods (some edge cases differ) |
| **NSURLConnection** | ✅ FULL | HTTP client support |
| **NSURLRequest** | ✅ FULL | Request configuration |
| **NSURLResponse** | ✅ FULL | Response handling |
| **NSError** | ✅ FULL | Error domain support |
| **NSThread** | ✅ FULL | Thread management |
| **NSNotification** | ✅ FULL | Notification center |
| **NSDate/NSCalendar** | ✅ FULL | Date handling |
| **NSInvocation** | ✅ FULL | Message forwarding |
| **NSCoder/NSKeyedArchiver** | ✅ FULL | Serialization |
| **NSBundle** | ✅ FULL | Resource loading |
| **NSProcessInfo** | ✅ FULL | Process information |
| **NSLock/NSRecursiveLock** | ✅ FULL | Synchronization |
| **dispatch_queue_t** | ✅ FULL | GCD via libdispatch |

### Partially Implemented / Apple-Only

| Class/Framework | Status | Workaround |
|-----------------|--------|------------|
| **NSURLSession** | ⚠️ DECL | Forward declarations only - use NSURLConnection |
| **os/log_t** | ❌ NONE | Use NSLog or custom wrapper |
| **os_log_create()** | ❌ NONE | Return dummy pointer, use NSLog macros |
| **Security/SecKeyRef** | ❌ NONE | OpenSSL EVP_PKEY for crypto operations |
| **SecRandom** | ❌ NONE | arc4random_buf() for random bytes |
| **CommonCrypto** | ❌ NONE | OpenSSL equivalents (EVP, HMAC, PBKDF2) |
| **os_trace.h** | ❌ NONE | Use NSLog for tracing |
| **XCTest** | ❌ NONE | Apple-only - no GNUstep equivalent |

## Compat Layer Architecture

Our compat layer is structured in two locations to handle both system-level and application-level compatibility:

```
Sources/Compat/
├── os/log.h              # os_log_t polyfill using NSLog
├── Security/Security.h   # SecKeyRef typedef
├── CommonCrypto/
│   ├── CommonCrypto.h    # Header aggregator
│   ├── CommonDigest.h    # SHA/MD5 via OpenSSL
│   ├── CommonHMAC.h      # HMAC via OpenSSL
│   └── CommonKeyDerivation.h  # PBKDF2 via OpenSSL
└── GNUstepBase/          # GNUstep-specific headers
    └── (used via Foundation.h)

ATProtoPDS/Sources/Compat/
├── Foundation/
│   ├── Foundation.h      # Routes to GNUstepBase on Linux
│   └── NSErrorCompat.h   # Routes to GNUstepBase on Linux
├── Security/
│   ├── Security.h        # Includes SecRandom.h on Linux
│   ├── SecKey.h          # SecKeyWrapper implementation
│   └── SecRandom.h       # SecRandomCopyBytes via arc4random_buf
└── PDSTypes.h            # Platform-specific type definitions
```

## os/log.h Compatibility Details

### Problem
Apple's `os/log.h` provides structured logging with:
- `os_log_t` type for log handles
- `os_log_create(subsystem, category)` factory
- `os_log()`, `os_log_info()`, `os_log_error()` macros
- Support for private/auto data in format strings

GNUstep has NO equivalent API.

### Solution
We provide a compat layer that:

```objc
// On Apple - uses real os/log.h
// On Linux - uses our compat layer
```

The compat layer:
1. Defines `os_log_t` as `void*`
2. Defines `OS_LOG_DEFAULT` as sentinel value
3. Provides `os_log_create()` that returns dummy handle
4. Maps macros to `NSLog()` with prefix for identification

### Important Note: %@ Format Specifiers

**NSLog on GNUstep fully supports `%@`** for object description:
```objc
NSLog(@"User: %@", user);  // Works on both platforms
```

Our compat macros handle this correctly by:
1. Building format string via `NSString stringWithFormat:`
2. Passing result to `NSLog(@"[prefix] %@", formattedString)`

## Security Framework Compatibility

### What's Missing
- `SecKeyRef` - Opaque key reference type
- `SecKeyEncrypt/SecKeyDecrypt` - RSA encryption
- `SecKeyRawSign/SecKeyRawVerify` - Signature operations
- `SecRandomCopyBytes` - Cryptographic random
- `SecCertificate` - X.509 certificate handling

### Our Implementation
```objc
// SecKeyRef is just an opaque pointer on Linux
typedef struct __SecKey *SecKeyRef;

// SecRandomCopyBytes uses arc4random_buf
static inline int SecRandomCopyBytes(int *drbg, size_t count, void *bytes) {
    arc4random_buf(bytes, count);
    return errSecSuccess;
}
```

### For Actual Crypto Operations
We use OpenSSL directly via the project's crypto utilities:
- `EVP_PKEY` for public/private keys
- `EVP_DigestSign/EVP_DigestVerify` for signatures
- `PKCS5_PBKDF2_HMAC` for key derivation

## CommonCrypto Compatibility

### Mapping Table

| CommonCrypto | OpenSSL Equivalent |
|--------------|-------------------|
| `CC_SHA256(data, len, md)` | `SHA256(data, len, md)` |
| `CCHmac(algo, key, klen, data, dlen, out)` | `HMAC(md, key, klen, data, dlen, out, &len)` |
| `CCKeyDerivationPBKDF2` | `PKCS5_PBKDF2_HMAC` |
| `kCCSuccess` | `0` |
| `kCCPBKDF2` | `2` |
| `kCCPRFHmacAlgSHA256` | `EVP_sha256()` |

### Error Code Constants
```c
enum {
    kCCSuccess = 0,
    kCCParamError = -4300,
    kCCBufferTooSmall = -4301,
    kCCMemoryFailure = -4302,
    kCCAlignmentError = -4303,
    kCCDecodeError = -4304,
    kCCUnimplemented = -4305,
    kCCOverflowError = -4306,
    kCCRNGError = -4307
};
```

## NSURLSession vs NSURLConnection

### The Issue
GNUstep has forward declarations for `NSURLSession` but no implementation.

### Our Approach
The codebase uses `NSURLConnection` which IS implemented:
```objc
// This works on GNUstep:
NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:request delegate:delegate];
```

If you need NSURLSession-like behavior, wrap NSURLConnection with a completion handler pattern.

## Dispatch Queues (GCD)

### Important: os_log_t Property Declaration

On Linux, `os_log_t` is `void*` (a pointer), so properties should use `assign`, not `strong`:

```objc
#if TARGET_OS_LINUX
@property (nonatomic, assign) os_log_t log;
#else
@property (nonatomic, strong) os_log_t log;
#endif
```

Similarly for `dispatch_queue_t`:
```objc
@property (nonatomic, assign) dispatch_queue_t queue;  // Both platforms
```

## Testing the Compat Layer

### On macOS (Native)
```bash
xcodegen generate
xcodebuild -scheme ATProtoPDS-CLI build
```

### On Linux (via GNUstep)
```bash
# On your Linux VM with GNUstep installed
cd /path/to/repo
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## Recommendations

1. **Keep os/log.h compat** - GNUstep has no unified logging API
2. **Keep Security compat** - Needed for SecKeyRef typedef
3. **Keep CommonCrypto compat** - OpenSSL wrappers work well
4. **Consider removing unused functions** from compat headers
5. **Add test cases** that verify behavior parity between platforms
6. **Document platform-specific code** with `TARGET_OS_LINUX` guards

## References

- [GNUstep Base Library Documentation](https://gnustep.github.io/resources/documentation/Developer/Base/Reference/Base.html)
- [GNUstep Base Release Notes](https://gnustep.github.io/resources/documentation/Developer/Base/ReleaseNotes/ReleaseNotes.html)
- [Apple os_log Documentation](https://developer.apple.com/documentation/os/logging)
- [OpenSSL EVP API](https://www.openssl.org/docs/manmaster/man3/EVP_DigestSign.html)
