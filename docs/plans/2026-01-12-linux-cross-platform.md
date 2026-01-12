# Linux Cross-Platform Build Plan

## Overview

Complete the cross-platform build to support both macOS (Xcode/Apple frameworks) and Linux (GNUstep/libobjc2/Clang).

## Current Status (as of Jan 12, 2026)

**VM:** `september` (Arch Linux with GNUstep + libobjc2)

**Completed:**
- [x] CMake configuration for Linux (Clang, OS_OBJECT_USE_OBJC=0)
- [x] Fixed dispatch_queue_t properties (strong → assign)
- [x] Security compat headers (SecRandom.h)
- [x] Foundation compat headers (Foundation.h, NSErrorCompat.h)
- [x] Linux test compatibility (LinuxXCTestCompat.h)
- [x] GNUstep detection with pkg-config fallback
- [x] SQLite3 imported target fix
- [x] libobjc2 built and installed

**Remaining Issues (blocking build):**
- os_log_t - Apple-only logging (PDSAccountService.m)
- NSURLSession - Apple-only networking (ExploreHandler.m)
- kCCSuccess - CommonCrypto constant (PDSAccountService.m)
- Format string warnings

## Task Breakdown (Beads IDs)

| ID | Task | Priority | Status |
|---|---|---|---|
| objpds-8m4 | Linux Cross-Platform Build Complete | P0 | open |
| objpds-mdu | Replace os_log_t with POSIX syslog | P1 | open |
| objpds-stv | Replace NSURLSession with libcurl | P1 | open |
| objpds-qpr | Replace CommonCrypto with OpenSSL | P1 | open |
| objpds-l7a | Fix format string warnings | P2 | open |
| objpds-351 | Fix remaining Apple-only imports | P2 | open |
| objpds-40l | Create Dockerfile.linux | P2 | open |
| objpds-7ec | Run tests on Linux and fix failures | P2 | open |

## Detailed Implementation Plan

### Task 1: Replace os_log_t with POSIX syslog (objpds-mdu)

**Files to create:**
- `ATProtoPDS/Sources/Compat/Logging/PDSLogging.h` - Main logging header
- `ATProtoPDS/Sources/Compat/Logging/PDSLogging.m` - Implementation

**Approach:**
```c
// PDSLogging.h
#ifdef __APPLE__
#import <os/log.h>
#define PDSLog os_log
#define PDSLogInfo os_log_info
#define PDSLogError os_log_error
#else
// Use syslog on Linux
#define PDS_LOG_DEBUG 7
#define PDS_LOG_INFO 6
#define PDS_LOG_ERR 3

static inline void PDSLog(int level, const char *subsystem, const char *format, ...) {
    // syslog-based implementation
}
#define PDSLogInfo(subsystem, format, ...) PDSLog(PDS_LOG_INFO, subsystem, format, ##__VA_ARGS__)
#define PDSLogError(subsystem, format, ...) PDSLog(PDS_LOG_ERR, subsystem, format, ##__VA_ARGS__)
#endif
```

**Files to modify:**
- `ATProtoPDS/Sources/App/Services/PDSAccountService.m` - Replace os_log_t with PDSLog
- Any other files using os_log_t

**Estimated effort:** 2-3 hours

### Task 2: Replace NSURLSession with libcurl (objpds-stv)

**Files to create:**
- `ATProtoPDS/Sources/Compat/Network/PDSHTTPClient.h` - HTTP client interface
- `ATProtoPDS/Sources/Compat/Network/PDSHTTPClient.m` - libcurl implementation

**Approach:**
```objc
// PDSHTTPClient.h
@interface PDSHTTPClient : NSObject

+ (instancetype)sharedClient;

- (void)GET:(NSString *)urlString 
 completion:(void (^)(NSData *data, NSHTTPURLResponse *response, NSError *error))completion;

- (void)POST:(NSString *)urlString 
         body:(NSData *)body
   completion:(void (^)(NSData *data, NSHTTPURLResponse *response, NSError *error))completion;

@end
```

**Files to modify:**
- `ATProtoPDS/Sources/App/Explore/ExploreHandler.m` - Replace NSURLSession with PDSHTTPClient

**Dependencies:**
- Requires libcurl (already in CMakeLists.txt as DISPATCH_LIB)

**Estimated effort:** 4-6 hours

### Task 3: Replace CommonCrypto with OpenSSL (objpds-qpr)

**Files to create:**
- `ATProtoPDS/Sources/Compat/Security/CommonCryptoCompat.h` - Constants mapping

**Approach:**
```c
// CommonCryptoCompat.h
#ifdef __APPLE__
#import <CommonCrypto/CommonCrypto.h>
#else
// OpenSSL mappings
#define kCCSuccess 0
#define kCCParamError -1
#define kCCBufferTooSmall -2
#define kCCMemoryFailure -3
#define kCCAlignmentError -4
#define kCCDecodeError -5
#define kCCUnimplemented -6

typedef int32_t CCCryptorStatus;
typedef uint32_t CCOperation;
typedef uint32_t CCAlgorithm;
typedef uint32_t CCOptions;

#define kCCEncrypt 0
#define kCCDecrypt 1
#define kCCAlgorithmAES128 0
#define kCCAlgorithmAES 0
#define kCCOptionPKCS7Padding 0x0001
#define kCCBlockSizeAES128 16

CCCryptorStatus CCCrypt(CCOperation op, CCAlgorithm alg, CCOptions options,
                        const void *key, size_t keyLength,
                        const void *iv, const void *dataIn, size_t dataInLength,
                        void *dataOut, size_t dataOutAvailable, size_t *dataOutMoved);
#endif
```

**Files to modify:**
- `ATProtoPDS/Sources/App/Services/PDSAccountService.m` - Replace kCCSuccess with 0

**Estimated effort:** 1-2 hours

### Task 4: Fix format string warnings (objpds-l7a)

**Issues:**
- Insecure format strings with NSLog/stringWithUTF8String
- Missing format specifiers

**Approach:**
```objc
// Before (insecure):
os_log_info(_log, "PDS server stopped");

// After (secure):
os_log_info(_log, "PDS server stopped");
```
Or use the new logging API.

**Files to check:**
- Any file using os_log_info with non-literal format strings

**Estimated effort:** 1-2 hours

### Task 5: Fix remaining Apple-only imports (objpds-351)

**Search and fix:**
```bash
grep -r "NSURLSession\|os_log_t\|kCCSuccess" --include="*.m" Sources/
```

**Known files:**
- ExploreHandler.m - NSURLSession
- PDSAccountService.m - os_log_t, kCCSuccess

**Estimated effort:** 2-3 hours

### Task 6: Create Dockerfile.linux (objpds-40l)

**Structure:**
```dockerfile
FROM archlinux:base

# Install dependencies
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm gnustep-base gnustep-make \
               libdispatch clang llvm openssl sqlite curl

# Build project
WORKDIR /app
COPY . .
RUN mkdir build && cd build && \
    CC=clang CXX=clang++ OBJC=clang cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc)

EXPOSE 2583 8081
CMD ["./bin/atprotopds"]
```

**Estimated effort:** 1-2 hours

### Task 7: Run tests on Linux (objpds-7ec)

**Steps:**
1. Run `./build/tests/AllTests` on VM
2. Fix any test failures
3. Some tests may require conditional compilation
4. May need to exclude Apple-specific tests on Linux

**Estimated effort:** 2-4 hours

## Build Instructions for Linux

```bash
# On Arch Linux VM (september)
cd pds-repo
mkdir build-linux && cd build-linux
CC=clang CXX=clang++ OBJC=clang cmake -DCMAKE_BUILD_TYPE=Debug ..
make -j$(nproc)
```

## Estimated Total Effort

| Phase | Tasks | Hours |
|-------|-------|-------|
| API Replacements | 1-3 | 7-11 |
| Build Fixes | 4-5 | 3-5 |
| Docker & Testing | 6-7 | 3-6 |
| **Total** | **7** | **13-22** |

## Dependencies Between Tasks

```
objpds-mdu (os_log)      ──┐
objpds-stv (NSURLSession)─┼─> objpds-351 (fix imports) ──> objpds-7ec (tests)
objpds-qpr (CommonCrypto)─┘
                              │
objpds-l7a (format strings) ──┘
                                    │
objpds-40l (Docker) <────────────────┘
```

## Success Criteria

- [ ] `atprotopds-cli` builds on Linux
- [ ] `atprotopds-server` builds on Linux  
- [ ] `AllTests` builds on Linux
- [ ] Tests pass (or known failures documented)
- [ ] Docker image builds successfully
- [ ] macOS build still works (no regressions)

## Notes

- GNUstep on Arch uses legacy runtime by default; we installed libobjc2 from source
- Some Apple APIs have no direct Linux equivalents (NSURLSession → libcurl)
- Consider maintaining two code paths with `#ifdef __APPLE__`
- Some tests may always be macOS-only (e.g., Keychain tests)
