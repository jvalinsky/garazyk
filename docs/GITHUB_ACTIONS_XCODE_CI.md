# GitHub Actions + Xcode CI/CD Best Practices

This document provides best practices for CI/CD with Xcode projects using GitHub Actions.

## Overview

This project uses GitHub Actions for:
1. **Build & Test** - Compile and run unit tests
2. **Fuzzing** - Security testing with libFuzzer
3. **Security Scanning** - Static analysis and vulnerability checks

## Workflow Files

| File | Purpose |
|------|---------|
| `.github/workflows/ci.yml` | Build, test, fuzzing, security scan |
| `.github/workflows/security.yml` | Comprehensive security testing |

## macOS Runners

### Recommended: Specific Version
```yaml
runs-on: macos-13  # More stable than macos-latest
```

### Why Not `macos-latest`?
- Maps to latest macOS (macOS 15)
- Potential Xcode compatibility issues
- Less predictable behavior

## Xcode Setup

### Recommended Action
```yaml
- name: Setup Xcode
  uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: '15.4'  # Specific version, not latest
```

### Verification Step
```yaml
- name: Verify Xcode
  run: |
    xcodebuild -version
    xcode-select -p
```

## xcodebuild Best Practices

### Essential Flags for CI
```bash
xcodebuild clean build \
  -scheme "$SCHEME" \
  -project "ATProtoPDS.xcodeproj" \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation  # Required for CI
```

### Key Flags Explained

| Flag | Purpose |
|------|---------|
| `CODE_SIGNING_ALLOWED=NO` | Skip code signing for unsigned builds |
| `-skipPackagePluginValidation` | Skip plugin validation (required in CI) |
| `-destination 'platform=macOS'` | Target macOS platform |
| `-configuration Debug` | Build configuration |

### Auto-Detect Scheme
```bash
scheme_list=$(xcodebuild -list -json | tr -d "\n")
default=$(echo $scheme_list | ruby -e "require 'json'; puts JSON.parse(STDIN.gets)['project']['targets'][0]")
```

## Concurrency Control

Prevent duplicate runs:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Caching

### XcodeGen Cache
```yaml
- name: Cache XcodeGen
  uses: actions/cache@v4
  with:
    path: /usr/local/bin/xcodegen
    key: xcodegen-${{ runner.os }}
```

## Testing in CI

### Run Unit Tests
```bash
TEST_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData -name "AllTests" -type f | head -1)
"$TEST_BUNDLE"
```

### Test Result Bundle
```bash
xcodebuild test \
  -scheme AllTests \
  -resultBundlePath TestResults.xcresult

- uses: kishikawakatsumi/xcresulttool@v1
  with:
    path: TestResults.xcresult
```

## Security Testing

### Clang-Tidy
```bash
make clang-tidy 2>&1 | tail -20
```

### Static Analyzer
```bash
xcodebuild build \
  RUN_CLANG_STATIC_ANALYZER=YES \
  CODE_SIGNING_ALLOWED=NO
```

## Fuzzing in CI

### Build Fuzzers
```bash
make fuzz-all 2>&1 | tail -10
```

### Run with Timeout
```bash
./fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_total_time=60 -jobs=4
./fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_total_time=60 -jobs=4
./fuzzing/fuzz_http fuzzing/corpus_http/ -max_total_time=60 -jobs=4
```

## Common Issues

### 1. Xcode Version Not Found
**Solution:** Use specific version, not "latest" or "beta"

### 2. Code Signing Errors
**Solution:** Set `CODE_SIGNING_ALLOWED=NO`

### 3. Plugin Validation Failed
**Solution:** Add `-skipPackagePluginValidation`

### 4. Hanging Builds
**Solution:** Add timeout to jobs, use `timeout-minutes`

## Useful Actions

| Action | Purpose |
|--------|---------|
| `maxim-lobanov/setup-xcode@v1` | Xcode version management |
| `actions/checkout@v4` | Repository checkout |
| `actions/cache@v4` | Cache dependencies |
| `kishikawakatsumi/xcresulttool@v1` | Parse test results |
| `apple-actions/import-codesign-certificates` | Code signing certificates |
| `github/codeql-action/init@v3` | Security analysis |

## References

- [GitHub Actions for Xcode](https://github.com/marketplace?query=xcode)
- [maxim-lobanov/setup-xcode](https://github.com/marketplace/actions/setup-xcode)
- [Quality Coding: GitHub Actions for CI with Xcode](https://qualitycoding.org/github-actions-ci-xcode/)
- [GitHub Docs: Installing Apple Certificate](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
