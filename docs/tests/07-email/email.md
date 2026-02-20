# Email Provider Tests

Tests for email providers, HTTP clients, and secrets management.

## Test Classes

### PDSResendEmailProviderTests
**File:** `Tests/Email/PDSResendEmailProviderTests.m`
**Purpose:** Resend email provider with API key handling.

| Method | Description |
|--------|-------------|
| `testInitWithSecretsProvider` | Init with secrets provider |
| `testInitWithCustomEndpoint` | Custom API endpoint |
| `testProperties` | Readonly properties |
| `testSendEmailWithMissingAPIKey` | Error for missing key |
| `testSendEmailSuccess` | Successful send with payload |
| `testSendEmailFailure` | HTTP error propagation |
| `testSendHtmlEmailSuccess` | HTML+text multipart |

---

### PDSEmailHTTPClientTests
**File:** `Tests/Email/PDSEmailHTTPClientTests.m`
**Purpose:** Email HTTP client configuration.

| Method | Description |
|--------|-------------|
| `testInit` | Init with base URL and API key |
| `testDefaultValues` | Default 30s timeout, 3 retries |
| `testConfigurableValues` | Custom timeout/retries |

---

### PDSKeychainSecretsProviderTests
**File:** `Tests/Email/PDSKeychainSecretsProviderTests.m`
**Purpose:** macOS keychain-backed secrets storage.

| Method | Description |
|--------|-------------|
| `testInitWithService` | Custom keychain service |
| `testInitDefaultService` | Default service name |
| `testStoreAndRetrieveSecret` | Secret round-trip |
| `testRetrieveNonExistentSecret` | Error for missing |
| `testSecretForKeyWithEmptyKey` | Empty key validation |
| `testDeleteSecret` | Secret deletion |
| `testUpdateExistingSecret` | Secret overwrite |

---

### PDSEnvironmentSecretsProviderTests
**File:** `Tests/Email/PDSEnvironmentSecretsProviderTests.m`
**Purpose:** Environment variable-backed secrets.

| Method | Description |
|--------|-------------|
| `testInitWithPrefix` | Key prefix support |
| `testInitWithoutPrefix` | No prefix mode |
| `testSecretForKeyWithSetVariable` | Retrieve set var |
| `testSecretForKeyWithPrefix` | Prefixed lookup |
| `testSecretForKeyWithMissingVariable` | Error for unset |
| `testSecretForKeyWithEmptyKey` | Empty key validation |

---

### EmailIntegrationTests
**File:** `Tests/Integration/EmailIntegrationTests.m`
**Purpose:** End-to-end email flow testing.

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSResendEmailProviderTests
./build/tests/AllTests -only-testing:AllTests/PDSKeychainSecretsProviderTests
./build/tests/AllTests -only-testing:AllTests/PDSEnvironmentSecretsProviderTests
```

## Secrets Provider Interface

```objc
@protocol PDSSecretsProvider
- (NSString *)secretForKey:(NSString *)key error:(NSError **)error;
- (BOOL)storeSecret:(NSString *)secret forKey:(NSString *)key error:(NSError **)error;
@end
```

## Related Documentation

- [Folder README](README.md) - Email tests overview
- [Test Index](../README.md) - Main test documentation index
- [Security Tests](../05-security/README.md) - Secrets management
- [Application Tests](../04-application/README.md) - Application services
