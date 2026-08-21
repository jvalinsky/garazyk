---
phase: 38
title: Governed backlog closeout with isolated Terra and Luna workers
status: complete
agent: default
depends_on: []
last_updated: 2026-08-20
completed_at: 2026-08-20
---

## Progress

Started 2026-08-20 under Sol orchestration. Sol owns this prompt, deciduous
nodes, integration, workstream/mega-plan evidence, and final gates. Terra and
Luna receive disjoint implementation branches in separate git worktrees.
Blocked Phase 5, Phase 35, and Phase 36 work is explicitly excluded.

Terra's initial local-source characterization found no gathered/redacted wire
schema. Sol supplied the official C2PA 2.4 claim-map-v2 and validation contract:
`gathered_assertions` are hashed URIs resolved in the current assertion store;
`redacted_assertions` are plain JUMBF URIs into ingredient manifests and must
not target the current claim's own assertions. Deciduous observation 460 records
the source-driven unblock.

Completed 2026-08-20. Terra landed additive gathered/redacted claim support in
`dc02706ae`; Luna closed Mikrus/Beskid M4 acceptance in `0a5657205`; Sol made
CTest's Admin UI asset contract explicit in `85e55f40e`. The bounded S2PA
helper validates absolute ingredient-manifest URI shape and rejects relative
self-redaction forms. Resolving cross-manifest targets or comparing an absolute
URI to the current manifest requires manifest context and remains outside this
claim helper.

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
- [C2PA 2.4 Technical Specification](https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html),
  claim-map-v2 and assertion/redaction validation

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
2. Implement additive, canonical encode/decode support for optional
   `gathered_assertions` hashed URIs and optional `redacted_assertions` JUMBF
   URI strings while preserving the existing created-only API.
3. Verify created and gathered assertion labels/digests against the current
   assertion store; fail closed on missing, malformed, duplicate, overlapping,
   or tampered entries.
4. Validate redacted JUMBF URI structure and reject a redaction that targets
   the current claim's own assertion store. Redacted targets are ingredient
   assertions and are not resolved in the current store by this bounded class.
5. Preserve current claim-bound verification for created assertions and
   ingredient embeds.
6. Add focused positive, round-trip, malformed, duplicate, self-redaction, and
   gathered-assertion tamper tests.

If the repository's pinned sources do not define an authoritative wire shape,
Terra must report the exact missing contract and stop. It must not invent a
Garazyk-only S2PA format.

Out of scope: cross-manifest ingredient traversal, redacted action/hard-binding
policy, fragmented-BMFF `initHash`, auxiliary Merkle boxes, certificate trust
chains, media UX, transcoder policy, and plan/deciduous edits.

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
claiming repository-wide green. A skipped or failing full gate must be named;
it must never be reported as passing.

## Completion evidence (2026-08-20)

- S2PA: `ATProtoS2PAClaimTests` passed 6/6 and
  `ATProtoS2PAJUMBFTests` passed 5/5 after `dc02706ae`.
- Admin UI: the focused Mikrus metric fixture passed 1/1; Mikrus/Beskid
  snapshot and pack tests plus shared host/runtime tests passed 69/69 after
  `0a5657205`.
- CTest asset integration: `85e55f40e` supplies
  `GARAZYK_ADMIN_UI_ASSETS_DIR` to every AllTests CTest entry. From `build/`,
  the previously asset-sensitive Mikrus title and UILab login tests passed
  1/1 each with that environment, and `ctest -N -V` showed the property on the
  shard.
- Structural gates passed: source and built module boundaries, namespace,
  recursive setters, no-host-process-exit, and the Admin UI design-system
  gate. Deno lint, NSID generation, skill-index generation, raw-XRPC-literal,
  and Codex agent-role checks passed.
- A pre-handoff four-shard CTest run was attempted and was not green. All four
  shard entries reported unrelated current-branch or sandbox failures,
  including prohibited socket/home access, an AdminAuthSync `Vary` expectation,
  a keychain error mismatch, and WS16 Streamplace environment/policy tests.
  `deno task check` also remains red on five pre-existing timer-handle type
  errors in Gruszka/Laweta. `deno task test` finished with 1,259 passed, 12
  failed (7 dependent steps), and 1 ignored; the failures include sandboxed
  socket/port tests, a checked-in Gruszka generator-artifact mismatch, and the
  same Deno timer-handle assumption. The GNUstep Docker gate was not run.
  Therefore this phase records scoped acceptance only and does not claim
  repository-wide green.

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
