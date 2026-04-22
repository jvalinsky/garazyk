---
title: OAuth 2.0 with DPoP
---

# OAuth 2.0 with DPoP

## Overview

Garazyk supports ATProto-style OAuth with DPoP-bound access tokens. The important contributor fact is that this is not one class or one check. The guarantee is split across authorization handling, token issuance, session persistence, and request-time proof verification.

## What The Current Implementation Guarantees

At a high level, the runtime does four things:

- validates OAuth client and grant state
- binds issued tokens to a DPoP thumbprint when required
- stores session state so refresh, revocation, and later request checks remain coherent
- verifies request-time DPoP proofs against method, URL, nonce, and token binding

That split is why an OAuth failure can originate in very different parts of the auth stack.

## The Main Runtime Boundary

The auth path is easiest to reason about when you separate the layers:

- `OAuth2Handler` (`Sources/Auth/OAuth2.m`) owns HTTP-facing authorization and token endpoints.
- `DPoPUtil` (`Sources/Auth/DPoPUtil.m`) handles proof verification and binding.
- `PDSNonceManager` (`Sources/Auth/PDSNonceManager.m`) enforces replay protection via nonces.
- `Session` owns persisted session state, refresh, and lookup.
- Auth helpers enforce request-time token and DPoP requirements.

If you read all OAuth failures as "token parsing bugs," you will miss most of the real causes.

## Common Failure Modes

When this flow breaks, the usual buckets are:

- client metadata or client authentication mismatch
- authorization code or PKCE state mismatch
- DPoP proof verification failure
- `use_dpop_nonce` challenge handling
- issuer, audience, or public URL mismatch behind a proxy
- session rotation or refresh state drift

Those are different debugging paths, which is why the deep dives exist.

## Why This Page Stays Short

The old version of this page mixed protocol explanation with long code excerpts. That made it hard to see which part of the runtime actually enforces which guarantee. The deep dives now carry the concrete flows, while this summary page keeps the mental model clean.

## Related Deep Dives

- [OAuth + DPoP Request Walkthrough](./oauth-dpop-request-walkthrough)
- [Session and JWT Lifecycle](./session-and-jwt-lifecycle)

## Related Reading

- [JWT Tokens](./jwt-tokens)
- [Auth Helpers](../04-network-layer/auth-helpers)
- [Security Best Practices](./security-best-practices)
- [Troubleshooting](../11-reference/troubleshooting)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n