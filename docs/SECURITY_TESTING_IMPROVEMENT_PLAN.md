# Security Testing Improvement Plan

## Current State Analysis

### Strengths
1. **Fuzzing Infrastructure**: 6 libFuzzer-based fuzzers (xrpc, cbor, http, auth, blob, sqlite)
2. **Static Analysis**: Clang-tidy configuration with security-focused checks
3. **Test Corpus**: Seeded corpus for all major parsing components
4. **Sanitizers**: Support for ASAN, UBSAN, TSan builds via Makefile
5. **Reporting**: Automated security test result generation

### Gaps
1. **No CI/CD Integration**: Security tests run manually, not on every PR
2. **No CodeQL**: GitHub's native security analysis not enabled
3. **No Dependency Scanning**: OSV/npm audit not integrated
4. **No Secret Scanning**: TruffleHog or similar not configured
5. **No Fuzzing Corpus CI**: Corpus not automatically updated
6. **Limited Sanitizer CI**: Sanitizer builds not in CI

---

## Improvement Roadmap

### Phase 1: CI/CD Integration (This Week)

#### 1.1 GitHub Actions Security Workflow
**Status:** PASS Created at `.github/workflows/security.yml`

**Components:**
- Static analysis with clang-tidy
- CodeQL security analysis
- Fuzzing with libFuzzer (configurable duration)
- Dependency scanning with OSV Scanner
- Secret scanning with TruffleHog
- Container security (if Dockerfile exists)
- Automated security report generation

**Triggers:**
- Every push to main/develop
- Every PR to main
- Weekly schedule (Sunday 2 AM UTC)
- Manual dispatch with configurable parameters

#### 1.2 Actions Required
```bash
# None - workflow file created
# Review and commit if approved
```

---

### Phase 2: Enhanced Fuzzing (Next Week)

#### 2.1 Corpus Growth Strategy
**Current Corpus Size:**
- CBOR: 17 files
- HTTP: 18 files  
- XRPC: 8 files
- SQL: 10 files

**Recommended Additions:**

| Corpus | New Files | Source |
|--------|-----------|--------|
| CBOR | +20 | RFC 8949 test vectors, fuzzing corpora |
| HTTP | +30 | OWASP HTTP attack vectors, edge cases |
| XRPC | +25 | Real ATProto method examples, edge cases |
| SQL | +15 | SQL injection patterns, edge cases |

#### 2.2 Continuous Fuzzing Corpus PRs
Create automation to:
1. Run fuzzers overnight
2. Collect interesting inputs
3. Submit PRs with corpus additions

#### 2.3 Guided Fuzzing Integration
Consider integrating:
- **LibFuzzer Enterprise**: For distributed fuzzing
- **Mayhem**: For AI-guided fuzzing (GitHub Action available)
- **AFL++**: For alternative fuzzing strategies

---

### Phase 3: Advanced Security Testing (This Month)

#### 3.1 Web API Security Testing
Add integration tests for:
- OAuth2 / OIDC flow security
- DPoP proof generation/validation
- JWT verification edge cases
- Rate limiting bypass attempts
- Authentication brute-force protection

#### 3.2 WebSocket Security
If WebSocket connections are used:
- Frame fuzzing
- Message size limits
- Reconnection logic security
- Authentication persistence

#### 3.3 CAR/IPLD Security
- DAG size limits
- Path traversal validation
- Cyclic reference detection
- Block size validation

---

### Phase 4: Dependency & Supply Chain (This Month)

#### 4.1 Dependency Scanning
- Enable GitHub Dependabot
- Configure OSV Scanner in CI
- Regular dependency updates

#### 4.2 SBOM Generation
Generate Software Bill of Materials:
```bash
# Using syft
brew install syft
syft atprotopds:latest -o cyclonedx-json > sbom.json
```

#### 4.3 SLSA Compliance
Work toward SLSA Level 2:
- Build provenance attestation
- Build integrity verification
- Secure build pipeline

---

### Phase 5: Runtime Security (Next Month)

#### 5.1 Runtime Application Self-Protection (RASP)
Consider adding:
- SQL injection detection hooks
- XSS prevention headers
- Request validation middleware
- Anomaly detection

#### 5.2 Security Headers
Ensure all HTTP responses include:
```
Content-Security-Policy
X-Content-Type-Options
X-Frame-Options
Strict-Transport-Security
X-XSS-Protection
```

#### 5.3 Audit Logging
Comprehensive security event logging:
- Authentication events
- Authorization failures
- Data access patterns
- Admin operations
- Rate limit triggers

---

## Implementation Priority Matrix

| Priority | Item | Effort | Impact | Status |
|----------|------|--------|--------|--------|
| P0 | GitHub Actions Security Workflow | Low | High | Done |
| P0 | CodeQL Integration | Low | High | In Workflow |
| P1 | Extended Fuzzing Corpus | Medium | Medium | Pending |
| P1 | Dependency Scanning | Low | High | In Workflow |
| P1 | Secret Scanning | Low | High | In Workflow |
| P2 | Sanitizer CI Matrix | Medium | Medium | In Workflow |
| P2 | Automated Corpus PRs | High | Medium | Pending |
| P3 | SLSA Compliance | High | Low | Future |
| P3 | RASP Integration | High | Medium | Future |

---

## Recommended Tools & Services

### Free/Open Source
1. **GitHub CodeQL** - Native security analysis
2. **OSV Scanner** - Dependency vulnerabilities
3. **TruffleHog** - Secret scanning
4. **Trivy** - Container scanning
5. **libFuzzer** - Coverage-guided fuzzing

### Enterprise (Consider for Production)
1. **GitHub Advanced Security** - $49/user/month
2. **Semgrep Pro** - Advanced SAST
3. **Mayhem** - AI-guided fuzzing
4. **Snyk** - Dependency + container security
5. **Checkmarx** - Comprehensive AST

---

## Success Metrics

### Quantitative
| Metric | Current | Target (3 months) |
|--------|---------|-------------------|
| CodeQL findings | 0 | 0 (maintain) |
| Fuzzer coverage | ~60% | 80% |
| Dependency CVEs | 0 | 0 |
| Secret leaks | 0 | 0 |
| Static analysis warnings | 32 | <15 |

### Qualitative
- Security review on every major PR
- Known vulnerability response < 24 hours
- Penetration test annually
- Security documentation up to date

---

## Immediate Action Items

1. **Review and merge** `.github/workflows/security.yml`
2. **Enable CodeQL** in repository settings
3. **Configure Dependabot** for dependency updates
4. **Add corpus files** from ATProto reference implementations
5. **Run initial security workflow** to establish baseline
6. **Create security incident response plan**
7. **Schedule quarterly security review meetings**

---

## References

- [GitHub Security Best Practices](https://docs.github.com/en/actions/security-for-github-actions)
- [libFuzzer Documentation](https://llvm.org/docs/LibFuzzer.html)
- [OpenSSF Security Scorecard](https://securityscorecard.dev)
- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- [Trail of Bits Fuzzing Handbook](https://trailofbits.github.io/tcs/fuzzing/)
