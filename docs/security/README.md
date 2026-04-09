---
title: Security Documentation
---

# Security Documentation

This directory is specialized security reference: reports, hardening notes, testing plans, and security-specific operational guidance. It complements the main contributor docs instead of replacing them.

For the current contributor path, start with:

- [Security Audit Guide](../11-reference/security-audit-guide)
- [Security Best Practices](../06-authentication/security-best-practices)
- [Troubleshooting](../11-reference/troubleshooting)
- [Testing Map](../11-reference/testing-map)

Use this directory when you need deeper security detail, historical audit context, or implementation-specific hardening notes.

## Main Documents

| File | Focus |
| --- | --- |
| [ADMIN_AUTH_CONFIGURATION.md](ADMIN_AUTH_CONFIGURATION) | admin authentication setup and rotation |
| [IDENTITY_HARDENING.md](IDENTITY_HARDENING) | identity-related hardening notes |
| [SECURITY_ANALYSIS_REPORT.md](SECURITY_ANALYSIS_REPORT) | broader security review and findings |
| [SECURITY_PLAN.md](SECURITY_PLAN) | security validation strategy |
| [SECURITY_TESTING_PLAN.md](SECURITY_TESTING_PLAN) | security testing plan and attack surfaces |
| [security_test_results.md](security_test_results) | test and validation results |
| [SQL_INJECTION_VULNERABILITY_REPORT.md](SQL_INJECTION_VULNERABILITY_REPORT) | SQL injection-focused report |
| [SSRF_PROTECTION.md](SSRF_PROTECTION) | SSRF protections for handle resolution |

## Historical Material

Additional reports live in `reports/`. Treat them as historical context unless a current contributor page links to them directly.

## Related Collections

- [OAuth2 Reference](../oauth2/README)
- [Security Tests](../tests/05-security/README)
- [Guides](../guides/README)
