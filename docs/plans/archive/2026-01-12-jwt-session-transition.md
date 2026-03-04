---
title: "Phase 2: JWT Session Token Transition Plan"
---

# Phase 2: JWT Session Token Transition Plan

**Goal:** Migrate PDS session management from opaque UUID tokens to signed JWT access tokens as per ATProto specification.

## Task 1: Enhance Session Class with JWTMinter

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/Session.h`
- Modify: `ATProtoPDS/Sources/Auth/Session.m`

**Steps:**
1. Add `JWTMinter` property to `Session`.
2. Update `mintTokens` to use `JWTMinter` for creating signed JWT access tokens.
3. Access tokens should include: `iss`, `sub`, `iat`, `exp`, `jti`, `did`, `scope`.

## Task 2: Update SessionStore for JWT Validation

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/Session.m` (SessionStore implementation)

**Steps:**
1. Update `getSessionByAccessToken:error:` to optionally validate the JWT if needed.
2. Ensure lookup still works using the JWT string as the key in `sessionsByAccessToken`.

## Task 3: Update XRPC Authentication Extraction

**Files:**
- Modify: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

**Steps:**
1. Update `extractDIDFromAuthHeader:controller:request:` to properly verify the JWT using `JWTVerifier`.
2. Ensure it handles both legacy UUIDs (for transition) and new JWTs, or fully migrate.

## Task 4: Fix Integration Tests

**Files:**
- Modify: `ATProtoPDS/Tests/Network/PDSIntegrationTests.m`

**Steps:**
1. Invert tests that currently assert tokens are NOT JWTs.
2. Add verification that tokens ARE valid JWTs with correct claims.

## Task 5: Controller Integration

**Files:**
- Modify: `ATProtoPDS/Sources/App/PDSController.m`

**Steps:**
1. Ensure `PDSController` initializes `Session` objects with a correctly configured `JWTMinter` (with the PDS private key).

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [OAuth2 Documentation](../../oauth2/README) - OAuth2 implementation details
