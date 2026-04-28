---
title: JWT Tokens
---

# JWT Tokens

## Overview

Garazyk uses JWTs for access tokens and refresh-token-adjacent session flows, with optional DPoP binding. Token handling is not purely stateless: session persistence is part of the contract.

## Token Families In Practice

The runtime works with three related token shapes:

- access tokens for authenticated API requests
- refresh-token-backed session renewal
- DPoP proofs that bind a request to the key the token was minted for

The token surface operates alongside session storage and auth helpers.

## Why Session State Still Matters

A valid JWT alone is insufficient. The runtime uses persisted session state to:

- look up active tokens quickly
- rotate and revoke sessions
- carry DPoP thumbprint binding forward
- enforce account and runtime identity checks consistently

That means many apparent "JWT bugs" are really session-lifecycle or runtime-identity bugs.

## What Contributors Should Keep Straight

Separate these concerns when you debug token behavior:

- token minting rules
- issuer and audience configuration
- session lookup and refresh behavior
- request-time verification in auth helpers

Mixing these concepts complicates debugging.

## Common Failure Modes

Start here when you see:

- tokens that mint correctly but fail on request use
- refresh flows that leave the caller with inconsistent session state
- issuer or audience mismatches between environments
- DPoP-bound tokens that fail only on some requests

## Related Deep Dives

- [Session and JWT Lifecycle](./session-and-jwt-lifecycle)
- [OAuth + DPoP Request Walkthrough](./oauth-dpop-request-walkthrough)

## Related Reading

- [OAuth 2.0 with DPoP](./oauth2-dpop)
- [Auth Helpers](../04-network-layer/auth-helpers)
- [Startup and Boot Sequence](../01-getting-started/startup-and-boot-sequence)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

