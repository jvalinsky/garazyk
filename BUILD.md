# Building ATProtoPDS

This project uses CMake for its build system. To keep the source tree clean, please use out-of-source builds.

## Prerequisites

- CMake 3.21+
- Xcode (on macOS) or GNUstep (on Linux)
- secp256k1 (included as a submodule)
- SQLite3
- OpenSSL

## Standard Build Process

```bash
# 1. Create and enter a build directory
mkdir -p build && cd build

# 2. Configure the project
cmake ..

# 3. Build the primary components
make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
```

## Build Targets

- `kaszlak` (formerly `september`): The main PDS CLI tool.
- `campagnola` (formerly `atproto-plc`): The standalone PLC server.
- `AllTests`: The unit test suite.

## Running Tests

After building:
```bash
./build/tests/AllTests
```

## Cleanup

To clean the build, simply remove the `build/` directory:
```bash
rm -rf build/
```

Avoid running `cmake` directly in the root directory to prevent cluttering the source tree with generated files.
