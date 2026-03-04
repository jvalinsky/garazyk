---
title: Admin Tests
---

# Admin Tests

Tests for admin controller, service, authentication, and middleware.

## Test Classes

### PDSAdminControllerTests
**File:** `Tests/Admin/PDSAdminControllerTests.m`

**Purpose:** Admin operations for account moderation, takedowns, and labeling.

#### How It Works

**Account moderation:**

```objc
PDSAdminController *controller = [[PDSAdminController alloc] initWithServiceDatabases:databases];

// Takedown account
NSError *error;
[controller moderateAccountWithDID:@"did:plc:abc"
                           action:@"takedown"
                            reason:@"spam"
                            error:&error];

// Verify takedown status
BOOL isTakedown = [controller isAccountTakedownActive:@"did:plc:abc" error:nil];
XCTAssertTrue(isTakedown);

// Reinstate account
[controller moderateAccountWithDID:@"did:plc:abc"
                           action:@"reinstate"
                            reason:@"appeal approved"
                            error:&error];
```

**Label creation:**

```objc
[controller createLabelWithURI:@"at://did:plc:abc/app.bsky.feed.post/123"
                         value:@"porn"
                        source:@"moderation"
                         error:&error];

NSArray *labels = [controller getLabelsWithURIPatterns:@[@"did:plc:abc"] limit:100 error:nil];
XCTAssertEqual(labels.count, 1);
```

---

### PDSAdminServiceTests
**File:** `Tests/Admin/PDSAdminServiceTests.m`

**Purpose:** Account updates, invite codes, database operations.

#### How It Works

**Invite code management:**

```objc
// Create invite code
NSString *code = [service createInviteCodeForAccount:@"did:plc:admin" uses:5 error:nil];

// List codes
NSArray *codes = [service getInviteCodesForAccount:@"did:plc:admin" error:nil];

// Disable code
[service disableInviteCode:code error:nil];
```

**Account updates:**

```objc
[service updateHandle:@"new.handle" forAccount:@"did:plc:abc" error:nil];
[service updateEmail:@"new@email.com" forAccount:@"did:plc:abc" error:nil];
[service updatePassword:@"newsecret" forAccount:@"did:plc:abc" error:nil];
```

---

### PDSAdminAuthTests
**File:** `Tests/Admin/PDSAdminAuthTests.m`

**Purpose:** JWT-based admin authentication and token validation.

#### How It Works

```objc
PDSAdminAuth *auth = [[PDSAdminAuth alloc] initWithIssuer:@"https://pds.example.com"
                                              tokenTTL:3600
                                             adminDIDs:@[@"did:plc:admin"]];

// Authenticate
NSDictionary *token = [auth authenticateWithPassword:adminPassword error:nil];
XCTAssertNotNil(token[@"access_token"]);

// Validate request
HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                headers:@{@"authorization": @"Bearer <token>"} ...];
BOOL isAuth = [auth isAuthenticatedWithRequest:request error:nil];
XCTAssertTrue(isAuth);

// Logout invalidates all tokens
[auth logout];
isAuth = [auth isAuthenticatedWithRequest:request error:nil];
XCTAssertFalse(isAuth);  // Token revoked
```

---

### AdminMiddlewareTests
**File:** `Tests/Admin/AdminMiddlewareTests.m`

**Purpose:** Request authorization and admin DID access control.

#### How It Works

```objc
AdminMiddleware *middleware = [[AdminMiddleware alloc] initWithAdminDIDs:@[@"did:plc:admin"]];

// Missing auth header
HttpResponse *response = [[HttpResponse alloc] init];
[middleware processRequest:request response:response next:nil];
XCTAssertEqual(response.statusCode, 401);

// Valid admin
request.headers[@"authorization"] = @"Bearer <admin-token>";
[middleware processRequest:request response:response next:nil];
XCTAssertEqual(response.statusCode, 200);  // Proceeds

// Non-admin token
request.headers[@"authorization"] = @"Bearer <user-token>";
[middleware processRequest:request response:response next:nil];
XCTAssertEqual(response.statusCode, 403);
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSAdminControllerTests
./build/tests/AllTests -only-testing:AllTests/PDSAdminServiceTests
./build/tests/AllTests -only-testing:AllTests/PDSAdminAuthTests
./build/tests/AllTests -only-testing:AllTests/AdminMiddlewareTests
```

## Related Documentation

- [Folder README](README) - Application tests overview
- [Test Index](../README) - Main test documentation index
- [Services Tests](services) - Business services
- [Controller Tests](controller) - Application lifecycle
- [Auth Security Tests](../05-security/auth-security) - Admin authorization
- [Security Hardening Tests](../05-security/hardening) - Production security
- [Admin Auth Configuration](../../security/ADMIN_AUTH_CONFIGURATION) - Admin auth setup
- [Database Tests](../03-database/service-databases) - Invite code storage
