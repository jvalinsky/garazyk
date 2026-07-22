---
phase: 11
title: Storage and MST optimization remainder
status: in-progress
agent: worker
depends_on: [7]
---

# Phase 11: Storage and MST optimization remainder

## Progress

**Started 2026-07-22: O2 phase C chat-store migration audit.** The source has
two independent chat schema paths plus a service-owned `collection_membership`
table, so the original five-table description needs implementation-specific
migrations rather than one unsafe generic rewrite. Each replacement table will
carry its original FK/default constraints and have fresh/upgrade/rollback
evidence before O2 phase C is marked complete.

**Completed 2026-07-22: O2 phase C.** PDS DB V12 migrates the four legacy
chat tables; service DB V15 migrates the service-owned `collection_membership`
table. Fresh DDL and both migrations have focused apply/rollback/re-apply
coverage that retains rows, indexes, foreign keys, and defaults. O2 phase D
(space store) is next.

**Completed 2026-07-22: O2 phase D.** Space-store V4 converts all seven
composite-key tables with FK-safe parent/child replacement ordering. The
focused test exercises populated data in every target table through V4
apply/rollback/re-apply. O4 covering-index evidence is next.

**Completed 2026-07-22: O4.** The query-plan audit added only actor-store V5
`idx_records_rev`, which SQLite uses as a covering index for the repo-status
revision query. Other candidate paths already use primary/existing indexes or
would need to duplicate BLOB payloads, so no speculative index was added. O3
lazy subtree hydration is next.

**Completed 2026-07-22: O3.** The production repo-block loader deserializes
only the root, while proof traversal resolves child blocks on demand through a
256-entry LRU side cache. A deterministic 10K-record profile proves zero
initial child fetches and seven path fetches versus 2,507 eager child fetches;
on macOS the retained eager tree added 5.4 MB RSS in the recorded run. The
CAR, STAR-L0, STAR-Lite, and pre-order fixture suites remain byte-identical.
O5 caching audit is next.

**Completed 2026-07-22: O5.** `DIDResolver` already matches the reference
one-hour stale / one-day maximum policy and shared production callers use that
cache. The audit found that `HandleResolver`'s advertised five-minute TTL was
not enforced; entries now carry timestamps and expire. AppView `#identity`
ingestion now invalidates the shared DID cache after persisting the new handle
mapping. Beskid's independent SQLite edge cache remains TTL-only because that
binary does not consume the firehose; its 24-hour expiry is the deliberate
cross-process bound. Request-scoped resolvers remain intentionally isolated
where a caller supplies a service-specific PLC URL or injected resolver; the
shared resolver is used by the durable PDS, repository, space, Beskid, and
Mikrus paths. `HandleResolverTests` (27) and `DIDResolverTests` (6) cover
cache hit, expiry, stale response, max-age eviction, and invalidation. O6
requires an operator-reviewed architecture decision.

## Mission

Finish workstream 07: the remaining `WITHOUT ROWID` conversions (O2 phases
C and D), lazy MST subtree hydration (O3), covering indexes for hot reads
(O4), the DID/handle resolution caching audit (O5), and the ingest/indexing
decoupling design (O6). O1 and O2 A/B are done — do not redo them.

Depends on phase 7 because both touch `MST`, `PDSRepositoryService`, and the
export fixtures; the byte-identical golden CAR/STAR fixtures from phase 7
slice 2 are the safety net for every MST-adjacent change here.

## Read first

- `docs/plans/workstreams/07-storage-and-mst-optimization.md` (authoritative;
  per-lane steps, files, verification, and rollback live there)
- `.agents/skills/sqlite-performance-optimization` — load before touching any
  lane (workstream rule)
- `docs/reports/2026-07-17-optimization-research.md`
- The O2 phase B lesson (workstream 07 Status): a `WITHOUT ROWID` rewrite
  must carry over every constraint (FKs, CHECKs, DEFAULTs), not just columns
  and the PK — phase B dropped an `ON DELETE CASCADE` and needed a fix
  commit (`2f7ba5bdb`).

## Scope and order

1. **O2 phase C (chat store)** then **O2 phase D (space store)**: one
   migration per commit, each with apply/rollback/re-apply round-trip tests
   and full-DDL constraint parity against the original schema. The space
   store change must keep the space test suites and reconciliation
   (ADR 0005) green.
2. **O4 covering indexes**: after O2 completes (workstream dependency
   order), driven by `EXPLAIN QUERY PLAN` evidence, not intuition.
3. **O3 lazy subtree hydration**: MST behavior change — golden export
   fixtures must stay byte-identical; track peak memory in tests.
4. **O5 caching audit**: evidence-first; report coverage gaps before adding
   any cache.
5. **O6 ingest/indexing decoupling**: design-first — write the design as an
   ADR draft and set `status: blocked` for operator review before
   implementing; it is an architectural change.

## Acceptance gate

- Each lane's workstream verification passes; export fixtures byte-identical
  after O3; migration round-trip tests for both O2 phases.
- Workstream 07 global gates pass (`deno task check/lint/test`, bounded
  `AllTests --parallel 4`, `--gated=run`).

## On completion

Update workstream 07 status rows and mega-plan Phase 4 item 8; set
`status: complete` here (or `blocked` at the O6 design checkpoint).

## O6 checkpoint

ADR 0008 records the durable queue design after confirming that the current
AppView relay path synchronously decodes and materializes events. The operator
approved its eventual-consistency contract, queue capacity/lease defaults,
dead-letter policy, and production disk budget on 2026-07-22. The migration
and durable queue API are now in place; worker handoff and recovery scenarios
remain.
