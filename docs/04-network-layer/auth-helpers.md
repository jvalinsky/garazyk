---
title: Auth Helpers
---

# Auth Helpers

`XrpcAuthHelper` is the primary authentication boundary for [XRPC](./xrpc-dispatch) endpoints. It centralizes security logic, including header parsing, [JWT](../GLOSSARY.md#jwt) verification, [DPoP](../GLOSSARY.md#dpop) proof checks, audience validation, and account moderation checks.

Centralizing this logic ensures consistent security enforcement across all handlers.

## Supported Authentication Methods

The helper supports two primary authentication schemes:
- **Bearer**: Standard authorization using JWT access tokens.
- **DPoP (Demonstrating Proof-of-Possession)**: Enhanced authorization combining a `Bearer` token with a `DPoP` proof header for key-binding.

## DPoP Verification

For DPoP-protected requests, the helper:
- Verifies the DPoP proof against the HTTP method and request URL.
- Enforces nonce usage and issues `DPoP-Nonce` challenges when necessary.
- Binds the access token to the presented public key via the `cnf.jkt` claim.

## JWT Validation

The helper uses `JWTVerifier` to validate tokens against configured key material. It enforces:
- **Expiration**: Rejection of expired tokens.
- **Issuer/Audience**: Verification that the token was issued by and intended for the current PDS.
- **Scope**: Ensuring the token identity matches the repository being accessed.

## Proxy and Host Header Handling

DPoP verification depends on the request URL. The helper trusts forwarded headers (e.g., `X-Forwarded-Host`) only if `PDS_TRUST_PROXY_HEADERS` is enabled and the request originates from a trusted proxy.

## Account and Administrative Status

Beyond cryptographic validation, the helper verifies account state:
- **Moderation**: Valid tokens are rejected if the account is suspended or deactivated.
- **Privilege**: Enforces authorization for administrative routes (see [Admin Service](../03-application-layer/admin-service)).

## Debugging Authentication Failures

When authentication fails, check the following:
- **Nonces**: Ensure the client is responding to `DPoP-Nonce` challenges.
- **Host Headers**: Verify the `Host` header matches the expected PDS hostname (common in proxy setups).
- **Key Binding**: Confirm the DPoP key matches the `cnf.jkt` claim in the access token.
- **Account State**: Verify the account is not suspended in the database.

## Related

- [OAuth + DPoP Request Walkthrough](../06-authentication/oauth-dpop-request-walkthrough)
- [Session and JWT Lifecycle](../06-authentication/session-and-jwt-lifecycle)
- [XRPC Dispatch](./xrpc-dispatch)
- [From NSID to Service Call](./from-nsid-to-service-call)
- [Account Service](../03-application-layer/account-service)
- [Cryptography](../02-core-concepts/cryptography)
- [Documentation Map](../11-reference/documentation-map.md)

