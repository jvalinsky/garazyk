# Email Tests

Tests for email providers, HTTP clients, and secrets management.

## Files

| File | Description |
|------|-------------|
| [email.md](email.md) | Resend email provider, HTTP client, keychain/environment secrets providers |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| PDSResendEmailProviderTests | Tests/Email/PDSResendEmailProviderTests.m | Resend API integration |
| PDSEmailHTTPClientTests | Tests/Email/PDSEmailHTTPClientTests.m | HTTP client config |
| PDSKeychainSecretsProviderTests | Tests/Email/PDSKeychainSecretsProviderTests.m | macOS keychain storage |
| PDSEnvironmentSecretsProviderTests | Tests/Email/PDSEnvironmentSecretsProviderTests.m | Environment variables |
| EmailIntegrationTests | Tests/Integration/EmailIntegrationTests.m | E2E email flow |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSResendEmailProviderTests
./build/tests/AllTests -only-testing:AllTests/PDSKeychainSecretsProviderTests
```

## Related Documentation

- [Test Index](../README.md) - Main test documentation index
- [Email Provider Tests](email.md) - Email provider details
- [Application Tests](../04-application/README.md) - Application services
- [Security Tests](../05-security/README.md) - Secrets management
