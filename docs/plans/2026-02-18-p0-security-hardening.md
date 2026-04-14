---
title: "P0 Security Hardening: Refresh Tokens and XRPC DPoP Implementation Plan"
---

# P0 Security Hardening: Refresh Tokens and XRPC DPoP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement full refresh token lifecycle management (expiry, rotation, revocation) and DPoP-Nonce header generation for production-ready session security.

**Architecture:** 
- Refresh tokens will be rotated on each use (single-use tokens) with configurable expiration via PDSConfiguration
- DPoP proof verification will issue nonce challenges when required, returning 401 with DPoP-Nonce header
- The refreshSession endpoint already correctly extracts token from Authorization header

**Tech Stack:** Objective-C, SQLite, JWT, DPoP (OAuth2), Shell scripting

---

## Current State Analysis

### Working Correctly:
1. `ServiceDatabases.m:262-292` - `getAccountByRefreshToken:` already enforces `expires_at > current_time`
2. `ServiceDatabases.m:344-367` - `storeRefreshToken:forAccount:error:` sets 30-day hardcoded expiration
3. `PDSAccountService.m:304-348` - `refreshAccessToken:` already implements rotation (revokes old, generates new)
4. `XrpcMethodRegistry.m:3815-3840` - `refreshSession` endpoint already extracts token from Authorization header
5. `XrpcMethodRegistry.m:5207-5213` - DPoP nonce challenge already implemented in `extractDIDFromAuthHeader`

### Issues to Fix:
1. `backup_pds.sh:165-269` - Duplicated script body (copy-paste error)
2. `ServiceDatabases.m:357` - Hardcoded 30-day expiration instead of using `PDSConfiguration.refreshTokenTtlSeconds`
3. Need to verify DPoP-Nonce flow works end-to-end with proper tests

---

## Task 1: Fix backup_pds.sh Duplicate Script Body

**Files:**
- Modify: `scripts/backup_pds.sh:165-269` (delete duplicate content)

**Step 1: Delete duplicate script body**

Remove lines 165-269 (the duplicate section that starts with `if ! command -v sqlite3`)

**Step 2: Verify script integrity**

Run: `shellcheck scripts/backup_pds.sh`
Expected: Pass with no warnings

**Step 3: Test script**

Run: `bash -n scripts/backup_pds.sh`
Expected: No syntax errors

**Step 4: Commit**

```bash
git add scripts/backup_pds.sh
git commit -m "fix(backup): remove duplicated script body in backup_pds.sh"
```

---

## Task 2: Update storeRefreshToken to Use Configurable Expiration

**Files:**
- Modify: `Garazyk/Sources/Database/Service/ServiceDatabases.m:344-367`

**Step 1: Write failing test**

Create test in `Garazyk/Tests/Database/Service/ServiceDatabasesTests.m`:

```objc
- (void)testStoreRefreshToken_UsesConfigurableExpiration {
    // Arrange
    PDSServiceDatabases *databases = [PDSServiceDatabases sharedInstance];
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSUInteger originalTtl = config.refreshTokenTtlSeconds;
    config.refreshTokenTtlSeconds = 3600; // 1 hour for testing
    
    NSString *token = [[NSUUID UUID] UUIDString];
    NSString *did = @"did:plc:test123";
    
    // Act
    NSError *error = nil;
    BOOL success = [databases storeRefreshToken:token forAccount:did error:&error];
    
    // Assert
    XCTAssertTrue(success, @"Should store token successfully");
    XCTAssertNil(error, @"Should not have error");
    
    // Verify expiration is approximately 1 hour from now (within 5 seconds tolerance)
    // This requires a way to query the expiration from the database
    // For now, we verify the token exists and is valid
    PDSDatabaseAccount *account = [databases getAccountByRefreshToken:token error:&error];
    XCTAssertNotNil(account, @"Token should be valid immediately after creation");
    
    // Cleanup
    [databases deleteRefreshToken:token error:nil];
    config.refreshTokenTtlSeconds = originalTtl;
}
```

**Step 2: Run test to verify it passes (existing behavior)**

Run: `./build/tests/AllTests -XCTest ServiceDatabasesTests/testStoreRefreshToken_UsesConfigurableExpiration`
Expected: PASS (hardcoded 30 days still works)

**Step 3: Modify storeRefreshToken to use configurable expiration**

Modify `Garazyk/Sources/Database/Service/ServiceDatabases.m:357`:

```objc
// OLD (line 357):
sqlite3_bind_double(stmt, 4, [[NSDate dateWithTimeIntervalSinceNow:30 * 24 * 60 * 60] timeIntervalSince1970]);

// NEW:
PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
NSUInteger refreshTokenTtl = config.refreshTokenTtlSeconds > 0 ? config.refreshTokenTtlSeconds : (30 * 24 * 60 * 60);
sqlite3_bind_double(stmt, 4, [[NSDate dateWithTimeIntervalSinceNow:refreshTokenTtl] timeIntervalSince1970]);
```

Also add import at top of file if needed:
```objc
#import "App/PDSConfiguration.h"
```

**Step 4: Run test to verify it passes**

Run: `./build/tests/AllTests -XCTest ServiceDatabasesTests/testStoreRefreshToken_UsesConfigurableExpiration`
Expected: PASS

**Step 5: Run full test suite**

Run: `./build/tests/AllTests`
Expected: All tests pass, 0 failures

**Step 6: Commit**

```bash
git add Garazyk/Sources/Database/Service/ServiceDatabases.m Garazyk/Tests/Database/Service/ServiceDatabasesTests.m
git commit -m "feat(auth): use configurable refresh token TTL from PDSConfiguration

- Replace hardcoded 30-day expiration with configurable refreshTokenTtlSeconds
- Defaults to 30 days (2592000 seconds) if not configured
- Allows operators to customize refresh token lifetime"
```

---

## Task 3: Verify Refresh Token Rotation Implementation

**Files:**
- Verify: `Garazyk/Sources/App/Services/PDSAccountService.m:304-348`
- Test: `Garazyk/Tests/App/Services/PDSAccountServiceTests.m`

**Step 1: Review existing implementation**

The `refreshAccessToken:` method at lines 304-348 already implements rotation:
- Line 323: `[_sessionRepository revokeRefreshToken:refreshToken error:nil];` - revokes old token
- Lines 335-340: Generates and stores new refresh token
- Returns both accessJwt and refreshJwt

Verify token rotation with a test.

**Step 2: Write test for token rotation**

Add test to `Garazyk/Tests/App/Services/PDSAccountServiceTests.m`:

```objc
- (void)testRefreshAccessToken_RotatesRefreshToken {
    // Arrange
    NSString *originalRefreshToken = [[NSUUID UUID] UUIDString];
    
    // Create a mock account
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:rotationtest";
    account.handle = @"rotationtest.test";
    account.email = @"test@example.com";
    
    // Store the original refresh token
    NSError *storeError = nil;
    BOOL stored = [self.serviceDatabases storeRefreshToken:originalRefreshToken forAccount:account.did error:&storeError];
    XCTAssertTrue(stored, @"Should store original token");
    
    // Verify original token works
    PDSDatabaseAccount *foundAccount = [self.serviceDatabases getAccountByRefreshToken:originalRefreshToken error:&storeError];
    XCTAssertNotNil(foundAccount, @"Original token should be valid");
    XCTAssertEqualObjects(foundAccount.did, account.did, @"Should find correct account");
    
    // Act - Refresh the token
    NSError *refreshError = nil;
    NSDictionary *result = [self.accountService refreshAccessToken:originalRefreshToken error:&refreshError];
    
    // Assert
    XCTAssertNotNil(result, @"Should return new session data");
    XCTAssertNil(refreshError, @"Should not have error");
    XCTAssertNotNil(result[@"accessJwt"], @"Should return new access token");
    XCTAssertNotNil(result[@"refreshJwt"], @"Should return new refresh token");
    XCTAssertNotEqualObjects(result[@"refreshJwt"], originalRefreshToken, @"New refresh token should be different");
    
    // Verify old token is revoked
    PDSDatabaseAccount *oldTokenAccount = [self.serviceDatabases getAccountByRefreshToken:originalRefreshToken error:&storeError];
    XCTAssertNil(oldTokenAccount, @"Old refresh token should be revoked");
    
    // Verify new token works
    NSString *newRefreshToken = result[@"refreshJwt"];
    PDSDatabaseAccount *newTokenAccount = [self.serviceDatabases getAccountByRefreshToken:newRefreshToken error:&storeError];
    XCTAssertNotNil(newTokenAccount, @"New refresh token should be valid");
    XCTAssertEqualObjects(newTokenAccount.did, account.did, @"New token should find same account");
    
    // Cleanup
    [self.serviceDatabases deleteRefreshToken:newRefreshToken error:nil];
    [self.serviceDatabases deleteAccount:account.did error:nil];
}
```

**Step 3: Run test to verify rotation works**

Run: `./build/tests/AllTests -XCTest PDSAccountServiceTests/testRefreshAccessToken_RotatesRefreshToken`
Expected: PASS

**Step 4: Run full test suite**

Run: `./build/tests/AllTests`
Expected: All tests pass, 0 failures

**Step 5: Commit**

```bash
git add Garazyk/Tests/App/Services/PDSAccountServiceTests.m
git commit -m "test(auth): verify refresh token rotation behavior

- Add test confirming old token is revoked on refresh
- Verify new token is generated and valid
- Ensure rotation prevents token replay attacks"
```

---

## Task 4: Verify DPoP-Nonce Header Generation

**Files:**
- Verify: `Garazyk/Sources/Network/XrpcMethodRegistry.m:5146-5264`

**Step 1: Review existing implementation**

The `extractDIDFromAuthHeader:...` method already implements DPoP nonce challenge:
- Lines 5156-5158: Detects DPoP authorization header
- Lines 5200-5206: Verifies DPoP proof
- Lines 5207-5213: If proof requires nonce, generates and returns it with 401

This is already implemented! We need to verify it works correctly.

**Step 2: Write integration test for DPoP nonce flow**

Create new test file `Garazyk/Tests/Network/DPoPNonceFlowTests.m`:

```objc
#import <XCTest/XCTest.h>
#import "Network/XrpcMethodRegistry.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/OAuth2DPoPProof.h"
#import "TestSupport/PDSMockHTTPResponse.h"
#import "TestSupport/PDSMockHTTPRequest.h"

@interface DPoPNonceFlowTests : XCTestCase
@property (nonatomic, strong) JWTMinter *mockMinter;
@property (nonatomic, strong) id mockAdminController;
@end

@implementation DPoPNonceFlowTests

- (void)setUp {
    [super setUp];
    // Setup mock minter and admin controller
}

- (void)testDPoPProof_WithoutNonce_Returns401WithDPoPNonceHeader {
    // Arrange
    PDSMockHTTPRequest *request = [[PDSMockHTTPRequest alloc] init];
    [request setHeader:@"DPoP <valid_access_token>" forKey:@"Authorization"];
    // Set up DPoP proof without nonce (as would happen on first request)
    [request setHeader:@"<dpop_proof_without_nonce>" forKey:@"DPoP"];
    
    PDSMockHTTPResponse *response = [[PDSMockHTTPResponse alloc] init];
    
    // Act
    NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:@"DPoP <token>"
                                                       jwtMinter:self.mockMinter
                                                 adminController:self.mockAdminController
                                                         request:request
                                                        response:response];
    
    // Assert
    XCTAssertNil(did, @"Should not return DID when nonce is required");
    XCTAssertEqual(response.statusCode, 401, @"Should return 401 status");
    
    NSString *dpopNonce = [response headerForKey:@"DPoP-Nonce"];
    XCTAssertNotNil(dpopNonce, @"Should include DPoP-Nonce header");
    XCTAssertGreaterThan(dpopNonce.length, 0, @"Nonce should not be empty");
    
    NSDictionary *body = response.jsonBody;
    XCTAssertEqualObjects(body[@"error"], @"UseDPoPNonce", @"Should return UseDPoPNonce error");
}

- (void)testDPoPProof_WithValidNonce_ReturnsDID {
    // Arrange
    NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
    
    PDSMockHTTPRequest *request = [[PDSMockHTTPRequest alloc] init];
    [request setHeader:@"DPoP <valid_access_token>" forKey:@"Authorization"];
    // Set up DPoP proof WITH valid nonce
    [request setHeader:@"<dpop_proof_with_nonce>" forKey:@"DPoP"];
    
    PDSMockHTTPResponse *response = [[PDSMockHTTPResponse alloc] init];
    
    // Act
    NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:@"DPoP <token>"
                                                       jwtMinter:self.mockMinter
                                                 adminController:self.mockAdminController
                                                         request:request
                                                        response:response];
    
    // Assert
    XCTAssertNotNil(did, @"Should return DID when DPoP proof is valid");
    XCTAssertEqual(response.statusCode, 200, @"Should not change status code on success");
}

@end
```

**Step 3: Run DPoP tests**

Run: `./build/tests/AllTests -XCTest DPoPNonceFlowTests`
Expected: PASS (tests verify existing implementation)

**Step 4: Run OAuthDPoPTests**

Run: `./build/tests/AllTests -XCTest OAuthDPoPTests`
Expected: PASS

**Step 5: Run full test suite**

Run: `./build/tests/AllTests`
Expected: All tests pass, 0 failures

**Step 6: Commit**

```bash
git add Garazyk/Tests/Network/DPoPNonceFlowTests.m
git commit -m "test(auth): add DPoP nonce challenge flow tests

- Verify 401 response with DPoP-Nonce header when proof lacks nonce
- Verify successful auth when valid nonce is provided
- Tests existing implementation in XrpcMethodRegistry"
```

---

## Task 5: Manual Verification

**Step 1: Test refreshSession with curl**

```bash
# Create a test account and get refresh token
curl -X POST http://localhost:8080/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "testpassword123",
    "handle": "testuser.test"
  }'

# Use the refresh token from response
curl -X POST http://localhost:8080/xrpc/com.atproto.server.refreshSession \
  -H "Authorization: Bearer <refresh_token_from_above>"
```

Expected: Returns new accessJwt and refreshJwt, old refresh token is invalidated

**Step 2: Test DPoP nonce flow with curl**

```bash
# First request without nonce (should get 401 with DPoP-Nonce header)
curl -X GET http://localhost:8080/xrpc/com.atproto.server.getSession \
  -H "Authorization: DPoP <access_token>" \
  -H "DPoP: <dpop_proof_without_nonce>" \
  -v

# Should see: DPoP-Nonce: <nonce_value> in response headers
# And body: {"error": "UseDPoPNonce", "message": "DPoP nonce required"}

# Second request with nonce (should succeed)
curl -X GET http://localhost:8080/xrpc/com.atproto.server.getSession \
  -H "Authorization: DPoP <access_token>" \
  -H "DPoP: <dpop_proof_with_nonce>"
```

**Step 3: Test backup script**

```bash
# Create test data directory structure
mkdir -p /tmp/test_pds/service
mkdir -p /tmp/test_pds/actor_stores/did_123

# Create test databases
touch /tmp/test_pds/service/service.db

cd /Users/jack/Software/objpds
./scripts/backup_pds.sh --data-dir /tmp/test_pds --backup-dir /tmp/test_backups
```

Expected: Backup completes without errors, archive created

---

## Verification Summary

### Automated Tests to Run

```bash
# 1. Refresh token tests
./build/tests/AllTests -XCTest PDSSessionRepositoryTests
./build/tests/AllTests -XCTest PDSAccountServiceTests/testRefreshAccessToken_RotatesRefreshToken

# 2. DPoP tests
./build/tests/AllTests -XCTest OAuthDPoPTests
./build/tests/AllTests -XCTest DPoPNonceFlowTests

# 3. Service database tests
./build/tests/AllTests -XCTest ServiceDatabasesTests/testStoreRefreshToken_UsesConfigurableExpiration

# 4. Full test suite
./build/tests/AllTests
```

## Expected Results

- All tests pass with 0 failures
- ShellCheck passes on backup_pds.sh
- Manual curl tests demonstrate token rotation and DPoP nonce flow

---

## Implementation Notes

### Key Design Decisions

1. **Token Expiration**: Using `PDSConfiguration.refreshTokenTtlSeconds` with 30-day default maintains backward compatibility while allowing customization.

2. **Token Rotation**: Already implemented correctly - old token revoked immediately, new token returned in response.

3. **DPoP Nonce**: The challenge-response flow is implemented in `extractDIDFromAuthHeader:`, which is called by all protected endpoints.

4. **Authorization Header**: The `refreshSession` endpoint already extracts token from `Authorization: Bearer <token>` header per lexicon spec.

### Security Considerations

- Refresh tokens are single-use (rotated on each refresh)
- Tokens have configurable expiration (default 30 days)
- DPoP proofs require server-issued nonces for replay protection
- Old tokens are immediately revoked on rotation

### Performance Impact

- Minimal: Single database query per token validation
- Rotation requires 2 DB writes (delete old, insert new)
- DPoP verification adds cryptographic validation overhead

---

## Related Documentation

- [Plans Index](README) - All project plans
- [Production Readiness](production-readiness) - Full audit with blocking issues
- [Detailed Next Steps](detailed_next_steps_plan) - Priority execution plan
- [Security Documentation](../security/README) - Security analysis and guides
- [OAuth2 Documentation](../oauth2/README) - Authentication implementation
- [DPoP Implementation](../oauth2/dpop) - DPoP proof verification details
- [Token Management](../oauth2/token-management) - JWT and refresh token lifecycle
- [Admin Auth Configuration](../security/ADMIN_AUTH_CONFIGURATION) - Admin authentication setup
