---
name: garazyk-testing
description: Garazyk PDS test infrastructure, mock patterns, environment gating, registration conventions, and runner workflow.
---

# Garazyk Testing Patterns

The test suite uses XCTest with a custom `test_main.m` runner (not XCTest's automatic discovery). Tests live in `Garazyk/Tests/` (33 subdirectories). Runner: `scripts/test/run-tests.sh` → `build/tests/AllTests`.

## Test Registration

**File:** `Garazyk/Tests/test_main.m:500-772`
**Pattern:** Explicit `NSArray *testClasses = @[ ... ]` containing ~270 class names. Every new test class must be added to this array.

### Registration Audit (`test_main.m:793`)
Set `PDS_TEST_REGISTRATION_AUDIT=1` to compare registered classes vs runtime `XCTestCase` subclasses:
```bash
PDS_TEST_REGISTRATION_AUDIT=1 build/tests/AllTests
```
Reports:
- **Missing:** runtime classes not in the registration array (need to be added)
- **Stale:** registered classes not found at runtime (need to be removed)

### Filtering (`test_main.m:170-239`)
Run a specific class or method:
```bash
build/tests/AllTests -XCTest PDSHealthCheckTests
build/tests/AllTests -XCTest "PDSHealthCheckTests/testHealthCheckHealthy"
```

## Environment Gating

### PDSEnvEnabled helper (`test_main.m:155`)
```objc
static BOOL PDSEnvEnabled(const char *name) {
    // checks getenv() for "1", "true", "yes", "on"
}
```

### Gated Class Lists (`test_main.m:241-299`)
- **Integration tests** (require `PDS_RUN_INTEGRATION_TESTS=1`): PDSPLCIntegrationTests, PDSIntegrationTests, RelayIntegrationTests, OAuthIntegrationTests, EmailIntegrationTests, FirehoseIntegrationTests, etc. (14 classes)
- **Socket tests** (require `PDS_RUN_SOCKET_TESTS=1`, or `PDS_RUN_INTEGRATION_TESTS=1`): HealthEndpointIntegrationTests, HttpServerTests, OAuth2EndpointTests, PDSApplicationTests, ATProtoHttpServerBuilderTests, PLCServerTests, PDSWebSocketServerTests, etc. (10 classes)

### Running Gated Tests
```bash
# Integration tests only
PDS_RUN_INTEGRATION_TESTS=1 build/tests/AllTests

# Socket tests only
PDS_RUN_SOCKET_TESTS=1 build/tests/AllTests
```

### PDS_RUNNING_TESTS Detection
Set automatically by `test_main.m:445`. Checked in production code at:
- `PDSApplication.m:89` — disables full app initialization
- `HandleResolver.m:54-60` — disables network DNS lookups
- `ATProtoServiceConfiguration.m:72` — uses test-safe defaults
- `XrpcLexiconResolver.m:463` — disables remote lexicon fetching
- `FederationClient.m:24` — disables real federation requests
- `OAuth2.m:60` — disables OAuth flows

Three-way detection (`HandleResolver.m:54-60`):
```objc
static BOOL PDSHandleResolverRunningTests(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if ([env[@"PDS_RUNNING_TESTS"] length] > 0 ||
        [env[@"XCTestConfigurationFilePath"] length] > 0)
        return YES;
    return NSClassFromString(@"XCTestCase") != Nil;
}
```

### Test Mode Defaults (`test_main.m:446-477`)
| Env Var | Default Value |
|---------|---------------|
| `PDS_USE_KEYCHAIN` | `0` |
| `PDS_USE_SECURE_ENCLAVE` | `0` |
| `PDS_USE_BIOMETRIC_PROTECTION` | `0` |
| `PDS_MASTER_SECRET` | `test-master-secret-123` |
| `PDS_PLC_URL` | `skip` |
| `PDS_LISTEN_HOST` | `127.0.0.1` |

## Mock Patterns

### Pattern A: MockURLSession + Subclass Override

**File:** `Tests/Identity/HandleResolverTests.m`
**For:** Classes that internally use SafeHTTP/NSURLSession and can't easily accept injected dependencies.

1. Create a `MockURLSession` that stores `mockResponse` + `mockError`, returns `MockDataTask` from `dataTaskWithRequest:`.
2. Create a `TestHandleResolver` subclass of the real class.
3. Override `executeSafeHTTPSRequest:options:attempt:completion:` to route through `mockSession`.
4. Wire `mockSession` via a property on the subclass.

```objc
MockURLSession *session = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:abc"} error:nil delay:0.1];
HandleResolver *resolver = [[TestHandleResolver alloc] init];
((TestHandleResolver *)resolver).mockSession = session;
```

### Pattern B: KVC Injection for Property-Backed Ivar

**File:** `Tests/Email/PDSEmailHTTPClientTests.m`
**For:** Classes that use a property ivar for SafeHTTP/URLSession.

1. Create a `TestHTTPSession` implementing the expected selectors (including `performSafeDataTaskWithRequest:options:completion:`).
2. Inject via `setValue:forKey:`.

```objc
PDSEmailHTTPClient *client = [[PDSEmailHTTPClient alloc] initWithBaseURL:url apiKey:@"test-key"];
[client setValue:session forKey:@"safeHTTPClient"];
```

### Pattern C: Method Swizzle for Singletons

**File:** `Tests/Database/Monitoring/PDSHealthCheckTests.m`
**For:** Classes that depend on `sharedInstance` singletons.

1. Create a `gTestServiceDatabases` static in the test file.
2. Add a test category with a `test_sharedInstance` method returning the static.
3. Use `method_exchangeImplementations` in `setUp` / `tearDown`.

```objc
static PDSServiceDatabases *gTestServiceDatabases = nil;

@implementation PDSServiceDatabases (Testing)
+ (instancetype)test_sharedInstance { return gTestServiceDatabases; }
@end

- (void)setUp {
    gTestServiceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDir ...];
    Method original = class_getClassMethod([PDSServiceDatabases class], @selector(sharedInstance));
    Method swizzled = class_getClassMethod([PDSServiceDatabases class], @selector(test_sharedInstance));
    method_exchangeImplementations(original, swizzled);
}
```

### Pattern D: Direct alloc/init (Preferred over Singleton)

**File:** `Tests/Database/Monitoring/PDSHealthCheckTests.m` (current approach)
**For:** Classes that support `initWithServiceDatabases:`.

Prefer `[[PDSHealthCheck alloc] initWithServiceDatabases:gTestServiceDatabases]` over swizzling `sharedInstance` whenever the class offers a direct initializer.

## Check Before Writing a New Test

1. Does the test class name exist in `test_main.m:500-772`? If not, add it.
2. Does the test require integration/socket env vars? Gate it in `PDSSkipReasonForClass()`.
3. Which mock pattern fits? (A: subclass override, B: KVC injection, C: swizzle, D: direct init)
4. Is the test GNUstep-compatible? Add `#ifndef GNUSTEP` for macOS-only tests.
5. Is there an existing test fixture? Check `Tests/Database/Integration/` for DB fixtures.

## Running Tests

### Full Suite
```bash
scripts/test/run-tests.sh
```
This runs `check_ui_design_system.sh` first, then executes `build/tests/AllTests`.

### Build + Test
```bash
xcodegen generate
xcodebuild -scheme AllTests build
scripts/test/run-tests.sh
```

### Quick Iteration
```bash
xcodebuild -scheme AllTests build && build/tests/AllTests -XCTest MyTestClass
```

### Pre-submit Quality Gate
Run `scripts/test/check_ui_design_system.sh` separately:
```bash
scripts/test/check_ui_design_system.sh
```
This validates HTML/CSS/JS files for inline styles and design token usage.

## Quick Reference

| Task | Command |
|------|---------|
| Build all tests | `xcodebuild -scheme AllTests build` |
| Run full suite | `scripts/test/run-tests.sh` |
| Run one class | `build/tests/AllTests -XCTest ClassName` |
| Run one method | `build/tests/AllTests -XCTest "Class/method"` |
| Registration audit | `PDS_TEST_REGISTRATION_AUDIT=1 build/tests/AllTests` |
| Integration tests | `PDS_RUN_INTEGRATION_TESTS=1 build/tests/AllTests` |
| Socket tests | `PDS_RUN_SOCKET_TESTS=1 build/tests/AllTests` |
| UI design check | `scripts/test/check_ui_design_system.sh` |
