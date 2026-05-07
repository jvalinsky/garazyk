# WebAuthn OAuth2 Integration Tests Plan

> **For Claude:** Use superpowers:executing-plans to implement test-by-test.

**Goal:** Add integration tests for complete WebAuthn + OAuth2 flow.

---

## Test File Location

**Create:** `ATProtoPDS/Tests/Auth/WebAuthnOAuth2IntegrationTests.m`

**Register in:** `ATProtoPDS/Tests/test_main.m` - add to `testClasses` array

---

## Tests to Implement

### Test 1: OAuth2 Authorization Request with WebAuthn

**Objective:** Verify webauthn=true parameter generates challenge in authorization code.

```objc
- (void)testWebauthnAuthorizationRequestGeneratesChallenge {
    // 1. Build OAuth2AuthorizationRequest with webauthn=true
    OAuth2AuthorizationRequest *req = [[OAuth2AuthorizationRequest alloc] init];
    req.clientID = @"test-client";
    req.redirectURI = @"http://localhost/callback";
    req.responseType = @"code";
    req.webauthn = YES;
    
    // 2. Handle authorization request
    [oauth2 handleAuthorizationRequest:req completion:^(URL, code, error) {
        XCTAssertNotNil(code);
        
        // 3. Retrieve code data and verify challenge stored
        NSDictionary *codeData = [oauth2 getAuthorizationCodeData:code];
        XCTAssertNotNil(codeData[@"webauthn_challenge"]);
    }];
}
```

### Test 2: WebAuthn Challenge Stored in Session

**Objective:** Verify challenge is valid data and not expired.

```objc
- (void)testWebauthnChallengeIsValidData {
    // Create auth request with webauthn
    // Retrieve code data
    // Verify challenge is NSData with length 32
    // Verify not empty
}
```

### Test 3: Token Request without WebAuthn Rejected

**Objective:** When account.webauthnEnabled=true but no webauthnAssertion, return error.

```objc
- (void)testTokenRequestRejectsMissingWebauthn {
    // Account with webauthnEnabled = YES
    // Token request WITHOUT webauthn_assertion
    // Expect error: webauthn_required
}
```

### Test 4: Token Request with Invalid Assertion

**Objective:** Invalid WebAuthn assertion returns error.

```objc
- (void)testTokenRequestRejectsInvalidAssertion {
    // Account with webauthnEnabled = YES
    // Token request with webauthn_assertion = @{}
    // Expect error: WebAuthn verification failed
}
```

### Test 5: Token Request with Valid Assertion - Success

**Objective:** Valid assertion leads to token issuance.

**Note:** This requires mocking the WebAuthnVerifier response. May need test fixtures:
```objc
- (void)testTokenRequestAcceptsValidAssertion {
    // Store credential in webauthn_credentials table
    // Mock WebAuthnVerifier to return YES
    // Token request with webauthn_assertion
    // Expect access_token returned
}
```

### Test 6: Sign Count Updates After Authentication

**Objective:** Verify sign_count increments after successful authentication.

```objc
- (void)testSignCountUpdatesAfterAuthentication {
    // Setup credential with sign_count = 5
    // Verify assertion
    // Retrieve credential, verify sign_count = 6
}
```

### Test 7: Cloned Authenticator Rejected

**Objective:** cloned authenticator (same or lower sign_count) is rejected.

```objc
- (void)testClonedAuthenticatorRejected {
    // Store credential with sign_count = 10
    // Assertion with sign_count = 5
    // Expect error: Sign count error (cloned authenticator?)
}
```

### Test 8: Missing Credential Rejected

**Objective:** No stored credentials returns error.

```objc
- (void)testNoCredentialsReturnsError {
    // Account with webauthnEnabled = YES
    // NO credentials in table
    // Expect error: No WebAuthn credentials found
}
```

---

## Dependencies

1. **Database fixture** - Need test database with webauthn_credentials table
2. **Mock WebAuthnVerifier** - May need to stub for deterministic tests
3. **Test fixtures** - Sample credential data, attestation, assertions

---

## Implementation Order

1. Register test class in test_main.m
2. Basic OAuth2 + webauthn test
3. Challenge storage test
4. Token rejection tests (no assertion, invalid)
5. Full flow test with valid assertion
6. Edge cases (sign count, cloned)