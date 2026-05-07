# WebAuthn Registration Endpoints Tests + OAuth2 Integration Tests Plan

This plan covers two areas:
1. **HTTP Endpoint Tests** - WebAuthnRegistrationHandler tests  
2. **OAuth2 Integration Tests** - WebAuthn + OAuth2 flow tests

---

# Part 1: WebAuthn Registration HTTP Endpoints Tests

**File:** Create `ATProtoPDS/Tests/Auth/WebAuthnRegistrationHandlerTests.m`

## Tests to Implement

### Test 1: Register Begin Returns Challenge

```
- (void)testRegisterBeginReturnsChallenge
  - POST /auth/webauthn/register/begin with did
  - Expect: 200, challenge in response, sessionId
```

### Test 2: Register Begin Missing DID

```
- (void)testRegisterBeginRequiresDid
  - POST without did field
  - Expect: 400 error
```

### Test 3: Register Begin Account Not Found

```
- (void)testRegisterBeginAccountNotFound
  - POST with non-existent did
  - Expect: 404 error
```

### Test 4: Register Complete Stores Credential

```
- (void)testRegisterCompleteStoresCredential
  - First call begin to get challenge
  - Then call complete with attestation
  - Verify credential in database
  - Expect: 200, success=true
```

### Test 5: Register Complete Invalid Attestation

```
- (void)testRegisterCompleteRejectsInvalidAttestation
  - Send invalid attestation object
  - Expect: 400 error
```

### Test 6: Assert Verifies Valid Assertion

```
- (void)testAssertVerifiesValidAssertion
  - First register a credential
  - Then call assert with valid assertion
  - Expect: 200, success=true
```

### Test 7: Assert Rejects Invalid Assertion

```
- (void)testAssertRejectsInvalidAssertion
  - Call assert with invalid assertion
  - Expect: 400 error
```

### Test 8: Assert Rejects Cloned Authenticator

```
- (void)testAssertRejectsClonedAuthenticator
  - Same sign_count in assertion as stored
  - Expect: 400 error (Sign count error)
```

---

# Part 2: WebAuthn OAuth2 Integration Tests

**File:** Create `ATProtoPDS/Tests/Auth/WebAuthnOAuth2IntegrationTests.m`

## Tests to Implement

### Test 1: OAuth2 Authorization Request with WebAuthn

```
- (void)testWebauthnAuthorizationRequestGeneratesChallenge
  - OAuth2AuthorizationRequest with webauthn=true
  - Handle authorization request
  - Retrieve code data, verify challenge stored
```

### Test 2: WebAuthn Challenge Format

```
- (void)testWebauthnChallengeIsValidData
  - Verify challenge is NSData with length 32
  - Verify not empty
```

### Test 3: Token Request without WebAuthn Rejected

```
- (void)testTokenRequestRejectsMissingWebauthn
  - Account with webauthnEnabled=YES
  - Token request WITHOUT webauthn_assertion
  - Expect error: webauthn_required
```

### Test 4: Token Request with Invalid Assertion

```
- (void)testTokenRequestRejectsInvalidAssertion
  - Account with webauthnEnabled=YES
  - Token request with invalid webauthn_assertion
  - Expect error: WebAuthn verification failed
```

### Test 5: Token Request with Valid Assertion - Success

```
- (void)testTokenRequestAcceptsValidAssertion
  - Store credential in webauthn_credentials
  - Token request with webauthn_assertion
  - Expect access_token returned
```

### Test 6: Sign Count Updates After Authentication

```
- (void)testSignCountUpdatesAfterAuthentication
  - Credential with sign_count=5
  - Verify assertion
  - Retrieve, verify sign_count=6
```

### Test 7: Cloned Authenticator Rejected

```
- (void)testClonedAuthenticatorRejected
  - Credential with sign_count=10
  - Assertion with sign_count=5
  - Expect error: Sign count error (cloned)
```

### Test 8: Missing Credentials Rejected

```
- (void)testNoCredentialsReturnsError
  - Account with webauthnEnabled=YES
  - NO credentials in table
  - Expect error: No WebAuthn credentials found
```

---

# Implementation Steps

1. **Create test file** - WebAuthnRegistrationHandlerTests.m
2. **Create test file** - WebAuthnOAuth2IntegrationTests.m (or combine into one)
3. **Register in test_main.m** - Add to testClasses array
4. **Implement tests** - Each test case above
5. **Run tests** - Verify all pass

# Dependencies

- Database with webauthn_credentials table (schema already added)
- Test fixtures for credentials, attestations, assertions
- May need to stub WebAuthnVerifier for deterministic tests

# Files to Create

```
ATProtoPDS/Tests/Auth/WebAuthnRegistrationHandlerTests.m
ATProtoPDS/Tests/Auth/WebAuthnOAuth2IntegrationTests.m
```

# Files to Modify

```
ATProtoPDS/Tests/test_main.m
```

# Test Execution

```bash
./build/tests/AllTests
# Or for specific test:
xcodebuild -scheme ATProtoPDSTests test -only-run WebAuthnRegistrationHandlerTests
```