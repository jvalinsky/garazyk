# ADR 0001 — Compat/ platform shims must not depend on Database/

**Status:** Accepted
**Date:** 2026-07-11
**Context skill:** raised during the QueryRunner deepening pilot
(`queryrunner_deepening_pilot_plan.md`).

## Context

`Compat/PlatformShims/Security/SecItemLinuxStore.m` runs raw `sqlite3_*` (≈46 calls) to back
Apple's Keychain/`SecItem` API on Linux with SQLite. The QueryRunner deepening effort swept
every raw-SQLite store as a candidate to migrate onto `ATProtoDatabaseQueryRunner`
(`Database/Utils/`).

`Compat/` is the lowest layer of the stack: it reimplements Apple framework API surfaces
(CommonCrypto, Security, CoreFoundation, LocalAuthentication, os/log, XCTest) so the rest of
the codebase can call those APIs unchanged on GNUstep/Linux. Code across every other
directory depends on `Compat/`. `Database/` sits **above** the platform layer and itself
consumes platform primitives.

Migrating `SecItemLinuxStore` onto `Database/Utils/ATProtoDatabaseQueryRunner` would make a
platform shim depend on a higher layer — a dependency inversion that would create a cycle in
the intended layering and couple the Security shim to the database module's evolution.

## Decision

`Compat/` shims **must not** depend on `Database/` (or any higher layer). `SecItemLinuxStore`
is **excluded** from `ATProtoDatabaseQueryRunner` adoption and retains its own
prepare/bind/step/finalize mechanics.

If a shared SQLite primitive is ever wanted at the platform layer, it belongs in `Compat/` or
below — not in `Database/`.

## Consequences

- `SecItemLinuxStore` keeps bespoke SQLite mechanics. The resulting duplication is **accepted**
  as the cost of a clean dependency direction (leverage is traded away deliberately to
  preserve layering).
- Future architecture reviews should **not** re-suggest migrating `Compat/` stores onto
  `Database/` modules under the banner of "finish QueryRunner adoption." This ADR is the
  standing answer.
- The `seam` for platform SQLite, if it ever needs one, is drawn inside `Compat/`, not by
  reaching up into `Database/`.
