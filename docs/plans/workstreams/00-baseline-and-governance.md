---
title: Baseline and Plan Governance
status: active
last_verified: 2026-07-17
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
   *Evidence (2026-07-17, commit 703723c4cc36033cb02887981982c457a878b39c):*
   - `deno run -A scripts/scenario-dashboard/browser_smoke_test.ts` — passed.
     Dashboard controls, mutation-capability enforcement, security headers,
     scenario navigation, and keyboard tab order verified.
   - `deno run -A scripts/admin_ui_browser_smoke_test.ts` — passed.
     Admin CSP (`script-src-attr 'none'`), hostile-identifier inertness,
     session/CSRF mutation guard, keyboard tab order, and OAuth consent
     rendering verified. A known intermittent PDS DPoP verification issue
     was observed and recorded as a warning; it does not regress the
     baseline and is tracked for workstream 01 follow-up.
   - Global gate triage (2026-07-17):
     - `deno task check` — passed.
     - `deno task lint` — 2043 pre-existing lint issues across `packages/`;
       unrelated to this baseline.
     - `deno task test` — 6 failures in
       `packages/gruszka/scripts/generate_test.ts` when run as part of the
       full suite. *Resolved 2026-07-16:* the failures were checked-in
       `lexicons.ts` artifact drift, not test isolation; the regeneration in
       `ad2bd39f1` fixed them. A full `deno task test` run on 2026-07-16
       passes clean (7284 passed, 0 failed, 6 ignored), and regenerating via
       `deno task generate-client` produces zero diff.
6. WASM smoke, notebook, and runtime-gap probes if a current kernel artifact can
   be built reproducibly.

Store large run output as CI artifacts or ignored reports. Keep only the dated
summary and command line in source control.

## B0.3 Reconcile branches

### Deno split branch (sync complete, deletion still pending)

`codex/split-deno-testing-repos` (tip `307e8764b`) removes more than 100,000
lines after copying them to two clean local repositories. As of 2026-07-15,
both `garazyk-atproto-testing` and `garazyk-tui` are synchronized with
`main`'s in-tree copies (see mega-plan Phase 0 item 3). The branch itself is
still a stale June 7 snapshot two commits ahead of nothing useful past that
point — it has not been rebased onto current `main` and still deletes files
`main` has since kept changing. Do not merge the old deletion commit as-is;
regenerating the deletion diff from current `main` is Phase 3 item 1 work,
gated on the released-package-version boundary the mega plan describes there.
Until then this branch is inactive, not abandoned.

### Objective-C modernization branch (code superseded, docs retained)

`refactor/plan01-hygiene-quick-wins` (tip `fdbd2dd42`) contained three hygiene
commits (raw logging, `@synthesize`, `#pragma mark` cleanup) stacked on the
Deno split branch. Those three are now cherry-picked onto `main` as
`5d048eb53`, `2f88fad66`, and `6511b4502` (code only). The branch is superseded
for that code and should not be merged as-is. Its remaining unique content —
`plan/objc-modernization-2026-07/*` and `docs/tui/asciinema-overlay/*` — was
deliberately left off `main` during the cherry-pick (unrelated to hygiene, and
`plan/` duplicates the governed `docs/plans/` structure). Keep the branch
around as reference input for Phase 4 item 3 (Objective-C god-file
decomposition); do not delete it without folding anything still useful into
`docs/plans/` first.

### Pre-rewrite backup branch (archival, do not merge)

`backup-pre-rewrite` (tip `fe63ac13a`) is the safety snapshot taken before the
network-rework history rewrite that stripped the transient `RateLimiter DEBUG`
logging commit (see QueryRunner/PLC entry below). All 12 of its other commits
have since landed on `main` in reworked form, and `main` has progressed 22
commits past this branch's tip. It has no unique content worth recovering —
keep it only as an archival record of the pre-rewrite state, not as a merge
candidate.

### QueryRunner/PLC work (complete)

The QueryRunner store migrations have all landed on `main`, including the
`PLCPersistentStore` + `PLCReplicaStore` migration, its schema-atomicity
closeout, and the `RateLimiter` migration (see the mega plan current state and
deciduous goal 1187, completed, with its commit-linked actions). The transient
debug logging that shipped with the network rework was removed by rewriting the
introducing commit, so `main` history carries no `RateLimiter DEBUG` lines. The
arc is finished; the implementation diary
(`queryrunner_deepening_pilot_plan.md`) was deleted on 2026-07-16 per the
plan-lifecycle rule (Git retains its text at `6f8921ab6`).

## B0.4 Replace false-confidence tests

`SecurityHardeningTests` includes empty import/export inputs and an
unconditional success assertion for SQL allowlisting. Replace them with tampered
CAR, bounded export, blob header, and rejected identifier fixtures. Preserve the
current production safeguards while making regression claims executable.

**Status (2026-07-14):** complete. Deterministic DPoP, SQL-allowlist,
refresh-token, import, and CAR coverage landed (`6d8ebe97b`, plus the
`NetworkSecurityHardeningTests` registration in `6cf9ed1c8` and the
`TestKeyFixtures` dedupe in `50624140f`). A fresh build from HEAD runs all 9
`NetworkSecurityHardeningTests` with 0 failures: `testImportTamperRejection`
sends real corrupted CAR bytes and asserts a CAR-parse 400 (not the empty-body
guard); `testSyncExportBound` asserts 404 RepoNotFound for a valid-but-unknown DID;
`testBlobHeaderMIME` asserts the stored MIME plus `X-Content-Type-Options: nosniff`;
`testSQLAllowlist` rejects injection/path-traversal DIDs. No placeholder
`XCTAssertTrue(YES)` or empty-input assertions remain (deciduous node 1199 closed).

## B0.5 Govern plan state

- This directory owns active planning.
- Deciduous nodes own decision and outcome history.
- ADRs own durable design choices.
- Scratchpads may hold evidence but cannot claim active priority.
- Each completed workstream updates the mega plan and retires its task detail in
  the same change.

Exit criteria:

- no active plan outside `docs/plans/`;
- documentation indexes and links pass;
- decisuous node 1153 links this plan and its completion outcome.
