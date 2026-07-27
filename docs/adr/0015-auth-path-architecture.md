# ADR 0015: Auth Verification Cluster Wired Rather Than Deleted

**Status:** Accepted
**Date:** 2026-07-27

## Context

Code review in workstream 01 S8 identified three files in `Garazyk/Sources/`
that exist but are never constructed:

- `Auth/Verifier/AuthVerifier.m` — a JWT-local-issuer verifier that wraps
  `JWTVerifier` with audience, issuer, admin-scope, DPoP, and takedown checks.
  Contains two self-recursive setters (`-setLocalPublicKey:`,
  `-setLocalIssuer:`) that are unbounded recursion.
- `Auth/PDS/PDSAuth.m:346-385` — `PDSAccountPolicy`, a takedown-policy
  check. `isAccountAllowed:` returns `YES` when its `adminController` is nil
  (the only possible state, since it's never set).
- `Security/GZAuthzManager.m` — a singleton authorization manager with
  `validateReadAccess:` and `isAuthorizedForAdminOperation:`. Zero production
  callers. Contains a broken mute check that denies owners reading their own
  repo, and a `validateAdminAccess:` that can never return `YES` yet runs a
  discarded database query.

One of two futures was possible:

- **Delete** — remove the three files, their headers, and their test suites.
  The live auth path (`XrpcAuthHelper` → `PDSAuth` → `adminController`) is
  complete and tested. Delete preserves the status quo.
- **Wire** — fix each file's defects, construct them, and route XRPC auth
  through them alongside the incumbent path, with a parity comparison before
  cutover.

The wire option was chosen. The reasoning:

- `AuthVerifier` captures a verification pattern (local-issuer JWT + DPoP +
  audience + takedown) that is duplicated across at least three call sites
  (`XrpcAuthHelper`, `PDSAuth`, individual route packs). A dedicated
  verifier reduces duplication and centralizes the security contract.
- `PDSAccountPolicy` formalizes the takedown check that is currently
  scattered across `XrpcAuthHelper.m:369` and individual `Xrpc*Pack.m`
  handlers. A single policy object is auditable and testable in isolation.
- `GZAuthzManager` provides admin-scope and owner-check utilities that
  route packs currently reimplement ad hoc. Deleting it would discard the
  only central admin-authorization point.
- The three files represent accumulated design work from multiple
  contributors. Deleting them without a documented rationale would lose
  institutional knowledge.

## Decision

1. **The three files are fixed, constructed, and wired** as the new auth
   path behind a zero-rebuild fallback switch. The incumbent
   `XrpcAuthHelper` path remains fully operational and is not deleted in
   this phase.

2. **Fix ordering is mandatory: fix first, wire last.** The defects must be
   resolved before the cluster carries traffic, because two of them would
   cause an outage:

   a. `GZAuthzManager validateReadAccess:` denies owners reading their own
      repo when the account row exists.
   b. `GZAuthzManager` (via `GZInputValidator isValidDID:`) rejects every
      `did:web` account, since the character class excludes `.`.

3. **The cutover is controlled by an environment variable**
   (`PDS_USE_AUTH_VERIFIER`). When set to `1`, `XrpcAuthHelper` delegates
   to the cluster first and falls back to the incumbent path if the cluster
   rejects. When unset, the incumbent path is used. This requires no
   rebuild: a running PDS can be switched by setting the env var and
   restarting.

4. **Parity is proven before the switch defaults to on.** A decision matrix
   covering all authentication outcomes (valid, expired, suspended,
   taken-down, `did:plc`, `did:web`, owner, non-owner, admin, non-admin,
   DPoP-valid, DPoP-mismatched, DPoP-none) is run on both paths. Identical
   outcomes across the matrix are required before the switch can be flipped
   in a production config.

5. **Rollback trigger.** If the cluster path introduces a regression:

   a. Unset `PDS_USE_AUTH_VERIFIER` and restart. This returns all auth
      decisions to the incumbent `XrpcAuthHelper` path immediately.
   b. The cluster code remains in the tree and can be re-enabled after the
      fix.
   c. No data migration or schema change is involved — the switch is a
      pure code-route change.

## Consequences

- **Risk is inverted.** The three files go from harmless dead code to
  load-bearing auth components. Each defect in them becomes a release
  blocker. The mandatory fix-first ordering mitigates this: steps 1–5 of
  phase 14 repair every known defect before step 6 wires anything.
- **Parity debt.** Until the switch defaults to on, two auth paths evolve
  independently. A change to `XrpcAuthHelper` that is not reflected in the
  cluster (or vice versa) widens the parity gap. The switch should be
  flipped to default-on within one release cycle, and the incumbent path
  removed in the next.
- **Test surface doubles.** Every auth-behavior test must be meaningful on
  both paths until deletion. New auth tests should exercise the cluster
  directly (constructing the verifier without the switch) and verify that
  the switch path produces the same result.
- **No incumbent path deleted.** `XrpcAuthHelper` and all its call sites
  remain untouched. Deleting them is a separate phase after the cluster is
  proven in production.
- **The switch is coarse (all-or-nothing).** Per-endpoint or per-issuer
  partial cutover would be more granular but adds complexity without clear
  benefit given the parity matrix requirement.
