---
title: Security Analysis Report - ATProto PDS
---

# Security Analysis Report - ATProto PDS

**Date:** January 7, 2025 (Updated: January 14, 2026)
**Analysis Tools:** clang-tidy + Fuzzers

---

## Summary

- **Critical Issues:** 0
- **High Priority Issues:** 2
- **Medium Priority Issues:** 5
- **Low Priority Issues:** 12
- **Fuzzer Crashes:** 0

---

## Security Fixes Applied (January 14, 2026)

### Memory Management Fixes
**Files:** `KeyManager.m`, `ActorStore.m`
**Issues Fixed:**
- Fixed SecKeyRef memory leaks with proper CFRelease calls in dealloc
- Clarified SecKeyRef ownership contract with assign property declarations
- Added CFRetain/CFRelease pairing for KeyPair lifecycle management

### Input Validation Enhancements
**Files:** `EventFormatter.m`, `WebAuthnVerifier.m`
**Issues Fixed:**
- Added bounds checking for CBOR decoding to prevent buffer overflows
- Enhanced credential data validation in WebAuthn verification
- Added proper error handling for malformed input data

### Network Security Improvements
**File:** `WebSocketConnection.m`
**Issues Fixed:**
- Added 16MB max frame size limit to prevent resource exhaustion
- Implemented connection closure for oversized frames

### Queue Property Standardization
**Multiple Files**
**Issues Fixed:**
- Standardized dispatch_queue_t properties with PDS_DISPATCH_QUEUE_STRONG macro
- Ensured proper ARC memory management for queue objects

---

## High Priority Issues

### 1. Deprecated API Usage (HIGH)
**File:** `Garazyk/Sources/App/PDSController.m:284`
**Issue:** Use of deprecated `NSURLConnection sendSynchronousRequest:` (macOS 10.3-10.11)
**Impact:** API removed in modern macOS, may cause runtime failures
**Resolution:** Replace with `NSURLSession dataTaskWithRequest:completionHandler:`

```objc
// Current (deprecated):
NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&requestError];
```

---

### 2. Missing Nullability Annotations (HIGH)
**File:** `Garazyk/Sources/Auth/Session.h:331`
**Issue:** Double pointer parameters lack nullability specifiers
**Impact:** Compiler cannot enforce null checks, potential null pointer dereference

```objc
// Current:
- (BOOL)createSessionWithDID:(NSString *)did
                       scope:(NSString *)scope
                  dpopJWK:(NSDictionary *)dpopJWK
               newSession:(Session **)newSession
                      error:(NSError **)error;

// Resolution: Add _Nullable/_Nonnull
                newSession:(Session * _Nullable * _Nonnull)newSession
```

---

## Medium Priority Issues

### 3. Code Duplication - CBOR Parser (MEDIUM)
**File:** `Garazyk/Sources/Repository/CBOR.m`
**Lines:** 377, 403, 469, 498, 556, 605, 662, 713
**Issue:** Multiple `bugprone-branch-clone` warnings - switch statements with identical branches
**Impact:** Maintenance burden, potential for bugs if branches should differ

### 4. Incomplete Method Implementations (MEDIUM)
**Files:**
- `Garazyk/Sources/Auth/DPoPUtil.m:7` - `createWithMethod:uri:nonce:error:` not implemented
- `Garazyk/Sources/Auth/Session.m:177` - `createSessionForDID:handle:scope:dpopJWK:error:` not implemented
- `Garazyk/Sources/Database/PDSDatabase.m:1083` - `getRecordsForDid:collection:error:` not implemented
- `Garazyk/Sources/Repository/MSTPersistence.m:7` - Multiple methods not implemented

**Impact:** These methods are declared in headers but may not be called, or are stubs

### 5. Type Mismatch in Auth Handler (MEDIUM)
**File:** `Garazyk/Sources/Admin/PDSAdminHandler.m:42`
**Issue:** Passing `nil` to `isAuthenticatedWithRequest:` which requires non-null
```objc
![auth isAuthenticatedWithRequest:nil]
```

### 6. Property Type Mismatch (MEDIUM)
**File:** `Garazyk/Sources/Admin/AdminMiddleware.m:10`
**Issue:** Property `adminDids` declared as `NSMutableArray<NSString *>` but setter expects `NSArray<NSString *>`

### 7. Missing Interface Declaration (MEDIUM)
**File:** `Garazyk/Sources/CLI/PDSCLIAccountCommand.m:292`
**Issue:** `@implementation PDSCLIAccountCommand : PDSBaseCommand` - class extension syntax issue

---

## Low Priority Issues

### 8. Format String Issues (LOW)
**Files:**
- `Garazyk/Sources/CLI/PDSCLIDispatcher.m:50,61,74` - `%s` with `const void *` (should be `%.*s` or cast)
- `Garazyk/Sources/CLI/PDSCLIInviteCommand.m:202,250` - Format string issues

### 9. NSMutableString Type Confusion (LOW)
**Files:**
- `Garazyk/Sources/Auth/JWT.m:196,197` - Assigning `NSString *` to `NSMutableString *`
- `Garazyk/Sources/Auth/PKCEUtil.m:56,57` - Same issue
- `Garazyk/Sources/Auth/DPoPUtil.m:269` - Passing `NSMutableString *` where `NSData *` expected

### 10. Incomplete Implementations (LOW)
**Files:**
- `Garazyk/Sources/Auth/PDSAppleKeyManager.m` - `publicKeyJWK` implementation exists
- Multiple files with `bugprone-branch-clone` warnings (identical then/else branches)

---

## Fuzzer Results

| Fuzzer | Runs | Crashes | Time |
|--------|------|---------|------|
| fuzz_xrpc | 5000 | 0 | ~30s |
| fuzz_http | 5000 | 0 | ~30s |
| fuzz_cbor | 5000 | 0 | ~30s |

**Results:** No parsing vulnerabilities found in HTTP, XRPC, or CBOR parsers with current corpus.

---

## Recommendations

1. **Immediate:** Fix the deprecated `NSURLConnection` API usage
2. **Short-term:** Add nullability annotations to all public API headers
3. **Medium-term:** Address incomplete method implementations or remove unused declarations
4. **Ongoing:** Run fuzzers with larger corpus and longer runs

---

## Scanner Configuration

**.clang-tidy checks enabled:**
- `bugprone-*` (bug-prone code patterns)
- `cert-*` (CERT C++ guidelines)
- `objc-*` (Objective-C specific)
- `clang-analyzer-*` (Clang static analyzer)

**Fuzzing configuration:**
- ASAN/UBSAN enabled for memory safety testing
- Corpus directories: `fuzzing/corpus_http/`, `fuzzing/corpus_xrpc/`, `fuzzing/corpus_cbor/`

---

## Related Documentation

- [Security Documentation Index](README) - Overview of all security docs
- [Security Plan](# Security plan) - Comprehensive security testing strategy
- [Security Testing Plan](SECURITY_TESTING_PLAN) - Detailed fuzzing and exploit testing
- [Security Test Results](security_test_results) - Current test results
- [Reports](reports/README) - Historical security analysis reports
- [OAuth2 Security](../oauth2/security) - OAuth2 implementation security
