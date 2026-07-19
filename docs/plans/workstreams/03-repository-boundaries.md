---
title: Repository Boundaries
status: active
last_verified: 2026-07-18
---

# Repository Boundaries

## Target

Garazyk remains the Objective-C server repository. Reusable TUI code lives in
`garazyk-tui`; ATProto test orchestration, scenarios, topology fixtures, and the
scenario dashboard live in `garazyk-atproto-testing`. Versioned JSR packages
form the dependency boundary.

## Current evidence

- Both external repositories exist and have clean worktrees dated 2026-06-07.
- The old split branch contains the in-tree deletion and compatibility cleanup.
- Current `main` differs from the external copies in Gruszka, Hamownia, Laweta,
  Schemat, and TUI.
- All 92 scenario files still import through `scripts/lib/deno` wrappers.
- `packages/hamownia/tasks.ts` still imports the wrapper client.
- The external package manifests now provide dedicated `fmt`, `lint`, `check`,
  and `test` task sets. A 2026-07-18 read-only R2 audit verified all four for
  `@garazyk/tui@0.1.0` (252 tests), Gruszka (304 passed, 6 intended integration
  skips), Laweta (85 passed), and Schemat (188 passed). Hamownia's package test
  task has 14 failures because `test_utils.ts` assumes the monorepo-relative
  `packages/hamownia/cli.ts` path; it needs a package-local fixture before its
  later alpha publication. Gruszka, Laweta, Schemat, and Hamownia also inherit
  their dependency mappings from the testing repository root, so their release
  manifests are not yet self-contained.
- **2026-07-18:** private GitHub remotes are established and initial local
  `main` histories are pushed: `jvalinsky/garazyk-tui` and
  `jvalinsky/garazyk-atproto-testing`. The local branches track `origin/main`.
  `@garazyk/tui@0.1.0` is the first verified release candidate, but its JSR
  publication is indefinitely deferred by maintainer decision (2026-07-18).
  Do not request or use publisher access, or publish this or any later package,
  until the maintainer explicitly reopens Phase 5.

## R1. Synchronize forward

Treat current `main` as the source for code added after extraction. Port each
external-repo difference with history-aware commits. Resolve configuration
differences explicitly; do not copy `deno.json` wholesale.

Run in each destination:

```bash
deno task fmt --check
deno task lint
deno task check
deno task test
```

For ATProto testing, also run scenario discovery, dashboard build, dashboard TUI
capture smoke, and one no-setup compatibility check.

## R2. Establish publication boundaries

1. Configure remotes and repository ownership.
2. Give each package `fmt`, `lint`, `check`, and `test` tasks.
3. Publish `@garazyk/tui` first, including `runtime` and `testing` exports.
4. Update ATProto testing to use the released TUI version.
5. Publish Gruszka, Laweta, Schemat, and Hamownia alpha versions.
6. Pin exact prerelease versions in Garazyk before deleting workspace packages.

Git paths are acceptable only on an explicit, expiring prerelease branch.

## R3. Remove wrapper dependencies

Rewrite scenario imports to package names and fix the Hamownia back-reference.
Delete wrappers only after the full scenario and dashboard checks pass. Keep
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
