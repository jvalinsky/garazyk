---
title: OAuth 2.0 with DPoP
---

# OAuth 2.0 with DPoP

## Overview

Garazyk supports ATProtocol-style OAuth with DPoP-bound access tokens. This ensures that tokens are cryptographically bound to a specific client key.

## Implementation Details

The implementation is spread across several layers:

- **Authorization Handling**: Managing OAuth client and grant state.
- **Token Issuance**: Binding tokens to a DPoP thumbprint.
- **Session Persistence**: Ensuring refresh and revocation remain coherent.
- **Proof Verification**: Verifying DPoP proofs against method, URL, and nonce.

## Core Components

- `OAuth2Handler` (`Sources/Auth/OAuth2Handler.m`): Handles HTTP authorization and token endpoints.
- `DPoPUtil` (`Sources/Auth/DPoPUtil.m`): Manages proof verification and binding.
- `PDSNonceManager` (`Sources/Auth/PDSNonceManager.m`): Enforces replay protection.
- `Session`: Owns persisted session state and lookup.
- **Auth Helpers**: Enforce request-time token and DPoP requirements.

## Common Failure Modes

- **Client Metadata Mismatch**: Incorrect client configuration or redirect URIs.
- **DPoP Proof Failure**: Invalid proof signature or mismatched URL/method.
- **Nonce Challenges**: Handlers must correctly manage `use_dpop_nonce` responses.
- **Proxy Misconfiguration**: Issuer or public URL mismatches caused by reverse proxies.
- **Content-Type Mismatch**: The token endpoint supports both `application/json` and `application/x-www-form-urlencoded`. Ensure the client and server agree on the format.

## Related Deep Dives
- [OAuth + DPoP Request Walkthrough](./oauth-dpop-request-walkthrough)
- [Session and JWT Lifecycle](./session-and-jwt-lifecycle)
- [JWT Tokens](./jwt-tokens)

## Related Reading
- [Security Best Practices](./security-best-practices)
- [Auth Helpers](../04-network-layer/auth-helpers)
- [Glossary](../GLOSSARY)

