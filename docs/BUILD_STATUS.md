# Build Status - macOS

**Last Updated:** 2026-01-13
**Platform:** macOS (Darwin 25.1.0)
**Xcode:** Command Line Tools
**Build System:** CMake + XcodeGen

## Current Status

**All builds successful**
**All tests passing (168/168)**
**CLI application functional**

## Build Results

### Targets

| Target | Status | Output | Notes |
|--------|--------|--------|-------|
| ATProtoPDS-CLI | Pass | `./build/bin/atprotopds-cli` | CLI tool builds with warnings only |
| AllTests | Pass | `./build/tests/AllTests` | Test runner builds successfully |
| Fuzzers | Pass | `./build/fuzzing/` | Fuzz testing tools available |

### Test Results

```
=== Test Suite Results ===
Tests run: 168
Failures: 0
Success Rate: 100%
```

#### Test Suites Passing

-ATProtoCoreTests (6/6)
-ActorStoreTests (All passing)
-ATProtoHandleValidatorTests (11/11)
-BlobStorageTests (All passing)
-CARInteropTests (All passing)
-CryptoTests (4/4)
-DIDResolverTests (4/4)
-DIDValidationTests (All passing)
-HandleResolverTests (21/21)
-IdentifierTests (6/6)
-JWTTests (All passing)
-KeyRotationTests (All passing)
-MSTInteropTests (All passing)
-OAuth2EndpointTests (All passing)
-OAuth2HandlerTests (4/4)
-OAuth2Tests (All passing)
-PDSCLITests (All passing)
-PDSControllerTests (All passing)
-PDSDatabaseIntegrationTests (All passing)
-PDSNewArchitectureTests (All passing)
-RateLimiterTests (15/15)
-RepoCommitTests (All passing)
-SSLPinningTests (All passing)
-SubscribeReposHandlerTests (All passing)
-TOTPTests (5/5)
-WebSocketConnectionTests (All passing)
-XrpcHandlerTests (All passing)
-XrpcIntegrationTests (All passing)

## Recent Fixes (2026-01-13)

### Issue 1: HandleResolver Property Access

**Problem:**
21 tests in `HandleResolverTests` were failing with:
```
-[HandleResolver setSkipSSRFCheck:]: unrecognized selector sent to instance
```

**Root Cause:**
The `skipSSRFCheck` property was declared as `readonly` in `HandleResolver.h:23`, preventing tests from setting it for test scenarios.

**Fix:**
Changed property declaration from:
```objc
@property (nonatomic, assign, readonly) BOOL skipSSRFCheck;
```
to:
```objc
@property (nonatomic, assign) BOOL skipSSRFCheck;
```

**Files Modified:**
- `ATProtoPDS/Sources/Identity/HandleResolver.h:23`
- `ATProtoPDS/Tests/Identity/HandleResolverTests.m` (removed redundant property redeclaration)

**Impact:**
All 21 HandleResolverTests now pass

---

### Issue 2: CBOR Map Encoding

**Problem:**
Test `testCBORMapSorting` in `IdentifierTests` was failing:
```
((data1) equal to (expectedData)) failed:
("{length = 7, bytes = 0xa26161f56162f5}") is not equal to
("{length = 7, bytes = 0xa2616101616202}")
```

Numbers like `@1` and `@2` were being encoded as booleans (`0xf5` = true) instead of integers (`0x01`, `0x02`).

**Root Cause:**
In `ATProtoCBORSerialization.m:47-54`, the code was checking `boolValue` on all `NSNumber` objects before checking their actual type. This caused all non-zero numbers to be encoded as boolean `true`.

**Fix:**
Reordered the logic to check `objCType` first and only treat actual `BOOL` or `char` types as booleans:

```objc
// Before: Checked boolValue first (WRONG)
NSNumber *num = (NSNumber *)obj;
if ([num boolValue]) {
    return [CBORValue simple:21]; // true
}

// After: Check objCType first (CORRECT)
const char *objCType = [obj objCType];
if (strcmp(objCType, @encode(BOOL)) == 0 || strcmp(objCType, @encode(char)) == 0) {
    NSNumber *num = (NSNumber *)obj;
    if ([num boolValue]) {
        return [CBORValue simple:21];
    } else {
        return [CBORValue simple:20];
    }
}
// Then handle integers...
```

**Files Modified:**
- `ATProtoPDS/Sources/Core/ATProtoCBORSerialization.m:47-62`

**Impact:**
CBOR encoding now correctly handles NSNumber types
testCBORMapSorting now passes
DAG-CBOR compliance maintained

---

## Build Commands

### Generate Project
```bash
xcodegen generate
```

### Build CLI
```bash
xcodebuild -scheme ATProtoPDS-CLI -project ATProtoPDS.xcodeproj -configuration Debug build
```

### Build & Run Tests
```bash
xcodebuild -scheme AllTests -project ATProtoPDS.xcodeproj -configuration Debug build
./build/tests/AllTests
```

### Verify CLI Application
```bash
# Check version
./build/bin/atprotopds-cli version

# Check health
./build/bin/atprotopds-cli health

# List accounts
./build/bin/atprotopds-cli account list
```

## Known Warnings

The build produces some deprecation warnings from macOS SDK headers:
- `ScriptTokenType` (deprecated in macOS 13.0)
- `NSSpeechSynthesizer` APIs (deprecated in macOS 14.0)
- ARC retain cycle warnings in test mocks

These are harmless and don't affect functionality.

## Continuous Integration

All quality gates passing:
1. `xcodegen generate` succeeds
2. `xcodebuild -scheme AllTests build` succeeds
3. `./build/tests/AllTests` passes (168 tests, 0 failures)
4. `xcodebuild -scheme ATProtoPDS-CLI build` succeeds
5. Application runs successfully

## Next Steps

- [ ] Linux build verification
- [ ] GNUstep compatibility testing
- [ ] CI/CD pipeline setup
- [ ] Integration test suite expansion

## References

- [AGENTS.md](../AGENTS.md) - Agent instructions and development workflow
- [README.md](../README.md) - Project overview and quick start
- [GNUSTEP_COMPATIBILITY.md](GNUSTEP_COMPATIBILITY.md) - Linux/GNUstep compatibility notes
