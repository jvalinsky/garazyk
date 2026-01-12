# Gap Analysis: GNUstep vs objpds Requirements

This document outlines the specific features and frameworks used by `objpds` that are currently missing or incompatible with the GNUstep environment on Linux, based on deep code analysis.

## 1. Network.framework (Critical)
- **Status**: **MISSING**
- **Usage**: Used in `Sources/Sync/WebSocketServer.m` for the WebSocket server implementation.
  - APIs: `nw_listener_create`, `nw_parameters_create`, `nw_listener_set_queue`, `nw_listener_set_state_changed_handler`.
- **Impact**: The current `WebSocketServer` will **not compile** on Linux.
- **Solution**: 
  - **Option A (Preferred)**: Rewrite `WebSocketServer` to use BSD sockets (sys/socket.h) or a cross-platform library (standard on Linux) within `#ifdef LINUX`.
  - **Option B**: Use a GNUstep-compatible alternative if available (rare for modern `Network.framework` replacements).

## 2. Security.framework (Critical)
- **Status**: **MISSING**
- **Usage**: Used extensively for cryptographic operations, key management, and WebAuthn.
  - Files: `ActorStore.m`, `KeyManager.m`, `WebAuthnVerifier.m`.
  - APIs: `SecKeyRef`, `SecKeyRawSign`, `kSecAttr...`, `SecRandomCopyBytes`.
- **Impact**: Authentication and signing flows will fail to compile.
- **Solution**: Implement a compatibility shim (`Compat/Security.h`) that maps these calls to OpenSSL `EVP` functions.

## 3. XCTest.framework (Major)
- **Status**: **MISSING**
- **Usage**: All unit and integration tests.
- **Impact**: Tests cannot be run using the standard `xcodebuild test` or simple compilation.
- **Solution**: Create a `LinuxXCTestCompat.h` shim that maps `XCTestCase` and `XCTAssert` to a simple custom test runner that executes methods starting with `test...`.

## 4. Modern Objective-C Runtime Features (Minor)
- **Status**: **AVAILABLE (via libobjc2)**
- **Detail**: `objpds` uses ARC, Blocks, and Weak references.
- **Verification**: `reference/libobjc2` confirms support (`objc_autoreleaseReturnValue`, etc.).
- **Action**: Must ensure the build system explicitly uses `-fobjc-runtime=gnustep-2.0` and links `libobjc`.

## 5. Foundation Gaps (Minor)
- **Status**: **PARTIAL / GOOD**
- **Detail**: 
  - `NSURLSession`: Implemented in `gnustep-base` (2024), supports delegates.
  - `CFDictionary`/`CoreFoundation`: `gnustep-corebase` exists but is an extra dependency.
## Detailed Research Findings & Solutions

### 1. Network.framework (WebSocketServer)
*   **Problem**: `Sources/Sync/WebSocketServer.m` relies on `Network.framework` (`nw_listener`, `nw_connection`), which is Apple-proprietary and has no direct Linux equivalent.
*   **GNUstep State**: `gnustep-base` provides `NSSocketPort` (legacy, DO-oriented) and `NSStream` (client-side focused). It does **not** provide a modern async socket listener.
*   **Solution**: 
    - **Rewrite**: Implement a `LinuxWebSocketServer` class using **BSD Sockets** (`<sys/socket.h>`, `<netinet/in.h>`) and `libdispatch` for async I/O (using `dispatch_source_create(DISPATCH_SOURCE_TYPE_READ)`).
    - **Libraries**: Alternatively, wrap `libwebsockets` (C library), but a tailored BSD socket implementation is likely lighter and sufficient for our specific needs.

### 2. Security.framework
*   **Problem**: Missing `SecKeyRef`, `SecRandomCopyBytes`, `kSecAttr...`.
*   **GNUstep State**: `gnustep-base` has `GSTLS.h` which wraps GnuTLS for internal use (URL loading), but does *not* expose `Security` framework compatible APIs.
*   **Solution**: 
    - **Shim**: Create `Compat/Security.h`.
    - **Implementation**: Map `SecRandomCopyBytes` to `RAND_bytes` (OpenSSL). Map `SecKeyRawSign` to `EVP_DigestSign`.
    - **Dependency**: Link against `openssl` (or `gnutls` if preferred, but OpenSSL is more standard for this manual mapping).

### 3. XCTest
*   **Problem**: `XCTest` framework is absent.
*   **GNUstep State**: `gnustep-base` uses a simple macro-based system (`Testing.h`) and compiles each test file as a standalone executable.
*   **Solution**: **`LinuxXCTestCompat` Shim**.
    - Define `XCTestCase` as a base class.
    - Define `XCTAssert...` macros that print to stderr/exit on failure.
    - Create a simple `TestRunner` that scans for methods starting with `test` using the ObjC runtime (`class_copyMethodList`) and executes them.

### 4. Dispatch Queue Typing
*   **Problem**: `objpds` uses `@property (strong) dispatch_queue_t`.
*   **GNUstep State**: On Linux, `dispatch_queue_t` is a C struct pointer (from `libdispatch`), **not** an Objective-C object. It cannot be retained/released by ARC.
*   **Solution**: Use `conditional property attributes`.
    ```objc
    #if TARGET_OS_LINUX
    @property (nonatomic, assign) dispatch_queue_t queue;
    #else
    @property (nonatomic, strong) dispatch_queue_t queue;
    #endif
    ```
    - Note: We must also manually `dispatch_retain`/`dispatch_release` handling if managing lifecycle manually, though often queues are singletons or just held by the struct pointer.
