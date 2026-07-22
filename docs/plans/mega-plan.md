---
title: Garazyk Mega Plan
status: active
last_verified: 2026-07-22
---

# Garazyk Mega Plan

## Objective

Deliver a production-ready AT Protocol stack in Objective-C: conformant with
every published specification (workstream 01 S6 owns the conformance matrix),
supporting experimental Proposal 0016 permissioned spaces behind its operator
flag, secure, portable to GNUstep/Linux, and easier to change while the
repository boundaries settle. This roadmap replaces the May 2026 scenario,
documentation, TUI, package, and refactor plans.

## Current state

- `main` contains 1,922 tracked files under `Garazyk/`, 234 under `packages/`,
  931 under `scripts/`, and 127 under `objc-jupyter-wasm/`.
- `deno task check` passes for all six in-tree packages as of 2026-07-12.
- `hamownia agent list` discovers 92 scenarios. A current Docker-backed run of
  scenario `01` passed 11 steps on 2026-07-12; the checked-in May matrix still
  cannot establish a current failure backlog.
- The strict XRPC coverage command now passes after removing same-pack graph
  duplicates and the unspecced labeler owner. A complete registry rebuild also
  replaces a prior application's handler set on a reused dispatcher, while
  individual duplicate registrations still fail. The existing percentage still
  measures name presence, not schema or behavior.
- The architecture audit now scans the live `Garazyk/Sources/Services` and
  `Garazyk/Tests` roots. Its smoke test finds 14 service implementations and
  339 Objective-C test files.
- The scenario dashboard now defaults to `127.0.0.1` and protects mutations
  with a per-launch capability, Host/Origin validation, and remote bearer
  authentication. AdminUIServer now rejects inline script attributes and
  enforces session-plus-CSRF checks on its POST mutations. Targeted tests pass.
  The "missing local OpenSSL dylib" that blocked a real Admin browser smoke was
  a stale `build/` CMake cache from before Homebrew's `openssl@3` was
  discoverable; a reconfigure on 2026-07-13 already fixed it
  (`testNonKeychainFactoryPersistenceWhenOpenSSLAvailable` passes, not
  skipped), the docs just never caught up. Playwright's Chromium binary was
  separately never installed (`deno run -A npm:playwright install chromium`,
  done 2026-07-15). Both blockers are cleared, and the browser smoke tests
  are now written and passing (`scripts/admin_ui_browser_smoke_test.ts`,
  `scripts/scenario-dashboard/browser_smoke_test.ts`; run 2026-07-17, see
  workstream 00 B0.2 item 5).
- `HttpConnectionIOCoordinator` now has independent 30-second idle and
  aggregate header deadlines. The aggregate deadline starts with the first
  header byte, cannot be extended by trickle input, cancels a stalled receive,
  and stops at the actual header terminator rather than a valid slow body.
- Lexicon generation now has one package-owned core rooted at
  `Garazyk/Resources/lexicons`. It fails before overwriting output when the
  inventory or endpoint set is empty; its checked-in TypeScript artifact covers
  519 lexicons and 392 endpoints deterministically. The Phase 3 Objective-C
  NSID follow-up has since landed: the generator (`f46ab5fb8`,
  `scripts/generate_nsid_constants.ts`) and the full call-site adoption sweep
  with a CI drift check (`e212288bd`). Only the raw-literal lint remains
  (phase-06 prompt).
- `AppViewDatabase` now records ordered schema versions and applies pending
  migrations atomically. File-backed legacy fixtures prove reopen/data/index
  preservation, and all 68 injected statement-failure positions roll back
  schema and version state. A production database backup remains required
  before this schema bump is deployed.
- The Deno split exists in clean local repositories at
  `/Users/jack/Software/garazyk-atproto-testing` and
  `/Users/jack/Software/garazyk-tui`, plus branch
  `codex/split-deno-testing-repos`. Both external repos are now synchronized
  with `main`'s in-tree copies as of 2026-07-15; the old deletion branch is
  still based on a stale June 7 snapshot and needs its own rebase (Phase 3
  item 1) before it can merge.
- The three Objective-C hygiene commits from `refactor/plan01-hygiene-quick-wins`
  are cherry-picked onto `main` (`5d048eb53`, `2f88fad66`, `6511b4502`),
  code-only. `refactor/plan01-hygiene-quick-wins` itself is still based on the
  Deno split and superseded for these three commits; its remaining content is
  the modernization plan docs, which were deliberately left off `main` (see
  Phase 0 item 4).
- The QueryRunner deepening arc is complete and retired: all stranded stores
  (`ATProtoMediaSQLiteStore`, Mikrus, Beskid, `JelczDatabase`, `PDSReplayCache`,
  `PDSSQLiteSessionStorage`, `PLCPersistentStore`/`PLCReplicaStore`,
  `RateLimiter`) run on `ATProtoConnectionManagerSerial` +
  `ATProtoDatabaseQueryRunner`, schema paths are atomic and rollback-tested,
  and every slice passed AllTests. The implementation diary
  (`queryrunner_deepening_pilot_plan.md`) is deleted per the plan-lifecycle
  rule; Git history and deciduous goal 1187 retain the record.
- Proposal 0016 permissioned spaces landed (`da296909f`, ADR 0004): isolated
  SQLite storage, fail-closed URI/scope/credential parsing, delegation,
  membership policy, private blobs, and notification fan-out, all behind
  `permissionedSpacesEnabled` (off by default). The ADR 0005 reconciliation
  protocol is fully implemented in source — CAR multi-root reading, full-CAR
  import, lightweight record-diff recovery, incremental ops, oplog pruning
  with a background timer, and `listRecords`/`listRepoOps` cursor fixes —
  with space test suites registered and green. Scenarios 93 and 94 plus PDS3
  topology config exist (`cc063779a`). Scenario 93 now passes 19/19; the two
  OAuth defects are fixed and Scenario 94's exact consent form is
  regression-covered (`9000097ba`). Scenario 94 now passes 25/25 in structured
  run `2026-07-18t2204z-20523`; the prior AppView failure was a transient
  external port collision. Private-blob acceptance now passes in scenario 93
  (21/21, `21eeb5719`). Phase 2 is now complete: scenario 94 passes 28/28
  (`2026-07-18t2238z-90828`) and observes incremental, lightweight, and full
  CAR recovery through a triple-gated, production-excluded test pack
  (`43b3ad9c3`; workstream 06).
- The 29 gated `AllTests` classes are folded back into CI (Phase 2 item 4,
  first slice of Phase 4/workstream 01 S5): the 2026-07-16 baseline of 76
  failures across 11 classes is repaired (per-class root causes in
  workstream 01 S5), a full `AllTests --gated=run` pass on 2026-07-17 is
  green (3455 tests, 0 failures, re-confirmed 2026-07-17), and
  `ctest`/`scripts/test/run-tests.sh`/`run-asan-tests.sh` all run with
  `--gated=run` again. Phase 4 has since fully closed: deterministic
  firehose backpressure and adversarial ingress landed (scenarios 33/95),
  gap-free cursor resume is proven live (scenario 96, `6387245a8`, with
  the `closeForUpgrade` handoff fix `80f5a56e6`), and the once-missing
  downstream account-status propagation is now implemented — admin
  takedown/reinstate emit real `#account` events, RelayClient/
  RelayUpstreamManager forward them, AppViewIngestEngine persists them
  (`28641e671`, `a3f8d3c53`), proven E2E by scenario 97 (`7bde0e0b6`).
  Scenarios 93-97 all exist beyond the original 92 discovered in May.
  Evidence in workstream 01 S5. A later regression (discovered 2026-07-19,
  12 suites/~68 failures, unrelated to phase 8's own changes) is now fully
  root-caused and repaired (2026-07-22): stale/mismatched test fixtures
  across seven suites, plus three real product bugs found along the
  way — `PDSAdminService.createLabel:` could insert a NOT NULL `cts`
  column as null via the real API path, AppView's `groups`/`group_members`
  schema didn't match what `AppViewGroupIndexer.m` actually writes (making
  `chat.bsky.group.definition` indexing entirely non-functional), and
  `PDSSequencerAnalyticsCollector.startCollecting` raced its own queue.
  Full detail and one still-open protocol-compliance question (a P-256
  low-S interop fixture now contradicting ADR 0007) in workstream 01 S5.
- Workstream 07 (storage and MST optimization) is underway: O1 landed
  (`3be4ee1ab` — `INSERT OR IGNORE` for `ipld_blocks`, plus 15 more
  `INSERT OR REPLACE` → `ON CONFLICT DO UPDATE` conversions, six missing
  indexes, and standardized PRAGMAs) and O2 phases A/B landed
  (`fc1705696` actor store V3 `record_tombstones`; `50f2482c2` +
  FK-restoration fix `2f7ba5bdb` service V14 moderation tables), both
  merged to `main`. O2 phases C/D (chat, space store), O4 (the evidence-backed
  actor V5 `records(rev)` covering index), and O3 are complete. The production
  MST path starts root-only and its 256-entry lazy subtree cache has a 10K
  profile proving 7 path loads versus 2,507 eager loads; CAR/STAR fixtures are
  byte-identical. O5 is complete: resolver TTLs are enforced and AppView
  `#identity` events invalidate the shared DID cache. O6 is implemented under
  accepted ADR 0008: a durable, leased SQLite ingest/index queue with atomic
  acknowledgement, recovery, and watermarked backpressure. A deterministic
  SIGSEGV found in the O6 drain worker after the initial checkpoint (an
  `@autoreleasepool` draining before the caller could safely read a written
  out-parameter — see workstream 07 O6) is root-caused and fixed; a full
  `AllTests --gated=run` and an AddressSanitizer run are both clean.
  Workstream global gates remain open only on the repository-wide lint
  baseline before Phase 11 can close. A dedicated skill exists at
  `.agents/skills/sqlite-performance-optimization`.

## Priority model

Each dimension uses 1 to 5. Higher boundary risk means greater operational or
contract exposure. Higher change safety means the item can ship in smaller,
better-isolated steps.

| Candidate                                     | Boundary risk | Structural drag | Test leverage | Change safety | Payoff | Priority        |
| --------------------------------------------- | ------------: | --------------: | ------------: | ------------: | -----: | --------------- |
| Dashboard and Admin mutation security         |             5 |               4 |             5 |             4 |      5 | P0              |
| XRPC ownership and truthful contract coverage |             5 |               4 |             5 |             4 |      5 | P0              |
| Absolute HTTP header/read deadlines           |             5 |               3 |             5 |             4 |      5 | P0              |
| Lexicon generator consolidation               |             5 |               4 |             5 |             4 |      5 | P0              |
| Permissioned spaces multi-PDS acceptance      |             5 |               2 |             5 |             5 |      5 | P1              |
| AppView numbered, atomic migrations           |             5 |               5 |             5 |             3 |      5 | P1              |
| OAuth Permissions spec (granular scopes)      |             4 |               3 |             4 |             3 |      4 | P1              |
| Replace false-confidence security tests       |             4 |               3 |             5 |             5 |      5 | P1              |
| PLC schema-upgrade atomicity                  |             4 |               4 |             5 |             3 |      4 | P1              |
| Deno repository-boundary completion           |             4 |               5 |             5 |             2 |      5 | P1              |
| Relay product decision and assembly           |             4 |               5 |             4 |             2 |      5 | Decided (ADR 0006) |
| Admin UI structural and accessibility work    |             4 |               5 |             4 |             3 |      4 | P1              |
| Spec conformance matrix (S6)                  |             3 |               2 |             5 |             5 |      4 | P2              |
| Incremental public sync                       |             4 |               4 |             4 |             2 |      5 | P2              |
| Dedicated space signing key rotation          |             4 |               2 |             3 |             3 |      4 | P2              |
| Space operational readiness (backup, metrics) |             3 |               2 |             3 |             4 |      3 | P2              |
| Storage and MST optimization (workstream 07)  |             3 |               3 |             4 |             4 |      4 | P1              |
| Objective-C god-file decomposition            |             3 |               5 |             4 |             2 |      4 | P2              |
| Generated NSID constants                      |             2 |               4 |             5 |             4 |      4 | P2              |
| WASM runtime gap closure                      |             2 |               4 |             4 |             3 |      3 | P2              |
| SMTP, cloud blob, and STAR completion         |             3 |               3 |             3 |             2 |      3 | Blocked: operator decision |
| Space app attestation (`appAccess#allowList`)  |             4 |               2 |             3 |             2 |      3 | Decided (ADR 0004 amendment) |

## Dependency order

```mermaid
flowchart TD
    B["Phase 0: prove baseline and reconcile ownership"]
    S["Phase 1: contain exposed security and resource risks"]
    P["Phase 2: repair protocol and persistence contracts"]
    R["Phase 3: finish repository and generated-code boundaries"]
    A["Phase 4: structural refactors and scale work"]
    D["Phase 5: product decisions and deferred runtimes"]
    B --> S --> P --> R --> A --> D
```

### Phase 0: baseline and ownership

Complete [workstream 00](workstreams/00-baseline-and-governance.md).

1. **Complete:** fix audit scanner roots and establish current Objective-C,
   Deno, browser, XRPC, and scenario baselines. The scanner and current
   scenario discovery/run are proven; the browser baseline is now complete.
   Both environment blockers that previously stopped this (stale OpenSSL
   detection in `build/`, missing Playwright Chromium binary) are cleared as
   of 2026-07-15 — see the current-state note above. Browser smoke tests for
   dashboard controls, Admin CSP/CSRF, OAuth consent, and keyboard workflows
   passed on 2026-07-17 (commit 703723c4cc36033cb02887981982c457a878b39c);
   see workstream 00 B0.2 item 5 for commands and evidence.
2. **Complete:** resolve duplicate XRPC ownership so the existing strict CI
   check is green.
3. **Complete:** synchronize the two external Deno repositories with newer
   in-tree changes. `garazyk-atproto-testing` picked up the real drift on
   `main` since the June 7 split (gruszka lexicon/DNS-timeout fixes, hamownia
   test quieting) and dropped `packages/gruszka/scripts/generate.ts` +
   `generate_test.ts`, which can no longer regenerate standalone now that
   lexicon generation is rooted at the monorepo-only `Garazyk/Resources/lexicons`;
   the repo is a pure vendored consumer of `lexicons.ts` going forward, verified
   clean (`check`/`lint`/`fmt`, 3790 tests). `garazyk-tui` needed no changes —
   zero real commits touched `packages/tui` since the split base.
4. **Complete:** rebase the Objective-C hygiene commits onto current `main`
   without the stale Deno deletion diff (`5d048eb53`, `2f88fad66`,
   `6511b4502`). Cherry-picked code-only from the three
   `refactor/plan01-hygiene-quick-wins` commits, dropping an unrelated
   `plan/objc-modernization-2026-07/` tree and `docs/tui/asciinema-overlay/`
   docs bundled into one of them. `AllTests` is green: 3198 passed, 0 failed.
5. **Complete:** replace security tests that assert empty inputs or
   `XCTAssertTrue(YES)` with fixtures that exercise the claimed boundary.
   Deterministic DPoP/SQL-allowlist/refresh-token/import/CAR coverage landed in
   `SecurityHardeningTests` (`6d8ebe97b` + `6cf9ed1c8` registration +
   `50624140f` fixture dedupe). A fresh HEAD build runs all 9
   `NetworkSecurityHardeningTests` with 0 failures; no placeholder assertions
   remain (deciduous node 1199 closed).

Exit gate: clean generated reports, current scenario run metadata, passing
package checks, and a documented branch disposition. Branch disposition is
now documented (workstream 00, B0.3): `codex/split-deno-testing-repos`
inactive pending Phase 3, `refactor/plan01-hygiene-quick-wins` superseded for
code and kept for its remaining docs, `backup-pre-rewrite` archival-only. All
five items are complete; the Phase 0 exit gate is met.

### Phase 1: containment

Complete the P0 items in
[workstream 01](workstreams/01-security-and-protocol-correctness.md) and
[workstream 04](workstreams/04-web-and-admin-ui.md).

1. **Complete first slice:** bind the scenario dashboard to loopback by default
   and protect all process controls with a launch capability, Origin/Host
   validation, and auth for non-loopback operation.
2. **Complete first slice:** remove inline browser event-handler dependence
   from Admin UI, enforce CSRF on every POST mutation, and reject code-valued
   rendering attributes. The real-browser CSP smoke now exists and passes
   (`scripts/admin_ui_browser_smoke_test.ts`, 2026-07-17).
3. **Complete first slice:** enforce independent idle and aggregate HTTP header
   deadlines that trickled bytes cannot reset, cancel stalled receives, and
   stop header accounting at `CRLFCRLF` so a valid slow request body is not
   rejected by the aggregate deadline.
4. **Complete first slice:** consolidate TypeScript lexicon generation on
   `Garazyk/Resources/lexicons`, fail closed on zero input or endpoints, and
   prove checked-in output drift-free. Objective-C NSID constants remain the
   explicitly ordered Phase 3 follow-up.

Exit gate: negative security tests, browser CSP smoke, slowloris simulation, and
deterministic generator tests.

### Phase 2: contracts and persistence

1. **Complete implementation/test slice:** add numbered, transactional AppView
   migrations with legacy file fixtures, rollback injection after every
   statement, and reopen tests. Verify a production database backup before the
   schema bump is deployed.
2. **Complete:** PLC schema-migration atomicity and legacy upgrade tests. The
   `PLCPersistentStore` + `PLCReplicaStore` migration onto ConnectionManagerSerial +
   QueryRunner landed, and schema creation plus the legacy ALTER upgrades now run
   inside a single `transact:` that rolls back on any failed statement. Proven by a
   legacy-schema upgrade fixture and an injected index-collision rollback test; the
   61-test PLC regression net stays green.
3. **Complete (report-only).** Split XRPC metrics published at
   `reports/xrpc_split_metrics.md`. Three semantic fixes applied:
   `chat.bsky.actor.declaration` phantom query removed,
   `app.bsky.labeler.getServices` validates required `dids`,
   `com.atproto.admin.getRecord` uses `ATURI` with documented compatibility
   policy. Schema validation in report-only mode.
4. **Complete (2026-07-17).** Firehose backpressure is deterministic:
   `PDS_FIREHOSE_MAX_PENDING_SENDS`/`_BYTES` now plumbed through `--binary`
   mode and the topology-compiler preset (docker-compose already had it);
   scenario 33 rewritten to poll for the drop instead of sleeping 90s.
   Adversarial data now hits the real PDS boundary too: new scenario 95
   sends malformed/oversized/junk payloads at live repo/blob endpoints and
   asserts rejection plus continued health (scenarios 65/66 previously
   only exercised the Deno-side parser). Evidence in workstream 01 S5.
5. **Complete (2026-07-17).** Write/read enforcement was already proven
   (scenario 55); `getRepoStatus` no longer lies about `active`; the
   downstream-propagation gap found by the audit is now implemented and
   proven E2E (takedown/reinstate → `#account` firehose events →
   Relay forwarding → AppView persistence; `28641e671`, `a3f8d3c53`,
   scenario 97) and cursor resume is proven live (scenario 96). One lead
   remains recorded in workstream 01 S5, not backlog: enforcement beyond
   passthrough (`RelayRepoStateManager` still has no callers; AppView
   does not yet un-index takendown accounts).
6. **Complete (2026-07-18):** permissioned-spaces multi-PDS
   acceptance scenarios (93 and 94) against an independently operated PDS3,
   including the private-blob and pruned-oplog recovery cases, and move the
   compatibility-gate rows on dated structured-run evidence
   ([workstream 06](workstreams/06-permissioned-spaces.md), P6.1). PDS3
   topology support across the scenario runner landed (`b807b3357`); scenario
   93 passes 19/19 and the OAuth fixes are characterization-guarded
   (`9000097ba`). Scenario 93's private-blob acceptance passes 21/21
   (`21eeb5719`), and Scenario 94 passes 28/28 with all three recovery
   selectors observed (`43b3ad9c3`, `2026-07-18t2251z-9158`). The Phase 2
   fixture was hardened to veto issuer-required environments and require a
   per-run local bearer capability, with no remaining security-audit findings.
   Phase completion is blocked until local disk capacity permits the full Deno
   and AllTests acceptance gates to finish.
7. **Complete (report-only).** Conformance matrix at
   `docs/reports/spec-conformance-matrix.md`: 21 rows, 16 supported, 4 partial,
   0 gap. Permissions-spec gap assessment at
   `docs/reports/permissions-spec-gap-assessment.md` with 4-phase implementation
   proposal. Known gaps G1-G4 seeded as backlog leads.

Exit gate: migration rollback proof, schema-aware coverage, current
structured scenario results for the affected endpoints, and recorded
scenario 93/94 runtime passes.

### Phase 3: boundaries

1. **Blocked (2026-07-18, maintainer decision):** complete the two-repository
   Deno extraction using released package versions as the boundary. Keep thin
   compatibility launchers until consumers pass. `@garazyk/tui@0.1.0` is the
   first verified release candidate: its dedicated format, lint, type-check,
   and 252-test tasks pass, and it exposes the required root, runtime, and
   testing exports. Its JSR publication is indefinitely deferred by maintainer
   decision: do not request or use publisher access, or run `deno publish`,
   until the maintainer explicitly reopens Phase 5. No package has been
   published; later ATProto package releases and the in-tree deletion (R4)
   remain deferred with it (workstream 03).
2. Remove the 92 scenario imports through `scripts/lib/deno` and the package
   back-reference in `packages/hamownia/tasks.ts` before the split deletion.
   The final form (imports by released package name) is deferred with item 1;
   a preparatory rewrite onto workspace specifiers is allowed only if the
   maintainer asks for it — otherwise this waits for the Phase 5 reopening.
3. **Complete (2026-07-18):** plain Objective-C NSID constants are generated
   deterministically (`f46ab5fb8`) and adopted at every call site with a CI
   drift check (`e212288bd`). A Narzedzia guard now rejects direct non-internal
   `registerMethod:@"..."` literals in production source, with six focused
   tests and a read-only CI scan; generator output remains in sync for 419
   endpoints.
4. **Complete (2026-07-19):** `GZCommandLineOptions` and `GZServiceLifecycle` adoption is complete across all remaining service binaries (`garazyk-ui`, `jelcz`, `syrena-chat`, `germ`, `kaszlak`, `campagnola`, `zuk`). Each binary has a dedicated characterization suite (`GarazykUICommandTests`, `JelczCommandTests`, `SyrenaChatCommandTests`, `GermCommandTests`, `KaszlakCommandTests`, `CampagnolaCommandTests`, `ZukCommandTests`) verified natively and inside GNUstep/Linux, preserving signal handling and `/tmp/<binary>-crash.log` diagnostic contracts. All ports are committed one binary per commit.

Exit gate: all three repositories pass format, lint, check, and tests; Garazyk
uses released dependencies and retains a launcher smoke test. This gate is
deferred while the publication deferral stands; items 3-4 are complete and the
remaining program does not depend on items 1-2.

### Phase 4: structure and scale

1. **Complete (2026-07-17):** `kaszlak relay serve` removed (Operator decision: Option 3). `PDSCLIRelayCommand` deleted; `zuk` is the canonical relay binary. Underlying relay components (RelayClient, UpstreamManager, DownstreamHandler, Firehose, etc.) are untouched and continue to serve zuk, PDSRelayService, and AppViewIngestEngine.
2. **Complete (2026-07-19):** stream repository export preparation and
   replace per-account summary scans with indexed metadata. The N+1 fix,
   byte-identical golden-fixture net, and materialized
   `collection_membership` index are committed (`6de6ebc64`); the
   incremental export producer with bounded fallback landed (`788592aca`)
   with byte-identical fixtures and memory bounds verified, and
   `PDSCollectionMembershipPruner` now has its own test suite
   (`6b52752e0`). Relay removal is recorded in ADR 0006. The Sync 1.1
   remainder stays open under item 7.
3. Decompose Objective-C god files after the branch recovery and
   characterization gates. Start with route ownership, then OAuth and Admin UI.
4. **Complete (2026-07-22):** Admin UI accessibility, CSS generation, and
   browser-module splits. The real-browser visual smoke proves 200%-zoom
   reflow, 44px targets, keyboard-visible focus, and reduced-motion behavior
   against the built `garazyk-ui` binary; the asset synchronization CTest
   prevents stale served UI files.
5. **Complete (2026-07-22):** Dedicated `#atproto_space` signing-key rotation
   and existing-DID migration path (workstream 06, P6.2). Purpose-isolated
   signers, explicit PLC operator tooling, and the runbook preserve the
   account-key fallback until the exact dedicated public key is published.
   Binary three-PDS scenario 93 run `2026-07-22t0530z-70080` passed 25/25,
   including remote verification of both credential key layouts during
   overlap.
6. Space operational readiness: backup/restore drill for the space database,
   downgrade-retention verification, and reconciler/pruner observability
   (workstream 06, P6.5).
7. **Complete (2026-07-19):** Sync 1.1 remainder (export block ordering,
   collection subsets) — closed, not implemented pending spec text
   (workstream 02, A6; workstream 01, S6 G2). Rechecked
   https://atproto.com/specs/sync 2026-07-19: both remain "Future Work"
   prose upstream, no version-numbered spec exists. The feature-flagged
   streamable-CAR pre-order enumerator (`+[MST
   setStreamableCARBlockOrderingEnabled:]`, default off) stays off by
   decision (`ed01c8085`, on `34e2b94ae`). Collection-based subsets are
   served independently via the `tools.garazyk.sync.getRepoFiltered`
   vendor extension, now with test coverage (3 new cases,
   `PDSRepositoryServiceTests.m`). See the phase-07 prompt for full
   detail.
8. **In progress (2026-07-18):** storage and MST optimization
   ([workstream 07](workstreams/07-storage-and-mst-optimization.md)).
   Done: `INSERT OR IGNORE` for `ipld_blocks` plus index/PRAGMA hardening
   (`3be4ee1ab`), and `WITHOUT ROWID` phases A/B (`fc1705696`,
   `50f2482c2`+`2f7ba5bdb`). Remaining: `WITHOUT ROWID` phases C/D (chat,
   space store), lazy MST subtree hydration, covering indexes, DID/handle
   resolution caching audit, and ingest/indexing decoupling.

Exit gate: cross-platform tests, protocol E2E for Relay/sync, and no public API
removals without caller proof.

### Phase 5: decisions

1. Regenerate the `objc-jupyter-wasm` capability baseline and choose a small
   supported subset before scheduling parser/runtime work.
2. Decide whether SMTP, cloud blob startup/listing/streaming, and STAR CAR reconstruction are
   supported products. Remove configuration promises for rejected features.
3. Keep AppView QueryRunner/pooling deferred until migration safety is fixed and
   measured contention justifies a concurrency change.
4. **Complete (2026-07-22):** app attestation for permissioned-spaces
   `appAccess#allowList` is fully implemented (client metadata, JWKS, key
   identifier, signature, issuer/subject equality, audience, expiry, nonce
   replay, app identity), recorded as an ADR 0004 amendment (workstream 06,
   P6.3). `policy: managing-app` itself stays rejected by design pending a
   separate `checkUserAccess` service-auth client, which the original
   disabled-scope note never described.
5. Track Proposal 0016 upstream drift on a monthly cadence (workstream 06,
   P6.4); re-pin, re-diff, and record impact before adopting any upstream
   change. `permissionedSpacesEnabled` stays off by default until the
   proposal stabilizes.

## Global gates

Every implementation lane must name targeted tests plus these applicable gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Run `xcodegen generate` before macOS Xcode builds. Run the Linux Docker gate for
Compat, Network, or binary entrypoint changes. Use structured `hamownia agent`
output for scenario evidence.

## Primary external contracts

- [AT Protocol specification index](https://atproto.com/specs/atp) — the
  conformance target is every published spec page (workstream 01, S6)
- [AT Protocol account lifecycle](https://atproto.com/specs/account)
- [AT Protocol event streams](https://atproto.com/specs/event-stream)
- [AT Protocol synchronization](https://atproto.com/specs/sync)
- [AT Protocol OAuth profile](https://atproto.com/specs/oauth)
- [AT Protocol Permissions](https://atproto.com/specs/permissions)
- [AT Protocol Lexicon](https://atproto.com/specs/lexicon)
- Proposal 0016 permissioned data, pinned
  `3f6c96d5d2d25438bd40fa89d6ecc37865f8e354` (experimental; ADR 0004)
- [did:plc v0.3](https://web.plc.directory/spec/v0.1/did-plc)
- [CSP Level 3](https://www.w3.org/TR/CSP/)
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- [SQLite transactions](https://www.sqlite.org/lang_transaction.html)
- [SQLite WAL](https://www.sqlite.org/wal.html)
