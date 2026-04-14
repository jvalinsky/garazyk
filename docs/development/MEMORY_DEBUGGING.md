---
title: Memory Debugging Guide
---

# Memory Debugging Guide

This project supports several tools for detecting and debugging memory issues in Objective-C.

## 1. AddressSanitizer (ASan)

ASan is the most powerful tool for detecting use-after-free, buffer overflows, and other memory errors.

### Usage
Run the helper script:
```bash
./scripts/run-asan-tests.sh
```

Or manually via CMake:
```bash
cmake .. -DENABLE_ASAN=ON
make AllTests
./tests/AllTests
```

## 2. macOS Leaks Utility

On macOS, you can use the built-in `leaks` tool to find memory leaks in a running process.

### Usage
Run the leak monitoring script:
```bash
./scripts/run-leaks.sh
```

This script enables `MallocStackLogging=1`, which allows the `leaks` tool to provide backtraces for where leaked objects were allocated.

## 3. Xcode Instruments

For a visual experience, use Xcode Instruments:
1. Open `ATProtoPDS.xcodeproj`.
2. Select the `AllTests` or `kaszlak` scheme.
3. Press `Cmd + I` (Product > Profile).
4. Select the **Leaks** or **Allocations** instrument.

## 4. Clang Static Analyzer

Static analysis can find potential issues before the code even runs.

### Usage
```bash
./scripts/run-scan-build.sh
```

## Tips for Objective-C Memory Management

- **ARC is Enabled**: Most memory management is automatic.
- **Retain Cycles**: Be careful with blocks capturing `self`. Use the weak-strong dance:
  ```objc
  __weak typeof(self) weakSelf = self;
  [object setBlock:^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      [strongSelf doSomething];
  }];
  ```text
- **CoreFoundation**: Objects starting with `CF` (e.g., `SecKeyRef`) are NOT managed by ARC. You MUST use `CFRetain` and `CFRelease`.
