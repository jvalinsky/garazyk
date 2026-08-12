---
title: Beskid Firehose Invalidation
status: proposed
last_verified: 2026-08-12
---

# Beskid Firehose Invalidation

Reduce `beskid` staleness by evicting or aging out cached entries promptly
on `com.atproto.sync.subscribeRepos` firehose events, so the TTL read-through
cache converges faster toward origin state.

This workstream replaces `13-beskid-edge-reconciliation.md` (rejected) by
addressing the real failure mode: **stale reads after upstream invalidation**.

## Current-state evidence (verified 2026-08-12)

- `beskid` route behavior is demand-driven read-through: on cache miss or
  expiry, it fetches from the originating PDS
  (`BeskidXrpcRoutePack.m` comment + logic: “Cache miss or expired:
  read-through to the originating PDS”).
- Cache TTLs are explicit:
  repo records default 3600 seconds; identity entries default 86400 seconds
  (`BeskidConfiguration.h`).
- The current `BeskidRuntime` starts only HTTP routes and an optional admin
  listener; it does not establish any firehose subscription
  (`BeskidRuntime.m`).

## Scope and non-goals

### In scope

1. Add an *optional* `subscribeRepos` firehose client to `beskid`.
2. On event receipt:
   - invalidate record cache entries impacted by a commit (`#commit` ops),
   - invalidate identity cache entries on identity events (`#identity`),
   - optionally track account status events (`#account`) for extra safety.
3. Measure and report staleness reduction:
   - hit ratio delta,
   - origin GET reduction / time-to-correct-after-update.

### Out of scope (explicit)

- Peer-to-peer cache replication or IBLT reconciliation.
- Multi-edge “convergence” goals for TTL caches.
- Serving any stale content past correctness TTL (keep TTL semantics
  authoritative).

## Phase 0 — DONE: governance and wiring decision

Design note: [14-beskid-firehose-invalidation-phase0.md](14-beskid-firehose-invalidation-phase0.md)
(accepted 2026-08-12). Connect to relay; full subscription; event mapping and
failure modes documented. Phase 1 may proceed.

## Phase 1 — internal subscription + invalidation hooks

- **Evidence.** `com.atproto.sync.subscribeRepos` is already supported by Garazyk
  as a firehose client (see `Sync/Firehose/Firehose.m`).
- **Change.** Extend `BeskidRuntime` to optionally start a `Firehose` instance:
  - store cursor in `beskid` data dir,
  - handle reconnect with backoff,
  - expose “subscription health” metrics.
- **Owner boundary.** `BeskidRuntime.m` and a new `BeskidFirehoseInvalidator.*`
  module; no changes to other binaries.
- **Gate.** Unit tests for invalidator mapping logic using fixture events.
- **Rollback.** Disable subscription; invalidator remains inert.

## Phase 2 — record invalidation mapping (`#commit`)

- **Evidence.** `BeskidDatabase` can delete cached records by
  `(did, collection, rkey)` and the route handler refreshes on miss.
- **Change.** Translate `FirehoseCommitEvent.ops` to affected record keys:
  - For ops with known `$type`/fields that identify `collection` and `rkey`,
    delete `beskid_records` rows matching `(did, collection, rkey)`.
  - For ops with unknown/unsupported shapes, fallback to conservative
    invalidation policy (configurable), e.g.:
    - invalidate all collections for that `did`, or
    - invalidate only collections in an allow-list.
- **Owner boundary.** `BeskidDatabase` gets new helper methods only if needed
  (e.g. delete-by-DID).
- **Gate.** Integration test:
  update a record upstream, assert:
  - `beskid` stops serving it after invalidation,
  - subsequent fetch returns the new value within bounded time.
- **Rollback.** Conservative mapping only (or invalidation disabled) so correctness is preserved.

## Phase 3 — identity invalidation mapping (`#identity`) and account events

- **Evidence.** `BeskidDatabase` caches identities with TTL and supports
  handle/DID mapping, but currently has no “delete identity now” API.
- **Change.**
  - Add `deleteIdentityForDID:` or `expireIdentityForDID:` to
    `BeskidDatabase`.
  - On identity events: invalidate the DID row.
  - On account events (`#account`): optionally purge records/identities if
    takedown/deactivation is signaled.
- **Gate.** Integration test:
  identity update upstream -> invalidator evicts cached identity promptly.
- **Rollback.** Leave identity TTL unchanged; still invalidate records.

## Phase 4 — observability, SLOs, and operational safety

- **Evidence.** Without metrics, invalidation can regress hit ratio or cause
  origin storms.
- **Change.** Add metrics:
  - invalidations received by type,
  - invalidations applied vs dropped (fallback),
  - time from firehose event to first cache purge,
  - origin GET rate attributable to invalidations.
- **SLO targets (initial).**
  - staleness window p95 reduction (measure from update time to corrected
    fetch),
  - invalidation-induced origin GETs bounded under configurable budget.
- **Gate.** Load test simulating bursty updates; no sustained origin
  overload.
- **Rollback.** Disable identity invalidation first, then record invalidation,
  then the subscription.

## Optional start condition

Start this workstream only when at least one holds:

1. You operate `beskid` as a meaningful edge tier for end users and observe
   staleness as a user-visible issue.
2. You need higher than TTL convergence guarantees (e.g., shorter record TTL
   than is otherwise safe).
3. You can run/monitor outbound firehose connectivity from `beskid`.

Otherwise, stick with TTL read-through until the staleness SLO demands it.

