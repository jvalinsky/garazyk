---
phase: 5
title: Repository boundary completion
status: pending
agent: claude
depends_on: []
---

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
