---
title: "Phase 1: OAuth 2.0/DPoP Compliance Plan"
---

# Phase 1: OAuth 2.0/DPoP Compliance

> **Status:** ~90% Complete - Implementation verified, compliance testing remaining
> **Priority:** P0 (Critical)
> **Generated:** 2026-04-10

## Executive Summary

The OAuth 2.0/DPoP implementation is largely complete. All critical endpoints exist:
- OAuth server metadata (`/.well-known/oauth-authorization-server`)
- Protected resource metadata (`/.well-known/oauth-protected-resource`)
- PKCE (Proof Key for Code Exchange)
- DPoP proof generation and verification
- DPoP nonce management

This plan focuses on verification and completing edge cases.

---

## Current Implementation Status

| Component | Status | File Location |
|-----------|--------|---------------|
| OAuth Server Metadata | ✅ Implemented | `OAuth2Handler.m:1484-1488` |
| Protected Resource Metadata | ✅ Implemented | `OAuth2Handler.m:1492-1496` |
| OAuth JWKS Endpoint | ✅ Implemented | `OAuth2Handler.m:1499-1504` |
| PKCE Validation | ✅ Implemented | `PKCEUtil.m` + tests |
| DPoP Proof Generation | ✅ Implemented | `DPoPUtil.m:77-145` |
| DPoP Proof Verification | ✅ Implemented | `DPoPUtil.m:147-195` |
| DPoP Nonce Management | ✅ Implemented | `PDSNonceManager.m` + `XrpcMethodRegistry.m:5146-5264` |
| Token Rotation | ✅ Implemented | `PDSAccountService.m:304-348` |
| PAR (Pushed Auth Requests) | ✅ Implemented | `OAuth2Handler.m:1507-1512` |

---

## Tasks

### Task 1.1: Run OAuth Conformance Tests

**Goal:** Verify RFC 9449 (DPoP) and OAuth 2.0 spec compliance

**Files:**
- Test: `Garazyk/Tests/Auth/OAuthConformanceTests.m`
- Implementation: `Garazyk/Sources/Auth/OAuth2Handler.m`

**Steps:**
1. Run conformance tests:
   ```bash
   ./build/tests/AllTests -XCTest OAuthConformanceTests
   ```
2. Review test results - all should pass
3. Document any failures with specific RFC section violated

**Expected:** All tests pass (9 tests in OAuthConformanceTests.m)

---

### Task 1.2: Review DPoP Nonce Handling Implementation

**Goal:** Verify complete nonce lifecycle

**Files:**
- Implementation: `Garazyk/Sources/Network/XrpcMethodRegistry.m:5146-5264`
- Manager: `Garazyk/Sources/Auth/PDSNonceManager.m`

**Steps:**
1. Review `extractDIDFromAuthHeader:` method for nonce validation
2. Verify nonce generation at `PDSNonceManager.m`
3. Verify nonce consumption/rotation after valid proof
4. Check nonce expiration timing (default 300 seconds per RFC)

**Citations:**
- Nonce challenge tests: `OAuth2HandlerTests.m:223-260`
- DPoP verification: `OAuthDPoPTests.m:112-128`

---

### Task 1.3: Add DPoP Replay Protection Tests

**Goal:** Ensure DPoP proof cannot be replayed

**Files:**
- Test: Create `Garazyk/Tests/Auth/DPoPReplayProtectionTests.m`
- Implementation: `Garazyk/Sources/Auth/DPoPUtil.m`

**Steps:**
1. Create new test file for replay protection:
   ```objc
   // Test: Replay of same DPoP proof should fail
   - (void)testDPoPProof_CannotBeReplayed {
       // Create DPoP proof
       DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST" 
                                                  uri:@"https://server.com/token" 
                                                nonce:nil 
                                                  key:_privateKey error:&error];
       // First verification should succeed
       BOOL valid1 = [DPoPUtil verifyDPoP:token.jwt 
                              withPublicKey:_publicKey 
                                    method:@"POST" 
                                       uri:@"https://server.com/token" 
                                    nonce:nil error:&error];
       XCTAssertTrue(valid1);
       
       // Same proof replayed should fail (if replay cache implemented)
       // Note: This requires PDSReplayCache integration
   }
   ```
2. Check if `PDSReplayCache` is used for DPoP proof caching
3. Add replay cache if not present

**References:**
- RFC 9449 Section 7: DPoP Proof Lifecycle
- Replay cache: `Garazyk/Sources/Auth/PDSReplayCache.m`

---

### Task 1.4: Verify Token Rotation (Property 2.2)

**Goal:** Ensure refresh token rotation per OAuth 2.0 spec

**Files:**
- Implementation: `Garazyk/Sources/App/Services/PDSAccountService.m:304-348`
- Test: `Garazyk/Tests/Auth/OAuth2PreservationTests.m` (Property 2.2)

**Steps:**
1. Run preservation tests:
   ```bash
   ./build/tests/AllTests -XCTest OAuth2PreservationTests/testProperty_PKCEValidationPreserved
   ```
2. Verify refresh token is single-use (old token revoked on refresh)
3. Verify new refresh token is generated on each refresh
4. Confirm rotation happens atomically (no race condition window)

**Citations:**
- Token rotation: `PDSAccountService.m:323` - `revokeRefreshToken:`
- Rotation test: `OAuth2PreservationTests.m:236-295`

---

### Task 1.5: Manual OAuth Flow Verification

**Goal:** End-to-end verification of OAuth dance

**Steps:**
1. Start PDS locally
2. Execute full OAuth authorization code flow with PKCE:
   ```bash
   # Step 1: Discover OAuth server metadata
   curl http://localhost:2583/.well-known/oauth-authorization-server
   
   # Step 2: Authorization request (open in browser)
   # http://localhost:2583/oauth/authorize?client_id=...&response_type=code&
   #   redirect_uri=...&scope=atproto&code_challenge=...&code_challenge_method=S256
   
   # Step 3: Token exchange
   curl -X POST http://localhost:2583/oauth/token \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "grant_type=authorization_code&code=...&client_id=...&redirect_uri=...&code_verifier=..."
   
   # Step 4: Use DPoP-bound access token
   curl http://localhost:2583/xrpc/com.atproto.server.getSession \
     -H "Authorization: DPoP <access_token>" \
     -H "DPoP: <dpop_proof>"
   ```
3. Verify all flows work correctly

---

### Task 1.6: Run Full Auth Test Suite

**Goal:** Ensure no regressions

**Steps:**
```bash
# Run all OAuth-related tests
./build/tests/AllTests -XCTest OAuth2HandlerTests
./build/tests/AllTests -XCTest OAuthDPoPTests
./build/tests/AllTests -XCTest OAuthPKCETests
./build/tests/AllTests -XCTest OAuthSessionTests
./build/tests/AllTests -XCTest OAuthIntegrationTests

# Full suite
./build/tests/AllTests
```

**Expected:** 0 failures

---

## Verification Checklist

- [ ] OAuthConformanceTests pass
- [ ] DPoP nonce handling verified
- [ ] Token rotation verified
- [ ] PKCE validation working
- [ ] Manual OAuth flow verified
- [ ] Full test suite passes
- [ ] No regressions in existing functionality

---

## Dependencies

- `Garazyk/Sources/Auth/OAuth2Handler.m` - OAuth flow
- `Garazyk/Sources/Auth/DPoPUtil.m` - DPoP proofs
- `Garazyk/Sources/Auth/PDSNonceManager.m` - Nonce management
- `Garazyk/Sources/Auth/PDSReplayCache.m` - Replay protection
- `Garazyk/Sources/Network/XrpcMethodRegistry.m` - Auth extraction
- `Garazyk/Sources/App/Services/PDSAccountService.m` - Token management

---

## Related Plans

- [Phase 2: Video Processing Pipeline](2026-04-10-video-processing-pipeline.md)
- [Phase 3: Chat/Conversation Support](2026-04-10-chat-conversation-support.md)
- [Production Readiness](production-readiness.md)
- [P0 Security Hardening](2026-02-18-p0-security-hardening.md) - Previous OAuth work

---

## Next Steps

After Phase 1 verification is complete:
1. If all tests pass → Move to Phase 2 (Video Processing)
2. If failures found → Fix and re-run verification
3. Document any spec deviations for future review