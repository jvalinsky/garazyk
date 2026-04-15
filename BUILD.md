# Build Guide

This page is the short build reference for September PDS. Use [Setup Guide](docs/01-getting-started/setup.md) for the full contributor workflow and [Testing Map](docs/11-reference/testing-map.md) when you need to choose a test scope.

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

## macOS Build Commands

September uses XcodeGen on macOS. The generated Xcode targets call CMake into the out-of-source `build/` directory; do not run CMake in the repository root.

```bash
xcodegen generate
xcodebuild -scheme AllTests build
xcodebuild -scheme kaszlak build
./build/tests/AllTests
```

### Running Tests On macOS

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

Target one class when the custom runner supports the selector you need:

```bash
./build/tests/AllTests -XCTest MSTInteropTests
```

New Objective-C test classes must be registered in `Garazyk/Tests/test_main.m`; otherwise they can compile without running.

## Linux and GNUstep Build Commands

Use an explicit out-of-source build directory:

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
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

### Build Targets

| Target | Description |
|--------|-------------|
| `AllTests` | Shared Objective-C test runner |
| `kaszlak` | PDS CLI tool |
| `campagnola` | PLC directory server |
| `zuk` | standalone relay server |
| `syrena` | standalone AppView server in the CMake build |
| `Fuzzers` | XcodeGen aggregate target for fuzz harnesses |

### Project Structure

The macOS project is generated from `project.yml`.

- `project.yml` - XcodeGen configuration
- `Garazyk.xcodeproj` - generated Xcode project
- `build/` - macOS CMake output used by generated Xcode schemes
- `build/tests/AllTests` - Test binary
- `build/bin/` - CLI binaries
- `build-linux/` - conventional Linux/GNUstep build directory

### Quick Start

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
xcodebuild -scheme kaszlak build
```

## Related Docs

- [Contributor Guide](docs/index.md)
- [Setup Guide](docs/01-getting-started/setup.md)
- [CLI Reference](docs/11-reference/cli-reference.md)
- [Test Selection Workflow](docs/11-reference/test-selection-workflow.md)
