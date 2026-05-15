---
title: JWT Tokens
---

# JWT Tokens

## Overview

Garazyk uses JSON Web Tokens (JWT) for access and refresh tokens. These tokens are often cryptographically bound to a client's key using DPoP.

## Token Types

- **Access Tokens**: Used for authenticated API requests.
- **Refresh Tokens**: Used to obtain new access tokens.
- **DPoP Proofs**: Ephemeral JWTs that prove ownership of a private key.

## Session-Backed Validation

Unlike purely stateless JWT implementations, Garazyk validates tokens against persisted session state in the service database. This allows for:

- Immediate revocation of sessions.
- Rotation of tokens.
- Strict DPoP thumbprint binding.
- Account state checks (e.g., suspension).

## Debugging Token Issues

- **Minting Rules**: Check `Garazyk/Sources/Auth/Session.m`.
- **Issuer/Audience Configuration**: Verified in `Garazyk/Sources/App/PDSApplication.m`.
- **Request Verification**: Handled by auth helpers in the network layer.

## Related Deep Dives
- [Session and JWT Lifecycle](./session-and-jwt-lifecycle)
- [OAuth + DPoP Request Walkthrough](./oauth-dpop-request-walkthrough)
- [OAuth 2.0 with DPoP](./oauth2-dpop)

## Related Reading
- [Auth Helpers](../04-network-layer/auth-helpers)
- [Security Best Practices](./security-best-practices)
- [Glossary](../GLOSSARY)

