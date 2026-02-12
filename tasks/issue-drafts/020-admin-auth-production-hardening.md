# Admin auth: production hardening + clear operator story

## Summary

Admin authentication is functional, but needs a clear production story: secret handling/rotation, request-level authorization ergonomics, and stronger guarantees around issuer/audience/algorithms and token invalidation.

## Background / current state (as of 2026-02-12)

- File: `ATProtoPDS/Sources/Admin/PDSAdminAuth.m`
- Current behavior highlights:
  - Admin requests authenticate via JWT verification and require `scope` containing `admin` (whitespace-delimited).
  - Tokens can be presented via:
    - `Authorization: Bearer <jwt>`
    - `X-Admin-Token: <jwt>` (fallback)
  - Admin token minting:
    - `authenticateWithPassword:` reads expected admin password from:
      - `PDS_ADMIN_PASSWORD_FILE` (preferred; file is re-read each time), or
      - `PDS_ADMIN_PASSWORD`
    - On success it mints a 1-hour JWT with:
      - `scope=admin`
      - `iss`/`aud` derived from `PDS_ISSUER` (defaults to `https://pds.local:8443`)
      - `sub=did:web:<issuerHost>`
  - Password verification supports:
    - plain-text (constant-time compare; intended for dev/testing)
    - `pbkdf2:<iterations>:<base64salt>:<base64hash>` (PBKDF2-SHA256)
  - Logout behavior:
    - `logout` clears the cached `adminToken` and sets an in-memory `minimumTokenIssuedAt` to invalidate older tokens (until process restart).

Also referenced by `tasks/project-tasks.md` (“Secure admin authentication + gating”).

## Execution update (2026-02-12)

Implemented:

- `PDS_ADMIN_TOKEN_TTL_SECONDS` support in `PDSAdminAuth` with bounded range (`60..86400`, default `3600`).
- Production issuer enforcement semantics:
  - require explicit `PDS_ISSUER` when `PDS_REQUIRE_ISSUER=1`, or
  - require explicit `PDS_ISSUER` when `PDS_ENV=production`.
- Optional disablement of legacy header auth via `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1` (forces Bearer-only).
- Dedicated unit coverage in `ATProtoPDS/Tests/Admin/PDSAdminAuthTests.m`:
  - issuer-required failure
  - TTL claim behavior
  - `X-Admin-Token` disabled/enabled behavior
- Admin endpoint classification hardening in `PDSAuthzManager`:
  - all `com.atproto.admin.*` methods now classify as admin by namespace prefix
  - explicit non-namespace admin set is limited to `com.atproto.temp.addReservedHandle`
  - removed stale `com.atproto.server.createInviteCode(s)` entries from admin classification
- Expanded `PDSAuthzManagerTests` coverage for newly added admin methods (`moderateAccount`, `moderateRecord`, `takeDownAccount`, `getAccountTakedown`, `disableInviteCodes`, `getSubjectStatus`, `updateSubjectStatus`) and non-admin invite-code checks.
- Registered `PDSAuthzManagerTests` in `ATProtoPDS/Tests/test_main.m` and fixed its DB setup to use temporary SQLite files so the suite runs reliably in CI/local runs.
- Fixed secp256k1 key reload correctness:
  - `Secp256k1KeyPair keyPairWithPrivateKey:` now derives the public key from the provided private key (instead of generating a fresh random pair), preventing signature verification failures after persisted-key reload.
  - Added regression coverage in `JWTTests` (`testKeyPairWithPrivateKeyDerivesMatchingPublicKey`).
- Added negative auth coverage for admin request paths:
  - `AdminAuthXrpcTests` now verifies issuer-mismatch and audience-mismatch admin tokens are rejected (`401 AuthRequired`).
  - `PDSAdminAuthTests` now verifies `logout` invalidates previously minted admin tokens.
- Added operator documentation:
  - `docs/security/ADMIN_AUTH_CONFIGURATION.md` now documents required env vars, production issuer semantics, `X-Admin-Token` policy, TTL bounds, and rotation/invalidation playbooks.
- Tightened JWT verification behavior for admin/auth request paths:
  - `PDSAdminAuth` now rejects admin tokens missing `iss` or `aud` claims.
  - `PDSAdminAuth` and `XrpcMethodRegistry` now derive `allowedAlgorithms` from configured `JWTMinter.signingAlgorithm` (with conservative fallback only when unset), reducing permissive algorithm acceptance.
  - Added tests for missing-issuer/missing-audience admin token rejection in `PDSAdminAuthTests`.
- Closed auth-enforcement gaps in application-registered admin handlers:
  - `com.atproto.admin.updateSubjectStatus`, `com.atproto.admin.getSubjectStatus`, `com.atproto.admin.moderateAccount`, and `com.atproto.admin.moderateRecord` now enforce `authorizeAdminRequest(...)` in the `registerMethodsWithDispatcher:application:` path.
  - Added explicit regression coverage in `AdminAuthApplicationXrpcTests` for `401` (missing auth), `403` (non-admin), and admin-allowed behavior.

## Gaps to address

- Operator UX:
  - Which env vars are required?
  - How do we rotate secrets?
  - What’s the recommended deployment pattern (file secret vs env secret)?
- Request-level authorization:
  - Avoid/limit process-global state beyond config and key material.
  - Ensure admin access is consistently gated (method allowlist, scope checks).
- Test coverage for auth:
  - Admin token rotation / minimum issued-at (if used).
  - Negative cases (bad issuer/audience/scope).

## Non-goals

- Replacing the JWT subsystem or key rotation architecture.
- Building a full RBAC system (we only need “admin yes/no” right now).
- Adding a dependency on an external secret manager (we can support file-based secrets).

## Proposed changes

### 1) Document and standardize admin auth configuration

- Add a short doc section (README or docs) covering:
  - required env vars (`PDS_ISSUER`, password config)
  - recommended secret sources (file-based secret; Docker/K8s secret mount)
  - rotation procedure (step-by-step)
  - recommended password storage format:
    - prefer `pbkdf2:` in production
    - recommended minimum iterations and salt size (decision needed; document)

### 2) Tighten verification semantics

- Ensure:
  - issuer and audience are set consistently and are not silently defaulted in production mode
  - allowed algorithms are explicit and reflect the actual server signing key configuration
  - scope parsing is strict (no partial matches like `administrator`)
  - admin token TTL is configurable (but defaults to a short, safe value)

Possible config knobs (pick a minimal set):
- `PDS_ADMIN_TOKEN_TTL_SECONDS` (default 3600)
- `PDS_REQUIRE_ISSUER=1` (fail startup if `PDS_ISSUER` missing) OR `PDS_ENV=production` semantics
- `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1` (force standard Bearer token usage)

### 3) Make endpoint gating explicit

- Ensure the “admin methods set” (e.g. `PDSAuthzManager`) is authoritative for:
  - which endpoints require admin
  - how non-admin tokens are rejected

Also ensure:
- there is a single, consistent mapping of:
  - 401 (no/invalid auth) vs
  - 403 (valid auth, but missing `admin` scope)

### 4) Add tests

- Extend `ATProtoPDS/Tests/Network/AdminAuthXrpcTests.m` and/or add a dedicated auth test file to cover:
  - missing auth -> 401
  - non-admin -> 403
  - wrong issuer/audience -> 401/403 as appropriate
  - scope absent -> forbidden
  - `logout` invalidates tokens minted before `minimumTokenIssuedAt`
  - `pbkdf2:` verification works and rejects malformed formats

## Subtasks (suggested breakdown)

- [x] Add docs: admin auth configuration + rotation guide.
- [x] Document “production mode” semantics for `PDS_ISSUER` (implementation now requires explicit issuer in production mode).
- [x] Add configurable admin token TTL.
- [x] Document `X-Admin-Token` policy (currently supported by default; can be disabled with `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=1`).
- [x] Confirm `allowedAlgorithms` is correct for the current JWT signing configuration; tighten if needed.
- [x] Add tests for issuer requirement and header policy (`PDSAdminAuthTests`).
- [x] Add tests for issuer/audience mismatch and logout invalidation in XRPC/admin route flows.
- [x] Verify admin method allowlist covers all `com.atproto.admin.*` endpoints (including newly added ones).

## Files likely touched

- `ATProtoPDS/Sources/Admin/PDSAdminAuth.m`
- `ATProtoPDS/Sources/Security/PDSAuthzManager.m`
- `ATProtoPDS/Tests/Admin/PDSAdminAuthTests.m`
- `ATProtoPDS/Tests/Network/AdminAuthXrpcTests.m`
- Documentation (TBD location)

## Definition of done

- [x] Clear operator documentation exists (how to configure + rotate).
- [x] Admin method allowlist is explicit and consistently enforced.
- [x] Tests cover the major negative auth cases.
- [x] Admin token TTL / issuer configuration is explicit and safe in production mode.
- [ ] No regressions to existing admin endpoints.
