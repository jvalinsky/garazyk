---
phase: 21
title: AppView hydration batching and ingest checkpoint
status: pending
agent: worker
depends_on: []
---

# Phase 21: AppView hydration batching and ingest checkpoint

## Mission

Execute workstream 07 § O7. This is an **optimization phase**: the AppView read
path is correct, parameterized, and indexed — it is just expensive. The
dominant cost is per-row profile hydration, and the defect is query volume,
not query shape.

Because it is an optimization, the binding constraint is that **response
payloads must be byte-identical before and after**. If output changes, the
change is wrong.

There is also one correctness item bundled in: the ingest checkpoint can move
backwards.

## Read first

- `docs/plans/workstreams/07-storage-and-mst-optimization.md` § O7
  (authoritative; if this prompt disagrees, the workstream wins)
- `.agents/skills/sqlite-performance-optimization` — load before touching any
  lane (workstream 07 rule)
- `Garazyk/Sources/Database/Schema.m:129-195` — the `kPDSAccountUsage*` trigger
  pattern to copy for the counts table. Note these triggers exist but were
  never installed; phase 15 slice 2 installs them. Reuse the shape, not the
  omission.
- `Garazyk/Sources/AppView/Services/FeedService.m:390-410` — the correct
  `IN (?,?,?)` placeholder batching already in this codebase. Copy it.

## What is already correct — do not "fix" it

- SQL is parameterized everywhere, including the `IN (%@)` sites, which build
  `?` placeholders and validate DIDs first.
- `ATProtoLexiconValidator` is sound: depth limit of 32 incremented correctly
  on recursion, `isKindOfClass:` checks throughout, and a correct
  NSNumber-vs-CFBoolean distinction.
- AppView validates records before indexing via `AppViewGenericIndexer` and
  dead-letters failures.
- The ADR 0008 queue is properly leased — expiry-based stealing,
  `lease_owner` guards on ack and terminal-error, an ordering constraint, and
  attempt counting.

## Scope and order

One coherent slice per commit.

1. **Materialize the counts.** `ActorService.getProfileForActor:` issues five
   queries per actor, three of which are `COUNT(*)` aggregates over `records`.
   The indexes (`Database/Schema.m:90-93`) make them range scans rather than
   table scans, but a range scan still visits every matching entry — an actor
   with 100k posts costs 100k index entries counted, per profile, per request.
   Maintain follower/follow/post counts in a counts table kept current by
   triggers, and backfill on migration.
2. **Batch profile hydration.** `getProfileForActor:` is called inside row
   loops at `ActorService.m:91`, `:327`, `:365`, `:483`,
   `ContactService.m:156`, `:192`, and `GraphService.m:308`. Replace those with
   a single batched fetch over the row set.
3. **Batch record-body hydration.** `getRecordBodyFromCID:` is one query per
   row at `FeedService.m:273`, `:366`, `:424`, `:554`, `:725` and
   `GraphService.m:126`, `:181`, `:241`. Same treatment.
4. **Guard the checkpoint.** `AppViewDatabase.m:141` saves with
   `INSERT OR REPLACE` and no monotonicity guard, so a stale or racing save
   can overwrite a higher `seq` with a lower one. Make the save conditional so
   the cursor only advances.
5. **Consolidate limit clamping.** `AppViewXRpcRoutePack.m:31 parseLimitParam`
   clamps correctly and the routes use it, so nothing is exploitable today.
   But `GraphService` re-clamps at ten sites, `FeedService`/`GroupService`/
   `NotificationService` never do, and
   `Security/GZInputValidator.m:150 validateLimitParameter:maxLimit:` is a
   third implementation with zero callers. Settle on one, applied at the route
   boundary, and remove the dead one.

## Acceptance gate

- **Query counts are asserted, not observed.** Hydrating a 50-actor page must
  issue a bounded number of queries independent of page size, asserted in a
  test. Do the same for a 50-post feed after slice 3.
- **Payloads are byte-identical** before and after slices 1-3. Capture
  responses for the affected endpoints first and diff them; any difference is
  a bug in the optimization.
- `EXPLAIN QUERY PLAN` evidence for the new counts path.
- Migration apply/rollback/re-apply coverage for the counts table, retaining
  rows, indexes, foreign keys, and defaults (workstream 07's O2 phase B
  lesson).
- A checkpoint test that attempts a lower-`seq` save and asserts the cursor
  does not move.
- After slice 5, every route still clamps — removing a redundant clamp is only
  safe if the boundary clamp is universal. Verify each route, do not assume.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure, or they silently run
zero tests. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`).

## Rollback

Each slice is a single-commit revert. Slice 1 rolls back via its migration
down path. Slices 2-3 must produce identical output, which makes them safe to
revert at any point — and means a payload diff is the signal to revert rather
than to patch forward. Slice 5 touches a shared helper: if any route loses its
clamp, revert immediately rather than adding the service-layer clamps back.

## On completion

Update O7 status in workstream 07 with commit hashes and the measured
before/after query counts, then set `status: complete` here.
