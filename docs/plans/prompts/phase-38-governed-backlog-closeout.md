---
phase: 38
title: Governed backlog closeout with isolated Terra and Luna workers
status: in-progress
agent: default
depends_on: []
last_updated: 2026-08-20
---

## Progress

Started 2026-08-20 under Sol orchestration. Sol owns this prompt, deciduous
nodes, integration, workstream/mega-plan evidence, and final gates. Terra and
Luna receive disjoint implementation branches in separate git worktrees.
Blocked Phase 5, Phase 35, and Phase 36 work is explicitly excluded.

# Phase 38: Governed backlog closeout

## Mission

Close two independently actionable P1 slices from the authoritative
workstreams without disturbing the private-submodule transition or the blocked
iroh labs:

1. finish the bounded gathered/redacted-assertion remainder in workstream 10
   Phase 10; and
2. turn workstream 11's implemented Mikrus/Beskid packs into recorded M4
   acceptance with executable evidence.

This file is derived execution text. Workstreams 10 and 11 win on any
disagreement. It does not reopen JSR publication, WS16 live labs, or any
closed-not-pursued product lane.

## Read first

- [`docs/plans/mega-plan.md`](../mega-plan.md), Phase 4 items 12–13
- [`docs/plans/workstreams/10-dasl-conformance.md`](../workstreams/10-dasl-conformance.md), Phase 10
- [`docs/plans/workstreams/11-per-service-admin-uis.md`](../workstreams/11-per-service-admin-uis.md), M4
- [`docs/plans/workstreams/service-admin-uis/mikrus.md`](../workstreams/service-admin-uis/mikrus.md)
- [`docs/plans/workstreams/service-admin-uis/beskid.md`](../workstreams/service-admin-uis/beskid.md)
- [`docs/adr/0032-dasl-conformance-profiles.md`](../../adr/0032-dasl-conformance-profiles.md)
- [`docs/adr/0033-per-service-embedded-admin-uis.md`](../../adr/0033-per-service-embedded-admin-uis.md)

## Ownership and isolation

### Sol — orchestration and integration

Sol owns only:

- this phase prompt and its index entry;
- deciduous goal 456, decision 457, actions 458–459, and their outcomes;
- creation of the isolated worktrees and integration of reviewed worker
  commits;
- authoritative workstream/mega-plan status updates after evidence exists;
- affected, boundary, and final verification gates.

Sol does not duplicate implementation assigned below while a worker is active.

### Terra — WS10 S2PA gathered/redacted assertions

Terra owns:

- `Garazyk/Sources/Security/S2PA/` additions or narrowly required changes;
- focused S2PA tests under `Garazyk/Tests/Security/`;
- test registration when a new XCTest class is added.

Required slice:

1. Characterize the existing `ATProtoS2PAClaim`, assertion-store, hashed-URI,
   and JUMBF contracts before editing.
2. Implement a bounded representation and encode/decode path for gathered and
   redacted assertion references using existing hashed-URI and canonical CBOR
   primitives.
3. Verify referenced assertion labels/digests fail closed on missing,
   malformed, duplicate, or tampered entries.
4. Preserve current claim-bound verification for created assertions and
   ingredient embeds.
5. Add focused positive, round-trip, malformed, duplicate, and tamper tests.

If the repository's pinned sources do not define an authoritative wire shape,
Terra must report the exact missing contract and stop. It must not invent a
Garazyk-only S2PA format.

Out of scope: fragmented-BMFF `initHash`, auxiliary Merkle boxes, certificate
trust chains, media UX, transcoder policy, and plan/deciduous edits.

### Luna — WS11 Mikrus/Beskid M4 acceptance

Luna owns:

- Mikrus/Beskid Admin UI tests;
- narrowly required Mikrus/Beskid snapshot, metrics, or pack corrections found
  by those tests;
- no shared Admin UI library changes unless Sol approves a demonstrated shared
  defect first.

Required slice:

1. Reconcile each brief's implemented slices with its still-open acceptance
   language.
2. Add executable fixture proof that snapshot counters reconcile with stored
   state and that empty/stale/error states remain distinct.
3. Prove Admin UI polling uses bounded snapshot/query paths and does not add an
   unbounded scan or alter public read-through/XRPC behavior.
4. Cover concurrent indexing/cache mutation while authenticated partials poll,
   including secret/body/path redaction.
5. Run focused Mikrus/Beskid Admin UI, metrics, snapshot, and existing
   firehose/read-through suites.

Out of scope: new operator mutations, new dashboard product surface, WS14's
live sustained-burst SLO lab, shared plan/deciduous edits.

## Integration sequence

1. Commit this prompt and graph state on the orchestration branch.
2. Create one branch/worktree per worker from that commit.
3. Workers implement, run focused gates, commit, and report commit hashes plus
   exact pass/fail evidence.
4. Sol reviews both diffs, cherry-picks or otherwise integrates them one at a
   time, and resolves only integration fallout.
5. Sol runs affected tests after each integration, then the combined boundary
   and native gates permitted by available disk headroom.
6. Sol records dated evidence in workstreams 10/11 and the mega plan, updates
   this prompt to `complete`, and closes deciduous actions/outcomes. If a lane
   is genuinely blocked, record the named input here and leave other completed
   lane evidence intact.

## Acceptance gates

Terra focused gate:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -XCTest 'ATProtoS2PAClaimTests' --gated=run
./build/tests/AllTests -XCTest 'ATProtoS2PAJUMBFTests' --gated=run
./scripts/dev/check_module_boundaries.sh .
./scripts/check-recursive-setters.sh
```

Luna focused gate:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --filter 'Mikrus*Tests' --filter 'Beskid*Tests' --gated=run
./scripts/test/check_ui_design_system.sh
./scripts/dev/check_module_boundaries.sh .
./scripts/check-recursive-setters.sh
```

Sol integration gate:

```bash
./scripts/test/affected-tests.sh --run
./scripts/dev/check_module_boundaries.sh .
./scripts/check_module_boundaries.sh build
./scripts/check_namespace.sh build
./scripts/check-recursive-setters.sh
./scripts/check_no_host_process_exit.sh
deno run -A scripts/generate_nsid_constants.ts --check
deno run -A scripts/dev/generate_skill_index.ts --check
```

The full `AllTests --gated=run` and GNUstep Docker gate are required before
claiming repository-wide green. With the host currently below the documented
disk floor, a skipped full gate must be named as a blocker; it must never be
reported as passing.

## Rollback

Each worker commit is independently revertible. Gathered/redacted S2PA support
is additive and must not change existing created-assertion verification.
Mikrus/Beskid corrections must preserve the default-off, loopback-only admin
listeners and public XRPC behavior. Reverting one lane does not require
reverting the other or the private package submodules.

## Blocked work deliberately not assigned

- Phase 5 publication and standalone release boundaries remain blocked on an
  explicit future maintainer message.
- Phase 35 S10/S11 remains blocked on sufficient Docker disk headroom.
- Phase 36 remains blocked on Phase 35 plus dated pinned-image Scenario 101.
- WS03's runtime compatibility check remains blocked on disk and a runnable
  `syrena` topology.

