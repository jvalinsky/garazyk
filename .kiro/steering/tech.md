# Technology Stack

## Languages and Runtime

- Objective-C with ARC
- C for low-level and performance-sensitive components
- Targets: macOS and Linux/GNUstep

## Build System

- CMake is the underlying build system
- XcodeGen is the canonical macOS project-generation path
- Out-of-source builds are required

## Core Dependencies

- SQLite
- OpenSSL
- libsecp256k1
- Foundation
- Security framework on macOS

## Canonical Build Commands

### macOS

```bash
xcodegen generate
xcodebuild -scheme kaszlak build
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

### Linux and GNUstep

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
```

Outputs follow the build directory you choose with CMake.

## Quality Gates

1. `xcodegen generate` succeeds
2. `xcodebuild -scheme AllTests build` succeeds
3. `./build/tests/AllTests` passes
4. `xcodebuild -scheme kaszlak build` succeeds
5. fuzzers build if modified

## Docs System

The canonical contributor docs live in `docs/` and are organized as a VitePress site. Older collections under `docs/guides/`, `docs/architecture/`, `docs/security/`, and `docs/tests/` are deep reference rather than the main onboarding path. Use `DOCUMENTATION.md` and `skills/rewrite-dev-docs-comments/` for doc and comment rewrites.
