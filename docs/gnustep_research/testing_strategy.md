# Testing Strategy

## Current State
- All tests are in `ATProtoPDS/Tests`.
- All tests inherit from `XCTestCase`.
- Uses `XCTAssert...` macros.

## Linux Limitations
- `XCTest.framework` is Apple proprietary and tightly coupled to Xcode.
- `gnustep-base` has a `Testing` kit, but it is not source-compatible with XCTest.
- `swift-corelibs-xctest` exists for Swift, but using it for pure ObjC on GNUstep is tricky/unsupported.

## Proposed Solution: `LinuxXCTestCompat.h`

Create a lightweight shim header that defines `XCTestCase` and `XCTAssert` macros mapping to a simple runtime runner or just `gnustep-tests`.

**Simple Shim Approach:**
```objc
#if defined(GNUSTEP)

@interface XCTestCase : NSObject
- (void)setUp;
- (void)tearDown;
@end

#define XCTAssertNotNil(x, ...) do { if (!(x)) { NSLog(@"FAIL: %@", ##__VA_ARGS__); exit(1); } } while(0)
// ... other macros
#endif
```

## Running Tests
Create a `run_tests_linux.m` `main()` entry point that:
1.  Introspects generic classes (using objc runtime).
2.  Finds subclasses of `XCTestCase`.
3.  Instantiates them.
4.  Runs all methods starting with `test`.

## Exclusions
Some tests will never pass on Linux (e.g., those testing `Security.framework` keychain integration specifically). We should wrap those in `#ifndef GNUSTEP`.
