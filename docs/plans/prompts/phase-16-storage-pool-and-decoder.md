---
phase: 16
title: Storage pool and MST decoder correctness
status: pending
agent: worker
depends_on: []
---

# Phase 16: Storage pool and MST decoder correctness

## Mission

Execute workstream 01 § S9 slices 7-10: fix the actor-store pool's silently
partial enumeration and unsafe eviction, make the MST node decoder reject
malformed input, and clear three named low-severity defects. Independent of
phase 15 — the two may run concurrently only in separate worktrees.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S9
  (authoritative)
- `Garazyk/Sources/Auth/PDSReplayCache.m` — already uses a `dispatch_source_t`
  timer routed through its connection manager's own queue. That is the shape
  the pool's eviction timer should adopt.
- Commit `b4d178c6` and `PDSDatabaseRaceTests` — the close/open guards that
  make the eviction race a correctness problem rather than a memory-safety
  one. Do not undo them.

## Decisions already taken (do not re-litigate)

- The MST decoder rejects malformed nodes rather than silently repairing
  them.

## Scope and order

One coherent slice per commit.

1. **Pool enumeration returns complete results.**
   `Database/Pool/DatabasePool.m:342-358` treats `knownDids` as an index of
   all DIDs, but `:170` adds on open and `:235` removes on eviction, so it
   tracks open stores. After one `storeForDid:` call the filesystem walk is
   skipped and `getAllReposWithError:`/`getAllAccountsWithError:` return only
   that subset, with no error. Live via
   `Core/Repositories/PDSSQLiteRepoRepository.m:55`. Either maintain a real
   on-disk index or drop the cache and always walk — the defect is the silent
   partial answer, so pick whichever reliably returns everything.
2. **Eviction stops closing stores that are in use, and stops blocking the
   pool.** `evictLRUStore` (`:202`) fires whenever `stores.count >= maxSize`
   (`:149`) and closes stores other threads hold, producing spurious
   "database not open" failures. Eviction also runs on the serial `poolQueue`
   and calls `close`, which does `dispatch_sync(dbQueue)`, so evicting a busy
   store stalls all pool traffic — and any transaction block that re-entered
   the pool would close a `poolQueue → dbQueue → poolQueue` cycle. Track
   in-flight use and skip or defer eviction of busy stores, and move `close`
   off `poolQueue`.
3. **Move store opening out of the pool's critical section.**
   `storeForDid:` holds `poolQueue` across two filesystem syscalls in
   `dbPathForDid:` (`:128-131`) plus a full SQLite open and migration run, so
   every cold-DID request serializes every other pool operation including
   metrics.
4. **Replace the eviction timer.** `:72` uses
   `NSTimer scheduledTimerWithTimeInterval:`, which requires a live run loop
   on the constructing thread; off such a thread, time-based eviction silently
   never runs. Use a `dispatch_source_t` per the `PDSReplayCache` pattern, and
   delete the `PDSDatabasePoolTimerProxy` `performSelector:` bounce (`:22`)
   along with it.
5. **Strict MST decode.** `Repository/MST.m nodeFromCBOR` silently `continue`s
   past malformed entries (`:1027,1046,1052`) and clamps an over-long `p`
   prefix (`:1035`), so malformed bytes decode into a different valid-looking
   tree. Reject instead. Also stop inferring node level from the first key's
   depth (`:1079-1082`) where the structure carries it; an empty node
   currently always gets level 0.
6. **Low-severity cleanup.** The unfreed `errMsg` in
   `Database/Migrations/PDSMigrationManager.m:1020-1087` (BEGIN and COMMIT
   pass `&errMsg`, nothing calls `sqlite3_free`; it is logged at `:1054`), and
   the unsigned `openFileHandleCount` decrement at `DatabasePool.m:236`.

## Acceptance gate

- **Enumeration:** open exactly one store, then assert `getAllRepos` and
  `getAllAccounts` return every on-disk repo/account. This test fails against
  today's code and is the regression guard for slice 1.
- **Eviction:** drive concurrent readers against more than `maxSize` distinct
  DIDs and assert no operation fails with "database not open", and that the
  pool remains responsive (metrics calls return) while a long transaction is
  in flight.
- **Timer:** construct the pool on a thread with no run loop and assert
  time-based eviction still occurs.
- **MST decode:** rejection cases for a malformed entry, an over-long `p`
  prefix, a non-tag `v`, and an empty node — each must return an error rather
  than a repaired tree. Existing golden CAR/STAR export fixtures must stay
  byte-identical; they are the safety net that the stricter decoder has not
  changed any valid path.

New suites need registration in `Garazyk/Tests/test_main.m` plus a cmake
reconfigure. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`).

## Rollback

Each slice is a single-commit revert and they are mutually independent. Slice
5 is the one that can reject data currently accepted: if a real peer's CAR
fails to import after it, capture the offending node bytes as a fixture and
decide explicitly whether the peer or the decoder is wrong before loosening
anything. Slices 2-4 change pool timing, so watch for new flakiness in the
gated suite rather than only the targeted tests.

## On completion

Update S9 slices 7-10 status in workstream 01 with commit hashes, then set
`status: complete` here. If slice 5 changes what the decoder accepts in a way
visible to peers, record it as an ADR alongside ADR 0009's STAR precedent.
