---
title: AppView Admin UI Brief
status: in-progress
last_verified: 2026-08-11
---

## 2026-08-11 — Slices 1-3 implemented, slice 4 packaging done

- Slice 1: SyrenaMetrics (serial-queue counters for ingest events/commits/ops/
  deletes/identities/errors, backfill completed/failed/enqueued, query families
  [backlink/manyToMany/identity/record/other], query errors, rate-limit rejects)
  instrumented in AppViewRuntime ingest/backfill delegates.
- Slice 2: GZSyrenaAdminSnapshot (bounded: health, uptime, ingest relayHealth/
  lagByRelay/throughput from AppViewIngestEngine, backfill queueDepth/
  activeWorkers/repo state counts, index collection counts, DB page_count PRAGMA,
  config relays/backfill/partial) + password-file helper.
- Slice 3: GZSyrenaAdminUIPack with 4 partials (appview-metrics, ingest-health,
  appview-backfill, appview-indexes) + embedded admin host on 127.0.0.1:2596
  wired into AppViewRuntime + syrena/main.m (SYRENA_ADMIN_PASSWORD,
  SYRENA_ADMIN_PASSWORD_FILE, --admin-password-file).
- Slice 4: NixOS module (nixos/modules/syrena.nix), flake package + module
  registration, CMake manifest, module-boundary script entries.
- Tests: SyrenaAdminUITests.m (15 tests: metrics counters/snapshot/sidebar,
  pack auth/scoping, HTML output, password helper). Compilation blocked by
  pre-existing AllTests linker error (GZCommandLineOptions symbol duplication).
- Existing AppViewAdminRoutePack fail-open (validateAuth returns YES when
  adminSecret nil) is preserved for internal automation callers; embedded UI
  uses session auth.

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
