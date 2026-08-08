---
phase: 16
title: Storage pool and MST decoder correctness
status: complete
agent: worker
depends_on: []
completed_at: 2026-07-27
---

# Phase 16: Storage pool and MST decoder correctness

## Progress

Started 2026-07-27 in worktree `../garazyk-storage` after Phase 15 completed.
Beginning the required read-first pass for pool enumeration, eviction, and MST
decode correctness before implementing slice 7.

Completed slice 7: pool enumeration now always walks the on-disk actor layout
rather than treating its open-store cache as a complete inventory. The
regression test seeds three actor databases, opens only one in a fresh pool,
and verifies account and repository enumeration returns all three.

Completed slice 8: pool-mediated reads, transactions, and convenience lookups
retain their store while in flight. Eviction skips those retained stores,
removes idle stores under `poolQueue`, and schedules their close on the
eviction queue. `DatabasePoolTests` passed 17 tests, including the new
long-transaction eviction and metrics responsiveness regression.

Completed the second commit of authoritative slice 8: cold actor-store path
derivation and SQLite opening now run outside `poolQueue`, with a per-DID
single-flight group preventing duplicate opens. The run-loop-bound timer was
replaced by a dispatch source on the eviction queue. `DatabasePoolTests` passed
18 tests, including a pool created on a thread without a run loop that was
evicted by the timer.

Completed slice 9: MST node decoding now rejects malformed entry maps,
over-long key prefixes, invalid CID tags, invalid UTF-8 or ordering, and empty
leaf nodes rather than repairing or skipping them. Structural forwarding nodes
remain valid. `MSTDecoderTests` executed five rejection cases, and the complete
MST filter passed 108 tests including byte-for-byte fixture verification.

Completed slice 10: every BEGIN/COMMIT `sqlite3_exec` error string is freed on
both migration apply and rollback paths. The old timer bounce and guarded pool
counter decrement were completed in slice 8. Migration-focused suites passed
20 tests, including existing apply/rollback/re-apply coverage.

Completed 2026-07-27: Phase acceptance and all mega-plan global gates passed.
Evidence and commit hashes are recorded in workstream 01 § S9.

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

7. **Pool enumeration returns complete results.**
   `Database/Pool/DatabasePool.m:342-358` treats `knownDids` as an index of
   all DIDs, but `:170` adds on open and `:235` removes on eviction, so it
   tracks open stores. After one `storeForDid:` call the filesystem walk is
   skipped and `getAllReposWithError:`/`getAllAccountsWithError:` return only
   that subset, with no error. Live via
   `Core/Repositories/PDSSQLiteRepoRepository.m:55`. Either maintain a real
   on-disk index or drop the cache and always walk — the defect is the silent
   partial answer, so pick whichever reliably returns everything.
8. **Eviction stops closing stores that are in use, and stops blocking the
   pool.** `evictLRUStore` (`:202`) fires whenever `stores.count >= maxSize`
   (`:149`) and closes stores other threads hold, producing spurious
   "database not open" failures. Eviction also runs on the serial `poolQueue`
   and calls `close`, which does `dispatch_sync(dbQueue)`, so evicting a busy
   store stalls all pool traffic — and any transaction block that re-entered
   the pool would close a `poolQueue → dbQueue → poolQueue` cycle. Track
   in-flight use and skip or defer eviction of busy stores, and move `close`
   off `poolQueue`.
   `storeForDid:` must also move path derivation and SQLite open out of the
   pool critical section, so a cold-DID request does not serialize other pool
   operations including metrics. Replace the eviction timer: `:72` uses
   `NSTimer scheduledTimerWithTimeInterval:`, which requires a live run loop
   on the constructing thread; off such a thread, time-based eviction silently
   never runs. Use a `dispatch_source_t` per the `PDSReplayCache` pattern, and
   delete the `PDSDatabasePoolTimerProxy` `performSelector:` bounce (`:22`)
   along with it.
9. **Strict MST decode.** `Repository/MST.m nodeFromCBOR` silently `continue`s
   past malformed entries (`:1027,1046,1052`) and clamps an over-long `p`
   prefix (`:1035`), so malformed bytes decode into a different valid-looking
   tree. Reject instead. Also stop inferring node level from the first key's
   depth (`:1079-1082`) where the structure carries it; an empty node
   currently always gets level 0.
10. **Low-severity cleanup.** The unfreed `errMsg` in
   `Database/Migrations/PDSMigrationManager.m:1020-1087` (BEGIN and COMMIT
   pass `&errMsg`, nothing calls `sqlite3_free`; it is logged at `:1054`), and
   the unsigned `openFileHandleCount` decrement at `DatabasePool.m:236`.

## Acceptance gate

- **Enumeration:** open exactly one store, then assert `getAllRepos` and
  `getAllAccounts` return every on-disk repo/account. This test fails against
  today's code and is the regression guard for slice 7.
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
./build/tests/AllTests --gated=run
```

Bounded parallelism only (`--parallel 4`).

## Rollback

Each commit is a single-purpose revert and the four authoritative slices are
mutually independent. Slice 9 is the one that can reject data currently accepted:
if a real peer's CAR
fails to import after it, capture the offending node bytes as a fixture and
decide explicitly whether the peer or the decoder is wrong before loosening
anything. Slice 8 changes pool timing, so watch for new flakiness in the
gated suite rather than only the targeted tests.

## On completion

Update S9 slices 7-10 status in workstream 01 with commit hashes, then set
`status: complete` here. If slice 9 changes what the decoder accepts in a way
visible to peers, record it as an ADR alongside ADR 0009's STAR precedent.
