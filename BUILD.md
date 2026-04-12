# Building garazyk/ATProtoPDS on macOS Tahoe

## Critical: SDK Name Change on macOS 26

**On macOS 26 Tahoe, the SDK is named `macosx26.4`, NOT `macosx`**

This affects all `xcrun` commands and SDK path lookups.

### Verifying Your SDK

```bash
# Show all available SDKs
xcodebuild -showsdks

# On macOS 26.4 Tahoe, you should see:
# macOS 26.4                    -sdk macosx26.4
```

### Build Commands

```bash
# Set SDKROOT to the actual SDK path (not relying on xcrun)
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

# Configure cmake
cmake -B build \
  -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

# Build
cmake --build build --target AllTests
```

### Alternative: Using Direct Compiler Path

If xcrun is broken (returns "unable to find sdk"), use direct paths:

```bash
export CC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang
export CXX=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++

cmake -B build \
  -DCMAKE_C_COMPILER=$CC \
  -DCMAKE_CXX_COMPILER=$CXX \
  -DCMAKE_OBJC_COMPILER=$CC \
  -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

cmake --build build
```

### Running Tests

```bash
./build/tests/AllTests
```

### Common Issues

#### xcrun returns "unable to find sdk: 'macosx'"

**Cause**: macOS 26 Tahoe changed the SDK naming convention.

**Fix**: Use explicit SDK path or SDK name `macosx26.4`:

```bash
# Option 1: Set SDKROOT
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

# Option 2: Use correct SDK name
xcrun --sdk macosx26.4 --show-sdk-path
```

#### CMake 4.0+ Changes

CMake 4.0+ no longer defines `CMAKE_OSX_SYSROOT` by default. You must:

1. Set `SDKROOT` environment variable, OR
2. Pass `-DCMAKE_OSX_SYSROOT=...` to cmake

### Build Targets

| Target | Description |
|--------|-------------|
| `AllTests` | Run all unit tests |
| `kaszlak` | PDS CLI tool |
| `campagnola` | PLC directory server |
| `zuk` | Relay server |

### Project Structure

This project uses **CMake** (NOT xcodegen). There is no `project.yaml`.

- `CMakeLists.txt` - Main build configuration
- `build/` - CMake build output
- `build/tests/AllTests` - Test binary

### Quick Start

```bash
# One-time setup
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
cmake -B build

# Build and test
cmake --build build --target AllTests
./build/tests/AllTests
```
