---
title: AppView Admin UI Brief
status: planned
last_verified: 2026-08-11
---

# AppView (`syrena`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
Coordinate the shared ingest vocabulary with [Mikrus](mikrus.md) and compare
source-level troubleshooting with [Relay](relay.md).

## Outcome and evidence

Give operators one view of ingestion, indexing, backfill, hooks, lexicons, and
query health. The existing AppView pack already renders metrics, ingest health,
and a paginated backfill queue with retry/cancel/rebuild/enqueue actions.
`AppViewAdminRoutePack` also exposes lexicon, hook/dead-letter, record, handler,
and endpoint inventories.

The current JSON admin route guard allows access when `adminSecret` is empty.
Embedding must remove that fail-open state: internal routes either require the
startup-minted loopback token or are unavailable, while browser routes require
the service session and CSRF for mutations.

## Dashboard shape

- **Overview:** health, uptime, indexed records/repos/collections, query rate and
  errors, ingestion cursor/lag, backfill depth/age, and dead-letter count.
- **Ingestion:** overall plus per-relay connection, cursor, event rate, last
  event, reconnect/error state, commits/operations accepted and rejected.
- **Backfill:** counts and oldest age by state, workers, throughput, bounded DID
  queue, retry/cancel, scope rebuild, and explicit DID enqueue.
- **Indexes:** collections, lexicons, generated/custom endpoints, hooks and
  dead-letter entries; record browsing remains bounded and redacted.
- **Storage:** database/migration health and cheap size/pressure gauges.

## Slices and acceptance

1. Define one immutable AppView snapshot spanning ingest, backfill, database,
   hooks, and endpoint registries; do not poll queue tables for headline cards.
2. Replace fail-open admin auth and preserve internal automation callers with a
   narrow loopback credential contract.
3. Move the existing pack into AppView ownership and add per-relay rendering
   using the same semantics, not shared mutable state, as Mikrus.
4. Embed the admin host and add secret-file/loopback NixOS or container options.
5. Test multiple relays, disabled ingest/backfill, stale cursor, dead letters,
   bounded pagination, mutation audit, session/CSRF rejection, and concurrent
   ingest while the dashboard polls.

Acceptance requires zero unauthenticated admin JSON when the secret is absent,
no ingest/backfill throughput regression, and parity through the compatibility
host. Rollback restores the compatibility UI, never fail-open auth.
