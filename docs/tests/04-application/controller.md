# Controller & Application Tests

Tests for PDS application lifecycle, controllers, and configuration.

## Test Classes

### PDSApplicationTests
**File:** `Tests/App/PDSApplicationTests.m`

**Purpose:** Application lifecycle, service initialization, controller wiring.

#### How It Works

**Application boot sequence:**

```objc
PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempDir];

// Services initialized but not started
XCTAssertNotNil(app.serviceDatabases);
XCTAssertNotNil(app.userDatabasePool);
XCTAssertNotNil(app.jwtMinter);
XCTAssertNotNil(app.accountService);
XCTAssertNotNil(app.recordService);
XCTAssertFalse(app.isRunning);

// Start application
NSError *error;
BOOL started = [app startWithError:&error];
XCTAssertTrue(started);
XCTAssertTrue(app.isRunning);
XCTAssertNotNil(app.httpServer);
XCTAssertGreaterThan(app.httpPort, 0);
```

**Graceful shutdown:**

```objc
[app stop];
XCTAssertFalse(app.isRunning);
XCTAssertNil(app.httpServer);

// Can restart
started = [app startWithError:&error];
XCTAssertTrue(started);
```

#### Why It Matters

| Phase | What Happens |
|-------|--------------|
| Init | Service containers created |
| Start | HTTP server binds, services activate |
| Stop | Connections drained, resources freed |

---

### PDSConfigurationTests
**File:** `Tests/App/PDSConfigurationTests.m`

**Purpose:** Configuration loading, environment overrides, rate limits.

#### How It Works

**Configuration hierarchy:**

```objc
// 1. Defaults
PDSConfiguration *config = [[PDSConfiguration alloc] init];
XCTAssertEqual(config.rateLimitDID, 5000);

// 2. Config file overrides defaults
[config loadFromFile:@"config.json" error:nil];
XCTAssertEqual(config.rateLimitDID, 10000);

// 3. Environment overrides all
setenv("PDS_RATE_LIMIT_DID", "20000", 1);
[config loadFromEnvironment];
XCTAssertEqual(config.rateLimitDID, 20000);
```

**Issuer configuration:**

```objc
setenv("PDS_ISSUER", "https://pds.example.com", 1);
[config loadFromEnvironment];

NSString *canonical = [config canonicalIssuerWithHost:@"pds.example.com" port:443];
XCTAssertEqualObjects(canonical, @"https://pds.example.com");
```

---

### PDSServiceContainerTests
**File:** `Tests/Core/PDSServiceContainerTests.m`

**Purpose:** Dependency injection container registration/resolution.

#### How It Works

```objc
PDSServiceContainer *container = [[PDSServiceContainer alloc] init];

// Register instance
PDSAccountService *accountService = [[PDSAccountService alloc] init];
[container registerInstance:accountService forKey:@"accountService"];

// Register factory (lazy)
[container registerFactory:^id { return [[PDSRecordService alloc] init]; } 
                  forKey:@"recordService"];

// Resolve
PDSAccountService *resolved = [container resolveForKey:@"accountService"];
XCTAssertEqual(resolved, accountService);  // Same instance

PDSRecordService *record = [container resolveForKey:@"recordService"];
PDSRecordService *record2 = [container resolveForKey:@"recordService"];
XCTAssertEqual(record, record2);  // Factory cached
```

---

### PDSAccountManagerTests
**File:** `Tests/Core/PDSAccountManagerTests.m`

**Purpose:** SQLite account repository CRUD and pagination.

#### How It Works

```objc
PDSAccountManager *manager = [[PDSAccountManager alloc] initWithDatabasePath:dbPath];

// Create account
[manager createAccountWithDID:@"did:plc:abc" handle:@"user.bsky.social" email:@"user@example.com"];

// Retrieve by DID
PDSDatabaseAccount *account = [manager accountForDID:@"did:plc:abc"];
XCTAssertEqualObjects(account.handle, @"user.bsky.social");

// Retrieve by handle
account = [manager accountForHandle:@"user.bsky.social"];
XCTAssertEqualObjects(account.did, @"did:plc:abc");

// Paginated listing
NSArray *accounts = [manager listAccountsWithCursor:nil limit:10];
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSApplicationTests
./build/tests/AllTests -only-testing:AllTests/PDSConfigurationTests
./build/tests/AllTests -only-testing:AllTests/PDSServiceContainerTests
```

## Related Documentation

- [Folder README](README) - Application tests overview
- [Test Index](../README) - Main test documentation index
- [Services Tests](services) - Business services
- [Admin Tests](admin) - Admin operations
- [HTTP Stack Tests](../02-network/http-stack) - HTTP server
- [Database Tests](../03-database/README) - Database initialization
- [Utilities Tests](../09-utilities/config-metrics) - Configuration details
