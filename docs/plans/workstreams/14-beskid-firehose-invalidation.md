---
title: Beskid Firehose Invalidation
status: active
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

## Phase 1 — DONE: internal subscription + invalidation hooks (2026-08-12)

- **`GZBeskidFirehoseInvalidator`:** optional relay subscription via
  `ATProtoFirehose`, cursor file under `<dataDir>/firehose.cursor`, reconnect
  with backoff, commit/identity/account → cache eviction mapping.
- **Feature flag:** `BESKID_FIREHOSE_ENABLED` (default off), `BESKID_FIREHOSE_URL`,
  `BESKID_FIREHOSE_CURSOR_PATH`; wired from `GZBeskidRuntime`.
- **Database helpers:** `deleteAllRecordsForDID:`, `deleteIdentityForDID:`.
- **Metrics:** firehose connected gauge, invalidation/reconnect/parse-error counters
  in `GZBeskidMetrics` snapshot.
- **Gate:** `BeskidFirehoseInvalidatorTests` (5/0) with fixture events.

Phase 2 may add integration coverage for read-through convergence after upstream
updates.

## Phase 2 — DONE: record invalidation mapping (`#commit`) (2026-08-12)

Implemented in Phase 1's `handleCommitEvent:`: known `path` ops delete
`(did, collection, rkey)`; unknown/malformed ops fall back to
`deleteAllRecordsForDID:`. Gate evidence extended with
`testCommitInvalidationThenReseedServesUpdatedRecord` (invalidate → miss →
reseed → fresh hit). Live multi-process read-through timing remains optional
hardening for Phase 4 SLOs.

## Phase 3 — DONE: identity invalidation and account events (2026-08-12)

`deleteIdentityForDID:` plus `handleIdentityEvent:` /
`handleAccountEvent:` (takedown/suspend/deactivate purge) shipped with Phase 1
fixture coverage (`testIdentityEventDeletesCachedIdentity`,
`testAccountTakedownPurgesRecordsAndIdentity`).

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

