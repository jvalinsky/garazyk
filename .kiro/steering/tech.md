# Technology Stack

## Languages & Runtime

- Objective-C with ARC (Automatic Reference Counting)
- Targets: macOS (Xcode/clang) and Linux (GNUstep 2.2 runtime)
- C for performance-critical components

## Build System

- CMake 3.21+ (primary build system)
- XcodeGen (macOS project generation)
- Out-of-source builds required

## Core Dependencies

- SQLite (data persistence)
- OpenSSL (cryptographic operations)
- libsecp256k1 (AT Protocol signing)
- Foundation framework
- Security framework (macOS)

## Common Build Commands

### macOS

```bash
# Generate Xcode project
xcodegen generate

# Build CLI
xcodebuild -scheme ATProtoPDS-CLI build
# Output: ./build/bin/kaszlak

# Build and run tests
xcodebuild -scheme AllTests build
./build/tests/AllTests

# Clean rebuild
./scripts/wipe_and_rebuild.sh
```

### Linux (GNUstep)

```bash
# Out-of-source build
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## Testing

```bash
# Run all tests (~1017 tests)
./build/tests/AllTests

# Run specific test class
./build/tests/AllTests -XCTest MSTInteropTests

# Run multiple test classes
./build/tests/AllTests -XCTest MSTInteropTests,CARInteropTests
```

## Static Analysis & Quality

```bash
# clang-tidy (requires compilation database)
cd build && cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cd ..
clang-tidy -p build ATProtoPDS/Sources/Repository/CBOR.m

# Build fuzzers
mkdir -p build && cd build
cmake .. -DBUILD_FUZZERS=ON
make -j$(sysctl -n hw.ncpu)

# Run fuzzer
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/xrpc_valid_create.txt

# ShellCheck
shellcheck scripts/*.sh
```

## Quality Gates (Pre-Push)

1. `xcodegen generate` succeeds
2. `xcodebuild -scheme AllTests build` succeeds
3. `./build/tests/AllTests` passes (0 failures)
4. `xcodebuild -scheme ATProtoPDS-CLI build` succeeds
5. Fuzzers build successfully

## Platform Compatibility

- Use `#if TARGET_OS_LINUX` / `#if __APPLE__` for platform-specific code
- Platform-specific implementations in `ATProtoPDS/Sources/Compat/`
- Network transport: `PDSNetworkTransportMac.m` / `PDSNetworkTransportLinux.m`
