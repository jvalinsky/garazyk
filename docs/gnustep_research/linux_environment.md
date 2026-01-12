# Linux Source-Built GNUstep Environment

## Overview
This document details the setup of the Debian Bookworm VM (`september`) on `exe.dev` used for building `objpds` with GNUstep. We built the toolchain from source to support modern Objective-C features, specifically Grand Central Dispatch (GCD) via `libdispatch` and Blocks.

## Version Manifest
- **OS**: Debian 12 (Bookworm)
- **Compiler**: Clang 14 (from Debian repos)
- **CMake**: 3.28.1 (Manual install, required for `libdispatch`)
- **GNUstep Make**: `gnustep/tools-make` (GitHub master)
- **Runtime**: `gnustep/libobjc2` (GitHub master)
- **Dispatch**: `apple/swift-corelibs-libdispatch` (GitHub master)
- **Foundation**: `gnustep/libs-base` (GitHub master)

## Critical Setup Details

### 1. libdispatch Dependencies
Debian Bookworm lacks `libdispatch-dev`. We built it from source (`apple/swift-corelibs-libdispatch`).
It requires:
- **CMake 3.26+**: Installed v3.28.1 from GitHub releases (Debian only has 3.25).
- **libkqueue**: Built from source (`mheily/libkqueue`) to provide kqueue emulation on Linux.
- **libpwq**: Built from source (`mheily/libpwq`) for pthread workqueues.
  - **Fix**: Required `CFLAGS="-fcommon"` to compile with Clang 14 due to duplicate symbol errors.

### 2. Build Order & Configuration
The build order is strict:
1.  **Dependencies**: `clang`, `libffi`, `libicu`, `libcurl`, `libxml2`, etc.
2.  **libkqueue** & **libpwq**: Essential low-level shims.
3.  **GNUstep Make**: Configured with `--with-library-combo=ng-gnu-gnu`.
4.  **libobjc2**:
    - **Crucial**: Must clean build directory to ensure `CC=clang` is respected. GCC cannot build this.
    - Configured with `-DCMAKE_INSTALL_PREFIX=/usr`.
5.  **swift-corelibs-libdispatch**:
    - Configured with `-DINSTALL_PRIVATE_HEADERS=YES` (needed for GNUstep Base).
6.  **GNUstep Base**:
    - Configured after `libdispatch` is installed so it detects and enables GCD support (`-ldispatch`).

## Verification
A test file `test_dispatch.m` was compiled to verify the stack:
```objective-c
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

int main() {
    @autoreleasepool {
        dispatch_queue_t queue = dispatch_queue_create("com.test", NULL);
        dispatch_sync(queue, ^{
             NSLog(@"In Queue!");
        });
    }
    return 0;
}
```
**Compilation Command:**
```bash
clang test_dispatch.m $(gnustep-config --objc-flags) $(gnustep-config --base-libs) -fblocks -ldispatch -o test_dispatch
```

## Provisioning Script
The full setup is automated in `provision_gnustep.sh` at the root of the repository.
