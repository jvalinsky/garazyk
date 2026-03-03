# CLI Tests

Tests for CLI command dispatcher and subcommands.

## Test Classes

### PDSCLITests
**File:** `Tests/CLI/PDSCLITests.m`

**Purpose:** CLI dispatcher and basic command registration.

#### How It Works

**Command registration:**

```objc
PDSCLIDispatcher *dispatcher = [PDSCLIDispatcher sharedDispatcher];

// Built-in commands
XCTAssertTrue([dispatcher hasCommand:@"help"]);
XCTAssertTrue([dispatcher hasCommand:@"serve"]);
XCTAssertTrue([dispatcher hasCommand:@"account"]);
XCTAssertTrue([dispatcher hasCommand:@"repo"]);
XCTAssertTrue([dispatcher hasCommand:@"invite"]);
XCTAssertTrue([dispatcher hasCommand:@"nuke"]);
```

**Command execution:**

```objc
int result = [dispatcher runWithArguments:@[@"help"] context:context];
XCTAssertEqual(result, 0);

result = [dispatcher runWithArguments:@[@"unknown-command"] context:context];
XCTAssertEqual(result, 1);  // Exit code for unknown command
```

---

### PDSCLIAccountCommandTests
**File:** `Tests/CLI/PDSCLIAccountCommandTests.m`

**Purpose:** Account subcommands (create, list, info).

#### How It Works

**Account creation:**

```objc
int result = [dispatcher runWithArguments:@[
    @"account", @"create",
    @"--email", @"user@example.com",
    @"--handle", @"user.bsky.social",
    @"--password", @"secret123"
] context:context];

XCTAssertEqual(result, 0);
```

**Account listing:**

```objc
int result = [dispatcher runWithArguments:@[
    @"account", @"list",
    @"--json"
] context:context];

XCTAssertEqual(result, 0);
// Output: [{"did": "did:plc:abc", "handle": "user.bsky.social", ...}]
```

---

### PDSCLIInviteCommandTests
**File:** `Tests/CLI/PDSCLIInviteCommandTests.m`

**Purpose:** Invite subcommands using stub manager.

#### How It Works

**Create invite:**

```objc
int result = [dispatcher runWithArguments:@[
    @"invite", @"create",
    @"--uses", @"5"
] context:context];

XCTAssertEqual(result, 0);
// Output: Created invite code: abc123...
```

**List invites:**

```objc
int result = [dispatcher runWithArguments:@[
    @"invite", @"list",
    @"--used"  // Include used/disabled
] context:context];

XCTAssertEqual(result, 0);
```

---

### PDSCLIServiceStubTests
**File:** `Tests/CLI/PDSCLIServiceStubTests.m`

**Purpose:** Service auth payload generation.

#### How It Works

```objc
PDSCLIServiceStub *stub = [PDSCLIServiceStub sharedStub];

// Generate auth payload
NSDictionary *payload = [stub authPayloadForDID:@"did:plc:abc"
                                    method:@"POST"
                                      path:@"/xrpc/com.atproto.repo.createRecord"
                                   service:@"https://pds.example.com"
                                      error:nil];

XCTAssertNotNil(payload[@"iss"]);  // Issuer DID
XCTAssertNotNil(payload[@"aud"]);  // Service URL
XCTAssertNotNil(payload[@"lxm"]); // Lexicon method
XCTAssertNotNil(payload[@"exp"]); // Expiration
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSCLITests
./build/tests/AllTests -only-testing:AllTests/PDSCLIAccountCommandTests
./build/tests/AllTests -only-testing:AllTests/PDSCLIInviteCommandTests
```

## CLI Commands

```
kaszlak account create --email user@example.com --handle user.bsky.social --password secret
kaszlak account list --json
kaszlak account info --handle user.bsky.social
kaszlak invite create --uses 5
kaszlak invite list --used
kaszlak invite revoke <code>
```

## Related Documentation

- [Folder README](README) - Application tests overview
- [Test Index](../README) - Main test documentation index
- [Services Tests](services) - Account and invite services
- [Controller Tests](controller) - Application lifecycle
- [Database Tests](../03-database/service-databases) - Invite code storage
- [Utilities Tests](../09-utilities/debug) - Debug tools
