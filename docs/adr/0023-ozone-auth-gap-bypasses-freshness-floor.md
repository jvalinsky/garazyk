# ADR 0023: Ozone Auth Enforces the Freshness Floor via `authorizeAdminRequest:`

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S14 (phase-24 slice 1) identified an authorization gap in the
Ozone (`tools.ozone.*`) XRPC route pack. The static `ExtractAdminDid`
function at `XrpcToolsOzonePack.m:23-39` performs two checks:

1. `extractDIDFromAuthHeader` — extracts the DID from the JWT
2. `isAdminDid:` — verifies the DID is in the admin roster

but it does **not** call `isAuthenticatedWithRequest:`, the freshness-floor
check that `authorizeAdminRequest:` (`XrpcAuthHelper.m:519-549`) includes as
its third step. The canonical auth path at `XrpcAuthHelper.m:519-549` runs
all three: extract DID → check admin roster → check freshness floor (iat ≥
`minimumTokenIssuedAt`). `ExtractAdminDid` skips the third check, so a stale
admin JWT — one minted before the operator ran `logout` to bump the freshness
floor — remains valid on all `tools.ozone.*` endpoints even after the
operator intended to expire all existing admin sessions.

This affects 28 Ozone endpoints (moderation events, team management, sets,
safelinks, settings, communication templates, verification, signatures,
hosting history, server config), each of which calls `ExtractAdminDid` as its
auth guard.

The gap was introduced when Ozone was split from the admin pack (S8 phase 14)
and got its own auth function rather than routing through the shared
`authorizeAdminRequest:`. The shared function had the freshness check; the
Ozone copy did not.

No alternative was considered — the fix is to bring `ExtractAdminDid` into
parity with the canonical path.

## Decision

1. **`ExtractAdminDid` calls `isAuthenticatedWithRequest:` as its third
   check.** After `extractDIDFromAuthHeader` and `isAdminDid:`, the function
   calls `[[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:request.headers]`.
   On failure, it returns 403 with `"Admin token expired or scope
   insufficient"`, matching the error surface of `authorizeAdminRequest:`.

2. **The check is added inline, not via a call to `authorizeAdminRequest:`.
   `authorizeAdminRequest:` at `XrpcAuthHelper.m:519-549` calls
   `extractDIDFromAuthHeader` internally, then `isAdminDid:`, then
   `isAuthenticatedWithRequest:`. But `ExtractAdminDid` already extracts the
   DID and checks `isAdminDid:` before the freshness check — calling
   `authorizeAdminRequest:` would duplicate the DID extraction and admin
   check. Adding only the missing third check keeps the existing structure
   and avoids a redundant JWT parse.

3. **A comment in `ExtractAdminDid` references the canonical path.** The
   comment records that `authorizeAdminRequest:` at
   `XrpcAuthHelper.m:519-549` is the canonical path and that
   `ExtractAdminDid` was missing the freshness-floor check until phase 24
   slice 1.

4. **`PDSAdminAuth`'s `isAuthenticatedWithRequest:` takes `NSObject *` but
   checks `isKindOfClass:[NSDictionary class]` internally.** The Ozone
   handlers call it with `request.headers` (an `NSDictionary`), which is the
   correct parameter type.

5. **Stale-token rejection and non-admin-JWT rejection are tested.**
   `XrpcToolsOzoneTests.m` gains `testEmitModerationEventRejectsStaleAdminToken`
   (sleeps 1.5s, calls `logout` to bump the floor, asserts 403 on the old
   admin JWT) and `testEmitModerationEventRejectsNonAdminJwt` (asserts 403
   on a user JWT). The `tearDown` resets `minimumTokenIssuedAt` to nil via
   KVC to prevent cross-test pollution from `logout` persisting the bumped
   floor to disk.

## Consequences

- **28 endpoints now enforce the freshness floor.** Any operator action that
  calls `logout` (setting `minimumTokenIssuedAt = now`) immediately
  invalidates all admin JWTs minted before that point for Ozone endpoints,
  matching the behavior already in place for `com.atproto.admin.*` endpoints.

- **No contract change.** The auth header format, admin roster, and JWT
  structure are unchanged. Only tokens with `iat < minimumTokenIssuedAt` are
  rejected — the same rejection that the admin endpoints already enforce.

- **Test teardown resets state.** `logout` persists `minimumTokenIssuedAt` to
  disk at `PDSAdminAuth.m:561`. Without the `tearDown` KVC reset, subsequent
  test runs (and subsequent test classes) would inherit the bumped floor.
  The reset sets the property to nil via `setValue:nil forKey:`.

- **Rollback.** Revert the slice-1 commit to remove the
  `isAuthenticatedWithRequest:` call. Ozone endpoints revert to accepting
  any admin JWT regardless of freshness floor. The stale-token test is
  removed with the revert.
