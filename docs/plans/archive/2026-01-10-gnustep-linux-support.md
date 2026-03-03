# GNUstep Linux Support Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable compilation and execution of the PDS codebase on Linux using the GNUstep toolchain.

**Architecture:** Use CMake as the cross-platform build system. Implement shims for Apple-specific frameworks (`CommonCrypto`, `Network.framework`, `CoreImage`) using OpenSSL and native Linux libraries.

**Tech Stack:** GNUstep (Clang, libobjc2, gnustep-base, libdispatch), CMake, OpenSSL, libqrencode.

### Task 1: GNUstep Build Environment & CMake

**Files:**
- Create: `CMakeLists.txt`
- Create: `.github/workflows/linux.yml`
- Create: `scripts/setup_linux.sh`

**Step 1: Create Linux setup script**
Create `scripts/setup_linux.sh` to install dependencies on Ubuntu/Debian:
```bash
#!/bin/bash
sudo apt-get update
sudo apt-get install -y clang cmake gnustep gnustep-devel libgnustep-base-dev \
    libdispatch-dev libssl-dev libqrencode-dev git
```

**Step 2: Create root CMakeLists.txt**
Create `CMakeLists.txt` that:
- Finds GNUstep packages.
- Finds OpenSSL.
- Adds `ATProtoPDS` executable target.
- Adds `secp256k1` subdirectory.
- Defines `GNUSTEP` and `LINUX` preprocessor macros.

**Step 3: Create CI workflow**
Create `.github/workflows/linux.yml` that runs the setup script and `cmake . && make`.

**Step 4: Commit**
```bash
git add CMakeLists.txt .github/workflows/linux.yml scripts/setup_linux.sh
git commit -m "build: add initial CMake setup for GNUstep"
```

### Task 2: CommonCrypto Shim

**Files:**
- Create: `Sources/Compat/CommonCrypto/CommonCrypto.h`
- Create: `Sources/Compat/CommonCrypto/CommonDigest.h`
- Create: `Sources/Compat/CommonCrypto/CommonHMAC.h`
- Create: `Sources/Compat/CommonCrypto/CommonKeyDerivation.h`
- Modify: `CMakeLists.txt`

**Step 1: Create CommonDigest shim**
Implement `CC_SHA256` family functions using OpenSSL's `EVP_Digest` or `SHA256_*` functions.

**Step 2: Create CommonHMAC shim**
Implement `CCHmac` using OpenSSL's `HMAC`.

**Step 3: Create CommonKeyDerivation shim**
Implement `CCKeyDerivationPBKDF` using OpenSSL's `PKCS5_PBKDF2_HMAC`.

**Step 4: Update CMakeLists**
Add `Sources/Compat/CommonCrypto` to include path ONLY for Linux builds.

**Step 5: Verify Compilation**
Run `make`. It should fail on `Network/Network.h` but pass Crypto imports.

### Task 3: Networking Layer Abstraction

**Files:**
- Create: `Sources/Network/PDSNetworkTransport.h`
- Create: `Sources/Network/PDSNetworkTransportMac.m`
- Create: `Sources/Network/PDSNetworkTransportLinux.m`
- Modify: `Sources/Network/HttpServer.m`
- Modify: `Sources/Sync/WebSocketConnection.m`

**Step 1: Define Transport Protocol**
Create `PDSNetworkTransport` protocol defining:
- `startListeningOnPort:`
- `sendData:`
- `stop`

**Step 2: Implement Mac Transport**
Move existing `Network.framework` code from `HttpServer.m` into `PDSNetworkTransportMac`.

**Step 3: Implement Linux Transport**
Implement `PDSNetworkTransportLinux` using GCD (`dispatch_io` or `dispatch_source`) and BSD sockets.
*Note: This is complex. For the first pass, a stub that returns error or a simple blocking socket on a background queue is acceptable to get it compiling.*

**Step 4: Refactor HttpServer**
Update `HttpServer` to use `id<PDSNetworkTransport>` factory based on platform.

**Step 5: Commit**
```bash
git add Sources/Network/*
git commit -m "refactor: abstract networking for Linux support"
```

### Task 4: CoreImage & GUI Replacements

**Files:**
- Modify: `Sources/Auth/TOTPService.m`
- Modify: `Sources/App/AppDelegate.m`
- Modify: `CMakeLists.txt`

**Step 1: TOTP Service Linux Implementation**
In `Sources/Auth/TOTPService.m`:
```objc
#if defined(GNUSTEP)
#import <qrencode.h>
// Implement generateQRCode using libqrencode
#else
#import <CoreImage/CoreImage.h>
// Existing code
#endif
```

**Step 2: AppDelegate GUI Guard**
In `Sources/App/AppDelegate.m`, guard `NSStatusBar` and `NSApplication` delegate methods that are AppKit specific if they cause issues (GNUstep Base does not include AppKit classes by default, gnustep-gui does, but we likely want a headless build).

**Step 3: Link qrencode**
Update `CMakeLists.txt` to link `libqrencode` on Linux.

**Step 4: Verify Full Build**
Run `make` and ensure executable is created.

**Step 5: Commit**
```bash
git add Sources/Auth/TOTPService.m Sources/App/AppDelegate.m CMakeLists.txt
git commit -m "feat: add Linux fallbacks for CoreImage and GUI"
```

---

## Related Documentation

- [Archive Index](./README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation
