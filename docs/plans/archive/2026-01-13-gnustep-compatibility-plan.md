---
title: GNUstep Compatibility Deep Dive - Implementation Plan
---

# GNUstep Compatibility Deep Dive - Implementation Plan

## Document Overview

This plan addresses the gap between our codebase's macOS-centric implementation and GNUstep/Linux compatibility requirements. The analysis compares our current compat layers against GNUstep 1.31.1 (February 2025) and identifies specific issues requiring resolution.

---

## 1. Executive Summary

### Current State
- Compat layers exist at `Sources/Compat/` for CommonCrypto, Security, and os/log.h
- Multiple source files bypass these compat layers with direct Apple-only imports
- NSURLSession usage throughout the codebase contradicts our documentation stating GNUstep only has declarations

### Critical Finding
GNUstep 1.31.1 ships with an **experimental NSURLSession implementation**. Our documentation is outdated. However, this implementation has known limitations around blocks-based code and should not be considered fully stable for production use.

### Goal
Ensure all code compiles and runs on Linux/GNUstep by routing imports through compat layers and adding platform guards where necessary.

---

## 2. Technical Findings

### 2.1 Compat Layer Completeness

| Layer | Location | Status | Notes |
|-------|----------|--------|-------|
| **CommonCrypto** | `Sources/Compat/CommonCrypto/` | Complete | SHA1, SHA256, MD5, HMAC, PBKDF2 all mapped to OpenSSL |
| **Security** | `Sources/Compat/Security/` | Complete | SecRandomCopyBytes via arc4random_buf |
| **os/log.h** | `Sources/Compat/os/log.h` | Complete | Maps to NSLog with prefix macros |
| **Foundation** | `Garazyk/Sources/Compat/Foundation/` | Minimal | Only Foundation.h and NSErrorCompat.h |

### 2.2 Files with Problematic Imports

The following files import Apple-only frameworks directly instead of using compat layers:

| File | Line | Import | Should Use |
|------|------|--------|------------|
| `HandleResolver.m` | 3 | `<Security/Security.h>` | `Sources/Compat/Security/Security.h` |
| `CID.m` | 2 | `<CommonCrypto/CommonCrypto.h>` | `Sources/Compat/CommonCrypto/CommonCrypto.h` |
| `MST.m` | 4 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `BlobStorage.m` | 5 | `<CommonCrypto/CommonCrypto.h>` | `Sources/Compat/CommonCrypto/CommonCrypto.h` |
| `KeyManager.m` | 4 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `PKCEUtil.m` | 2 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `CryptoUtils.m` | 2-3 | `<CommonCrypto/CommonHMAC.h>`, `<CommonCrypto/CommonDigest.h>` | Compat layer |
| `JWT.m` | 4 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `DPoPUtil.m` | 2-3 | `<CommonCrypto/CommonDigest.h>`, `<CommonCrypto/CommonKeyDerivation.h>` | Compat layer |
| `WebSocketConnection.m` | 3 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `SSLPinningManager.m` | 4 | `<CommonCrypto/CommonCrypto.h>` | `Sources/Compat/CommonCrypto/CommonCrypto.h` |
| `PDSController.m` | 30-31 | `<CommonCrypto/CommonDigest.h>`, `<CommonCrypto/CommonKeyDerivation.h>` | Compat layer |
| `AdminService.m` | 3 | `<CommonCrypto/CommonHMAC.h>` | `Sources/Compat/CommonCrypto/CommonHMAC.h` |
| `PDSAccountService.m` | 9-10 | `<CommonCrypto/CommonDigest.h>`, `<CommonCrypto/CommonKeyDerivation.h>` | Compat layer |
| `PDSRecordService.m` | 7 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `PDSBlobService.m` | 6 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `FeedService.m` | 5 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `EventFormatter.m` | 3 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `Firehose.m` | 4 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |
| `OAuth2.m` | 11 | `<os/log.h>` | Already uses compat layer at root |
| `Secp256k1.m` | 2 | `<CommonCrypto/CommonDigest.h>` | `Sources/Compat/CommonCrypto/CommonDigest.h` |

### 2.3 NSURLSession Usage

The following files use NSURLSession, which is experimental on GNUstep:

| File | Usage Pattern |
|------|---------------|
| `HandleResolver.m:19-22` | `NSURLSession sessionWithConfiguration:` |
| `DID.m:77-80` | `NSURLSession sessionWithConfiguration:` |
| `FederationClient.m:18-21` | `NSURLSession sessionWithConfiguration:` |
| `ExploreHandler.m:943,1109` | `NSURLSession sharedSession` |
| `SSLPinningManager.m:58-59` | `NSURLSession sessionWithConfiguration:` delegate pattern |

### 2.4 PDSNetworkTransportLinux Issues

File: `Garazyk/Sources/Network/PDSNetworkTransportLinux.m`

| Line | Issue |
|------|-------|
| 87-89 | `handleRead` method is empty - no actual read implementation |
| 62-66 | Client connection logic shows error but isn't implemented |
| 111-118 | `sendData:` uses basic send() but doesn't handle partial sends |

---

## 3. Issues Summary

### Issue Category 1: Import Path Corrections
**Priority: Medium**
Files that import Apple frameworks directly need to use the compat layer headers. This is straightforward find-and-replace work but affects many files.

### Issue Category 2: NSURLSession Handling  
**Priority: High**
NSURLSession is experimental on GNUstep. Code should either:
- Add platform guards with NSURLConnection fallback
- Accept the limitation for development/testing only

### Issue Category 3: Linux Network Transport
**Priority: High**
`handleRead` in PDSNetworkTransportLinux.m is empty, breaking network functionality on Linux.

### Issue Category 4: Documentation Update
**Priority: Low**
`GNUSTEP_COMPATIBILITY.md` incorrectly states NSURLSession has no implementation.

---

## 4. Implementation Plan

### Phase 1: Import Path Corrections

#### Step 1.1: Create Import Header
Create a single umbrella header at `Garazyk/Sources/Compat/ATProtoCompat.h`:

```objc
#ifndef ATProtoCompat_h
#define ATProtoCompat_h

#ifdef __APPLE__
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#else
#import "Security/Security.h"
#import "CommonCrypto/CommonCrypto.h"
#endif

#ifdef __APPLE__
#import <os/log.h>
#else
#import "os/log.h"
#endif

#endif /* ATProtoCompat_h */
```

#### Step 1.2: Update Individual Files
For each affected file, replace:

```objc
#import <CommonCrypto/CommonDigest.h>
```

With:

```objc
#import <CommonCrypto/CommonDigest.h>
```

Wait - the compat layer headers need to be in the header search path. The existing structure at `Sources/Compat/` suggests they're meant to be added to include paths. We need to verify the CMake configuration includes `Sources/Compat/` in header search paths.

#### Step 1.3: Verify Build Configuration
Check `CMakeLists.txt` and `project.yml` to ensure:
1. `Sources/Compat/` is added to include directories
2. The path order places compat layer before system headers (so `#include_next` works on Apple)

### Phase 2: NSURLSession Strategy Decision

Two options exist:

**Option A: Conservative (Recommended)**
Add platform guards and use NSURLConnection on Linux:

```objc
#if defined(__APPLE__)
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    _session = [NSURLSession sessionWithConfiguration:config];
#else
    _session = nil;  // Use NSURLConnection class methods instead
#endif
```

This requires refactoring call sites to handle nil session.

**Option B: Experimental**
Accept GNUstep 1.31.1's experimental NSURLSession for development, with fallback to NSURLConnection when it fails. This is riskier but less code change.

### Phase 3: Network Transport Completion

Implement `handleRead` in `PDSNetworkTransportLinux.m`:

```objc
- (void)handleRead {
    uint8_t buffer[4096];
    ssize_t bytesRead = recv(_sockfd, buffer, sizeof(buffer), 0);
    
    if (bytesRead > 0) {
        NSData *data = [NSData dataWithBytes:buffer length:bytesRead];
        if (self.dataHandler) {
            self.dataHandler(data, NO);  // isComplete = NO for stream
        }
    } else if (bytesRead == 0) {
        // Connection closed
        if (self.dataHandler) {
            self.dataHandler(nil, YES);  // isComplete = YES, no more data
        }
    } else {
        // Error - check errno for EAGAIN vs actual error
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            if (self.errorHandler) {
                self.errorHandler(error);
            }
        }
        // EAGAIN/EWOULDBLOCK means no data available yet, which is fine
    }
}
```

Also implement proper partial send handling in `sendData:`.

### Phase 4: Documentation Update

Update `GNUSTEP_COMPATIBILITY.md` section "NSURLSession vs NSURLConnection":

**Current (Incorrect):**
> GNUstep has forward declarations for NSURLSession but no implementation.

**Updated:**
> GNUstep 1.31.1 (February 2025) introduced an experimental NSURLSession implementation. However, it has known limitations around blocks-based code patterns. For production Linux compatibility, use NSURLConnection with a completion handler wrapper pattern.

---

## 5. File Change Summary

| File | Change Type | Lines Affected |
|------|-------------|----------------|
| `Garazyk/Sources/Compat/ATProtoCompat.h` | New file | N/A |
| `CMakeLists.txt` | Modify | Include path addition |
| `project.yml` | Modify | Include path addition |
| `HandleResolver.m` | Modify | Lines 3, 19-25 |
| `DID.m` | Modify | Lines 2, 77-80 |
| `FederationClient.m` | Modify | Lines 3, 18-21 |
| `ExploreHandler.m` | Modify | Lines 943, 1109 |
| `SSLPinningManager.m` | Modify | Lines 4, 58-59 |
| `PDSNetworkTransportLinux.m` | Modify | Lines 62-66, 87-118 |
| 15+ CommonCrypto import files | Modify | Single import line each |
| `GNUSTEP_COMPATIBILITY.md` | Modify | Lines 172-182 |

---

## 6. Testing Strategy

### 6.1 macOS Build Verification
```bash
xcodegen generate
xcodebuild -scheme ATProtoPDS-CLI build
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

### 6.2 Linux Build Verification (Requires GNUstep)
```bash
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

### 6.3 Specific Test Cases
After changes, verify:
1. NSURLSession code paths work on macOS (existing tests)
2. NSURLConnection fallback paths work on Linux
3. Network transport handles incoming data correctly
4. All cryptographic operations produce identical output on both platforms

---

## 7. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Compat layer headers not in include path | Medium | Verify CMake configuration first |
| NSURLSession experimental on GNUstep | High | Add NSURLConnection fallback |
| handleRead empty breaking network | High | Implement proper buffer management |
| Breaking existing macOS functionality | Medium | Run full test suite before commit |

---

## 8. Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Import Corrections | 2-3 hours |
| Phase 2: NSURLSession Strategy | 4-6 hours |
| Phase 3: Network Transport | 4-8 hours |
| Phase 4: Documentation | 30 minutes |
| **Total** | **10-18 hours** |

---

## 9. Questions for Clarification

1. **NSURLSession Approach**: Should we implement the conservative approach with NSURLConnection fallback, or accept the experimental NSURLSession for now?

2. **Linux Testing**: Do you have access to a Linux VM with GNUstep installed for testing, or should this be marked as future work pending environment setup?

3. **Scope**: Should we include the NSURLConnection wrapper utility class in this plan, or handle that as a separate task?

---

## 10. Next Steps

1. Review and approve this plan
2. Confirm NSURLSession handling preference
3. Begin Phase 1: Import path verification and corrections

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation
