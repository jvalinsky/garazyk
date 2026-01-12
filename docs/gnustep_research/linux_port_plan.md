# Linux Port Implementation Plan

Based on the research and gap analysis, this document outlines the step-by-step plan to port `objpds` to Linux using the GNUstep toolchain.

## Phase 1: Build System & Toolchain Configuration
**Goal**: Get the project to configure via CMake and attempt compilation, identifying all immediate syntax/linking errors.

1.  **Dependencies**:
    *   Ensure strict dependency on `libc`, `libobjc2`, `gnustep-base`, `libdispatch`, and `openssl` (dev variants).
2.  **CMakeLists.txt Updates**:
    *   Add detection for `GNUSTEP` environment.
    *   Use `gnustep-config` to fetch include paths and library paths.
    *   **CRITICAL**: Set compiler flags `-fobjc-runtime=gnustep-2.0 -fblocks -fobjc-arc`.
    *   Link libraries explicitly: `-lobjc -lgnustep-base -ldispatch -lssl -lcrypto`.
    *   Define `LINUX` macro globally for conditional compilation.

## Phase 2: Core Compatibility Layer (Shims)
**Goal**: Resolve "missing symbol" errors for Security and Dispatch types.

1.  **Dispatch Queue Types**:
    *   Problem: `dispatch_queue_t` is a struct, not an object, on Linux.
    *   Action: Introduce a macro or typedef wrapper, or simply use `#ifdef LINUX` to change `@property (strong)` to `@property (assign)` for all queue properties.
2.  **Security Framework Shim**:
    *   Problem: `Security/Security.h` is missing.
    *   Action: Create `Sources/Compat/Security.h` and `Sources/Compat/Security.m`.
    *   Implement Stubs/Wrappers:
        *   `SecRandomCopyBytes` -> `RAND_bytes` (OpenSSL).
        *   `SecKeyRef` -> `EVP_PKEY*` (void pointer wrapper).
        *   `SecKeyRawSign` -> `EVP_DigestSign`.

## Phase 3: Networking Adaptation
**Goal**: Make `WebSocketServer` compile and function.

1.  **WebSocketServer**:
    *   Problem: Uses `Network.framework` (`nw_listener`).
    *   Action: 
        *   Rename existing `WebSocketServer` to `AppleWebSocketServer`.
        *   Create `LinuxWebSocketServer` using **BSD Sockets** and `libdispatch` (`dispatch_source_t` for read/write events).
        *   Create a factory/interface configuration to select the correct class at compile time.

## Phase 4: Verification & Testing Support
**Goal**: Run the existing test suite on Linux.

1.  **XCTest Shim**:
    *   Problem: No `XCTest` framework.
    *   Action: Create `Tests/Compat/LinuxXCTestCase.h`.
        *   Define `XCTestCase` base class.
        *   Define `XCTAssert...` macros that map to simple assertions printing to stderr.
2.  **Test Runner**:
    *   Create `Tests/LinuxTestRunner.m`.
    *   Action: Use Objective-C Runtime functions (`class_copyMethodList`) to discover methods starting with `test` in all `XCTestCase` subclasses and execute them.
3.  **CMake Test Target**:
    *   Create a specific executable target `objpds_tests_linux` that includes the runner and excludes standard XCTest linking.

## Execution Order
1.  **Step 1**: Update CMake and fix simple compile errors (Dispatch types).
2.  **Step 2**: Implement Security Shim (allows compilation of Auth/Database layers).
3.  **Step 3**: Stub or Port `WebSocketServer` (fixing main link errors).
4.  **Step 4**: Implement Test Runner and Verify with `ATProtoPDS` tests.
