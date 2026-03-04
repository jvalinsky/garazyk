---
title: Security Hardening Implementation Plan
---

# Security Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement enterprise-grade security controls (OAuth client secret validation, JWT algorithm restriction, etc.) to address identified P0 and P1 vulnerabilities.

**Architecture:** Enhancements to existing `OAuth2Handler`, `JWTVerifier`, and `HttpServer` components. No new architectural layers.

**Tech Stack:** Objective-C, SQLite (existing)

---

## Task 1: OAuth Client Secret Validation

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2Handler.m`
- Test: `ATProtoPDS/Tests/Auth/OAuth2HandlerTests.m` (Create if needed, or add to existing)

**Step 1: Write the failing test**

```objectivec
// In OAuth2HandlerTests.m
- (void)testTokenRequestRejectsInvalidClientSecret {
    // Setup request with valid client_id but wrong client_secret
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://pds.local/oauth/token"]];
    request.HTTPMethod = @"POST";
    NSString *body = @"grant_type=authorization_code&code=valid&client_id=test-client&client_secret=wrong";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    // Execute handler
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleTokenRequest:[HttpRequest requestFromURLRequest:request] response:response];
    
    // Assert 401 Unauthorized
    XCTAssertEqual(response.statusCode, 401);
}
```

**Step 2: Run test to verify it fails**

Run: `./build/tests/AllTests`
Expected: FAIL (likely returns 200 or 400, not 401 for secret mismatch)

**Step 3: Write minimal implementation**

```objectivec
// In ATProtoPDS/Sources/Auth/OAuth2Handler.m - handleTokenRequest:
// After client ID validation:
NSString *clientSecret = params[@"client_secret"];
if (!clientSecret || ![clientSecret isEqualToString:client[@"client_secret"]]) {
    response.statusCode = 401;
    [response setJsonBody:@{
        @"error": @"invalid_client", 
        @"error_description": @"Invalid client credentials"
    }];
    return;
}
```

**Step 4: Run test to verify it passes**

Run: `./build/tests/AllTests`
Expected: PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Auth/OAuth2Handler.m ATProtoPDS/Tests/Auth/OAuth2HandlerTests.m
git commit -m "fix(auth): enforce client_secret validation in token endpoint"
```

---

### Task 2: JWT Algorithm Restriction

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/JWT.h` (Add property)
- Modify: `ATProtoPDS/Sources/Auth/JWT.m` (Use property)
- Modify: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m` (Set allowed algs)
- Test: `ATProtoPDS/Tests/Auth/JWTTests.m`

**Step 1: Write the failing test**

```objectivec
// In JWTTests.m
- (void)testVerifyJWTRejectsNoneAlgorithm {
    // Create token with "none" alg
    NSDictionary *header = @{@"alg": @"none", @"typ": @"JWT"};
    NSDictionary *payload = @{@"sub": @"did:test", @"iss": @"https://pds.local"};
    NSString *token = [self createNoneAlgTokenWithHeader:header payload:payload];
    
    JWT *jwt = [JWT jwtWithToken:token error:nil];
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.allowedAlgorithms = @[@"RS256", @"ES256"]; // Property doesn't exist yet, will fail compile
    
    NSError *error = nil;
    BOOL valid = [verifier verifyJWT:jwt error:&error];
    
    XCTAssertFalse(valid);
}
```

**Step 2: Run test to verify it fails**

Run: `./build/tests/AllTests`
Expected: FAIL (Compile error or test failure)

**Step 3: Write minimal implementation**

In `ATProtoPDS/Sources/Auth/JWT.h`:
```objectivec
@property (nonatomic, copy) NSArray<NSString *> *allowedAlgorithms;
```

In `ATProtoPDS/Sources/Auth/JWT.m - verifyJWT:error:`:
```objectivec
if (self.allowedAlgorithms && ![self.allowedAlgorithms containsObject:jwt.header.alg]) {
    if (error) {
        *error = [NSError errorWithDomain:JWTErrorDomain 
                                     code:JWTErrorInvalidAlgorithm 
                                 userInfo:@{NSLocalizedDescriptionKey: @"Algorithm not allowed"}];
    }
    return NO;
}
```

In `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`:
```objectivec
verifier.allowedAlgorithms = @[@"RS256", @"ES256"];
```

**Step 4: Run test to verify it passes**

Run: `./build/tests/AllTests`
Expected: PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Auth/JWT.h ATProtoPDS/Sources/Auth/JWT.m ATProtoPDS/Sources/Network/XrpcMethodRegistry.m ATProtoPDS/Tests/Auth/JWTTests.m
git commit -m "feat(auth): restrict allowed JWT algorithms"
```

---

### Task 3: OAuth State Parameter Requirement

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2Handler.m`
- Test: `ATProtoPDS/Tests/Auth/OAuth2HandlerTests.m`

**Step 1: Write the failing test**

```objectivec
- (void)testAuthorizeRejectsMissingState {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://pds.local/oauth/authorize?client_id=test&response_type=code&redirect_uri=http://localhost/cb"]]; // No state
    
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeRequest:[HttpRequest requestFromURLRequest:request] response:response];
    
    XCTAssertEqual(response.statusCode, 400);
}
```

**Step 2: Run test to verify it fails**

Run: `./build/tests/AllTests`
Expected: FAIL (returns 200/302)

**Step 3: Write minimal implementation**

In `ATProtoPDS/Sources/Auth/OAuth2Handler.m`:
```objectivec
if (!params[@"state"] || [(NSString *)params[@"state"] length] == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{@"error": @"invalid_request", @"error_description": @"state parameter required"}];
    return;
}
```

**Step 4: Run test to verify it passes**

Run: `./build/tests/AllTests`
Expected: PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Auth/OAuth2Handler.m ATProtoPDS/Tests/Auth/OAuth2HandlerTests.m
git commit -m "fix(auth): require state parameter for CSRF protection"
```

---

### Task 4: Basic Rate Limiting

**Files:**
- Modify: `ATProtoPDS/Sources/Network/HttpServer.m`
- Test: `ATProtoPDS/Tests/Network/RateLimitingTests.m` (New file)

**Step 1: Write the failing test**

```objectivec
- (void)testAuthEndpointRateLimiting {
    // Simulate 11 requests in rapid succession
    for (int i = 0; i < 11; i++) {
        [self sendAuthRequest];
    }
    // 11th should fail
    XCTAssertEqual(lastResponse.statusCode, 429);
}
```

**Step 2: Run test to verify it fails**

Run: `./build/tests/AllTests`
Expected: FAIL (all 200)

**Step 3: Write minimal implementation**

In `ATProtoPDS/Sources/Network/HttpServer.m`:
```objectivec
#import "Network/RateLimiter.h"

// In dispatch logic
if ([path hasPrefix:@"/oauth/"]) {
    RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForIP:clientIP];
    if (!result.allowed) {
        response.statusCode = 429;
        [response setJsonBody:@{@"error": @"too_many_requests"}];
        return;
    }
}
```

**Step 4: Run test to verify it passes**

Run: `./build/tests/AllTests`
Expected: PASS

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Network/HttpServer.m ATProtoPDS/Tests/Network/RateLimitingTests.m
git commit -m "feat(security): implement rate limiting for auth endpoints"
```

---

### Task 5: Log Sanitization

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2Handler.m`
- Modify: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

**Step 1: Manual Review (Non-TDD)**
Identify sensitive logs: `NSLog(@"Failed to parse JWT token: %@", parseError.localizedDescription);`

**Step 2: Modify Code**
Replace with: `NSLog(@"JWT parsing failed for request from IP: %@", request.remoteAddress);` (Don't log token/error content)

**Step 3: Verify**
Run tests and check logs (manual verification or grep)

**Step 4: Commit**
```bash
git add .
git commit -m "chore(security): sanitize authentication logs"
```

---

### Task 6: JWT Audience Validation

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/JWT.m`
- Modify: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- Test: `ATProtoPDS/Tests/Auth/JWTTests.m`

**Step 1: Write failing test**
Create token with wrong audience, verify rejection.

**Step 2: Implement**
In `XrpcMethodRegistry.m`:
```objectivec
verifier.expectedAudience = @"https://pds.local:8443";
```

**Step 3: Verify**
Run tests.

**Step 4: Commit**
```bash
git commit -m "feat(auth): enforce JWT audience validation"
```

---

### Task 7: Token Revocation Ownership

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2Handler.m`
- Test: `ATProtoPDS/Tests/Auth/OAuth2HandlerTests.m`

**Step 1: Write failing test**
Client A tries to revoke Client B's token. Should fail 403.

**Step 2: Implement**
Check if token was issued to `clientID` before revoking.

**Step 3: Verify**
Run tests.

**Step 4: Commit**
```bash
git commit -m "fix(auth): prevent cross-client token revocation"
```

---

### Task 8: Configurable JWT Issuer

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2Handler.m`
- Test: `ATProtoPDS/Tests/Auth/OAuth2HandlerTests.m`

**Step 1: Write failing test**
Set ENV var, verify issuer changes.

**Step 2: Implement**
Use `[[NSProcessInfo processInfo] environment][@"PDS_ISSUER"]`.

**Step 3: Verify**
Run tests.

**Step 4: Commit**
```bash
git commit -m "feat(config): make JWT issuer configurable"
```

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Security Docs](../../security/README) - Security-related documentation
- [OAuth2 Documentation](../../oauth2/README) - OAuth2 implementation details
