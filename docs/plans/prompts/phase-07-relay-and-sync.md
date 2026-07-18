---
phase: 7
title: Relay product decision and incremental public sync
status: in-progress
agent: claude
depends_on: [4]
last_updated: 2026-07-17
---

# Phase 7: Relay product decision and incremental public sync

## Mission

Resolve the two scale-shaped Phase 4 items: decide what `kaszlak relay
serve` is (then implement the choice), and make repository export
preparation incremental instead of materializing up to 100k records.

## Progress (2026-07-17)

- **Part 1 — relay decision: complete and committed** (`d9fa51a1d`).
  Operator chose Option 3 (remove). `PDSCLIRelayCommand.m/.h` and
  `PDSCLIRelayCommandTests.m` deleted; `PDSCLIRegisterAll.m` and
  `test_main.m` cleaned. `zuk` remains the canonical relay binary; the
  underlying relay components (RelayClient, UpstreamManager,
  DownstreamHandler, Firehose) are untouched and continue to serve zuk,
  PDSRelayService, and AppViewIngestEngine. Recorded as ADR 0006
  (`docs/adr/0006-remove-kaszlak-relay-serve.md`).
- **Part 2 — incremental public sync: slices 1-2 complete and committed**
  (`6de6ebc64`). Slice 1: N+1 fix — `headInfoForDid` method, updated
  `listRepos`/`getRecord`, unit tests. Slice 2: golden fixtures —
  structural CAR/STAR golden tests, byte-identical re-export test, peak
  memory/size bounds. Also landed in that commit: a materialized
  `collection_membership` index (kept current by `PDSRecordService` on
  every create/update/delete) that `listReposByCollection` now queries
  first, falling back to the old per-actor-store scan on index failure;
  a new admin endpoint exposes index stats and an on-demand prune. All
  42 targeted tests pass (33 `PDSRepositoryServiceTests`, 9
  `SyncEndpointXrpcTests`), verified against an isolated build of that
  commit's tree.
- The former worktree hazard (this phase's changes mixed with phase 6's
  uncommitted NSID sweep in the same worktree) is resolved: relay
  removal, sync slices, and the NSID sweep landed as three separate
  commits, each verified with its own targeted tests. See
  `docs/plans/prompts/README.md` for the loop-protocol rule this
  produced.

## Remaining work

1. Slice 3: the incremental export producer behind a bounded fallback,
   peak memory tracked in tests (golden fixtures from slice 2 are the
   safety net — exports must stay byte-identical).
2. `PDSCollectionMembershipPruner` (committed in `6de6ebc64`) has no
   tests yet — give it its own test coverage and commit.
3. Sync 1.1 remainder (export block ordering, collection subsets): still
   no published spec text — tracked as S6 gap G2; recheck before closing
   this phase.

## Read first

- `docs/plans/workstreams/02-core-architecture-and-reliability.md` (A5, A6)
- `docs/plans/workstreams/01-security-and-protocol-correctness.md` (S6 G2)
- `docs/adr/0006-remove-kaszlak-relay-serve.md`
- https://atproto.com/specs/sync

## Acceptance gate

- Decision recorded as an ADR — **met** (ADR 0006) once committed.
- Export fixtures byte-identical before/after the incremental producer —
  fixtures exist (slice 2); producer still pending.
- Protocol E2E for Relay/sync green in structured runs; global gates pass.

## On completion

Update workstream 02 A5/A6, mega-plan Phase 4 items 1-2 and 7; set
`status: complete` here.
