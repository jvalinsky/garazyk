# Test Organization

September PDS uses a comprehensive test suite with over 1,000 tests organized by functional area. This document describes the test structure, naming conventions, and discovery mechanism.

## Test Directory Structure

Tests mirror the source code organization under `ATProtoPDS/Tests/`:

```
ATProtoPDS/Tests/
├── Admin/              # Admin endpoints & moderation tests
├── App/                # Application layer tests
├── Auth/               # Authentication & OAuth tests
├── Blob/               # Blob storage tests
├── CharacterizationTests/  # Characterization tests
├── CLI/                # CLI command tests
├── Core/               # Core protocol tests (CBOR, CAR, CID, MST)
├── Database/           # Database layer tests
├── Email/              # Email provider tests
├── Identity/           # DID & handle resolution tests
├── Integration/        # Integration tests
├── Interop/            # Interoperability tests
├── Lexicon/            # Lexicon validation tests
├── Metrics/            # Metrics collection tests
├── Network/            # HTTP server & XRPC tests
├── PLC/                # PLC directory tests
├── Repository/         # Repository operations tests
├── Security/           # Security hardening tests
├── Services/           # Service layer tests
├── Sync/               # Firehose & WebSocket tests
├── XRPC/               # XRPC protocol tests
├── fixtures/           # Test fixtures and data
└── test_main.m         # Test runner entry point
```

## Test Discovery Mechanism

September uses Objective-C runtime reflection for test discovery. The test runner (`test_main.m`) discovers test methods dynamically:

### Discovery Algorithm

```objective-c
NSArray *discoverTestMethodsForClass(Class testClass) {
  NSMutableArray *methods = [NSMutableArray array];
  unsigned int methodCount;
  Method *methodList = class_copyMethodList(testClass, &methodCount);
  
  for (unsigned int i = 0; i < methodCount; i++) {
    Method method = methodList[i];
    SEL selector = method_getName(method);
    NSString *methodName = NSStringFromSelector(selector);
    
    // Match methods starting with "test"
    if ([methodName hasPrefix:@"test"]) {
      char *returnType = method_copyReturnType(method);
      int numArgs = method_getNumberOfArguments(method);
      
      // Must return void and take no arguments (except self, _cmd)
      if (returnType && strcmp(returnType, "v") == 0 && numArgs == 2) {
        [methods addObject:methodName];
      }
      free(returnType);
    }
  }
  free(methodList);
  return [methods copy];
}
```

### Test Class Registration

Test classes must be registered in the `testClasses` array in `test_main.m`:

```objective-c
NSArray *testClasses = @[
  @"MSTInteropTests",
  @"CARInteropTests",
  @"OAuthIntegrationTests",
  @"FirehoseIntegrationTests",
  // ... 150+ test classes
];
```

**Adding a new test class:**

1. Create test class inheriting from `XCTestCase`
2. Add class name to `testClasses` array in `test_main.m`
3. Rebuild and run tests

## Naming Conventions

### Test Class Names

Test classes follow the pattern: `<Component><TestType>Tests`

Examples:
- `MSTInteropTests` - MST interoperability tests
- `OAuthIntegrationTests` - OAuth integration tests
- `PDSAccountServiceTests` - PDSAccountService unit tests
- `ActorStoreCharacterizationTests` - ActorStore characterization tests

### Test Method Names

Test methods must:
- Start with `test` prefix
- Use camelCase
- Be descriptive of what is being tested
- Return `void`
- Take no parameters

Examples:
```objective-c
- (void)testCreateAccount;
- (void)testBroadcastCommitCARContainsRecordBlocks;
- (void)testFullOAuthFlow;
- (void)testHandleResolutionWithSSRFProtection;
```

### Test Categories

Tests are organized into several categories:

1. **Unit Tests** - Test individual components in isolation
   - Example: `PDSAccountServiceTests`, `JWTTests`

2. **Integration Tests** - Test multiple components working together
   - Example: `OAuthIntegrationTests`, `FirehoseIntegrationTests`
   - Located in `ATProtoPDS/Tests/Integration/`

3. **Interoperability Tests** - Test compliance with AT Protocol specs
   - Example: `MSTInteropTests`, `CARInteropTests`
   - Located in `ATProtoPDS/Tests/Interop/`

4. **Characterization Tests** - Document existing behavior
   - Example: `ActorStoreCharacterizationTests`, `MSTCharacterizationTests`
   - Located in `ATProtoPDS/Tests/CharacterizationTests/`

5. **Security Tests** - Test security hardening and attack prevention
   - Example: `CBORSecurityTests`, `HandleResolverSSRFTests`
   - Located in `ATProtoPDS/Tests/Security/`

## Test Fixtures

Test fixtures are stored in `ATProtoPDS/Tests/fixtures/`:

```
fixtures/
├── car/           # CAR file test data
├── cbor/          # CBOR encoding test data
├── did/           # DID document fixtures
├── lexicons/      # Lexicon schema fixtures
└── mst/           # MST tree fixtures
```

### Using Fixtures

```objective-c
NSBundle *bundle = [NSBundle bundleForClass:[self class]];
NSString *fixturePath = [bundle pathForResource:@"test-car" ofType:@"car"];
NSData *carData = [NSData dataWithContentsOfFile:fixturePath];
```

## Test Environment Configuration

The test runner configures the environment for non-interactive testing:

```objective-c
// Disable interactive features
setenv("PDS_RUNNING_TESTS", "1", 1);
setenv("PDS_USE_KEYCHAIN", "0", 1);
setenv("PDS_USE_SECURE_ENCLAVE", "0", 1);
setenv("PDS_USE_BIOMETRIC_PROTECTION", "0", 1);

// Bind to loopback to avoid macOS network permission prompts
setenv("PDS_LISTEN_HOST", "127.0.0.1", 1);

// Disable rate limiting
RateLimiterSetDisabledGlobally(YES);
[RateLimiter sharedLimiter].enabled = NO;

// Disable biometric protection
[PDSConfiguration sharedConfiguration].useBiometricProtection = NO;
[PDSConfiguration sharedConfiguration].useKeychain = NO;
```

## Running Tests

### Run All Tests

```bash
./build/tests/AllTests
```

### Run Specific Test Class

```bash
./build/tests/AllTests -XCTest MSTInteropTests
```

### Run Multiple Test Classes

```bash
./build/tests/AllTests -XCTest MSTInteropTests,CARInteropTests
```

### Build and Run Tests (macOS)

```bash
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

## Test Output

The test runner provides detailed output:

```
=== Starting Test Suite: All Tests ===
Test suites: 150

Test Case '-[MSTInteropTests testBasicTreeOperations]' started.
Test Case '-[MSTInteropTests testBasicTreeOperations]' passed (0.023 seconds).

Test Case '-[OAuthIntegrationTests testFullOAuthFlow]' started.
Test Case '-[OAuthIntegrationTests testFullOAuthFlow]' passed (0.156 seconds).

=== Test Suite Finished ===
Tests run: 1017
Failures: 0
```

### Failure Output

When tests fail, detailed diagnostics are provided:

```
FAIL: -[HandleResolverTests testSSRFProtection] at HandleResolverTests.m:45: 
Expected private IP to be rejected
```

## Test Lifecycle

### Setup and Teardown

```objective-c
@interface MyTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, copy) NSString *tempDir;
@end

@implementation MyTests

- (void)setUp {
    [super setUp];
    
    // Create temporary directory
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:guid];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:nil];
    
    // Initialize controller
    self.controller = [[PDSController alloc] initWithDirectory:self.tempDir
                                                serviceMaxSize:5
                                              userDatabaseSize:5];
}

- (void)tearDown {
    // Cleanup
    [self.controller stopServer];
    if (self.tempDir) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    }
    [super tearDown];
}

- (void)testSomething {
    // Test implementation
}

@end
```

## Platform-Specific Tests

Some tests are platform-specific and use conditional compilation:

```objective-c
#ifndef GNUSTEP
- (void)testMacOSSpecificFeature {
    // macOS-only test
}
#endif

#ifdef __linux__
- (void)testLinuxSpecificFeature {
    // Linux-only test
}
#endif
```

## Test Skipping

Tests can be skipped conditionally:

```objective-c
- (void)testRequiresNetworkAccess {
    if (getenv("PDS_SKIP_NETWORK_TESTS")) {
        XCTSkip(@"Network tests disabled");
    }
    // Test implementation
}
```

## Best Practices

1. **Isolation** - Each test should be independent and not rely on other tests
2. **Cleanup** - Always clean up resources in `tearDown`
3. **Descriptive Names** - Test names should clearly describe what is being tested
4. **Fast Execution** - Keep tests fast; use mocks for slow operations
5. **Deterministic** - Tests should produce the same result every time
6. **Temporary Files** - Use unique temporary directories for each test
7. **Error Messages** - Provide clear failure messages with context

## See Also

- [Property-Based Testing](property-based-testing.md) - PBT framework and generators
- [E2E Testing](e2e-testing.md) - End-to-end test scenarios
- [Test Coverage Goals](test-coverage-goals.md) - Coverage targets and gaps
- [Troubleshooting](troubleshooting.md) - Common test failures and solutions
