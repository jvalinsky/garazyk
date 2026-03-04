---
title: Authorization Security Tests
---

# Authorization Security Tests

Tests for XRPC endpoint authorization and access control.

## Test Classes

### AdminAuthXrpcTests
**File:** `Tests/Network/AdminAuthXrpcTests.m`

**Purpose:** Admin XRPC endpoint authentication and authorization.

#### How It Works

**401 for unauthenticated requests:**

```objc
HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                headers:@{}  // No auth
                                                   ...];
HttpResponse *response = [[HttpResponse alloc] init];
[dispatcher handleRequest:request response:response];
XCTAssertEqual(response.statusCode, 401);
```

**403 for non-admin authenticated requests:**

```objc
NSString *userToken = [jwtMinter mintTokenForDID:@"did:plc:user" ...];
request.headers[@"authorization"] = [NSString stringWithFormat:@"Bearer %@", userToken];

[dispatcher handleRequest:request response:response];
XCTAssertEqual(response.statusCode, 403);  // Forbidden
```

**Admin access succeeds:**

```objc
NSString *adminToken = [jwtMinter mintTokenForDID:@"did:plc:admin" ...];
request.headers[@"authorization"] = [NSString stringWithFormat:@"Bearer %@", adminToken];

[dispatcher handleRequest:request response:response];
XCTAssertEqual(response.statusCode, 200);
```

**JWT claim validation:**

```objc
// Issuer mismatch
request.headers[@"authorization"] = @"Bearer <token-with-wrong-iss>";
[dispatcher handleRequest:request response:response];
XCTAssertEqual(response.statusCode, 401);

// Audience mismatch
request.headers[@"authorization"] = @"Bearer <token-with-wrong-aud>";
[dispatcher handleRequest:request response:response];
XCTAssertEqual(response.statusCode, 401);
```

---

### RepoAuthXrpcTests
**File:** `Tests/Network/RepoAuthXrpcTests.m`

**Purpose:** Repository operation authorization.

#### How It Works

**Cross-repo write protection:**

```objc
// User tries to write to another user's repo
NSString *userToken = [jwtMinter mintTokenForDID:@"did:plc:alice" ...];

HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                       path:@"/xrpc/com.atproto.repo.putRecord"
                                                    headers:@{@"authorization": userToken}
                                                       body:jsonBody
                                             remoteAddress:@"127.0.0.1"];
// Body contains: {"repo": "did:plc:bob", ...}

[dispatcher handleRequest:request response:response];
XCTAssertEqual(response.statusCode, 403);  // Cannot write to bob's repo
```

**Session revocation:**

```objc
[controller deleteSessionForDID:@"did:plc:alice" error:nil];

// Old token should no longer work
request.headers[@"authorization"] = oldToken;
[dispatcher handleRequest:request response:response];
XCTAssertEqual(response.statusCode, 401);
```

---

### AdminModerationAuthTests
**File:** `Tests/XRPC/AdminModerationAuthTests.m`

**Purpose:** Admin moderation endpoint authorization.

---

### PDSAuthzManagerTests
**File:** `Tests/Security/PDSAuthzManagerTests.m`

**Purpose:** Authorization manager for access control.

---

## Authorization Matrix

| Endpoint | Anonymous | Authenticated User | Admin |
|----------|-----------|-------------------|-------|
| getRepo | ✓ | ✓ | ✓ |
| putRecord | ✗ | ✓ (own repo) | ✓ |
| deleteRecord | ✗ | ✓ (own repo) | ✓ |
| getAccountInfo | ✗ | ✗ | ✓ |
| moderateAccount | ✗ | ✗ | ✓ |
| createLabel | ✗ | ✗ | ✓ |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/AdminAuthXrpcTests
./build/tests/AllTests -only-testing:AllTests/RepoAuthXrpcTests
./build/tests/AllTests -only-testing:AllTests/AdminModerationAuthTests
```

## Related Documentation

- [Folder README](README) - Security tests overview
- [Test Index](../README) - Main test documentation index
- [Hardening Tests](hardening) - Production security hardening
- [Validation Tests](validation) - Input validation
- [OAuth Tests](../00-identity-auth/oauth) - OAuth2 flows
- [JWT & Crypto Tests](../00-identity-auth/jwt-crypto) - JWT verification
- [XRPC Tests](../02-network/xrpc) - XRPC protocol
- [Admin Tests](../04-application/admin) - Admin operations
- [OAuth2 Security](../../oauth2/security) - OAuth2 security model
- [Admin Auth Configuration](../../security/ADMIN_AUTH_CONFIGURATION) - Admin auth setup
