---
title: Addressing Test and Feature Gaps Implementation Plan
---

# Addressing Test and Feature Gaps Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Address identified gaps in tests and features to reach feature parity with reference implementations

**Architecture:** Use TDD approach for new features, repair existing broken tests, implement missing Linux support, and add test coverage

**Tech Stack:** Objective-C, CMake, XCTest, GNUstep (for Linux), secp256k1, SQLite

## Task 1: Implement PDSNetworkTransport for Linux

**Files:**
- Modify: `ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m`
- Test: `ATProtoPDS/Tests/Network/PDSNetworkTransportTests.m` (create if not exists)

**Step 1: Write the failing test for startWithQueue**

```objc
- (void)testStartWithQueue {
    PDSNetworkTransportLinux *transport = [[PDSNetworkTransportLinux alloc] init];
    dispatch_queue_t queue = dispatch_get_main_queue();
    NSError *error;
    BOOL success = [transport startWithQueue:queue error:&error];
    XCTAssertFalse(success, @"Should fail before implementation");
    XCTAssertNotNil(error, @"Error should be present");
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme AllTests build test -only-testing:ATProtoPDS/Tests/Network/PDSNetworkTransportTests/testStartWithQueue`
Expected: FAIL

**Step 3: Write minimal implementation using GNUstep/libdispatch**

Implement `startWithQueue:error:` method with basic socket setup.

**Step 4: Run test to verify it passes**

Run same command, Expected: PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m ATProtoPDS/Tests/Network/PDSNetworkTransportTests.m
git commit -m "feat: implement startWithQueue for Linux transport"
```

### Task 2: Repair OAuth2HandlerTests

**Files:**
- Modify: `ATProtoPDS/Tests/Auth/OAuth2HandlerTests.m`
- Uncomment in: `CMakeLists.txt:276` (remove exclusion)

**Step 1: Write/update failing test for token handling**

Add test for `handleTokenRequest` method.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme AllTests test -only-testing:ATProtoPDS/Tests/Auth/OAuth2HandlerTests`
Expected: FAIL (if broken)

**Step 3: Fix OAuth2 logic in OAuth2Handler.m**

Implement missing token validation.

**Step 4: Run test to verify it passes**

Run same, Expected: PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Tests/Auth/OAuth2HandlerTests.m ATProtoPDS/Sources/Auth/OAuth2Handler.m CMakeLists.txt
git commit -m "fix: repair OAuth2HandlerTests and logic"
```

### Task 3: Implement token refresh in OAuth2.m

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2.m:478`
- Test: `ATProtoPDS/Tests/Auth/OAuth2Tests.m` (if exists, else create)

**Step 1: Write failing test for refreshToken**

```objc
- (void)testRefreshToken {
    OAuth2 *oauth = [[OAuth2 alloc] init];
    NSError *error;
    NSDictionary *result = [oauth refreshToken:@"oldToken" error:&error];
    XCTAssertNotNil(result, @"Should return new tokens");
}
```

**Step 2: Run test**

Expected: FAIL

**Step 3: Implement refreshToken method**

Add logic to refresh tokens.

**Step 4: Run test**

Expected: PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Auth/OAuth2.m ATProtoPDS/Tests/Auth/OAuth2Tests.m
git commit -m "feat: implement token refresh"
```

### Task 4: Add DNS TXT record resolution for handle resolution

**Files:**
- Modify: `ATProtoPDS/Sources/Identity/HandleResolver.m:209`
- Test: `ATProtoPDS/Tests/Identity/HandleResolverTests.m`

**Step 1: Write failing test**

Test DNS TXT lookup.

**Step 2: Run test**

FAIL

**Step 3: Implement DNS resolution**

Use appropriate DNS library.

**Step 4: Run test**

PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Identity/HandleResolver.m ATProtoPDS/Tests/Identity/HandleResolverTests.m
git commit -m "feat: implement DNS TXT record resolution"
```

### Task 5: Implement repository synchronization operations

**Files:**
- Modify: `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m:115-116,160`
- Test: `ATProtoPDS/Tests/Sync/SubscribeReposHandlerTests.m`

**Step 1: Write failing tests for extract operations and blobs**

Tests for the TODO methods.

**Step 2: Run tests**

FAIL

**Step 3: Implement extraction logic**

Add code to extract operations and blobs from commits.

**Step 4: Run tests**

PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Sync/SubscribeReposHandler.m ATProtoPDS/Tests/Sync/SubscribeReposHandlerTests.m
git commit -m "feat: implement repo sync operations"
```

### Task 6: Add missing API endpoint com.atproto.server.getServiceAuth

**Files:**
- Create: `ATProtoPDS/Sources/XRPC/Methods/GetServiceAuthMethod.m`
- Modify: `ATProtoPDS/Sources/XRPC/XrpcMethodRegistry.m`
- Test: `ATProtoPDS/Tests/XRPC/GetServiceAuthMethodTests.m`

**Step 1: Write failing test**

Test the endpoint.

**Step 2: Run test**

FAIL

**Step 3: Implement the method**

Add logic for service auth.

**Step 4: Register in registry**

Add to XrpcMethodRegistry.

**Step 5: Run test**

PASS

**Step 6: Commit**

```bash
git add ATProtoPDS/Sources/XRPC/Methods/GetServiceAuthMethod.m ATProtoPDS/Sources/XRPC/XrpcMethodRegistry.m ATProtoPDS/Tests/XRPC/GetServiceAuthMethodTests.m
git commit -m "feat: add getServiceAuth endpoint"
```

### Task 7: Re-enable DIDResolverTests

**Files:**
- Uncomment: `CMakeLists.txt:276`
- Fix: `ATProtoPDS/Tests/Identity/DIDResolverTests.m`

**Step 1: Write/update failing tests**

Ensure tests are up to date.

**Step 2: Run tests**

FAIL if broken

**Step 3: Fix DID resolution logic**

Update resolver.

**Step 4: Run tests**

PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Tests/Identity/DIDResolverTests.m CMakeLists.txt
git commit -m "fix: re-enable DIDResolverTests"
```

### Task 8: Add CLI command tests

**Files:**
- Create: `ATProtoPDS/Tests/CLI/PDSCLITests.m`
- Modify: `CMakeLists.txt` to include

**Step 1: Write failing tests for repo create-record**

Test CLI command execution.

**Step 2: Run tests**

FAIL

**Step 3: Ensure CLI logic is correct**

Already implemented. Test.

**Step 4: Run tests**

PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Tests/CLI/PDSCLITests.m CMakeLists.txt
git commit -m "feat: add CLI command tests"
```

### Task 9: Add integration tests for XrpcHandler

**Files:**
- Create: `ATProtoPDS/Tests/XRPC/XrpcHandlerTests.m`
- Modify: `CMakeLists.txt`

**Step 1: Write failing integration tests**

Test handler with real requests.

**Step 2: Run tests**

FAIL

**Step 3: Fix handler if needed**

But assume it's working.

**Step 4: Run tests**

PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Tests/XRPC/XrpcHandlerTests.m CMakeLists.txt
git commit -m "feat: add XrpcHandler unit tests"
```

### Task 10: Integrate GNUstep for Linux tests

**Files:**
- Modify: `CMakeLists.txt`
- Create: `ATProtoPDS/Tests/Linux/GNUstepTests.m` or similar

**Step 1: Write failing test for Linux compatibility**

**Step 2: Run on Linux**

FAIL

**Step 3: Configure GNUstep build**

**Step 4: Run tests**

PASS

**Step 5: Commit**

```bash
git add CMakeLists.txt ATProtoPDS/Tests/Linux/GNUstepTests.m
git commit -m "feat: integrate GNUstep for Linux tests"
```

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Tests Docs](../../tests/README) - Testing documentation