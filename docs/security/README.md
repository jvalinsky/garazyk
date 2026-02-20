# Security Documentation

This directory contains security documentation for the ATProto PDS Objective-C implementation, including vulnerability reports, testing plans, and security configurations.

## Main Security Documents

| File | Title | Topic |
|------|-------|-------|
| [ADMIN_AUTH_CONFIGURATION.md](ADMIN_AUTH_CONFIGURATION.md) | Admin Auth Configuration & Rotation Guide | Admin authentication setup, password rotation, JWT key management |
| [SECURITY_ANALYSIS_REPORT.md](SECURITY_ANALYSIS_REPORT.md) | Security Analysis Report - ATProto PDS | Static analysis findings, fuzzer results, code quality issues |
| [SECURITY_PLAN.md](SECURITY_PLAN.md) | Security Validation Strategy | Comprehensive security testing strategy with clang-tidy, fuzzing, and sanitizers |
| [SECURITY_TESTING_PLAN.md](SECURITY_TESTING_PLAN.md) | ATProto PDS Security Testing Plan | Parsing exploits, SQL injection, blob upload security, fuzzing strategies |
| [security_test_results.md](security_test_results.md) | Security Test Results | CBOR, HTTP, XRPC, SQL payload testing results (66 tests passing) |
| [SQL_INJECTION_VULNERABILITY_REPORT.md](SQL_INJECTION_VULNERABILITY_REPORT.md) | Security Vulnerability Report | SQL injection vulnerabilities found and remediation guidance |
| [SSRF_PROTECTION.md](SSRF_PROTECTION.md) | SSRF Protection for Handle Resolution | Server-side request forgery protection for handle resolution |

## Security Reports

Historical security analysis reports are available in [reports/](reports/). These reports document the progression of security issue resolution over time.

## Quick Links

- **Current Status**: All critical/high/medium issues resolved
- **Fuzzers**: 6 fuzzers (xrpc, cbor, http, auth, blob, sqlite)
- **Test Coverage**: 66 security payload tests, 31 unit tests passing
- **CI/CD**: Automated security workflow in `.github/workflows/security.yml`

## Related Files

- `.clang-tidy` - Clang-tidy configuration for static analysis
- `fuzzing/` - Fuzzing corpus and harnesses
- `.github/workflows/security.yml` - GitHub Actions security workflow

## Related Documentation

- **OAuth2 Security**: [../oauth2/security.md](../oauth2/security.md) - OAuth2 security implementation
- **Admin Auth**: [../oauth2/admin-auth.md](../oauth2/admin-auth.md) - Admin authentication details
- **DPoP Implementation**: [../oauth2/dpop.md](../oauth2/dpop.md) - DPoP proof validation
- **Security Tests**: [../tests/05-security/README.md](../tests/05-security/README.md) - Security test documentation
- **Token Management**: [../oauth2/token-management.md](../oauth2/token-management.md) - Token lifecycle
