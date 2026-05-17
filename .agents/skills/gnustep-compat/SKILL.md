---
name: gnustep-compat
description: "Deprecated legacy GNUstep compatibility notes for the former Garazyk Objective-C PDS. Use only for archaeology or explicitly scoped historical native-code work."
---

# GNUstep/Cross-Platform Compatibility

Covers platform detection, known GNUstep bugs and their workarounds, shim implementations, build system configuration, and the Docker workflow. The compat layer lives in `Garazyk/Sources/Compat/` (`PDSTypes.h` + `PlatformShims/` with 34 files).

## Platform Detection

| Macro | Defined In | When True |
|-------|-----------|-----------|
| `PDS_PLATFORM_APPLE` | `Compat/PDSTypes.h:21` | `__APPLE__` |
| `PDS_PLATFORM_LINUX` | `Compat/PDSTypes.h:32` | `!__APPLE__` |
| `PDS_GCD_OBJC_SUPPORT` | `Compat/PDSTypes.h:60` | Apple (GCD + ObjC ARC) |
| `PDS_DISPATCH_QUEUE_STRONG` | `Compat/PDSTypes.h:69` | `strong` on Apple, `assign` on Linux |
| `PDS_GCD_STRONG` | `Compat/PDSTypes.h:82` | Same as above for all GCD types |

### Raw Guard Patterns in Source (54 occurrences)

- `#if defined(GNUSTEP)` — most common, use for most platform branches
- `#if defined(__APPLE__) && !defined(GNUSTEP)` — Apple-only, exclude GNUstep
- `#if !defined(__APPLE__)` — non-Apple (includes GNUstep/Linux)
- `#if !defined(__APPLE__) || defined(GNUSTEP)` — shared non-Apple path

## Known GNUstep Bugs & Workarounds

### 1. NSURLSession Timeout (completion handler never fires)

**Location:** `PDSSafeHTTPClient.m:188`
**Symptom:** `performSafeDataTaskWithRequest:` blocks forever on GNUstep because the NSURLSession completion handler never fires on timeout.
**Fix:**
```objc
// After creating the data task:
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
               dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    if (![completedTrackingIDs containsObject:@(trackingID)]) {
        [task cancel];
        completion(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut ...]);
    }
});
```
Use a monotonic tracking ID counter and a set of completed IDs to avoid double-completion.

### 2. PLC HTTPS → curl NSTask Fallback

**Location:** `Core/DID.m:597-641`
**Symptom:** GNUstep cannot do HTTPS to `plc.directory` (NSURLSession TLS failure).
**Fix:** Under `#if defined(GNUSTEP)`, reduce NSURLSession timeout to 2s. On failure, fall back to:
```objc
NSTask *task = [[NSTask alloc] init];
[task setLaunchPath:@"/usr/bin/curl"];
[task setArguments:@[@"--max-time", @"10", urlString]];
// Use setLaunchPath: (not executableURL:) — GNUstep compat
// Use [task launch] (not launchAndReturnError:) — GNUstep compat
```

### 3. NSTask API Differences

**Location:** `Video/FFmpegTranscoder.m:6-13`, `Video/VideoThumbnailGenerator.m:11-17`, `Admin/PDSInstallerCommand.m`
**Pattern:**
```c
#ifdef LINUX
#define PDS_TASK_SET_EXECUTABLE(task, path) task.launchPath = path
#define PDS_TASK_LAUNCH(task, error) ([task launch], YES)
#else
#define PDS_TASK_SET_EXECUTABLE(task, path) task.executableURL = [NSURL fileURLWithPath:path]
#define PDS_TASK_LAUNCH(task, error) [task launchAndReturnError:error]
#endif
```
GNUstep `NSTask` lacks `executableURL` and `launchAndReturnError:`.

### 4. CFRelease Under ARC

**Location:** `PlatformShims/CoreFoundation/CFBase.h:64-72`, `PlatformShims/CoreFoundation/CFRelease.h:33-72`
**Problem:** GNUstep Foundation uses ARC — `CFRelease` is a no-op on CFTypeRef.
**Macros:**
```objc
#define CF_RELEASE(ref) do { \
    if (ref) { CFRelease(ref); ref = nil; } \
} while(0)

#define SECKEY_RELEASE(ref) do { \
    if (ref) { SecKeyRelease(ref); ref = NULL; } \
} while(0)
```
Always use `CF_RELEASE()` and `SECKEY_RELEASE()` instead of raw `CFRelease()`.

### 5. arc4random

**Location:** `PlatformShims/Security/SecRandom.m:17-62`
**Implementation:** Uses `getrandom(2)` syscall (Linux 3.17+), falls back to `/dev/urandom` with EINTR retry. Zeroes buffer on fatal read failure.
```objc
extern uint32_t arc4random(void); // declared in SecRandom.h
extern uint32_t arc4random_uniform(uint32_t upper_bound);
extern void arc4random_buf(void *buf, size_t n);
```

### 6. SecItem Keychain → SQLite-backed Store

**Location:** `PlatformShims/Security/SecItemLinuxStore.m`
**DB location:** `~/.pds/keychain.db` with WAL mode.
**Thread safety:** `dispatch_sync` on serial `com.pds.keychain` queue.
**Error codes:** `-50` (param), `-25299` (duplicate), `-25300` (not found).
**SQLite cleanup:** Uses `PDS_SQLITE_AUTORELEASE_STMT` (`__attribute__((cleanup))`).

### 7. CommonCrypto → OpenSSL Shims

| Apple API | OpenSSL Replacement | Location |
|-----------|-------------------|----------|
| `CC_SHA256` | `SHA256()` | `CommonDigest.h` |
| `CC_SHA1` | `SHA1()` | `CommonDigest.h` |
| `CC_MD5` | `MD5()` | `CommonDigest.h` |
| `CCHmac()` | `HMAC()` | `CommonHMAC.h` |
| `CCKeyDerivationPBKDF` | `PKCS5_PBKDF2_HMAC` | `CommonKeyDerivation.h` |
| `CCCrypt()` (AES-CBC) | `EVP_Encrypt/DecryptInit/Update/Final` | `CommonCryptor.c` |

### 8. os/log → NSLog

**Location:** `PlatformShims/os/log.h`
```objc
// Maps os_log to NSLog with [ATProtoPDS INFO/ERROR/DEBUG/FAULT] prefix
#define os_log(log, fmt, ...) NSLog(@"[ATProtoPDS INFO] " fmt, ##__VA_ARGS__)
```

### 9. OSAtomic → GCC __atomic Builtins

**Location:** `PlatformShims/libkern/OSAtomic.h`
Uses `__atomic_add_fetch`, `__atomic_sub_fetch`, `__atomic_store_n`, `__atomic_load_n`, `__atomic_compare_exchange_n`.

### 10. LocalAuthentication → Always-Fails Stub

**Location:** `PlatformShims/LocalAuthentication.m`
`LAContext` always returns `LAErrorBiometryNotAvailable`.

## Build System

### CMakeLists.txt GNUstep Flags (`CMakeLists.txt:90-117`)
```cmake
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-runtime=gnustep-2.2 -fobjc-arc -fblocks")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -lobjc")
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources/Compat/PlatformShims)
```

### GNUstep Toolchain (`cmake/gnustep-clang-toolchain.cmake`)
Sets `clang`/`clang++` as compilers before `project()` to avoid CMake cache invalidation. Uses `-fobjc-runtime=gnustep-2.0`.

### Docker (`docker/Dockerfile.gnustep`, 224 lines, 3-stage)
1. **Build GNUstep:** Ubuntu 22.04 + clang-14, builds `libobjc2` v2.2, `gnustep-make`, `swift-corelibs-libdispatch`, `gnustep-base` with `--with-libcurl`
2. **Build project:** Builds `kaszlak`, `campagnola`, `zuk`, `syrena`
3. **Runtime:** Ubuntu 22.04 minimal, non-root `pds` user, entrypoint `kaszlak serve`

## Quick Reference: Symptom → Fix

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `performSafeDataTaskWithRequest:` hangs | GNUstep NSURLSession timeout bug | Add `dispatch_after` fallback |
| PLC DID resolution fails | GNUstep can't do HTTPS to plc.directory | curl NSTask fallback with 2s NSURLSession timeout |
| `NSTask` selector crash | `executableURL:` / `launchAndReturnError:` not available | Use `setLaunchPath:` / `launch` macros |
| `CFRelease` on CFTypeRef is no-op | ARC under GNUstep | Use `CF_RELEASE()` / `SECKEY_RELEASE()` macros |
| `arc4random` symbol not found | Not on Apple platform | Include `PlatformShims/Security/SecRandom.h` |
| SecItem operations fail | No Apple Security framework | Use `SecItemLinuxStore` |
| Build error: unknown type `NSOperatingSystemVersion` | Not available on GNUstep | Guard with `#if !defined(GNUSTEP)` |
| `HTTPShouldUsePipelining` unavailable | Not in GNUstep NSURLSession config | Guard with `#if !defined(GNUSTEP)` |

## Testing on GNUstep

1. Build Docker image: `docker build -f docker/Dockerfile.gnustep -t garazyk-gnustep .`
2. Run tests inside container: `docker run garazyk-gnustep /bin/bash -c "cd /app && build/tests/AllTests"`
3. Many tests are gated with `#ifndef GNUSTEP` — this is expected
4. Compat-specific tests are in `Garazyk/Tests/Compat/`
