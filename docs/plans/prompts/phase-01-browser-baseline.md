---
phase: 1
title: Browser smoke baseline
status: complete
agent: claude
depends_on: []
completed_at: 2026-07-17T00:09:21Z
commit: 703723c4cc36033cb02887981982c457a878b39c
---

# Phase 1: Browser smoke baseline

## Mission

Write and run the real-browser smoke that closes mega-plan Phase 0 item 1 —
the only open Phase 0 gap. Cover: scenario-dashboard process controls, Admin
UI CSP/CSRF enforcement, OAuth consent flow, and keyboard workflows.

## Read first

- `docs/plans/workstreams/00-baseline-and-governance.md` (B0.2 item 5)
- `docs/plans/workstreams/04-web-and-admin-ui.md` (U1-U3 describe the
  protections the smoke must prove; U4 keyboard expectations)
- `docs/plans/mega-plan.md` current-state notes: both prior environment
  blockers are cleared — OpenSSL detection fixed by reconfigure (2026-07-13),
  Playwright Chromium installed (2026-07-15).

## Before writing anything

Check the worktree: `scripts/scenario-dashboard/browser_smoke_test.ts` and
`scripts/scenario-dashboard/test-results/` were observed untracked on
2026-07-16 — another session may have started this work. Reconcile with and
extend what exists; do not clobber it.

## Scope

1. Playwright (via `deno run -A npm:playwright`) smoke against a locally
   launched scenario dashboard and AdminUIServer.
2. Assert: mutation routes reject missing/wrong capability; Host/Origin
   validation; Admin CSP blocks inline script attributes (hostile
   identifiers rendered inert); CSRF required on POST mutations; OAuth
   consent renders and moves focus; core keyboard workflows function.
3. Record a dated baseline summary (commit + date + command) per B0.2;
   large output goes to ignored/CI-artifact paths.

Out of scope: fixing accessibility findings (workstream 04 U4-U5 owns
those — file them as evidence), any dashboard/Admin feature work.

## Acceptance gate

- Smoke runs green from a clean checkout with one documented command.
- Mega plan Phase 0 item 1 flipped to complete with evidence; Phase 0 exit
  gate re-evaluated.
- Global gates pass (`deno task check/lint/test`; AllTests if any ObjC
  changed — none should).

## Completed

- Dashboard smoke: `deno run -A scripts/scenario-dashboard/browser_smoke_test.ts` passed.
- Admin UI smoke: `deno run -A scripts/admin_ui_browser_smoke_test.ts` passed.
- Evidence recorded in workstream 00 B0.2 item 5 and mega-plan Phase 0 item 1.
- Pre-existing `deno task lint` issues in `packages/` are unrelated to this
  baseline. The `deno task test` failures observed at the time (gruszka
  `generate_test.ts`) were `lexicons.ts` artifact drift, fixed by the
  `ad2bd39f1` regeneration; the full suite passes clean as of 2026-07-16
  (workstream 00 B0.2 item 5).

## On completion

Update mega-plan current state + Phase 0, workstream 00 B0.2; set
`status: complete` here.
