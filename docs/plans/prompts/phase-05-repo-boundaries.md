---
phase: 5
title: Repository boundary completion
status: blocked
agent: worker
depends_on: []
last_updated: 2026-07-18
---

## Progress

Started 2026-07-18: audit the two external repositories, their package task
surfaces, and remotes to prepare an evidence-backed R1/R2 handoff. This slice
is read-only and will stop at the declared remote/ownership checkpoint.

2026-07-18 R2 publication audit (read-only): `@garazyk/tui@0.1.0` has the
required root, `runtime`, and `testing` exports and its `fmt --check`, lint,
check, and test tasks pass (252 tests). Gruszka (304 passed, 6 intentional
integration skips), Laweta (85 passed), and Schemat (188 passed) also pass
their four package tasks. Hamownia's package-local test task fails (295
passed, 14 failed, 1 ignored) because `test_utils.ts` hard-codes the
repository-root-relative `packages/hamownia/cli.ts` path. The later ATProto
packages also still rely on the workspace import map instead of self-contained
published dependencies; those are follow-up work after the first TUI release.

2026-07-18 operator decision: defer the `@garazyk/tui` publication
indefinitely. Do not request or use JSR publisher access, and do not run a
publish command, unless the maintainer explicitly reopens this phase.

## Blocked on

An explicit maintainer decision to lift the indefinite publication deferral and
reopen Phase 5. Until then, do not request or use JSR publisher access and do
not publish `@garazyk/tui` or any later `@garazyk` package.

## Deferred publication record

The verified but deferred first publication would be `@garazyk/tui@0.1.0` from
the following command:

```bash
cd /Users/jack/Software/garazyk-tui
deno publish
```

The package contains the files declared by its `deno.json` publish include
list (`README.md`, `LICENSE`, `deno.json`, root TypeScript files, and
`testing/**/*.ts`/`testing/**/*.json`) and exports `.`, `./runtime`,
`./testing`, and `./testing/world_schema.json`. No publish command has been
run, and none will run while this deferral is in effect.

## Prior checkpoints

### Checkpoint resolved (2026-07-18)

Owner `jvalinsky` authorized creation of both repositories as **private**,
their `origin` remotes, and initial pushes. Package publication remains a
separate approval.

### Remote setup evidence (2026-07-18)

Created and pushed private `origin/main` repositories:

- `https://github.com/jvalinsky/garazyk-tui`
- `https://github.com/jvalinsky/garazyk-atproto-testing`

# Phase 5: Repository boundary completion

## Mission

Finish the two-repository Deno extraction with released package versions as
the boundary (workstream 03, R1-R4), then regenerate the in-tree deletion on
current `main`. This phase contains hard human checkpoints — expect to pause.

## Read first

- `docs/plans/workstreams/03-repository-boundaries.md` (authoritative)
- `docs/plans/workstreams/00-baseline-and-governance.md` (B0.3 branch
  disposition: the old deletion branch is a change manifest, never a merge)
- External repos: `/Users/jack/Software/garazyk-atproto-testing` and
  `/Users/jack/Software/garazyk-tui`, both synchronized with `main` as of
  2026-07-15

## Scope

1. **R2 publication boundaries**: per-package `fmt/lint/check/test` tasks;
   publish `@garazyk/tui` first (with `runtime`/`testing` exports), then
   Gruszka, Laweta, Schemat, Hamownia alphas; pin exact prerelease versions
   in Garazyk.
2. **R3 wrapper removal**: rewrite all 92 scenario imports off
   `scripts/lib/deno`, fix the `packages/hamownia/tasks.ts` back-reference,
   keep `scripts/run_scenarios.ts` as a thin launcher for one deprecation
   window.
3. **R4 deletion regeneration**: recreate the deletion diff from current
   `main` (do not rebase/merge `codex/split-deno-testing-repos`), tag the
   last in-tree commit, land behind the exit gate.

## Human checkpoints (set status: blocked and stop at each)

- **Remote/ownership setup**: creating GitHub repos/remotes and JSR scopes
  requires account decisions and credentials — present the exact commands
  and wait.
- **Each package publish**: publishing is externally visible — present the
  version/contents diff and wait for approval per publish.
- **The deletion commit**: >100k lines removed — present the regenerated
  manifest summary and wait before committing.

## Acceptance gate (from workstream 03)

- All three repositories pass format/lint/check/test.
- Launcher `--list` smoke succeeds through released Hamownia.
- No workspace references to removed packages; rollback path is a version
  pin, not source restoration.
- Objective-C full suite green.

## On completion

Update workstream 03, mega-plan Phase 3 items 1-2, branch disposition in
workstream 00 B0.3; set `status: complete` here.
