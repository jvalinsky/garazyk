# OAuth / Authentication Compliance Summary

**Date**: 2026-04-20
**Full Report**: `docs/archive/planning/oauth2-spec-compliance-report.md`

---

## Issue Summary

| Severity | Count | Status |
|----------|-------|--------|
| 🔴 CRITICAL | 5 | Known, documented |
| ⚠️ MODERATE | 8 | Known, documented |
| 💡 LOW | 4 | Known, documented |

---

## 🔴 CRITICAL Issues

### 1. No Dynamic Client Metadata Fetching
- **Impact**: Third-party clients cannot authenticate without pre-registration
- **Location**: `OAuth2Handler.m:124-191`
- **Spec**: Server must `GET <client_id>` to fetch client metadata

### 2. `plain` PKCE Method Allowed
- **Impact**: Weakens PKCE security
- **Location**: `OAuth2.m:1366-1379`
- **Fix**: Reject `plain`, require `S256`

### 3. DPoP Nonce TTL Exceeds Spec (10 min vs 5 min max)
- **Impact**: Nonces live twice as long as permitted
- **Location**: `PDSNonceManager.m:45`
- **Fix**: Change `600` to `300`

### 4. DPoP Nonces One-Time Use (Should Be Reusable)
- **Impact**: Every request forces nonce-error-retry cycle
- **Location**: `PDSNonceManager.m:55-71`
- **Fix**: Remove nonce deletion, use expiration only

### 5. Confidential Client JWT Assertion Not Verified
- **Impact**: Confidential clients cannot properly authenticate at token endpoint
- **Location**: `OAuth2Handler.m:1505-1590`
- **Fix**: Implement `client_assertion` JWT verification

---

## ⚠️ MODERATE Issues

### 6. Protected Resource Metadata Format Non-Standard
- `authorization_servers` should be URL array, not object array
- **Location**: `OAuth2Handler.m:966-977`

### 7. Missing `atproto` Scope Enforcement
- Sessions may lack required `atproto` scope
- **Location**: `OAuth2.m:1256`

### 8. Scope Constants Don't Match Spec
- Custom scopes (`atproto:identify`, etc.) vs spec scopes (`atproto`)
- **Location**: `OAuth2.h:32-36`

### 9. No `code_challenge` Reuse Prevention
- Potential PKCE replay attacks
- **Impact**: 24-hour tracking needed

### 10. PKCE Not Mandatory
- PKCE skipped if no challenge sent
- **Location**: `OAuth2.m:1192`

### 11. Authorization Code Reuse Not Fully Prevented
- In-memory dictionary may have race conditions
- **Location**: `OAuth2.m:1158-1218`

### 12. In-Memory Session Storage
- Sessions lost on restart
- **Impact**: Refresh tokens invalid after restart

### 13. `transition:email` Scope Missing
- Metadata omits scope required by spec
- **Location**: `OAuthServerMetadata.m:49-50`

---

## 💡 LOW Issues

### 14. No `DPoP-Nonce` Header on Token Response
- Inconsistent DPoP-Nonce header behavior

### 15-17. Additional minor compliance gaps
- See full report for details

---

## ✅ Compliant Areas

- Authorization Server Metadata (all required fields)
- PKCE SHA-256 implementation
- DPoP proof structure (typ, alg, claims)
- DPoP signature verification (ES256)
- DPoP JTI replay detection
- DPoP URL canonicalization
- JWK thumbprint computation
- CORS configuration
- Identity resolution flow
- Token revocation endpoint

---

## Recommendations

**Priority Order**:

1. **Fix DPoP nonce handling** (CRITICAL #3, #4)
   - Reduces to 5-minute TTL
   - Makes nonces reusable until expiry
   - Small code change, high security impact

2. **Implement dynamic client metadata fetching** (CRITICAL #1)
   - Required for third-party client interop
   - Larger implementation effort

3. **Reject `plain` PKCE method** (CRITICAL #2)
   - One-line fix, security enhancement

4. **Enforce `atproto` scope** (MODERATE #7)
   - Required for spec compliance

5. **Add session persistence** (MODERATE #12)
   - Prevent session loss on restart

---

## Related Files

- **OAuth Handler**: `Garazyk/Sources/Auth/OAuth2Handler.m`
- **OAuth Protocol**: `Garazyk/Sources/Auth/OAuth2.m`
- **DPoP**: `Garazyk/Sources/Auth/OAuth2DPoPProof.m`
- **Nonce Manager**: `Garazyk/Sources/Auth/PDSNonceManager.m`
- **Server Metadata**: `Garazyk/Sources/Auth/OAuthServerMetadata.m`
- **Full Report**: `docs/archive/planning/oauth2-spec-compliance-report.md`
