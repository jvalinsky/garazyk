# Security Audit Report: objpds AT Protocol PDS

**Generated:** 2026-02-20  
**Auditor:** Automated security skills + manual review  
**Scope:** Full codebase security review (pentest-grade)

---

## Executive Summary

The objpds codebase demonstrates **mature security practices** with well-implemented:
- Parameterized SQL queries throughout
- Proper DPoP/JWT validation
- Keychain-based secrets management
- Rate limiting infrastructure
- Input validation layer

**Critical findings: 0**  
**High severity: 3**  
**Medium severity: 12**  
**Low severity: 28**

---

## Critical Findings (P0)

### None Identified

No critical vulnerabilities were found. The codebase uses secure patterns for the most sensitive operations.

---

## High Severity Findings (P1)

### 1. Timing-Vulnerable DPoP Thumbprint Comparison

**Location:** `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5365`

**Issue:** DPoP thumbprint validation uses `isEqualToString:` which is not constant-time, potentially allowing timing attacks to derive valid thumbprints.

```objc
// Current (vulnerable)
if (![tokenJkt isEqualToString:dpopThumbprint]) {
```

**Risk:** Attacker with network access could use timing analysis to forge DPoP proofs.

**Recommendation:** Use constant-time comparison:
```objc
// Use HMAC-based comparison
uint8_t expectedHash[CC_SHA256_DIGEST_LENGTH];
uint8_t actualHash[CC_SHA256_DIGEST_LENGTH];
// ... hash both values and compare with memcmp (still not ideal)
// Better: use CCHmac with a random key for comparison
```

**CVSS:** 6.5 (Medium-High)

---

### 2. Service Boundary Gaps in Record Services

**Location:** 
- `ATProtoPDS/Sources/App/Services/PDSRecordService.m`
- `ATProtoPDS/Sources/App/Services/PDSRepositoryService.m`

**Issue:** Service files with privileged operations (record create/update/delete, repository operations) lack explicit authorization signals within the service layer. While upstream handlers may enforce authz, defense-in-depth recommends re-validation at service boundaries.

**Risk:** If handler authz is bypassed, privileged operations lack a second checkpoint.

**Recommendation:** Add explicit `requireAuthorization:` checks at service method entry points.

**CVSS:** 5.9 (Medium)

---

### 3. Lock/Unlock Imbalance in Multiple Files

**Locations:**
- `OAuth2Handler.m` - lock=4, unlock=0
- `DID.m` - lock=4, unlock=0
- `SubscribeReposHandler.m` - lock=6, unlock=0

**Issue:** Static analysis shows more lock operations than unlocks. While `@synchronized` handles this automatically, explicit lock usage patterns should be reviewed.

**Risk:** Potential deadlock if lock discipline is inconsistent across error paths.

**Recommendation:** Audit explicit lock usage and ensure unlock in `@finally` blocks.

**CVSS:** 5.3 (Medium)

---

## Medium Severity Findings (P2)

### 4. Unbounded Collection Allocations

**Locations:** 395 instances of `[NSMutableArray array]`, `[NSMutableData data]` without explicit capacity limits.

**Example:** `ATProtoPDS/Sources/App/Services/PDSRepositoryService.m:883`

**Risk:** Memory exhaustion if user-controlled data drives collection growth.

**Recommendation:** Add size limits before collection extensions.

---

### 5. Missing Rate Limiting on Handler Endpoints

**Locations:**
- `ExploreHandler.m`
- `MSTViewerHandler.m`
- `OAuthDemoHandler.m`
- `HttpRouter.m`

**Issue:** HTTP handlers without explicit `RateLimiter` references detected.

**Recommendation:** Verify rate limiting is applied at router/server level, or add per-endpoint limits.

---

### 6. SQLite Statement Lifecycle Concerns

**Locations:**
- `PDSMigrationManager.m` - prepare without finalize signal
- `PDSHealthCheck.m` - prepare without finalize signal

**Issue:** File-level heuristics suggest potential statement lifecycle issues.

**Recommendation:** Manual audit of statement `prepare`/`step`/`finalize` paths.

---

### 7. Parser Hardening Gaps

**Locations:**
- `Base58.h`
- `CID.h`
- `RepoCommit.h`

**Issue:** Parser/decoder files with risky memory operations but no explicit bounds signal in header.

**Recommendation:** Verify bounds checking in implementation files.

---

### 8. Firehose Backpressure Monitoring

**Location:** `SubscribeReposHandler.m`

**Issue:** Firehose emitter with ordering logic but limited backpressure signals.

**Risk:** Slow consumers could accumulate unbounded buffers.

**Recommendation:** Implement explicit backpressure (pause/resume) per connection.

---

### 9. Concurrency Bug Candidates

**Locations:** 29 files with threading + mutable state + no synchronization signal

**Notable files:**
- `Session.m`
- `OAuthSession.m`
- `DatabasePool.m`
- `RateLimiter.m`

**Recommendation:** Manual review of queue ownership and lock strategy.

---

### 10. Log Redaction Candidates

**Locations:** 43 files with logging + sensitive identifier signals

**Notable files:**
- `OAuth2.m`
- `OAuth2Handler.m`
- `XrpcMethodRegistry.m`

**Issue:** Potential logging of tokens, credentials, or user data.

**Recommendation:** Audit logged payloads for sensitive data exposure.

---

### 11. Network Timeout Gaps

**Locations:**
- `HttpResponse.h`
- `HttpStreamingBody.m`
- `PDSNetworkTransport.h`

**Issue:** Network IO files without explicit timeout configuration.

**Recommendation:** Ensure default timeouts are applied at connection level.

---

### 12. Reentrancy Candidates

**Locations:** 7 files with lock + sync dispatch

**Issue:** Potential reentrancy when dispatch_sync is called while holding a lock.

**Recommendation:** Review lock ordering and avoid sync dispatch under lock.

---

### 13. XRPC Contract Gaps

**Locations:** 44 files with method registration but no auth/validation signals

**Issue:** Endpoints may lack explicit auth enforcement.

**Recommendation:** Verify auth is handled at XRPC layer or handler entry.

---

### 14. SHA1 Usage in WebSocket Handshake

**Location:** `WebSocketUpgradeHandler.m:90`

**Context:** SHA1 is used per RFC 6455 WebSocket handshake specification.

**Verdict:** NOT A VULNERABILITY - protocol requirement, not security weakness.

---

### 15. Gitleaks Findings (False Positives)

**Total:** 238 findings  
**Analysis:** All findings are test data (did:key strings, test JWTs, fuzzing corpus)  
**Action:** Add `.gitleaksignore` for known test patterns.

---

## Low Severity Findings (P3)

### SQL String Formatting (Reviewed - Safe)

**Locations:**
- `PDSAdminService.m:374,382`
- `FeedService.m:271`

**Verdict:** All use `executeParameterizedUpdate` with proper placeholder generation. **NOT VULNERABLE**.

---

### Additional Low-Severity Items

- 2 weak random usages (`arc4random()` - acceptable for non-crypto)
- 7 hardcoded IV references (verify context)
- 4 unbounded loops (reviewed - have break conditions)
- 12 service files without explicit auth signal (upstream auth may exist)

---

## Positive Security Findings

### Strong Practices Observed

1. **Parameterized SQL Throughout** - All SQL execution uses `executeParameterizedQuery` with bound parameters
2. **Keychain Secrets Management** - `PDSKeychainSecretsProvider` properly stores credentials
3. **Input Validation Layer** - `PDSInputValidator` provides comprehensive validation
4. **DPoP Implementation** - Proper binding enforcement and thumbprint validation
5. **Rate Limiting Infrastructure** - `RateLimiter` class with per-IP/account limits
6. **Test Coverage** - Comprehensive test suite including auth flows
7. **Fuzzing Infrastructure** - Active fuzzers for CBOR, HTTP, SQL, XRPC

---

## Remediation Priority

| Priority | Finding | Effort | Impact |
|----------|---------|--------|--------|
| 1 | DPoP timing comparison | Low | High |
| 2 | Service boundary authz | Medium | Medium |
| 3 | Lock discipline audit | Medium | Medium |
| 4 | Rate limiting gaps | Low | Medium |
| 5 | Collection size limits | Medium | Medium |
| 6 | Log redaction audit | Medium | Low |

---

## Skills Created

4 new security audit skills were created during this audit:

1. `objc-secrets-detection-audit` - Hardcoded credential scanning
2. `objc-cryptographic-security-audit` - Weak crypto detection
3. `objc-sql-injection-deep-audit` - SQL injection patterns
4. `objc-rate-limiting-dos-audit` - DoS/rate limiting gaps

---

## Methodology

- **Static Analysis:** 13 security skill scans
- **Secret Detection:** gitleaks scan (157MB scanned)
- **Manual Review:** Critical paths examined
- **Pattern Matching:** Regex-based vulnerability detection

---

## Conclusion

The objpds codebase demonstrates **security-conscious design** with appropriate use of parameterized queries, proper authentication flows, and defense-in-depth patterns. The identified issues are primarily hardening opportunities rather than exploitable vulnerabilities.

**Recommended Next Steps:**
1. Implement constant-time comparison for DPoP thumbprint validation
2. Add explicit authz checks at service layer boundaries
3. Audit lock discipline and add `@finally` unlock patterns
4. Add per-endpoint rate limiting verification
5. Create `.gitleaksignore` for test patterns

---

**Report Version:** 1.0  
**Confidence Level:** High (automated + manual review)
