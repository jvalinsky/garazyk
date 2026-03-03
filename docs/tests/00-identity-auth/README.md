# Identity & Authentication Tests

Tests for identity resolution, OAuth flows, JWT handling, cryptography, and multi-factor authentication.

## Files

| File | Description |
|------|-------------|
| [identity-resolution.md](identity-resolution) | Handle resolution via HTTPS/DNS, DID resolution with caching, SSRF protection, handle validation rules |
| [jwt-crypto.md](jwt-crypto) | JWT parsing/signing/verification, ES256K cryptography, key management, replay cache |
| [mfa.md](mfa) | TOTP generation/verification, WebAuthn/Passkey registration, YubiKey OATH |
| [oauth.md](oauth) | OAuth 2.0 flows, PKCE, DPoP proofs, token rotation, session management |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| HandleResolverTests | Tests/Identity/HandleResolverTests.m | HTTPS/DNS handle resolution |
| HandleResolverSSRFTests | Tests/Identity/HandleResolverSSRFTests.m | SSRF protection |
| DIDResolverTests | Tests/Identity/DIDResolverTests.m | DID document resolution |
| ATProtoHandleValidatorTests | Tests/Identity/ATProtoHandleValidatorTests.m | Handle format validation |
| JWTTests | Tests/Auth/JWTTests.m | JWT operations |
| CryptoTests | Tests/Auth/CryptoTests.m | SHA-256, HMAC, random bytes |
| TOTPTests | Tests/Auth/TOTPTests.m | TOTP generation |
| WebAuthnVerifierTests | Tests/Auth/WebAuthnVerifierTests.m | WebAuthn verification |
| OAuth2Tests | Tests/Auth/OAuth2Tests.m | OAuth token flows |
| OAuthDPoPTests | Tests/Auth/OAuthDPoPTests.m | DPoP proof handling |
| OAuthConformanceTests | Tests/Auth/OAuthConformanceTests.m | OAuth spec conformance |
| OAuthPublicClientTests | Tests/Auth/OAuthPublicClientTests.m | Public client flows |
| OAuthSessionTests | Tests/Auth/OAuthSessionTests.m | OAuth session management |
| OAuthIntegrationTests | Tests/Auth/OAuthIntegrationTests.m | OAuth integration |
| SessionStoreTests | Tests/Auth/SessionStoreTests.m | Session lifecycle |
| PDSReplayCacheTests | Tests/Auth/PDSReplayCacheTests.m | Replay attack prevention |
| PDSOpenSSLKeyManagerTests | Tests/Auth/PDSOpenSSLKeyManagerTests.m | OpenSSL key management |
| KeyManagerCharacterizationTests | Tests/CharacterizationTests/KeyManagerCharacterizationTests.m | Key manager behavior |
| SessionCharacterizationTests | Tests/CharacterizationTests/SessionCharacterizationTests.m | Session behavior |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/HandleResolverTests
./build/tests/AllTests -only-testing:AllTests/JWTTests
./build/tests/AllTests -only-testing:AllTests/OAuth2Tests
```

## Related Documentation

- [Test Index](../README) - Main test documentation index
- [OAuth2 Documentation](../../oauth2/README) - OAuth2 architecture and flows
- [Security Documentation](../../security/README) - Security hardening and validation
- [Authorization Flow](../../oauth2/authorization-flow) - OAuth2 authorization process
- [Token Management](../../oauth2/token-management) - JWT token handling
- [SSRF Protection](../../security/SSRF_PROTECTION) - Handle resolver SSRF protection
