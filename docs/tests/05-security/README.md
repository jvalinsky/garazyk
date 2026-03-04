---
title: Security Tests
---

# Security Tests

Tests for authorization, security hardening, and input validation.

## Files

| File | Description |
|------|-------------|
| [hardening.md](hardening) | Production security, CBOR parser hardening, token rotation, DPoP nonces |
| [validation.md](validation) | SQL injection prevention, path traversal blocking, XSS prevention, null-byte detection |
| [auth-security.md](auth-security) | XRPC endpoint authorization, admin access control, cross-repo write protection |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| ProductionSecurityTests | Tests/Security/ProductionSecurityTests.m | Production hardening |
| CBORSecurityTests | Tests/Security/CBORSecurityTests.m | Parser robustness |
| PDSInputValidatorTests | Tests/Security/PDSInputValidatorTests.m | Input sanitization |
| SecurityHardeningTests | Tests/Network/SecurityHardeningTests.m | Token security |
| AdminAuthXrpcTests | Tests/Network/AdminAuthXrpcTests.m | Admin endpoint auth |
| RepoAuthXrpcTests | Tests/Network/RepoAuthXrpcTests.m | Repository auth |
| AdminModerationAuthTests | Tests/XRPC/AdminModerationAuthTests.m | Moderation auth |
| PDSAuthzManagerTests | Tests/Security/PDSAuthzManagerTests.m | Authorization manager |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ProductionSecurityTests
./build/tests/AllTests -only-testing:AllTests/CBORSecurityTests
./build/tests/AllTests -only-testing:AllTests/PDSInputValidatorTests
```

## Related Documentation

- [Test Index](../README) - Main test documentation index
- [Security Documentation](../../security/README) - Security analysis
- [Security Analysis Report](../../security/SECURITY_ANALYSIS_REPORT) - Detailed security review
- [OAuth2 Security](../../oauth2/security) - OAuth2 security model
- [Admin Auth Configuration](../../security/ADMIN_AUTH_CONFIGURATION) - Admin auth setup
- [Identity Tests](../00-identity-auth/README) - Authentication tests
- [Network Tests](../02-network/README) - Network security
