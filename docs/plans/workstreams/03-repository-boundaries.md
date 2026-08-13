---
title: Repository Boundaries
status: active
last_verified: 2026-08-08
---

# Repository Boundaries

## Target

Garazyk remains the Objective-C server repository. Reusable TUI code lives in
`garazyk-tui`; ATProto test orchestration, scenarios, topology fixtures, and the
scenario dashboard live in `garazyk-atproto-testing`. Versioned JSR packages
form the dependency boundary.

## Current evidence

- Both external repositories exist, track their private `origin/main`, and had
  clean worktrees after the 2026-08-08 synchronization pass.
- The old split branch contains the in-tree deletion and compatibility cleanup.
- `garazyk-tui` already contained the authoritative in-tree TUI changes through
  the latest package commit, so no source commit or push was needed. Its
  `fmt --check` (40 files), lint (36 files), check, and 252-test suite passed.
- `garazyk-atproto-testing` commit `61fd0ef5` synchronized Gruszka, Hamownia,
  Laweta, Schemat, scenario 99, scenarios 93/94, and the missing scenario and
  topology adapters, then was pushed to private `origin/main`. Format (2,532
  files), lint (2,290 files), check, package-entrypoint checks, 3,946 tests (4
  ignored), 99-scenario discovery, dashboard build (24 routes, 16 islands), and
  a headless dashboard TUI capture passed.
- **2026-07-25:** no TypeScript file under `scripts/scenarios/` or `packages/`
  imports through `scripts/lib/deno`; `packages/hamownia/tasks.ts` now imports
  `XrpcClient` from the workspace `@garazyk/gruszka` package. The package-local
  Hamownia check and 328-test suite pass. This is the permitted preparatory
  rewrite, not a released-package boundary.
- The external package manifests now provide dedicated `fmt`, `lint`, `check`,
  and `test` task sets. A 2026-07-18 read-only R2 audit verified all four for
  `@garazyk/tui@0.1.0` (252 tests), Gruszka (304 passed, 6 intended integration
  skips), Laweta (85 passed), and Schemat (188 passed). Hamownia's package test
  task originally had 14 failures because `test_utils.ts` assumed the
  monorepo-relative `packages/hamownia/cli.ts` path. **Fixed 2026-07-26 in the
  external repo** (`garazyk-atproto-testing` commit `533262b`): `CLI_PATH` is
  now resolved via `fromFileUrl(import.meta.url)` instead of a hardcoded
  relative path, so it works regardless of where the package is checked out.
  Re-verified 2026-07-27: `deno task test` in
  `garazyk-atproto-testing/packages/hamownia` passes 328/328 (0 failed, 1
  ignored). The same commit also fixed a related Gruszka test
  (`generateLexicons` default-output test now skips gracefully when
  `Garazyk/Resources/lexicons` isn't available in an external checkout);
  Gruszka now passes 321/321 there. Gruszka, Laweta, Schemat, and Hamownia also inherit
  their dependency mappings from the testing repository root, so their release
  manifests are not yet self-contained.
- **2026-07-18:** private GitHub remotes are established and initial local
  `main` histories are pushed: `jvalinsky/garazyk-tui` and
  `jvalinsky/garazyk-atproto-testing`. The local branches track `origin/main`.
  `@garazyk/tui@0.1.0` is the first verified release candidate, but its JSR
  publication is **indefinitely deferred by maintainer decision** (2026-07-18,
  reaffirmed explicitly on 2026-08-08). Do not request or use publisher access,
  or publish this or any later package, until the maintainer gives explicit
  permission in a future message and reopens Phase 5.
  This deferral blocks R2 (publication boundaries), R3 (wrapper removal), and
  R4 (deletion branch regeneration). R1 source synchronization is not blocked
  and completed on 2026-08-08; one runtime compatibility check remains.

## R1. Synchronize forward — source sync complete; runtime gate pending

Treat current `main` as the source for code added after extraction. Port each
external-repo difference with history-aware commits. Resolve configuration
differences explicitly; do not copy `deno.json` wholesale.

**Not blocked** on the publication deferral — can proceed independently.

Run in each destination:

```bash
deno task fmt --check
deno task lint
deno task check
deno task test
```

For ATProto testing, also run scenario discovery, dashboard build, dashboard TUI
capture smoke, and one no-setup compatibility check.

The first three passed on 2026-08-08. The no-setup runtime check was not run:
no local services were active, and a bounded binary-network start stopped
because the shared build lacks `build/bin/syrena`. Docker images for the full
local topology are not present, and pulling/building them with 9.5 GB free would
violate the disk-headroom constraint. R1 remains open only for that named
runtime check; this does not reopen package publication.

### Blocked on (2026-08-12 recheck)

**Named input:** ≥~15 GB free on the host volume used for Docker image pulls /
binary topology, plus a built `build/bin/syrena` (or staged Linux ELF). Until
disk headroom clears, do not invent alternate "complete" evidence paths.

## R2. Establish publication boundaries

1. Configure remotes and repository ownership.
2. Give each package `fmt`, `lint`, `check`, and `test` tasks.
3. Publish `@garazyk/tui` first, including `runtime` and `testing` exports.
4. Update ATProto testing to use the released TUI version.
5. Publish Gruszka, Laweta, Schemat, and Hamownia alpha versions.
6. Pin exact prerelease versions in Garazyk before deleting workspace packages.

Git paths are acceptable only on an explicit, expiring prerelease branch.

## R3. Remove wrapper dependencies

**Preparatory rewrite complete (2026-07-25).** Scenario and package source no
longer use the wrapper path; the final package-name imports still require
released packages, which the maintainer has explicitly deferred. Delete wrappers
only after publication and the full scenario and dashboard checks pass. Keep
`scripts/run_scenarios.ts` as a thin compatibility launcher for one deprecation
window.

Move dashboard-coupled MCP TUI tooling with ATProto testing. Keep generic PTY
capture tooling where its dependency direction is clean; record the owner in an
ADR if it remains shared.

## R4. Regenerate the deletion branch

After R1-R3 pass, recreate the deletion on current `main`. The old branch is a
change manifest, not a merge candidate.

Garazyk exit gate:

- Objective-C full suite passes;
- boundary checks pass;
- launcher `--list` smoke succeeds through released Hamownia;
- no workspace references point at removed packages;
- rollback can restore one pinned package version without restoring deleted
  source.

## Rollback

Keep the last in-tree commit tagged until two released package versions have
passed CI. If a package release fails, pin the previous version. If the launcher
contract fails, restore only the thin wrapper, not the full package sources.
