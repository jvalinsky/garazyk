# GNUstep Compatibility Research: Overview

**Goal:** Enable `objpds` to compile and run on Linux using the GNUstep toolchain.

## Current State
The `objpds` codebase is heavily reliant on Apple-specific frameworks and modern Objective-C features. 

### Key Dependencies Identified
- **Foundation**: `NSURLSession` (Networking), `NSJSONSerialization`, `RunLoop` integration.
- **Security**: `Security.framework` is imported in core auth components (`ActorStore`, `KeyManager`, `WebAuthn`).
- **Grand Central Dispatch (GCD)**: pervasive use of `dispatch_queue`, `dispatch_sync`, `dispatch_once`.
- **XCTest**: All tests are written using the XCTest framework.

## Strategy Summary
To achieve Linux support, we need a multi-layered approach:

1.  **Build System**: Use `cmake` with `gnustep-config` to locate headers/libs.
2.  **Runtime**: **CONFIRMED** `libobjc2` is the required runtime.
    - **Source Analysis**: Checked `reference/libobjc2/objc/objc-arc.h` and `arc.mm`.
    - **Features**: Fully supports ARC (`objc_autoreleaseReturnValue`), weak references, and Blocks.
    - **Conclusion**: We must compile with `-fobjc-runtime=gnustep-2.0` and link `libobjc` (which is `libobjc2` on modern systems) to enable these features.
3.  **Foundation Polyfills**: 
    - `NSURLSession` is CONFIRMED implemented in `gnustep-base` (2024 version), utilizing `libcurl` and `libdispatch`.
    - `Security` framework does not exist on GNUstep. We must create a compatibility shim (`Compat/Security.h`) specifically for the symbols we use (`SecKey`, `kSec...`) mapping them to OpenSSL/GnuTLS or just stubbing them if possible.
4.  **Testing**: XCTest is not standard on GNUstep. We may need to exclude tests from Linux builds initially or use a simple test runner test-shim.

## Navigation
- [Foundation & Networking](./foundation_compat.md)
- [Security & Crypto](./security_compat.md)
- [Testing Strategy](./testing_strategy.md)
