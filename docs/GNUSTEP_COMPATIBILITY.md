# GNUstep Compatibility

This repository supports Linux builds through GNUstep with explicit compatibility shims and targeted feature exclusions.

## Current Status

- Linux builds are driven by CMake and `Sources/Compat/*` shims.
- A subset of macOS-only components is excluded from Linux targets in `CMakeLists.txt`.
- Linux smoke builds run through Docker using `docker/Dockerfile.gnustep`.

## Compatibility Layers

- `Sources/Compat/CommonCrypto/*` provides CommonCrypto-compatible headers on Linux.
- `Sources/Compat/Security/Security.h` provides Security API shims used by non-Apple builds.
- `Sources/Compat/os/log.h` provides `os_log`-style macros for Linux builds.
- `Sources/Compat/Stubs/LinuxStubs.m` provides Linux stubs for selected macOS-only components.

## Linux Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=ON
cmake --build build --parallel
```

Docker alternative:

```bash
docker build -f docker/Dockerfile.gnustep .
```

## Known Constraints

- Linux builds intentionally exclude several macOS-only files (for example, `Network.framework` and selected Security-backed implementations).
- `NSURLSession` usage remains mixed; some Linux paths use compatibility fallbacks while others are excluded from Linux targets.
- The Linux target is suitable for ongoing porting and validation, but feature parity with macOS is not yet complete.

## Validation Checklist

1. Regenerate/refresh build: `cmake -S . -B build`.
2. Build Linux target in GNUstep environment.
3. Run test suite available in that environment.
4. Re-run XRPC coverage script after endpoint changes:
   `node scripts/generate_xrpc_coverage_report.js --source-only`.
