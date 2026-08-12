---
title: Beskid Edge Reconciliation
status: rejected
last_verified: 2026-08-12
---

# Beskid Edge Reconciliation

Add an internal, authenticated reconciliation protocol so `beskid` edge nodes
can converge cache inventories efficiently after lag, restart, or partition,
without shipping full inventories.

This workstream is additive to current `beskid` cache behavior. It does not
replace normal upstream fetch paths or cache policy; it accelerates convergence
between trusted peers.

## Optional / deferred start condition

This workstream is intentionally **optional**. It should only be started when at
least one of the following is true:

1. You run `beskid` as a multi-node edge tier where cache inventories
   frequently diverge (restic, rolling deploys, partition events, or
   geographically distributed edges).
2. The cost of “catch-up” is operationally meaningful (e.g., high origin
   egress, slow recovery, or large cold caches) and full inventory transfer
   or plain keylist diffs are too expensive.
3. You can run inter-node reconciliation between **trusted** nodes with an
   explicit auth boundary (no open federation).

If none of the above is true, you should prefer simpler mechanisms:
firehose replay + upstream fetch + cache TTL-based convergence.

## Status (2026-08-12)

Planning only. No implementation is landed. This file defines phases, gates,
owner boundaries, and rollback paths for execution. Phases 1–8 describe the
intended shape, but implementation should be postponed until the optional
start condition is met.

## Decision: rejected in favor of cache invalidation

This reconciliation plan is rejected after re-reading the actual `beskid`
implementation.

### Why rejected (key points)

1. `beskid` is a **demand-filled TTL read-through cache**, not a replica.
   When entries expire, route handlers fetch from the originating PDS and
   refresh the cache (see `BeskidXrpcRoutePack` comment:
   “Cache miss or expired: read-through to the originating PDS”).
   Divergence across edges is therefore expected and correct; it represents
   different local access patterns, not drift that needs repair.
   TTLs are explicitly configured for records (default `3600s`) and
   identities (default `86400s`) in `BeskidConfiguration.h`.

2. The plan’s core action (peer value transfer / “pull missing values”)
   introduces correctness risk: pulling `K@cid1` from one edge may extend the
   lifetime of a value that has since become stale at origin. The IBLT diff
   does not carry causality needed to choose “newer wins”.

3. TTL expiry invalidates the primary precondition for effective set
   reconciliation: high overlap and stable element identity. Record
   freshness churn yields a continuously non-empty symmetric difference.

4. Evidence gaps: the original plan asserted “inventory drift” and “multi-edge
   miss cost” without measurements of (a) how often multi-edge divergence
   matters, or (b) whether staleness invalidation is the true SLO bottleneck.

### Generalized lesson

The failure here is of the *premise* shared by every set-reconciliation
protocol, not of IBLT specifically: swapping in range-based reconciliation would
not have helped, because a demand-filled TTL cache has no set-equality invariant
to reconcile. The three disqualifiers — no invariant, an already-enumerated
universe, or an ordered keyspace — are written up in
[IBLT for atproto reconciliation](../../20-explanation/guides/iblt-for-atproto-reconciliation.md)
and
[Range-based set reconciliation and the Willow protocol](../../20-explanation/guides/range-based-set-reconciliation.md).
Check them before proposing reconciliation for another service.

### Recommended replacement

Treat the genuine distributed-systems weakness as **staleness under invalidation**,
not reconciliation of inventories.

The replacement work is in Workstream 14:
`docs/plans/workstreams/14-beskid-firehose-invalidation.md`.

## Workstream 14 summary

- Subscribe `beskid` to `com.atproto.sync.subscribeRepos` (firehose).
- On commit/identity/account events, evict or age out relevant cache rows
  so the TTL-based cache converges to origin faster.
- Keep reconciliation out of scope.

## Current-state evidence (verified 2026-08-12)

`beskid` is documented as an edge record/identity cache service, with admin UI
work focused on metrics/snapshots rather than inter-node cache reconciliation.

| Site | Observed state |
| --- | --- |
| `docs/11-reference/glossary.md` | `beskid` is "Edge record + identity cache service" |
| `docs/plans/workstreams/service-admin-uis/README.md` | role is "Record and identity read-through caches" |
| `docs/plans/workstreams/service-admin-uis/beskid.md` | admin snapshots/metrics are planned and implemented; no peer reconciliation protocol is defined |

## Scope and non-goals

### In scope

- Key-inventory reconciliation between trusted `beskid` peers.
- Namespace/shard-based diffing.
- Pulling missing cache values after key diff.
- Backpressure controls, observability, and fallback mode.

### Out of scope

- Public or unauthenticated peer federation.
- Replacing upstream origin fetch logic.
- Reconciliation for other binaries (`mikrus`, `syrena`, etc.).
- Strong consistency/consensus semantics.

## Design constraints

| Constraint | Implication |
| --- | --- |
| Cache correctness wins over sync speed | Reconciled values must pass existing validation before writes |
| Serving latency is primary SLO | Reconciliation must be bounded and backpressure-aware |
| Edge nodes are trusted-but-failable | Protocol must authenticate peers and tolerate partial failure |
| Cache policy remains authoritative | Reconciliation cannot bypass TTL/eviction rules |

## Phase 0 — governance and protocol decisions

- **Evidence.** A distributed reconciliation path introduces new trust and
  operational concerns that are not captured in current `beskid` docs.
- **Change.** Record ADR-level decisions: key-first reconciliation, namespace
  partitioning, reconciliation fallback policy, and the trust/auth model.
- **Owner boundary.** `docs/adr/` and this workstream only.
- **Gate.** ADR accepted and linked from this file.
- **Rollback.** Drop the ADR and close this workstream; no code impact.

## Phase 1 — inventory index foundation

- **Evidence.** `beskid` functions as a read-through cache, but no durable
  inventory index for inter-node set comparison is documented.
- **Change.** Add a local inventory representation keyed by namespace and
  `key_hash`, with `value_fingerprint` and `last_seen_at`.
- **Key set definition.**
  - `records` namespace elements: a stable key for cached records
    (recommendation: `hash(did + collection + rkey)` plus a version marker).
  - `identities` namespace elements: a stable key for cached identities
    (recommendation: `hash(did + plcDocCidOrVersion)`).
- **Owner boundary.** `Garazyk/Sources/` files owned by `beskid` cache/storage
  implementation. No cross-binary schema coupling.
- **Gate.** Unit tests prove inventory updates are atomic with cache
  insert/update/delete paths.
- **Rollback.** Feature-flag inventory maintenance; off reverts to current cache
  behavior.

## Phase 2 — reconcile state tracking

- **Evidence.** Reconciliation sessions need persistent progress and failure
  state to avoid repeated expensive retries.
- **Change.** Add peer+namespace reconcile state (`last_success_epoch`,
  `last_diff_size`, backoff/error counters).
- **Session coordination model.**
  - Each reconcile session has a short-lived `session_id` and a monotonic
    `epoch` derived from “inventory snapshot time” (not from system wall clock).
  - State persists: last completed `epoch` per peer+namespace, and
    backoff parameters used by the scheduler.
- **Owner boundary.** `beskid` local storage only.
- **Gate.** Restart/recovery tests verify state survives process restarts and
  controls scheduling decisions.
- **Rollback.** Disable scheduler usage of persisted state and continue without
  peer reconciliation.

## Phase 3 — internal authenticated reconcile API

- **Evidence.** Inter-node reconciliation requires bounded, explicit internal
  endpoints; admin and public surfaces are not suitable transport.
- **Change.** Add internal routes (or RPC handlers) with fixed request/response
  shapes, authenticated and rate-limited. All payloads must be size-capped:

  1. `POST /internal/reconcile/hello`
     - input: `{peer_id, namespace, epoch, element_count, digest_checksum}`
     - output: `{match: bool, protocol_version, iblt_params}`
  2. `POST /internal/reconcile/symbols`
     - input: `{session_id, namespace, epoch, symbols: [bytes...] }`
     - output: `{need_more: bool, decoded_missing_keys: [key_hash...] }`
  3. `POST /internal/reconcile/fetch-keys`
     - input: `{session_id, namespace, missing_key_hashes: [...] }`
     - output: `{values: [{key_hash, value_fingerprint, encoded_value_bytes}...] }`
  4. `POST /internal/reconcile/commit`
     - input: `{session_id, namespace, fetched_count, validated_count, pruned_count}`
     - output: `{ok: bool}`

  Notes:
  - The sender and receiver roles can be symmetric (both can request missing
    values), but Phase 4 starts with a single direction to reduce complexity.
  - `digest_checksum` can be a fast XOR checksum or a Merkle-root-like digest
    over the key hashes; it is only a cheap mismatch signal, not proof.
- **Owner boundary.** `beskid` server runtime and internal auth middleware.
  No public XRPC registration.
- **Gate.** Security tests for unauthorized access, replay, oversized payloads,
  and malformed requests.
- **Rollback.** Disable internal reconcile listener by config; cache continues
  serving with origin-only behavior.

## Phase 4 — fixed-size IBLT engine (v1)

- **Evidence.** Full keylist diff is expensive for large, high-overlap cache
  inventories; fixed-size IBLT is the smallest useful improvement.
- **Change.** Implement session flow:
  digest mismatch -> IBLT exchange -> decode `missing`/`extra` keys.
- **Protocol parameters to decide (phase-gated).**
  - IBLT cell count `m` (derived from inventory size and target max diff).
  - number of hash functions `k`.
  - element size for keys (use fixed-length key_hash).
  - decode-time limits (max iterations and max CPU budget).
- **Decoding behavior.**
  - If decode succeeds: compute `missing` and `extra` sets of key hashes.
  - If decode fails: one retry with a larger `m` OR a downgrade to
    chunked keylist diff (both require careful caps).
- **Owner boundary.** `beskid` reconciliation module and tests. Avoid coupling
  to unrelated service modules.
- **Gate.** Property/unit tests across overlap/diff distributions; deterministic
  decode success/failure behavior.
- **Rollback.** Protocol downgrade to Phase 3 transport with chunked keylist
  diff only.

## Phase 5 — missing value transfer and validation

- **Evidence.** Key-level diff alone does not converge cache content.
- **Change.** Fetch missing values from peer (or upstream fallback), validate
  against `value_fingerprint` and existing cache safety rules, then write.
- **Transfer order and batching.**
  - Pull missing keys in bounded batches (`max_keys_per_fetch`).
  - For each value: validate before write; reject and quarantine on mismatch.
- **Extra key policy.**
  - Default: do not immediately prune extras (preserve cache TTL semantics).
  - Optional strict prune: only after multiple consecutive reconciliation
    failures and only for entries older than a configured watermark.
- **Owner boundary.** `beskid` cache write path and validator stack.
- **Gate.** Integration tests ensure hostile/corrupt peer payloads are rejected
  and never poison cache.
- **Rollback.** Keep key reconciliation but disable peer value transfer,
  falling back to origin fetch.

## Phase 6 — scheduler, backpressure, and fairness

- **Evidence.** Unbounded reconciliation can degrade serving latency.
- **Change.** Add jittered scheduler with per-peer and global concurrency caps,
  max symbols/session, max bytes/session, and adaptive backoff.
- **Fairness policy.**
  - Reserve a portion of bandwidth budget for reconciliation per namespace.
  - Apply circuit breakers when serving latency increases or when error rates
    exceed thresholds.
- **Owner boundary.** `beskid` runtime scheduling and metrics.
- **Gate.** Load tests with mixed read traffic show no serving regression beyond
  agreed threshold.
- **Rollback.** Disable scheduled reconciliation and retain manual/on-demand
  mode only.

## Phase 7 — observability and admin visibility

- **Evidence.** Operational rollout requires visibility into convergence, error
  rates, and fallback frequency.
- **Change.** Add metrics and bounded admin snapshots for peer health,
  namespace lag, diff sizes, decode failures, and bytes transferred.
- **Suggested metric cardinality discipline.**
  - Avoid per-record metrics; aggregate by namespace and peer_id.
  - Keep decode failures as counters by phase and error class.
- **Owner boundary.** `beskid` metrics emitters and admin partials only.
- **Gate.** Snapshot tests for empty/stressed states and metric cardinality
  bounds.
- **Rollback.** Hide reconciliation UI sections and disable metric emitters.

## Phase 8 — canary rollout and runbook

- **Evidence.** Reconciliation introduces new failure modes that require staged
  deployment and explicit rollback.
- **Change.** Ship under feature flags:
  disabled -> single peer-pair canary -> limited ring -> full edge set.
  Document runbook with disable/rollback steps.
- **Runbook must include.**
  - how to identify stuck sessions
  - how to disable value transfer only (keep key diff)
  - how to disable IBLT decode retry and force keylist diff fallback
- **Owner boundary.** Deployment config + `docs/20-explanation/guides/` runbook.
- **Gate.** Canary evidence: convergence targets met, no sustained serving
  regression, no security incidents.
- **Rollback.** Flip feature flag off cluster-wide; no schema rollback required
  for safety.

## Deferred — rateless IBLT (rIBLT) upgrade

Not ready for implementation until fixed-size IBLT behavior is measured.

- **Evidence needed.** Real production diff distributions and decode-failure
  profile for fixed-size IBLT.
- **Planned change.** Replace fixed table sizing with rateless symbol streaming
  and adaptive stop conditions.
- **Gate.** Demonstrated reduction in transfer/latency over v1 on representative
  workloads.
- **Rollback.** Retain fixed-size IBLT path as stable fallback.

## Proposed metrics and SLOs

| Metric | Target (initial) |
| --- | --- |
| Reconcile success rate | >= 99% over 24h |
| Decode fallback rate | < 5% sessions |
| p95 reconcile duration (small diff) | < 2s |
| Convergence after peer restart | < 10 min for hot namespaces |
| Serving latency regression during reconcile | no sustained regression over agreed threshold |

## Risk register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Decode instability for skewed diffs | Slow convergence | Resize retry + chunked fallback |
| Peer sends invalid values | Cache poisoning | Strict validation pre-write |
| Reconcile traffic competes with serving | Latency regression | Hard caps + adaptive backoff |
| Inventory drift from write-path bugs | False diffs/rework | Atomic inventory updates + audit tests |
| High operational complexity | Slow adoption | phased rollout + clear runbook |

## Acceptance gate checklist

Before marking this workstream complete:

1. ADR decision record accepted and linked.
2. Inventory and reconcile state tests are green.
3. Internal API security tests are green.
4. Reconciliation integration and fault-injection tests are green.
5. Mixed-load performance evidence is recorded.
6. Admin observability and rollout runbook are published.

