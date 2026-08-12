---
title: Beskid Firehose Invalidation — Phase 0 Design
status: accepted
last_verified: 2026-08-12
---

# Phase 0 design: Beskid firehose invalidation

Governance gate for [workstream 14](14-beskid-firehose-invalidation.md).
Records wiring decisions before any subscription code lands.

## Connection source

**Decision: connect to the relay (`zuk`), not directly to upstream PDS hosts.**

Rationale:

- Beskid is an edge cache; it already treats PDS as origin on read-through.
  A single relay subscription matches the federation topology Garazyk tests
  (`PDS → relay → consumers`) and avoids N upstream WebSocket connections
  when many PDS instances are configured.
- `ATProtoFirehose` and `ATProtoRelayClient` already exist in `ATProtoSync`;
  reusing them keeps cursor/backoff behavior consistent with AppView ingest.
- Relay exposes `com.atproto.sync.subscribeRepos` with the same framing as
  direct PDS firehose; Beskid does not need repo write access.

Configuration (proposed env keys on `GZBeskidConfiguration`):

| Key | Default | Purpose |
| --- | --- | --- |
| `BESKID_FIREHOSE_ENABLED` | `0` | Feature flag; off preserves current TTL-only behavior |
| `BESKID_FIREHOSE_URL` | `ws://127.0.0.1:2587` | Relay WebSocket endpoint |
| `BESKID_FIREHOSE_CURSOR_PATH` | `<dataDir>/firehose.cursor` | Persisted sequence cursor |

## Subscription mode

**Decision: full firehose subscription (no interest-graph filter) for Phase 1.**

Rationale:

- Beskid caches records and identities keyed by `(did, collection, rkey)` without
  maintaining a local follow graph. Partial subscription would require Beskid
  to track viewer interest, which is AppView's job.
- Invalidation is cheap (SQLite `DELETE` by key); the cost is bandwidth on the
  relay stream, acceptable for single-edge deployments. A future phase may add
  DID allow-list filtering when Beskid is scoped to a known PDS set.

## Event → invalidation mapping

| Event type | Action on `GZBeskidDatabase` |
| --- | --- |
| `#commit` with known `(collection, rkey)` in op | `DELETE FROM beskid_records WHERE did=? AND collection=? AND rkey=?` |
| `#commit` with op shape unknown | Configurable fallback: delete all records for `did` (default conservative) |
| `#identity` | Delete identity row for `did` (new API: `deleteIdentityForDID:`) |
| `#account` (deactivated/takedown) | Delete all records + identity for `did` |
| `#sync`, `#info`, `#labels` (if present) | No cache action in Phase 1 |

Record TTL semantics remain authoritative: invalidation is an *early eviction*
optimization; expired rows are already refreshed on miss.

## Failure modes when subscription is down

| Condition | Behavior |
| --- | --- |
| WebSocket disconnect | Exponential backoff reconnect; cursor replay from last persisted sequence |
| Cursor gap / relay ahead | Log warning; continue from relay's suggested cursor; may miss events → TTL still bounds staleness |
| Parse error on frame | Drop frame, increment `beskid_firehose_parse_errors`, continue |
| Subscription disabled | No background thread; cache operates as today |
| Relay unreachable at startup | Log error; retry in background; HTTP read-through still serves (stale until TTL) |

Metrics (Phase 4 preview, stub counters in Phase 1):

- `beskid_firehose_connected` (gauge)
- `beskid_firehose_invalidations_total{type=commit|identity|account}` (counter)
- `beskid_firehose_reconnects_total` (counter)

## Rollback

Set `BESKID_FIREHOSE_ENABLED=0`. No schema migration required for Phase 1;
cursor file may remain on disk unused.

## Gate satisfied

This note satisfies workstream 14 Phase 0. Phase 1 may implement
`GZBeskidFirehoseInvalidator` behind the feature flag.
