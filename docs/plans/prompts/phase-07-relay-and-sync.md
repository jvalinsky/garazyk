---
phase: 7
title: Relay product decision and incremental public sync
status: complete
agent: worker
depends_on: [4]
last_updated: 2026-07-19
---

# Phase 7: Relay product decision and incremental public sync

## Mission

Resolve the two scale-shaped Phase 4 items: decide what `kaszlak relay
serve` is (then implement the choice), and make repository export
preparation incremental instead of materializing up to 100k records.

## Progress (2026-07-19)

- **Part 2 — Slice 3 complete**: Implemented incremental repository export producer and bounded fallback (`loadMSTForDid:store:error:` + paginated record CIDs via `listRecordCIDsForDid:limit:offset:error:` with 10k batching and 200k safety cap). `prepareRepoExportForDid:deltaMode:error:` now avoids pre-materializing up to 100k records in memory when generating CAR exports, and Tier 4 database fallback (`getRecordByCID:` via `ActorStore`) is wired into `buildRepoWriterForDid:` and `repoContentsSTARL0ChunkProducer` to ensure non-materialized records can be exported seamlessly. Byte-identical export fixtures and memory growth bounds verified across `PDSRepositoryServiceTests`.
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

All items are closed; this phase is complete.

1. ~~Slice 3: the incremental export producer behind a bounded fallback~~ —
   **done** (`788592aca`, 2026-07-19): paginated record-CID batching with a
   200k safety cap, Tier 4 database fallback wired into the writer and STAR
   chunk producer, byte-identical fixtures and memory bounds verified.
2. ~~`PDSCollectionMembershipPruner` test coverage~~ — **done**
   (`6b52752e0`, 2026-07-19), including on-demand pruning when stopped.
3. ~~Commit the regenerated `packages/gruszka/lexicons.ts` pickup of
   `tools.garazyk.admin.getCollectionMembershipStats`~~ — **done**
   (`1269ee19`, 2026-07-19).
4. Sync 1.1 remainder (export block ordering, collection subsets) — **closed**
   (2026-07-19). A forward-compat streamable-CAR pre-order enumerator was
   already committed (`ed01c8085`, on `34e2b94ae`) — MST.h/MST.m
   (`-enumerateStreamableCARBlocksUsingBlock:recordProvider:error:`
   behind `+[MST setStreamableCARBlockOrderingEnabled:]`, default off),
   `PDSRepositoryService.m` wiring, and `MSTPreorderTests`/
   `MSTPreorderFixtureTests`/`STARPreorderTests`. Collection-based
   repository subsets were already implemented independently as a vendor
   extension, `tools.garazyk.sync.getRepoFiltered`
   (`PDSRepositoryService.m:filteredRepoContentsChunkProducer:since:collections:error:`,
   registered in `XrpcVendorPack.m`), but had no test coverage — three
   tests added covering collection inclusion/exclusion, the no-match case,
   and the empty-collections error path (`PDSRepositoryServiceTests.m`,
   36/36 green including the 3 new cases).
   - **Spec-text recheck (2026-07-19):** refetched
     https://atproto.com/specs/sync. Export block ordering and
     collection-based subsets remain under a "Future Work" heading —
     described there as "likely to support," not published or finalized.
     No version-numbered "Sync 1.1" text exists upstream; nothing has
     changed since the 2026-07-18 note.
   - **Flag-on decision:** keep `streamableCARBlockOrderingEnabled` at its
     default (off). Turning it on ahead of finalized spec text risks
     shipping block ordering that upstream later changes incompatibly, and
     no consumer currently requires it — the existing default full-export
     ordering is unaffected either way. Revisit when upstream publishes
     Sync 1.1 as spec text rather than future-work prose. Garazyk's own
     collection-subset need is already served by the `tools.garazyk`
     vendor extension above, independent of this flag.

## Read first

- `docs/plans/workstreams/02-core-architecture-and-reliability.md` (A5, A6)
- `docs/plans/workstreams/01-security-and-protocol-correctness.md` (S6 G2)
- `docs/adr/0006-remove-kaszlak-relay-serve.md`
- https://atproto.com/specs/sync

## Acceptance gate

- Decision recorded as an ADR — **met** (ADR 0006).
- Export fixtures byte-identical before/after the incremental producer —
  **met** (`788592aca`, `PDSRepositoryServiceTests`).
- Protocol E2E for Relay/sync green in structured runs; global gates pass —
  **met**: `PDSRepositoryServiceTests` 36/36 (including the 3 new filtered-
  export tests); full `AllTests --parallel 4` build and run green.

## On completion

Workstream 02 A5/A6, workstream 01 S6 G2, and mega-plan Phase 4 items 1-2
and 7 updated in the same change. `status: complete` here.
