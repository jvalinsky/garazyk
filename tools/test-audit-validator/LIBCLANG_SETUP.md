# libclang Setup for test-audit-validator

## Issue

The test-audit-validator tool uses `github.com/go-clang/clang-v14` which requires libclang to be properly installed and linked.

## macOS Setup

### Option 1: Using Homebrew LLVM

```bash
# Install LLVM via Homebrew
brew install llvm@14

# Set CGO flags for building
export CGO_LDFLAGS="-L/opt/homebrew/opt/llvm@14/lib"
export CGO_CPPFLAGS="-I/opt/homebrew/opt/llvm@14/include"

# Or for Intel Macs:
export CGO_LDFLAGS="-L/usr/local/opt/llvm@14/lib"
export CGO_CPPFLAGS="-I/usr/local/opt/llvm@14/include"

# Build and test
cd tools/test-audit-validator
go test ./internal/analysis/
```

### Option 2: Using Xcode's libclang

```bash
# Set CGO flags to use Xcode's libclang
export CGO_LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
export CGO_CPPFLAGS="-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include"

# Build and test
cd tools/test-audit-validator
go test ./internal/analysis/
```

## Linux Setup

```bash
# Install libclang development files
sudo apt-get install libclang-14-dev

# Build and test
cd tools/test-audit-validator
go test ./internal/analysis/
```

## Verification

To verify libclang is properly configured:

```bash
# Check if libclang can be found
pkg-config --libs libclang

# Try building
cd tools/test-audit-validator
go build ./internal/analysis/
```

## Alternative: Skip CGO Tests

If libclang setup is problematic, you can skip tests that require CGO:

```bash
go test -tags=no_cgo ./...
```

## Future Consideration

For production deployment, consider:
1. Using a Docker container with libclang pre-installed
2. Providing pre-built binaries for common platforms
3. Documenting libclang as a required dependency in README
