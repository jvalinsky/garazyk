---
title: Baseline and Plan Governance
status: active
last_verified: 2026-07-14
---

# Baseline and Plan Governance

## Purpose

Build a trustworthy baseline before importing claims from old plans or merging
old branches.

## B0.1 Repair audit tooling

Current architecture scanner results undercount services and tests because the
scripts look for `Garazyk/Sources/App/Services` and `Tests` instead of
`Garazyk/Sources/Services` and `Garazyk/Tests`. Fix those roots and add a smoke
fixture that asserts nonzero service and test counts.

Generated scan hits remain leads. For example, the SQLite scan treats files
using `PDS_SQLITE_AUTORELEASE_STMT` as missing finalization.

Verification:

- scanner discovers `Garazyk/Sources/Services` and `Garazyk/Tests`;
- a known fixture appears in each report;
- generated reports stay outside the source tree or in an ignored directory.

Rollback: revert only scanner changes. No product code depends on them.

## B0.2 Establish current baselines

Capture these results with commit and date:

1. Objective-C targeted and full suites.
2. Deno format, lint, check, unit tests, and boundary checks.
3. XRPC default and expanded inventories, with duplicates enforced.
4. `hamownia agent list` plus a current compatible scenario run. Do not promote
   May 2026 failure counts into backlog.
5. Browser smoke for dashboard controls, Admin CSP/CSRF, OAuth consent, and
   keyboard workflows.
6. WASM smoke, notebook, and runtime-gap probes if a current kernel artifact can
   be built reproducibly.

Store large run output as CI artifacts or ignored reports. Keep only the dated
summary and command line in source control.

## B0.3 Reconcile branches

### Deno split branch

`codex/split-deno-testing-repos` removes more than 100,000 lines after copying
them to two clean local repositories. Since June, in-tree Gruszka, Hamownia,
Laweta, Schemat, and TUI files changed. Synchronize those changes into the
external repositories first, then regenerate the deletion diff from current
`main`. Do not merge the old deletion commit as-is.

### Objective-C modernization branch

`refactor/plan01-hygiene-quick-wins` contains commits for raw logging,
`@synthesize`, and `#pragma mark` cleanup, but inherits the Deno split branch.
Cherry-pick or rebase only the three hygiene commits after checking them against
current files. Keep the plan findings as audit input; the mega plan owns the
remaining schedule.

### QueryRunner/PLC work (complete)

The QueryRunner store migrations have all landed on `main`, including the
`PLCPersistentStore` + `PLCReplicaStore` migration, its schema-atomicity
closeout, and the `RateLimiter` migration (see the mega plan current state and
deciduous goal 1187, completed, with its commit-linked actions). The transient
debug logging that shipped with the network rework was removed by rewriting the
introducing commit, so `main` history carries no `RateLimiter DEBUG` lines. The
arc is finished; the implementation diary
(`queryrunner_deepening_pilot_plan.md`) has no outstanding outcomes and can be
deleted per the plan-lifecycle rule (Git retains its text).

## B0.4 Replace false-confidence tests

`SecurityHardeningTests` includes empty import/export inputs and an
unconditional success assertion for SQL allowlisting. Replace them with tampered
CAR, bounded export, blob header, and rejected identifier fixtures. Preserve the
current production safeguards while making regression claims executable.

**Status (2026-07-14):** in progress. Deterministic DPoP, SQL-allowlist,
refresh-token, import, and CAR coverage has landed (`6d8ebe97b`, plus the
`NetworkSecurityHardeningTests` registration in `6cf9ed1c8`). Remaining
negative-path and fixture work is active in the uncommitted `SecurityHardeningTests`
/ `OAuth2HandlerTests` / `TestKeyFixtures` / `LexiconResolveXrpcTests` working set
(deciduous node 1199).

## B0.5 Govern plan state

- This directory owns active planning.
- Deciduous nodes own decision and outcome history.
- ADRs own durable design choices.
- Scratchpads may hold evidence but cannot claim active priority.
- Each completed workstream updates the mega plan and retires its task detail in
  the same change.

Exit criteria:

- no active plan outside `docs/plans/` except the explicitly preserved dirty
  QueryRunner diary;
- documentation indexes and links pass;
- decisuous node 1153 links this plan and its completion outcome.
