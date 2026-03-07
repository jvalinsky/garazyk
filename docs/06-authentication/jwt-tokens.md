---
title: JWT Tokens
---

# JWT Tokens

## Overview

September uses JWTs for access tokens and refresh-token-adjacent session flows, with optional DPoP binding layered on top. The important contributor detail is that token handling is not purely stateless in this repo: session persistence remains part of the contract.

## Token Families In Practice

The runtime works with three related token shapes:

- access tokens for authenticated API requests
- refresh-token-backed session renewal
- DPoP proofs that bind a request to the key the token was minted for

The token surface only makes sense when you read it together with session storage and auth helpers.

## Why Session State Still Matters

A valid JWT is not the whole answer. The runtime also uses persisted session state so it can:

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

Collapsing them into one mental model makes token bugs look much more mysterious than they are.

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
