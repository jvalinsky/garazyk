# Identity & Authentication Tests

Tests for identity resolution, OAuth flows, JWT handling, cryptography, and multi-factor authentication.

## Files

| File | Description |
|------|-------------|
| [identity-resolution.md](identity-resolution.md) | Handle resolution via HTTPS/DNS, DID resolution with caching, SSRF protection, handle validation rules |
| [jwt-crypto.md](jwt-crypto.md) | JWT parsing/signing/verification, ES256K cryptography, key management, replay cache |
| [mfa.md](mfa.md) | TOTP generation/verification, WebAuthn/Passkey registration, YubiKey OATH |
| [oauth.md](oauth.md) | OAuth 2.0 flows, PKCE, DPoP proofs, token rotation, session management |

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
| SessionStoreTests | Tests/Auth/SessionStoreTests.m | Session lifecycle |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/HandleResolverTests
./build/tests/AllTests -only-testing:AllTests/JWTTests
./build/tests/AllTests -only-testing:AllTests/OAuth2Tests
```
