# Building September PDS on macOS

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

September uses **XcodeGen** on macOS (not CMake). Out-of-source builds are required.

```bash
# Generate Xcode project
xcodegen generate

# Build tests
xcodebuild -scheme AllTests build

# Build server
xcodebuild -scheme ATProtoPDS-CLI build

# Run tests
./build/tests/AllTests
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

### Build Targets

| Target | Description |
|--------|-------------|
| `AllTests` | Run all unit tests |
| `ATProtoPDS-CLI` | PDS CLI tool (kaszlak) |
| `ATProtoPDS-PLC` | PLC directory server (campagnola) |

### Project Structure

This project uses **XcodeGen** (NOT cmake). The project is defined in `project.yml`.

- `project.yml` - XcodeGen configuration
- `build/` - Xcode build output
- `build/tests/AllTests` - Test binary
- `build/bin/` - CLI binaries

### Quick Start

```bash
# Generate Xcode project
xcodegen generate

# Build and test
xcodebuild -scheme AllTests build
./build/tests/AllTests

# Build server
xcodebuild -scheme ATProtoPDS-CLI build
```
